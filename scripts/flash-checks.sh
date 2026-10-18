#!/usr/bin/env bash
# doha-roms: post-flash verification. Run this after booting a new build.
# It checks, in one pass, the things this repo actually changed:
#
#   1. TOUCH      - is a touch driver loaded? (the modules.load fix)
#   2. GOVERNOR   - schedutil + post_boot ran? (FORTIFY crash fix + guard)
#   3. SIM/MCFG   - did BOTH SIMs get a modem carrier config? (SIM 1 calls)
#   4. DOLBY      - is libswdap installed and wired? (DOLBY=1 builds)
#   5. USB OTG    - can the USB HAL switch port_type? (sepolicy B9)
#   6. SENSORS    - is the variant sensor config mounted? (sepolicy B1)
#   7. SEPOLICY   - are the latent avc denials gone? (B1-B10)
#
# Usage: bash scripts/flash-checks.sh
# Works over plain adb; root is not required for sections 1-6. Section 7
# uses adb root if available and skips silently otherwise.
set -u
command -v adb >/dev/null 2>&1 || { echo "adb not found" >&2; exit 1; }
state=$(adb get-state 2>/dev/null || echo none)
[ "$state" = device ] || { echo "No device connected ($state)" >&2; exit 1; }
sh() { adb shell "$@" 2>/dev/null | tr -d '\r'; }

pass=0; fail=0
ok()   { echo "  [ OK ] $1"; pass=$((pass+1)); }
bad()  { echo "  [FAIL] $1"; fail=$((fail+1)); }

echo "== doha-roms flash checks =="
echo "build: $(sh getprop ro.lineage.version)"
echo

echo "1) Touch (modules.load fix)"
echo "   modules.load: $(sh cat /vendor/lib/modules/modules.load | tr '\n' ' ')"
lsmod=$(sh lsmod)
for m in focaltech_0flash_mmi focaltech_0flash_mmi_doha nova_0flash_mmi; do
  echo "$lsmod" | grep -q "$m" && ok "$m loaded" || echo "  [ .. ] $m not loaded (fine if another touch driver bound)"
done
# a touch input device must exist
events=$(sh getevent -pl 2>/dev/null | grep -c "add device")
ts=$(sh ls /sys/class/touchscreen/ 2>/dev/null)
if [ -n "$ts" ]; then ok "touchscreen sysfs node present: $ts"; else bad "no /sys/class/touchscreen - touch driver did not bind"; fi
echo "   (touch actually working? touch the screen: adb shell getevent -lt /dev/input/event?)"
echo

echo "2) CPU governor + post_boot (FORTIFY crash fix + cpugov guard)"
for c in 0 4; do
  g=$(sh cat /sys/devices/system/cpu/cpu$c/cpufreq/scaling_governor)
  [ "$g" = schedutil ] && ok "cpu$c governor: schedutil" || bad "cpu$c governor: $g (expected schedutil)"
  f=$(sh cat /sys/devices/system/cpu/cpu$c/cpufreq/scaling_cur_freq)
  echo "       cpu$c current freq: $f"
done
# post_boot evidence: if the script ran, it leaves its hispeed values set
hs0=$(sh cat /sys/devices/system/cpu/cpu0/cpufreq/schedutil/hispeed_freq)
[ "$hs0" = 1305600 ] && ok "post_boot ran (hispeed_freq=1305600)" || bad "post_boot tuning absent (hispeed_freq='$hs0') - the script may still crash, check /data/tombstones"
echo

echo "3) SIM 1 / modem carrier config (the Vi/Jio call issue)"
mcfg=$(sh getprop persist.vendor.radio.mcfg_version)
echo "   mcfg_version: $mcfg"
if echo "$mcfg" | grep -q null; then
  bad "one SIM slot has NULL modem carrier config (the known SIM 1 call bug state)"
elif [ -z "$mcfg" ]; then
  echo "  [ .. ] mcfg_version prop empty on this build"
else
  ok "both SIM slots have a modem carrier config ($mcfg)"
fi
net=$(sh getprop gsm.network.type)
echo "   network type per slot: $net"
[ "$(echo "$net" | cut -d, -f1)" = LTE ] && ok "SIM 1 camped on LTE" || bad "SIM 1 NOT on LTE ($net) - calls on Vi will fail"
echo "   Try, in order, if it failed:"
echo "     a) adb shell cmd connectivity airplane-mode enable; sleep 5; disable"
echo "     b) reboot with only SIM 1 inserted, check again, then reinsert SIM 2"
echo "     c) swap the two SIMs physically: does the problem follow the SLOT"
echo "        (software) or the CARD (carrier)? Tell the thread either way."
echo

echo "4) Dolby (DOLBY=1 builds only)"
if [ -n "$(sh ls /vendor/lib64/soundfx/libswdap.so 2>/dev/null)" ]; then
  ok "libswdap.so installed in vendor"
  eff=$(sh cat /vendor/etc/audio_effects.xml)
  echo "$eff" | grep -q libswdap && ok "audio_effects.xml wired" || bad "audio_effects.xml missing the dolby entry"
else
  echo "  [skip] no libswdap - build was DOLBY=0"
fi
echo

echo "5) USB OTG / role switch (sepolicy B9)"
# The USB HAL writes port_type when role detection runs. With the fix,
# plugging an OTG adapter should register the device; without it, it won't.
if [ -n "$(sh ls /sys/class/typec/port0/ 2>/dev/null)" ]; then
  data=$(sh cat /sys/class/typec/port0/data_role 2>/dev/null)
  echo "   typec port0 data_role: $data"
  ok "typec port0 present - plug an OTG adapter + USB stick and watch:"
  echo "     adb shell dmesg | grep -iE 'typec|role|otg' | tail -5"
else
  echo "  [ .. ] /sys/class/typec/port0 not visible without root - skip"
fi
echo

echo "6) Sensor variant config (sepolicy B1) - the empty-config fix"
ncfg=$(sh ls /vendor/etc/sensors/config 2>/dev/null | wc -l)
if [ "$ncfg" -gt 5 ]; then
  ok "sensor config mounted: $ncfg files in /vendor/etc/sensors/config (stock: 40+)"
else
  bad "sensor config EMPTY ($ncfg files) - the config-doha bind-mount still fails"
fi
orient=$(sh dumpsys sensorservice 2>/dev/null | grep -c "Orientation")
[ "$orient" -ge 1 ] && ok "Orientation virtual sensor present" || bad "Orientation sensor missing (expected 2 on the fixed build)"
echo

echo "7) Latent avc denials (B1-B10) - needs adb root"
if adb root >/dev/null 2>&1; then
  sleep 2
  d=$(sh dmesg 2>/dev/null | grep -c "avc: denied")
  l=$(sh "logcat -d -b all 2>/dev/null | grep -c 'avc: denied'" 2>/dev/null)
  echo "   avc denials this boot (dmesg: $d, logcat: $l)"
  bads=$(sh dmesg 2>/dev/null | grep "avc: denied" | grep -cE "amogus-sh.*sensors|hal_usb_impl.*port_type|rild.*mnt_vendor|fsck.*(modem|blk)|modprobe.*cmdline|system_suspend.*batteryinfo")
  if [ "${bads:-0}" = 0 ]; then
    ok "none of the fixed denial signatures remain"
  else
    bad "still seeing $bads of the fixed denial signatures - check docs/BUG-REGISTER.md"
  fi
  tb=$(sh ls /data/tombstones 2>/dev/null)
  case "$tb" in *post_boot*) bad "post_boot tombstone present - script still crashing" ;; *) ok "no post_boot tombstone" ;; esac
else
  echo "  [skip] adb root unavailable - denial counts need root"
fi
echo

echo "== summary: $pass ok, $fail fail =="
[ $fail -eq 0 ] || exit 1
