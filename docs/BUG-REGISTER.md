# doha-roms BUG REGISTER

Every defect found in the 2026-09-26 LineageOS 23.2 (Android 16) build for
Moto G8 Plus (doha), from the full triage of three device dumps taken
2026-10-15 (stock Android 10, crDroid 9.20 / Android 13, LineageOS 23.2).
Only the lineage16 dump was taken with root, so kernel-level evidence
(dmesg, tombstones) is lineage16-only; userspace evidence is compared
across all three ROMs.

Fix status key:
- **FIXED** - a patch/step in this repo fixes it
- **PARTIAL** - mitigation shipped, root cause needs more data
- **DOCUMENTED** - real but not fixable from this repo yet (needs kernel
  DT data, AOSP-side change, or hardware test)
- **NO-OP** - technically an error, provably without effect on Android 16

Severity = user-visible impact if left alone.

| # | Bug | Severity | Status |
|---|-----|----------|--------|
| 1 | Touch dead at boot | critical | FIXED |
| 2 | SIM 1 calls fail | critical | PARTIAL |
| 3 | CPU governor pinned to performance | high | FIXED (twice over) |
| 4 | Dolby Atmos absent | feature | FIXED (integration path) |
| 5 | Thermal HAL sensor name mismatch | high | FIXED |
| 6 | post_boot FORTIFY SIGABRT - all tuning lost | **critical** | FIXED |
| 7 | Sensor variant config bind-mount denied | high | FIXED |
| 8 | system_suspend blocked from battery wakeup stats | medium | DOCUMENTED |
| 9 | USB HAL cannot write port_type (OTG/role) | medium | FIXED |
| 10 | rild blocked from /mnt/vendor (persist) | medium | FIXED |
| 11 | vold blocked from /mnt/product (prodpersist) | low | FIXED |
| 12 | fsck denied on modem + prodpersist partitions | low | FIXED |
| 13 | BT HAL cannot read Motorola vendor props | low | FIXED |
| 14 | Camera HAL cannot read default-prop area | low | FIXED |
| 15 | modprobe denied /proc/cmdline | low | FIXED |
| 16 | InputReader denied sysfs "country" node | low | DOCUMENTED |
| 17 | init sys_ptrace self-denial | noise | NO-OP |
| 18 | installd quotaget denial spam (30/boot) | noise | NO-OP |
| 19 | ro.product.bevice typo in build_doha.prop | noise | FIXED |
| 20 | Legacy vendor props never set (WFD, RIL, BT LE) | medium | PARTIAL |
| 21 | Camera sensor EEPROM + actuator not probing | medium | DOCUMENTED |
| 22 | IPA / SMMU bus registration failure | medium | DOCUMENTED |
| 23 | Display driver DT mismatches (5 errors) | low | DOCUMENTED |
| 24 | msm-dai-tdm sen-rx/sen-tx probe failure | noise | NO-OP |
| 25 | wificond NL80211 AKM-suites warnings | noise | NO-OP |
| 26 | stune/cpuctl cgroup exhaustion (nnapi-hal) | low | DOCUMENTED |
| 27 | CapSense (SAR) sensors missing vs stock | feature | DOCUMENTED |
| 28 | Orientation sensors missing vs crDroid 13 | low | FIXED (via #7) |
| 29 | RIL IMS bearer only on slot 1 | info | PARTIAL (see #2) |
| 30 | Crashed-system-check gaps (dropbox empty) | info | NO-OP |

Details below. Every FIXED item has a verify step in
`scripts/flash-checks.sh`.

---

## #1 Touch dead at boot - FIXED (shipped earlier)

`modules.load` lists only 4 modules; the three FocalTech FTS touch
drivers ship in /vendor/lib/modules but never load. This unit has a
FocalTech FT8719 panel (fts_* sysfs nodes on stock/crDroid, absent on
lineage16; Himax built-in driver probes and finds nothing).
Fix: `patches/device/motorola/amogus_doha.patch` adds the three touch
drivers to `BOARD_VENDOR_KERNEL_MODULES_LOAD`. No kernel rebuild needed.

## #2 SIM 1 (Vi) calls fail - PARTIAL

Evidence: `persist.vendor.radio.mcfg_version` = `null,RJIO_IND` on
lineage16 (stock: `VODAFONE_IND_VOLTE,RJIO_IND`); `gsm.network.type` =
`EDGE,LTE` (slot 0 fell back to 2G); IMS bearer exists only for phoneId 1
(telephony/ims_status.txt: single `ApnSetting IMS ... 405871` = Jio);
Vi voice registers on GSM and PS data is OUT_OF_SERVICE (radio log).
Root cause: qcrild's per-slot MCFG selection fails for slot 0 (Vi) on the
Android 16 boot. The modem-side MCFG database is identical across ROMs.
New evidence this session: two Android-16-tree-specific failures land in
the same boot window and are now FIXED - see #10 (rild denied
/mnt/vendor, the gateway to persist EFS files) and #20
(`ril.subscription.types` never set). Either or both may be the missing
piece for reliable slot-0 provisioning.
Test: flash the new build, then run the docs/SIM1-CALLS.md matrix. If
SIM 1 still fails, capture `adb logcat -b radio` during a boot +
airplane-mode toggle.

## #3 CPU governor pinned to performance - FIXED (true cause found)

All 8 CPUs on `performance`, cpu0 pinned 1804.8 MHz, CPU6 58 C idle.
Earlier theory (AIDL power HAL power-libperfmgr) is now RETIRED as the
primary cause: the real cause is #6 - the vendor post_boot script that
sets schedutil + hispeed + min freq + core_ctl + sched migration
thresholds + DDR bw_hwmon + memory params for trinket CRASHES at every
boot, so none of its writes ever happen. The kernel default governor on
this kernel is performance.
Fixes shipped: #6 (interpreter swap) + `variants/init.doha.cpugov.rc`
(boot-completed guard, kept as belt-and-braces).

## #4 Dolby Atmos absent - FIXED (integration path)

Stock vendor carries the full DMS stack (libswdap 32/64,
dax-default.xml, DMS HAL service, media_codecs_dolby_audio.xml);
custom ROMs ship none of it. Integration: variants/dolby/
(extract-from-stock.sh, wire-audio-effects.sh, dolby.mk), enabled with
DOLBY=1. Experimental until first listen test.

## #5 Thermal HAL sensor name mismatch - FIXED (inherited)

`xo_therm` vs `xo-therm-adc` sensor-name mismatch (christiaan's
thermal patch, in patches/vendor/qcom/opensource/thermal.patch).

## #6 post_boot FORTIFY SIGABRT - ALL trinket post-boot tuning lost - FIXED - **headline bug**

Evidence chain (lineage16 only has root, all from one boot):
- tombstone_00 + crash buffer: `/vendor/bin/sh /vendor/bin/init.qcom.post_boot.sh`
  aborts with `FORTIFY: write: count > SSIZE_MAX` in `c_print` ->
  `__write_chk` (libc), process uptime 0s, at every boot (the
  timestamps look like "09-27" because the RTC is unsynced at that boot
  moment - the crash IS in the current boot's logcat).
- `cpu/post_boot_service_status.txt`: `stopped`.
- The script is the 6334-line Qualcomm post-boot tuner. For trinket
  (soc_id 394/467/468) it sets: schedutil + hispeed_freq + min_freq per
  cluster, core_ctl big-cluster parameters, sched up/down migrate (67/77)
  + group (85/100), sched_walt_rotate_big_tasks, sched_load_boost -6,
  configure_memory_parameters (min_free_kbytes, LMK adj), DDR
  bw_hwmon + min_freq 762 + mbps_zones per DDR type, input boost,
  readahead 128/512K, LMK parameters, plus the final
  setprop persist.vendor.mmi.misc_dev_path.

Root cause: /vendor/bin/sh is the Android-10-era mksh binary; running
against the Android 16 bionic (APEX com.android.runtime) it hits the
newer FORTIFY runtime check and dies inside the echo/print builtin on
the first offending write. Old vendor binary + new libc = deterministic
crash.

Impact: with the script dead since the first boot, this build has been
running with zero vendor power/performance tuning - which is why the
governor sits on performance (#3), why the device ran hot, and why
battery life is worse than crDroid 13 (which runs the same script on
the Android 13 libc, where the old mksh is fine).

Fix: scripts/apply-latent-fixes.sh re-points the post_boot service (and
the init.aospa.perf.common.sh exec + any shipped script shebangs) at
/system/bin/sh - the ROM's own current mksh, built against the same
bionic. The script itself is unmodified vendor content.
Verify: flash-checks.sh section 2 - no tombstone for init.qcom.post_,
governor schedutil, `init.svc.vendor.post_boot` = stopped (oneshot,
completed) AND tuning values present (hispeed_freq = 1305600/1401600).

## #7 Sensor variant config bind-mount DENIED - FIXED

Evidence (5 avc denials at boot, lineage16 only):
```
avc: denied { sys_admin } for comm="mount" scontext=u:r:amogus-sh:s0 tclass=capability
avc: denied { mounton } for comm="mount" path="/vendor/etc/sensors/config" tcontext=u:object_r:vendor_sensor_data_file:s0 tclass=dir
avc: denied { ioctl } for comm="mount" path="/vendor/etc/sensors/config-doha" ioctlcmd=0x125d
```
The amogus vendor image covers 4 device variants (doha/rav/sofia/
sofiar). At boot a variant script bind-mounts the right config dir over
/vendor/etc/sensors/config. The mount is denied, so the sensors stack
runs with /vendor/etc/sensors/config **EMPTY** - stock has 40+ JSON
files (lsm6dso, mmc5603x, mot_devorient, nicobar_* variants...) there.
Consequences: the Orientation virtual sensors never appear (#28 - 47
h/w sensors on lineage16 vs 49 on crDroid 13, missing exactly
"Orientation Wakeup/Non-wakeup"), and all sensor tuning JSONs are
ignored (SLPI defaults only).
Fix: doha_amogus_fixes.te B1 (sys_admin + mounton + ioctl for amogus-sh
on vendor_sensor_data_file). Verify: flash-checks.sh section 4 -
`ls /vendor/etc/sensors/config` non-empty after boot, Orientation
sensors present in `dumpsys sensorservice`.

## #8 system_suspend blocked from battery wakeup stats - DOCUMENTED

117 denials per boot (scontext=system_suspend, tclass=file on
/sys/class/power_supply/battery/{name,active_count,last_change_ms,
max_time_ms,total_time_ms,active_time_ms} labeled sysfs_batteryinfo).
crDroid 13 has the same denial, so this is a cross-version gap, not an
Android 16 regression. Suspend itself works (mUseAutoSuspend=true, no
wakelock stuck); the impact is incomplete wakeup-source attribution for
battery/charger IRQs in the suspend service.
Not fixed: system_suspend is a system-side domain and sysfs_batteryinfo
a vendor-side type - the allow rule fits in neither partition's policy
cleanly. A clean fix belongs upstream (relabel the power-supply wakeup
attrs, or an AOSP-side allow). Downgraded to documented.

## #9 USB HAL cannot write port_type - FIXED

20+ denials, recurring through uptime (hal_usb_impl denied write on
/sys/.../port_type, vendor_sysfs_usb_c). The AIDL USB HAL's role-switch
write fails every time it retries - USB-C role/OTG adapter behaviour is
degraded. crDroid shows the same denial (2x). Fix:
doha_qcom_fixes.te B9. Verify: flash-checks.sh section 5 (plug an OTG
adapter with a USB stick after flashing).

## #10 rild blocked from /mnt/vendor - FIXED

qcrild's dispatcher thread denied search on /mnt/vendor (mnt_vendor_file)
at the moment the radio stack comes up (~22s into boot). /mnt/vendor is
the gateway to /mnt/vendor/persist (EFS/RF/modem files). Present on
crDroid 13 too. Fix: doha_qcom_fixes.te B6. Possibly part of #2 - retest
SIM 1 after flashing.

## #11 vold blocked from /mnt/product - FIXED

vold denied search on mnt_product_file (prodpersist mount). Fix:
doha_qcom_fixes.te B7.

## #12 fsck denied on modem + prodpersist - FIXED

e2fsck denied {read} then {read write} on mmcblk0p34 (modem,
vendor_modem_block_device) and mmcblk0p47 (prodpersist, block_device).
fs_mgr runs the check before mounting; denied, both ext4 partitions
mount unchecked every boot - a latent corruption risk (prodpersist
holds factory calibration and is formattable). The tree's own fsck.te
already allows the dsp partition the same way, so this is a regression
in coverage. Fix: doha_qcom_fixes.te B8.

## #13 BT HAL cannot read Motorola vendor props - FIXED

bluetooth@1.0-service denied read of the vendor_mot_prop area
(Motorola BT chip/variant config in /vendor/build.prop). Fix:
doha_amogus_fixes.te B3.

## #14 Camera HAL cannot read default-prop area - FIXED

hal_camera_default denied reading the default_prop property area -
vendor build_doha.prop camera props never reach the HAL. Fix:
doha_amogus_fixes.te B4. (Also relates to #19 - the same prop file.)

## #15 modprobe denied /proc/cmdline - FIXED

8 denials per boot: kmod's modprobe (running in vendor_moto_init_shell
from init.modprobe.sh) is denied /proc/cmdline, which it reads to match
module options passed on the kernel command line. Fix:
doha_amogus_fixes.te B2.

## #16 InputReader denied sysfs "country" node - DOCUMENTED

system_server InputReader denied read on a sysfs node named "country"
(generic sysfs label, so a targeted allow would be a broad
`allow system_server sysfs:file read` - not acceptable). Likely the
touch panel country attribute; with #1 fixed the node exists and the
poll may succeed (the node then carries a touchscreen-specific label)
or keep producing harmless denials. Re-check after flashing; if still
denied on a labeled node, add the targeted allow then.

## #17 init sys_ptrace self-denial - NO-OP

init denied sys_ptrace on itself at the exact moment it reaped the
crashed post_boot process (00:11:15.906). Disappears with #6.

## #18 installd quotaget denial spam - NO-OP

30 denials per boot: installd quotaget on firmware_file/bt_firmware/
vendor_fsg mounts during dex scans. Cosmetic (quota query is optional);
a dontaudit would need installd (a system domain) touched from vendor
policy. Left as log noise.

## #19 ro.product.bevice typo - FIXED

/vendor/build_doha.prop ships `ro.product.bevice=doha` (typo; also a
duplicate of the system-set ro.product.device, so the prop was dead
code on stock too). Fix: apply-latent-fixes.sh step 5 corrects the name
wherever the file lives in the build tree.

## #20 Legacy vendor props never set - PARTIAL

vendor_init (loading the vendor prop files) is denied setting 6
system-labeled props at every boot:
- `ril.subscription.types` (radio_prop) - qcrild per-slot subscription
  config; **the most telephony-relevant one** (see #2)
- `persist.debug.wfd.enable` (persist_debug_prop) - WFD/Miracast default
- `persist.demo.hdmirotationlock` (default_prop) - demo prop, obsolete
- `bluetooth.profile.tbs.server.enabled` + `vc.server.enabled`
  (bluetooth_prop) - LE-Audio telephone-bearer defaults; the system BT
  stack reads bluetooth_prop, which vendor policy cannot relabel without
  breaking the system reader - the values also match framework defaults
- `ro.lmk.threshold_decay` (default_prop) - legacy lmkd knob, unused by
  Android 16 lmkd (PSI-based)

Fix shipped (doha-latent property_contexts.add): re-label
`ril.subscription.types` -> vendor_radio_prop and
`persist.debug.wfd.enable` -> vendor_default_prop, plus reader allows
(B5/B10). The remaining four are NO-OP on Android 16 and documented.

## #21 Camera sensor EEPROM + actuator not probing - DOCUMENTED

Kernel-only evidence (lineage16 dmesg):
```
msm_actuator_platform_probe: No/Error Actuator GPIOs
msm_eeprom_platform_probe failed 1802   (x4)
CAM-SOC msm_camera_get_reg_base: err: mem resource vfe_fuse not found
eeprom_init_config32: memory map parse failed  (x2, ~15.8s - camx userspace)
```
The camera WORKS (all exposure metadata exposed, no userspace camera
errors), but the sensor EEPROM (lens/AWB/AF calibration) and actuator
GPIOs fail to probe on the community 4.14.190 kernel - image quality
may be subtly degraded versus stock (4.14.117, where presumably they
probe). crDroid 13 uses the same community kernel; no kernel logs
available for it, so "works on stock only" is unproven but likely.
Fix path (needs data this dump set lacks): pull
`/proc/device-tree/*/soc:qcom,msm-eeprom*` + camss eeprom/actuator
nodes from the STOCK ROM with root, compare against the kernel DTS in
Aldair402/msm-4.14, and patch the missing memory-map/GPIO nodes. The
next debug_device.sh run should capture the DT nodes.

## #22 IPA / SMMU bus registration failure - DOCUMENTED

```
arm-smmu c600000.apps-smmu: Bus client registration failed  (x3)
ipa ipa3_pre_init: fail to register with bus mgr!  (x3)
ipa ipa3_plat_drv_probe: ipa3_init failed  (x3)
usb_bam_ipa_delete_resources: Failed to delete USB_PROD/USB_CONS resource
```
The IPA (IP-accelerator) driver fails to init because its SMMU bus
client registration fails. Userspace impact is mitigated: tethering
hardware offload HALs are "not started" on BOTH custom ROMs and BPF
offload carries tethering instead (tether_offload.txt). Residual cost:
the modem data path loses IPA acceleration and USB-BAM paths error.
Kernel-level fix (SMMU bus master IDs / DT bus config) - documented,
same kernel family as crDroid 13, low priority.

## #23 Display driver DT mismatches - DOCUMENTED

Five boot-time errors, display works: DSI backlight config parse rc=-22;
MDP missing vbif_nrt_phys + sid_phys memory resources; 2x
"invalid feature map 12 for feature 31" (SSPP); rotator bus client
registration failed (AXI path src 1 -> dest 590 missing). All indicate
the community 4.14 kernel DTS drifts from the vendor's panel/MDP
expectations. Cosmetic-to-minor; fix requires DT work in the kernel.

## #24 msm-dai-tdm sen-rx/sen-tx probe failure - NO-OP

Two unused audio TDM interfaces fail -22 at probe. Audio path on doha
uses the primary I2S/SLIMbus DAIs; these TDM nodes are for other
boards' variants. Harmless.

## #25 wificond NL80211 warnings - NO-OP

48 warnings: wificond cannot get NL80211_ATTR_MAX_NUM_AKM_SUITES from
the 4.14-era wlan driver. Cosmetic; WPA3-SAE itself works (kernel
cherry-pick from christiaan's repo, kept in our patch set).

## #26 stune/cpuctl cgroup exhaustion - DOCUMENTED

Android 16's system init.rc expects a newer kernel cgroup API:
`mkdir /dev/stune/nnapi-hal` fails "No space left on device" (the 4.14
stune hierarchy is full), `cpu.uclamp.min/latency_sensitive` writes
fail (no uclamp in this kernel). The framework falls back gracefully.
Part of the known kernel-generation gap; the same class of issue will
grow on Android 17 (see crdroid-17/README.md risks).

## #27 CapSense (SAR) sensors missing vs stock - DOCUMENTED

stock10 exposes 3 extra sensor entries: Moto CapSense Ch0/Ch2/Ch4
(semtech SX933x SAR/grip sensing). Both custom ROMs lack them even
though the sx933x_sar module loads on lineage16 (it is one of the 4
modules in modules.load!) - the SSC registry/sensor-config entries that
expose it are absent (stock's sns_reg_config differs: 553 vs 627 bytes).
Feature loss: grip detection Moto uses for antenna tuning/hold-to-mute.
Fix path: port stock's sns_reg_config + semtech sensor JSONs into the
sensor config (worth doing together with #7 verification - after the
config-doha mount works, check whether the JSON set covers sx933x).

## #28 Orientation sensors missing vs crDroid 13 - FIXED (via #7)

55 sensor entries on lineage16 vs 59 on crDroid 13; the 4 missing are
exactly "Orientation Wakeup/Non-wakeup" (x2 formats) + noise lines.
Fixed by restoring the sensor config mount (#7). Verify with
flash-checks.sh section 4.

## #29 RIL IMS bearer only on slot 1 - PARTIAL (see #2)

ims_status.txt: exactly one IMS data connection (phoneId=1, subId=2,
Jio, CONNECTED with P-CSCF addresses); nothing for phoneId=0. Consistent
with #2's mcfg failure. Re-test after #10/#20 fixes.

## #30 dropbox empty - NO-OP

/data/system/dropbox has no entries on lineage16 (empty dir listing) -
the crash reporter works (tombstones exist, dropbox entries expire by
retention). Not a defect.

---

## What the register means for the build

The fix layer order in build.sh:
1. repo patches (christiaan's 17 + touch extension)
2. **latent-fixes** (post_boot interpreter, sepolicy B1-B10, prop
   relabels, typo) - scripts/apply-latent-fixes.sh
3. variant layer (cpugov guard, debloat, Dolby, GApps editions)
4. breakfast + bacon

The sepolicy drop-ins are new files (no context matching to fail). If a
future branch rejects a block (type visibility changes), delete that
block from latent-fixes/*.te and rebuild - blocks are independent and
commented. The post_boot interpreter fix is content-searched, so it
survives branch layout changes.

crDroid 17 note: every finding in this register applies to the crDroid
17 bring-up too (same device trees, same vendor, same kernel). The
apply-latent-fixes.sh script is written to be reused there unchanged -
see crdroid-17/README.md.
