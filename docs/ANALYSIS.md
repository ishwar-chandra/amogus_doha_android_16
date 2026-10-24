# Three-ROM differential analysis: stock 10 vs crDroid 13 vs LineageOS 16

Data: three full device dumps taken on **2026-10-15** on this exact phone
(Moto G8 Plus, XT2019, FPC 2.1 fingerprint variant, FocalTech FT8719
touch panel), with the debug script from this repo
(`debug_device.sh`, v3):

| ROM | Dir | Kernel | Build |
|---|---|---|---|
| stock Android 10 | `stock10` | 4.14.117-perf+ (2021-09-29) | stock QPI30 |
| crDroid 9.20 (Android 13) | `crdroid13` | 4.14.190+ #2 (2025-01-15) | TQ3A.230901.001 |
| LineageOS 23.2 (Android 16) | `lineage16` | 4.14.190+ #6 (2026-09-26) | 23.2-20260926-UNOFFICIAL |

The user reports: crDroid 13 = "the most stable ROM, no bugs". LineageOS 16
= working except **SIM 1 calls** and **touch** (touch fixable via ADB).
This document is the evidence for every fix this repo ships.

---

## 1. Touch — root cause PROVEN

The phone's touch panel is a **FocalTech FT8719** (`/sys/class/touchscreen/ft8719`
present on stock; `fts_*` nodes on the SPI bus `4a88000.spi/spi0.0`).

| Evidence | stock 10 (touch works) | crDroid 13 (touch works) | lineage16 (touch dead) |
|---|---|---|---|
| `/vendor/lib/modules/modules.load` | **does not exist** | **does not exist** | exists: `aw8624 aw8695 sx933x_sar stmvl53l1` |
| touch modules in `lsmod` | himax_v2_mmi, himax_v2_mmi_hx83112, focaltech_0flash_mmi | focaltech_0flash_mmi, focaltech_0flash_mmi_doha, nova_0flash_mmi | **none** |
| `fts_*` sysfs nodes | present | present | **absent** ("No such file or directory") |
| dmesg | (no root) | (no root) | Himax built-in driver probes, finds no panel, gives up |

Mechanism: `init.modprobe.sh` loads every module in `/vendor/lib/modules`
**only when `modules.load` does not exist**. LineageOS 23.2's kernel.mk
always writes `modules.load` (empty if the board list is empty — and the
list christiaan's patch set contained only haptics/SAR/ToF). Result: the
three touch `.ko` files ship in `/vendor/lib/modules` but never load, no
driver binds to the FT8719, touch is dead. The ADB workaround the user
found is almost certainly `modprobe focaltech_0flash_mmi_doha` (or
equivalent) after boot.

**Fix (shipped):** `BOARD_VENDOR_KERNEL_MODULES_LOAD` in
`lineage-16/patches/device/motorola/amogus_doha.patch` now lists the three
touch drivers as well, matching what the working ROMs load. The kernel
builds all three; the ones that don't match this panel simply don't bind.
Verify after flashing: `scripts/flash-checks.sh` section 1.

## 2. SIM 1 calls — root cause PROVEN (slot 0 never gets an MCFG)

SIMs: **SIM 1 = Vi India** (mcc 404 / mnc 15, carrierId 2378, ICCID 89910…),
**SIM 2 = Jio** (405/871, carrierId 2018). User symptom: VoLTE works, data +
signal on both SIMs, SIM 2 calls fine, **SIM 1 outgoing calls fail**. The
same defect was reported on crDroid 13 with the Jio card in SIM 1; the
2026-10-24 crDroid 13 dump confirms the mechanism.

| Evidence | stock 10 (calls work) | crDroid 13 | lineage16 |
|---|---|---|---|
| `persist.vendor.radio.mcfg_version` | `VODAFONE_IND_VOLTE,RJIO_IND` | **`null,BSNL_VOLTE`** | **`null,RJIO_IND`** |
| `persist.vendor.radio.mcfg_ver_num` | `0x08010809,0x08011B0C` | **`0,0x08010809`** | **`0,0x08011B0C`** |
| `set_ims_service_enable_config` slot 0 | works | **`ril_err: 54, qmi res: 70`** | never sent (feature not READY) |
| `set_ims_service_enable_config` slot 1 | works | `ril_err: 0, qmi res: 0` | `ril_err: 0, qmi res: 0` |
| `gsm.network.type` (slot 0, slot 1) | `LTE,LTE` | `LTE,LTE` | `LTE,LTE` |
| IMS on slot 0 | call dials over IMS (`useImsForCall=true`) | MMTEL `Voice:false` | `isImsRegistered=false`, feature never READY |

Mechanism, proven by the logs: slot 0 finishes boot with
`mcfg_version=null` / `mcfg_ver_num=0`. The modem therefore rejects the
IMS service-enable request for that stack with `QMI_ERR_INVALID_OPERATION`
(`qmi res: 70`). Slot 1 has a valid MCFG, accepts the request, and Jio
registers VoLTE. The failure follows the **slot**, not the card: swapping
Jio into SIM 1 reproduces it, swapping it back to SIM 2 fixes it. Android
16 additionally never brings the slot-0 `ImsFeature` to READY; Android 13
brings it to READY but with empty MMTEL capabilities. Both are downstream
of the same missing MCFG.

The MCFG files (`mcfg_hw.mbn`/`mcfg_sw.mbn`) are byte-identical across the
three dumps, so the data is present; Motorola QCRIL's AP-side SW-MBN
selector (`qcril_qmi_sw_mbn_select_mbn`, `mot_mbn_set_mcfg_ver`,
`/data/vendor/modem_config/mcfg_sw/`) is what fails. Stock sets the QCRIL
inputs in its `vendor.prop`; the hand-written doha `common-prop.mk` omitted
them, including `persist.vendor.radio.no_wait_for_card=1`, which gates the
selection path.

**Fix (shipped):** `patches/device/motorola/common.patch` restores the
stock Motorola QCRIL/IMS props (`no_wait_for_card`, `hidl_dev_service`,
`aosp_usr_pref_sel`, `enable_temp_dds`, `force_get_pref`, `jbims`,
`ro.vendor.radio.ims_version`). Same device tree is used by crDroid 13 and
the Android 17 kit, so the hunk carries to both. `flash-checks.sh` section
3 now checks each slot separately and fails if either MCFG is null or IMS
is registered on fewer than 2 slots. If a future boot still shows slot 0
null, docs/SIM1-CALLS.md documents the qcrild-ordering/retry step.

## 2b. Hotspot — modem SSR from the IPA WDI force-clear path

The 2026-10-24 crDroid 13 dump caught the hotspot bug in the kernel log.
Every suspend while the WiFi AP was up produced:

```
ipa3_qmi_enable_force_clear_datapath_send:1313 send Req 37 failed, rc= -110
ipa3_enable_force_clear:979 ... failed -110
ipa3_suspend_gsi_wdi_pipe:2819 failed to force clear -110
ipa3_suspend_gsi_wdi_pipe:2820 remove delay from SCND reg
ipa3_cfg_ep_ctrl:5034 pipe setting delay is not supported
modem subsystem failure reason: ipa_hal.c:2393:IPA Assert:
  ... Received IPA IRQ. IRQ_STTS: 0x01812080 ...
Fatal error on modem!
subsys-restart: Restart sequence requested for modem, restart_level = RELATED
```

The modem restarts, both telephony stacks broadcast `POWER_OFF`, and both
SIMs drop registration — the "hotspot kills the SIMs" symptom. The WLAN
firmware dump follows because its root PD is the modem
(`icnss: PD service down ... Root PD crashed`).

Root cause: IPA v4.2 (trinket) with the stock modem firmware does not
implement the force-clear QMI request. `ipa3_suspend_gsi_wdi_pipe()`
sends it anyway; the request times out (`-110`) and the modem asserts on
the pending IPA IRQ. The same code is in the LineageOS 23.2 kernel pin
(`6509e92`, same `ipa_uc_wdi.c` line numbers), so the bug carries to
Android 16 and to the Android 17 kit (same kernel pin).

**Fix (shipped):** the kernel patch skips the force-clear request when
`ipa_hw_type == IPA_HW_v4_2` and takes the existing failure path (clear
the endpoint delay, stop the GSI channel). No request, no modem IRQ
storm. Wi-Fi station mode keeps IPA offload; only the WDI suspend path
changes. Verify by enabling the hotspot, letting the screen sleep, then
checking that `dmesg` has no `Fatal error on modem` and both SIMs stay
registered.

## 3. CPU governor pinned to performance — new bug found

| Evidence | stock 10 | crDroid 13 | lineage16 |
|---|---|---|---|
| governor, all 8 CPUs | schedutil | schedutil | **performance** |
| cpu0 cur/max freq | — | — | **1804800 / 1804800 (pinned max)** |
| CPU6 temperature | 49.3 °C | (no root) | **58.0 °C** |

The vendor's `init.qcom.post_boot.sh` **does** set schedutil (present and
correct in the lineage16 vendor too), so something that runs later switches
the governor back. ~~Prime suspect: the AIDL power HAL~~ — **superseded:
the script itself crashes at every boot (see section 6 / BUG-REGISTER #6);
the power-HAL theory is retired.**

**Fix (shipped):** `variants/init.doha.cpugov.rc` — a boot-completed guard
that rewrites schedutil on both policies, plus a delayed second pass after
the power HAL reports running. Copied into the build by `build.sh`.
If the governor still flips back after this, the HAL is actively pinning
it and the real fix is in its powerhint config — see
docs/CPU-GOVERNOR.md for the next step.

## 4. Dolby — this device's stock firmware HAS the full stack

Stock Android 10's vendor partition carries (custom ROMs ship none of it):

```
/vendor/bin/hw/vendor.dolby.hardware.dms@1.0-service     (DMS HAL service)
/vendor/etc/dolby/dax-default.xml                        (61.4 KB default profile)
/vendor/etc/media_codecs_dolby_audio.xml                 (codec entries)
/vendor/lib/soundfx/libswdap.so                          (the Atmos effect, 32-bit)
/vendor/lib64/soundfx/libswdap.so                        (the Atmos effect, 64-bit)
/vendor/lib/libstagefrightdolby.so                       (old DS2 decoder path)
```

crDroid 13 and LineageOS 16 have no Dolby blobs and no dolby entry in
`audio_effects.xml` (the qcom DS2 flags `vendor.audio.dolby.ds2.enabled=false`
are unrelated). The integration for this repo: extract the blobs from the
phone's own stock ROM (`variants/dolby/extract-from-stock.sh`), wire the
effect into `audio_effects.xml`/`.conf` at build time
(`variants/dolby/wire-audio-effects.sh`), ship `dax-default.xml`. See
docs/DOLBY.md. Marked experimental until the first build+listen test.

## 5. Small sanity findings

- SELinux: **Enforcing** on all three ROMs.
- `modules.dep`/`modules.alias` present; `ets_fps_mmi` (ETS fingerprint
  module) loads on all three — fine.
- Radio daemons: dual-instance `qcrild` on all three ROMs (not old rild).
- Stock runs 62 kernel modules vs crDroid 9 / lineage 7 — most of stock's
  are audio (wcd937x/cirrus codec chains) that the community audio trees
  build differently; no action needed, both audio paths work.
- Thermal: lineage16 with the pinned-governor bug ran hot (skin 39.4 °C,
  CPU6 58 °C idle). crDroid/stock sit at skin ~39 °C with schedutil —
  expect the cpugov fix to bring lineage down to the same range.
- Boot chain, IMS framework, Wi-Fi, BT, NFC, GPS, fingerprint, camera:
  no meaningful deltas in the dumps beyond the items above.

## 6. Deep-dive round 2 (2026-10-17): the latent-bug hunt

A second, deeper pass over the same dumps (crashes, tombstones, all
343 avc denials, every dmesg error line, per-subsystem logcat, sensor
inventories, fstab/fsck paths) found the bugs nobody had noticed.
Full register with evidence: **docs/BUG-REGISTER.md** (30 items).
The headline items:

- **init.qcom.post_boot.sh crashes at EVERY boot** (FORTIFY SIGABRT:
  Android-10-era `/vendor/bin/sh` vs Android 16 bionic, dies in the
  echo/print builtin). Consequence: the ENTIRE trinket post-boot tuning
  is lost — schedutil governor, hispeed/min freqs, core_ctl, sched
  migration thresholds, sched_load_boost, DDR bw_hwmon + mbps zones,
  memory parameters, input boost, readahead. This is the TRUE root
  cause of the performance-governor bug (section 3's power-HAL theory
  is retired) and of the heat/battery gap vs crDroid 13. The dump's
  bogus clock (unsynced RTC at boot) explains why the crash looked 3
  weeks old: it is from the same boot the dump was taken on.
- **Sensor variant config bind-mount is DENIED** (5 avc denials,
  amogus-sh lacks sys_admin/mounton/ioctl): /vendor/etc/sensors/config
  runs EMPTY (stock: 40+ JSONs), the Orientation virtual sensors are
  missing and sensor tuning is ignored.
- **10 fixable avc denial families** total (USB HAL port_type writes =
  OTG degraded; rild blocked from /mnt/vendor; vold from /mnt/product;
  fsck from modem+prodpersist partitions; BT and camera HAL prop reads;
  modprobe /proc/cmdline; more) — 8 of them unique to the Android 16
  tree, 2 shared with crDroid 13.
- **Legacy vendor props never set**: `ril.subscription.types` (RIL
  per-slot subscription config — telephony-relevant, possibly the SIM 1
  missing piece) and `persist.debug.wfd.enable` are denied at every
  boot; now re-labelled and shipped. `bluetooth.profile.tbs/vc` and
  `ro.lmk.threshold_decay` are documented NO-OPs on Android 16.
- **Kernel-side (both custom ROMs, not just 16)**: camera sensor
  EEPROM + actuator probes fail (quality risk, needs stock DT data to
  fix), IPA/SMMU init failure (tether offload falls back to BPF — same
  on crDroid), display DT mismatches (benign).
- **Feature gaps vs stock**: CapSense/SAR sensors not exposed (missing
  SSC registry entries — fix path documented).

Everything fixable from the build tree is now installed by
`scripts/apply-latent-fixes.sh` (called by build.sh, LATENT_FIXES=0 to
skip); each fix has a verify step in `scripts/flash-checks.sh`.

---

## How the dumps were made / where they live

The debug script (`debug_device.sh`, ~820 lines, v3 from the October
research session) captures 35 sections: props, dmesg with per-subsystem
filters, all logcat buffers with per-feature greps, touch sysfs
(fts_* nodes, getevent, /proc/bus/input/devices), telephony
(carrier_config, telephony.registry, service_state, RIL props), thermal
zones, CPU governors, lsmod, modules.load, VINTF manifests, init rc
contents, SELinux denials, the full vendor inventory with labels
(`ls -lRZ /vendor`), and an optional SIM-1 call repro mode (`REPRO_SIM1=1`).
Redacted copies were shared; the originals stay with the owner.
