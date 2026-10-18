# CPU governor: the performance-pin bug

## The measurement (2026-10-15)

On the LineageOS 23.2 build (2026-09-26), on a warm, mostly idle phone:

```
cpu0..cpu7  scaling_governor = performance      (stock + crDroid: schedutil)
cpu0        scaling_cur_freq  = 1804800          (== max, pinned)
cpu4..cpu7  scaling_cur_freq  = 1804800/2016000  (== max, pinned)
CPU6 temperature = 58.0 C   (stock: 49.3 C)
skin temperature = 39.4 C
```

All eight cores pinned at max frequency, always. Battery drain is the
visible symptom; the heat is the measurable one.

## Why - root cause FOUND (2026-10-17 triage, supersedes the power-HAL theory)

The vendor's `init.qcom.post_boot.sh` contains the correct setup for
trinket (`echo "schedutil" > .../scaling_governor` + hispeed/min freq +
core_ctl + sched migration + DDR bw_hwmon + memory parameters). But on
the Android 16 build **the script never gets that far**: it crashes at
every boot with

```
F libc    : FORTIFY: write: count <ID-REDACTED> > SSIZE_MAX
F libc    : Fatal signal 6 (SIGABRT) in tid 3510 (init.qcom.post_)
  Executable: /vendor/bin/sh
  Cmdline:   /vendor/bin/sh /vendor/bin/init.qcom.post_boot.sh
  backtrace: c_print -> __write_chk -> __fortify_fatal
```

(tombstone_00 + crash buffer, process uptime 0s, present in the
current boot's logcat - the "09-27" timestamps are the unsynced RTC,
not an old crash.)

`/vendor/bin/sh` is the Android-10-era mksh. Running against Android
16's bionic (from the APEX runtime) it trips the newer FORTIFY runtime
check inside the echo/print builtin and dies before reaching any of
the trinket tuning. The kernel default governor on this kernel is
`performance` - so that is what stays.

This also explains why the phone runs hot and drains faster than
crDroid 13, which runs the same script fine on the Android 13 libc.
See docs/BUG-REGISTER.md #6 for the full list of tuning that was being
lost (it is much more than the governor).

The earlier theory (AIDL power HAL power-libperfmgr re-pinning the
governor) is RETIRED as the primary cause. The HAL has not been
observed writing the governor at all once the post_boot script works.

## The shipped fix (two layers)

1. **Root cause** - scripts/apply-latent-fixes.sh re-points the
   post_boot service (and any shipped script shebangs + the
   init.aospa.perf.common.sh exec) from `/vendor/bin/sh` to
   `/system/bin/sh` - the ROM's own current mksh, built against the
   same bionic. The script content is untouched vendor code.
2. **Guard** - `variants/init.doha.cpugov.rc` still re-selects
   schedutil on `sys.boot_completed=1` + a delayed second pass, in
   case anything else ever flips it.

## Verify

```sh
adb shell cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor  # schedutil
adb shell cat /sys/devices/system/cpu/cpu4/cpufreq/scaling_governor  # schedutil
adb shell cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq  # varies
adb shell ls /data/tombstones   # no init.qcom.post_ tombstone
adb shell cat /sys/devices/system/cpu/cpu0/cpufreq/schedutil/hispeed_freq  # 1305600
```

`scripts/flash-checks.sh` section 2 does this for you.

## If it is STILL "performance" after this

Then (and only then) the remaining suspect is the power HAL actively
re-pinning:

1. Confirm:
```sh
adb root
adb shell "echo schedutil > /sys/devices/system/cpu/cpufreq/policy0/scaling_governor"
sleep 30
adb shell cat /sys/devices/system/cpu/cpufreq/policy0/scaling_governor
# flips back to performance = something is actively writing it
adb shell dmesg | grep -iE "perfmgr|powerhint|boost" | tail -50
adb shell dumpsys power | grep -iE "hint|boost|mode"
```
2. The power HAL's config is `powerhint.json` under
`device/motorola/common/power-libperfmgr/` in the source tree. Look for
any hint whose actions write `scaling_governor` and adjust.
3. Rebuild. The init guard stays as a safety net either way.

## Not the kernel

The kernel defconfig is shared by the working ROMs (crDroid 13 runs
schedutil on the same defconfig family), so the kernel default is not
the cause. The `performance` state is written by userspace after boot
(or rather: the schedutil write never happens).
