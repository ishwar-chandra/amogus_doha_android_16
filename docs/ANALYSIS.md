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

## 2. SIM 1 calls — root cause FOUND (modem carrier config fails on slot 0)

SIMs: **SIM 1 = Vi India** (mcc 404 / mnc 15, carrierId 2378, ICCID 89910…),
**SIM 2 = Jio** (405/871, carrierId 2018). User symptom: VoLTE works, data +
signal on both SIMs, SIM 2 calls fine, **SIM 1 outgoing calls fail**.

| Evidence | stock 10 (calls work) | crDroid 13 (calls work) | lineage16 (calls fail) |
|---|---|---|---|
| `persist.vendor.radio.mcfg_version` | `VODAFONE_IND_VOLTE,RJIO_IND` | (prop not present, older qcrild) | **`null,RJIO_IND`** |
| `persist.vendor.radio.mcfg_ver_num` | `0x08010809,0x08011B0C` | — | **`0,0x08011B0C`** |
| `gsm.network.type` (slot 0, slot 1) | `LTE,LTE` | `LTE,LTE` | **`EDGE,LTE`** |
| Vi voice/data reg (radio log) | — | `voice=LTE data=LTE IN_SERVICE` | voice=**GSM** HOME, data **OUT_OF_SERVICE** |
| IMS active sub | — | — | `vendor.ims.activesub=1` (Jio only) |

Mechanism: **qcrild failed to select a modem carrier configuration (MCFG)
for slot 0 (Vi)** on the Android 16 build — the prop is literally `null`
while slot 1 (Jio) matched `RJIO_IND` fine. Without the VODAFONE_IND_VOLTE
policy, the Vi SIM cannot do LTE/VoLTE properly, falls back to 2G (EDGE),
and calls on it fail (2G in this circle is patchy; PS data also out of
service). On stock the same SIM, same slot, same modem firmware selects
VODAFONE_IND_VOLTE and LTE/LTE. The MCFG database lives in the modem
partition (untouched by ROM flashes — `mcfg_hw.mbn`/`mcfg_sw.mbn` are
byte-identical), so this is a **qcrild userspace/selection issue**, not a
missing-file issue.

Likely mechanism: MCFG selection runs per-slot at SIM detection; on the
Android 16 boot, slot 0's selection ran before the Vi SIM's PLMN was
readable (or otherwise failed) and was never retried. Not yet reproduced
under controlled conditions.

**Status: no build-side fix shipped yet** — the fix needs one controlled
repro (see docs/SIM1-CALLS.md for the 15-minute test matrix; airplane-mode
toggle or a reboot is the expected workaround and may confirm the theory).
`scripts/flash-checks.sh` section 3 prints the state so every build now
logs it.

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
