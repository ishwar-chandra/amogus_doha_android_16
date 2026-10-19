# WORKLOG — doha-roms: complete project context

**Purpose of this file: preserve the ENTIRE work context of this project so
that any human or AI agent can pick it up at any point and continue without
re-deriving anything.** Read top to bottom once; afterwards the "Decisions"
and "Open items" sections are what you extend.

Everything below is chronological. "Result:" lines state what was
OBSERVED, not what was hoped. Known past errors are included on purpose
(see §B item 8 and §F) — they are the cheapest way to not repeat them.

---

## 0. The project at a glance (state as of 2026-10-18, after Session 9)

- **Device:** Motorola Moto G8 Plus, codename `doha`, build target
  `amogus_doha`, XT2019-1/2, Snapdragon 665 (trinket), 4 GB RAM,
  A/B slots, launched on Android 10 (API 29 / FCM level 5), vendor
  partition ~592 MB, unlocked bootloader.
- **This specific unit:** FPC 2.1 fingerprint variant (device-tree branch
  `2.1`), **FocalTech FT8719 touch panel** (not Himax — verified by
  `/sys/class/touchscreen/ft8719` on stock and `fts_*` sysfs nodes),
  PN553 NFC on `nq-nci`, dual SIM in DSDS: **SIM 1 = Vi India**
  (404/15, carrierId 2378), **SIM 2 = Jio** (405/871, carrierId 2018).
- **User's ROM history:** tried many custom ROMs; **crDroid 9.20
  (Android 13, from XDA, built by Aldair402's sources, kernel
  4.14.190+ 2025-01-15) was the most stable, "no bugs"**; then
  LineageOS 23.2 (Android 16) from christiaan's recipe (build
  2026-09-26, kernel 4.14.190+ #6); stock Android 10 also available and
  re-flashable. User flashed ALL of these and made device dumps of each.
- **Current deliverable:** this repo (`doha-roms`) = christiaan's proven
  Android 16 recipe + runtime-verified fixes (touch, post_boot FORTIFY
  crash + full latent-bug layer, CPU governor guard) + SIM 1 diagnosis
  + Dolby + GApps editions + a crDroid 17 bring-up kit. The complete
  defect inventory lives in docs/BUG-REGISTER.md (30 items). Build
  infra (GPU/Colab/Kaggle/GDrive) answered in docs/BUILD-INFRA.md; the
  build.sh path bug (would have silently applied 0 patches) was found
  and fixed on 2026-10-17 chat 4, with scripts/selftest-paths.sh as the
  regression test (15/15 PASS). **Since chat 6 (2026-10-17): ALL 27
  device-specific repos are vendored INTO the kit as git mirror
  tarballs at the exact pinned SHAs (`mirrors/`, 3.4 GB full set —
  15/27 upstreams are already ARCHIVED). build.sh auto-restores the
  mirror pool and repoints repo sync at file:// copies; after
  `bash doha.sh vendor`, no build step contacts the community
  upstreams. See docs/MIRRORS.md + §D5.**
- **Since Session 9 (2026-10-18):** a second Android 16 ROM base,
  **crDroid 12.x** (`crdroid-16/`, `bash doha.sh buildcr16`, menu 12), built
  from the same device projects, patches, latent fixes and variants.
  **All 17 patches are now verified** with `git apply --check` against the
  exact upstream commits for BOTH ROMs (crdroid-16/VERIFIED.md). Also fixed:
  restore-mirrors silently doing nothing on a read-only kit mount (the
  README's old Docker command), and the debloat calculator name. Nothing
  from Sessions 4-9 has been built or flashed yet. Caveat for the chat zip:
  it carries 23 of 27 mirror tarballs (the 4 largest are left out) - run
  `bash doha.sh vendor` once. See Session 9 at the end of this file.

## A. Session 0 — christiaan builds the base (2026-09-25/26)

Repo: `github.com/christiaan/lineage-23-amogus_doha` (13 commits, all on
those two days; no license; co-authored with claude).

1. Pinned manifest (1,184 projects: 873 AOSP on `android-16.0.0_r4`,
   284 LineageOS on `lineage-23.2`, 27 community: moto-common 15,
   Aldair402 8, AOSPA 3, ThankYouMario 1), 17 patches, `build.sh`
   (repo init/sync → reset+apply patches idempotently via a stamp file →
   empty `kernel-headers` file hack → `breakfast amogus_doha userdebug` →
   `mka target-files-package bacon` → copy zip+boot+dtbo+vbmeta).
2. Patch set summary (what each does — full table in the original README
   and `dumps/research/doha-rom-research/RESEARCH.md` §4): BPF
   kernel-version gates relaxed (4.14 on Android 16!), VINTF kernel
   requirement disabled (no 4.14 at FCM 5 in Android 16 matrices),
   kernel-headers shadowing fix, sepolicy dedup legacy-um vs newer qcom
   trees, libqsap_sdk prebuilt for qcrild, WPA3-SAE kernel cherry-pick,
   modules.load for haptics, fm@1.0 HIDL for BT HAL, fingerprint fps_id
   fallback, NFC 10 ms retry, QCC GPS removal, thermal HAL sensor names
   (`xo_therm`, no `soc`), SafetyNet patch from docker-lineage-cicd.
3. **Result:** the 2026-09-26 build BOOTS and runs on the phone. README
   claims tested-working: boot, calls+data (SIM), Wi-Fi incl. WPA3-SAE,
   BT A2DP+HID, NFC tags, GPS, fingerprint, vibration, camera, audio,
   charging. Not verified by author: VoLTE/IMS, BT HFP.
4. Build costs measured by author: 2 h 51 min clean on 16 threads/30 GB
   RAM; ~7 min warm ccache; needs 32 GB RAM + 32 GB swap (28+8 was
   OOM-killed); ~350 GB disk; ~100 GB download.

## B. Session 1 — the October research session (2026-10-07 to 10-15)

(Original artifacts: `dumps/research/doha-rom-research/` in the project
workspace — README, RESEARCH.md, WORKLOG.md, analysis/, scripts/, tests/.
Everything below is condensed from those.)

1. **Probed all 27 community repos**: all 15 moto-common ARCHIVED;
   AOSPA/ThankYouMario pinned to frozen `uvite`; Aldair402 bursty-active
   (Jan–Mar 2025, Jun 2026). Every community pin = branch tip at probe
   time. Kernel has 13 branches; branch `16` = branch 15 + 2 commits
   (kernel-headers `Android.bp`, unifdef constexpr rename) — the
   forward-looking work.
2. **LineageOS pin drift**: 44 of 311 GitHub-hosted pins moved; 2 patched
   projects moved (`hardware/nxp/nfc`, `system/core`) → re-pinning means
   rebasing those patches.
3. **Touch hypothesis (source-level, then unverified)**: kernel
   defconfig builds 3 touch suppliers — Himax built-in (`=y`) + FocalTech
   (`focaltech_0flash_mmi`, `focaltech_0flash_mmi_doha`) and Novatek
   (`nova_0flash_mmi`) as modules. LineageOS 20/crDroid 13 kernel.mk
   writes NO modules.load when the list is empty → init.modprobe.sh loads
   everything; LineageOS 23.2 ALWAYS writes modules.load → with only 4
   modules listed, touch modules never load. **This is now PROVEN by the
   dumps (session 2).**
4. **crDroid 17 verified to exist:** `crdroidandroid/android` branch
   `17.0`, AOSP `android-17.0.0_r1`, tracks `lineage-24.0` daily;
   breakfast lunches `lineage_<device>` so the doha product applies
   unchanged (untested). crDroid forks `system/core` and
   `packages/modules/Connectivity` → those patches must be re-targeted.
5. **LineageOS 24.0 released 2026-10-11** (Changelog 32): officially only
   ships kernels with 1:1 eBPF backports, GCC-free; 4.4/4.9 rejected
   outright; **4.14 still viable when maintained (SM8150 common kernel →
   Android 17; OnePlus 7 series in the 24.0 roster)**. RestlessOS 17 GSI
   carries Android-17 versions of the old-kernel relaxations — evidence
   the relax approach still works on 17.
6. **Built and tested an "overlay repo" generator** (`make-overlay.sh`
   v4, 22 trees baked with patches, 1,162-project manifest,
   verify-overlay.py 22/22, simulate-build 7/7). Not carried into
   doha-roms: this repo keeps christiaan's simpler patch-file approach
   (proven by a real build+boot) instead. The overlay machinery remains
   available in the research zip if pin drift forces a fork strategy.
7. **Produced `debug_device.sh` v3** (816 lines, 35 sections, guided
   feature tests, SIM-1 repro mode, redaction, analyzer) — tested against
   a simulated phone (12/12 checks). **The user then RAN IT ON THE REAL
   PHONE on all three ROMs** — those dumps are the foundation of
   everything in session 2.
8. Known ERRORS the research session made and corrected (kept here so
   nobody repeats them): claimed "no Novatek driver" (case-sensitive grep
   missed `NT36xxx` — Novatek exists); first `fix-touch.patch` was
   corrupt; first v3 `build.sh` doubled the zip name; `rom/crdroid.mk`
   concept was wrong (no ROM switch needed for crDroid).

## C. Session 2 — repo deep-dive + Android 17 feasibility (2026-10-17, chat 1)

1. Read christiaan's repo end-to-end (README, build.sh, default.xml,
   all patches). Confirmed the 17-patch structure, the BPF gate
   relaxations in detail (`NetBpfLoad.cpp` 4.9/4.14/4.19/25Q2 gates →
   warnings; `BpfHandler` same; `BpfNetMaps` null-map tolerance), kernel
   = Aldair402 msm-4.14 @ 6509e92, device trees pinned at branches
   2.1/16/14/15.
2. Researched current (Oct 2026) state: LineageOS 24.0 = Android 17,
   released 2026-10-11 (six days prior). Confirmed official kernel
   policy (above) and the SM8150-4.14-on-17 precedent.
3. Answer for the user: Android 16 works ✅; Android 17 on the SAME 4.14
   kernel is feasible via the same relax-the-gates approach (more gates
   to relax, more patches, progressive BPF feature loss); a NEWER kernel
   is not practical (vendor blobs are 4.14-ABI-bound); the proper
   long-term path is eBPF backports into 4.14 (the OnePlus 7 sm8150
   route), optional.
4. Aldair402's kernel `16` branch found active (Jun 2026) with the
   kernel-headers/Android.bp + unifdef fixes — community direction
   confirmed.
5. SIM 1 and touch: gave the swap-test and logcat diagnosis plan at
   chat level (the dumps then arrived — session 3).

## D. Session 3 — the three dumps + this repo (2026-10-17, chat 2)

**Inputs:** three device dumps (stock10, crdroid13, lineage16; see
docs/ANALYSIS.md for the full evidence tables) + the research zip +
the user's request: "create a completely new repo for everything patched
for Android 16 and Android 17 (crDroid), no-GApps/GApps editions with
safe debloating, Dolby Atmos, and a complete worklog."

1. **Touch: PROVEN.** modules.load exists on lineage16 with 4 modules and
   no touch driver loaded (fts nodes absent, Himax probes and fails);
   crDroid/stock have NO modules.load → load-everything → FocalTech
   driver bound → touch works. Fix shipped in
   `lineage-16/patches/device/motorola/amogus_doha.patch` (all 3 touch
   modules added; patch verified to apply cleanly against a mock of the
   original file).
2. **SIM 1: root cause FOUND.** `persist.vendor.radio.mcfg_version =
   null,RJIO_IND` on lineage16 vs `VODAFONE_IND_VOLTE,RJIO_IND` on
   stock; `gsm.network.type = EDGE,LTE` vs `LTE,LTE`; Vi CS=HOME on GSM
   but calls fail, PS data OUT_OF_SERVICE; IMS active only on Jio.
   qcrild's per-slot modem carrier config selection fails for slot 0 on
   the Android 16 build. NO build-side fix shipped (needs the 15-min
   confirmation test in docs/SIM1-CALLS.md first — expected outcome:
   airplane-mode toggle or reboot re-runs selection; then the fix is an
   init trigger or qcrild init ordering).
3. **CPU governor: NEW BUG.** All 8 CPUs pinned `performance`/max on
   lineage16 (CPU6 58 °C); schedutil on the working ROMs; vendor
   post_boot script is correct; suspect = new AIDL power HAL
   (power-libperfmgr from branch-16 device/motorola/common). Mitigation
   shipped: `variants/init.doha.cpugov.rc` (boot-completed guard +
   delayed second pass). Deeper fix documented in docs/CPU-GOVERNOR.md.
4. **Dolby: stock HAS the full stack** (libswdap 32+64, dax-default.xml,
   DMS service, codecs xml); custom ROMs ship none. Integration
   designed: user extracts own-firmware blobs once
   (`variants/dolby/extract-from-stock.sh`), build copies them into the
   vendor blob tree + wires audio_effects.xml/.conf
   (`wire-audio-effects.sh`, prefers the stock-extracted entry, verified
   working on a mock). DMS service deliberately deferred (needs
   sepolicy, untested). Marked experimental.
5. **Editions:** nogapps (default) / gapps (VARIANT=gapps → debloat
   tiers + MindTheGapps sideload at the "additional zip" prompt = Play
   services + Play Store only). Safe tier: Jelly, Twelve, Etar, Glimpse,
   Recorder, Calculator2 (+AudioFX when Dolby). Aggressive: + DeskClock,
   messaging, Contacts, Dialer (with warnings). Never-remove list with
   reasons (documentsui = system picker!, launcher, keyboard, camera,
   providers, emergency, updater…). Full rationale: docs/DEBLOAT.md.
6. **This repo assembled:** lineage-16/ (default.xml + build.sh + 17
   patches, all fetched from christiaan's repo; amogus_doha.patch
   extended with the touch fix; build.sh extended with VARIANT/DEBLOAT/
   DOLBY, variant layer appended after patches, stamp-aware), crdroid-17/
   (pinned crDroid manifests from the research zip + local manifest with
   the doha pins + re-target map + ordered plan), variants/, scripts/
   (flash-checks.sh — touch/governor/MCFG/Dolby in one pass), docs/ (5
   documents), this WORKLOG.
7. **Verification done so far (honest list):** patch applies cleanly to a
   mock of the original BoardConfig region; `bash -n` on all scripts;
   wire-audio-effects.sh tested on a mock tree (correct XML insertion);
   build.sh variant layer logic dry-reviewed. **NOT done:** a real
   `repo sync` + build (needs ~350 GB / 3 h), a flash, a boot. The touch
   fix is dump-proven but phone-unverified until the next flash.

## D2. Session 4 — the latent-bug hunt + fix layer (2026-10-17, chat 3)

**Input:** user: "I don't only want those bugs I discovered; I want all
those I still haven't discovered — analyse and patch all of them in our
new repo." A second, deeper triage of the same three dumps (only
lineage16 has kernel-level logs — root at dump time — so kernel evidence
is lineage16-only; userspace compared across all three).

**Method:** crash tombstones + dropbox → all 343 avc denials categorized
by comm/scontext → every dmesg error line → per-subsystem logcat greps →
sensor inventories (dumpsys sensorservice) → thermal zones diff → fstab
vs fsck denials → property-set denials with file attribution → sensor
config dir listing (the smoking gun) → post_boot script source reading.
Cross-verified type visibility against the real LineageOS
`sepolicy_vndr` lineage-23.2-legacy-um branch (fetched 2026-10-17) before
writing any sepolicy rule.

**Findings — full register in docs/BUG-REGISTER.md (30 items). Headlines:**

8. **post_boot FORTIFY SIGABRT — THE headline bug.**
   `/vendor/bin/sh` (Android-10-era mksh) + Android 16 bionic (APEX) →
   deterministic abort inside the echo/print builtin (c_print →
   __write_chk), process uptime 0s, at EVERY boot (bogus-RTC timestamps
   initially disguised it as 3 weeks old). The 6334-line trinket tuner
   dies before writing anything: schedutil, hispeed/min freqs, core_ctl,
   sched migrations, sched_load_boost, DDR bw_hwmon+mbps zones, memory
   params, input boost, readahead. **Retires the power-HAL theory for the
   governor bug and explains the heat/battery gap vs crDroid 13** (same
   script runs fine on the Android 13 libc). Fix: re-point the service at
   `/system/bin/sh` (content-searched sed in apply-latent-fixes.sh so it
   survives tree-layout changes; cpugov.rc guard kept as backup).
9. **Sensor variant config bind-mount DENIED** (5 avc denials; amogus-sh
   lacks sys_admin/mounton/ioctl on vendor_sensor_data_file):
   `/vendor/etc/sensors/config` runs EMPTY (stock: 40+ JSONs; variant
   dirs config-doha/-rav/-sofia/-sofiar exist but never mount). Missing
   Orientation virtual sensors (47 vs 49 h/w sensors on crDroid 13),
   zero sensor tuning. Fix: B1 in doha_amogus_fixes.te.
10. **8 more denial families FIXED** (all dump-proven):
    USB HAL port_type writes (20+ denials = OTG/role switch degraded),
    rild denied /mnt/vendor (persist — SIM-relevant), vold denied
    /mnt/product, fsck denied on modem+prodpersist partitions (latent
    corruption risk), BT HAL vendor_mot_prop read, camera HAL
    default_prop read, modprobe /proc/cmdline, init sys_ptrace (goes away
    with #8). Two more are cross-version and documented, not fixed
    (system_suspend→sysfs_batteryinfo — 117 denials but system↔vendor
    type boundary, crDroid 13 has it too; installd quotaget — noise).
11. **Legacy vendor props silently failing at every boot** — vendor_init
    denied setting 6 system-labeled props. FIXED by re-labelling the two
    that matter: `ril.subscription.types` → vendor_radio_prop (qcrild
    per-slot subscription config — possibly the SIM 1 missing piece) and
    `persist.debug.wfd.enable` → vendor_default_prop. The other four are
    Android-16 NO-OPs (bluetooth.profile.tbs/vc = framework defaults,
    ro.lmk.threshold_decay = lmkd no longer reads it, hdmirotationlock =
    demo prop) — documented.
12. **ro.product.bevice typo** in /vendor/build_doha.prop — auto-fixed by
    the applier wherever it lives in the tree.
13. **Kernel-level findings (apply to BOTH custom ROMs, need kernel/DT
    work, DOCUMENTED not fixed):** camera sensor EEPROM + actuator probes
    fail (quality risk; fix needs stock DTB eeprom nodes — capture
    /proc/device-tree on stock next time), IPA/SMMU bus registration
    failure (tether offload already falls back to BPF, same on crDroid),
    display DT mismatches (backlight parse, vbif_nrt/sid, SSPP feature
    map, rotator bus client — display works, cosmetic), stune/nnapi-hal
    cgroup exhaustion (Android 16 init vs 4.14 kernel cgroup API —
    expected kernel-generation gap), msm-dai-tdm sen probe failures
    (unused interfaces), CapSense/SAR sensors not exposed vs stock
    (missing SSC registry entries; sx933x module loads but no sensor).
14. **Also retired/verified this session:** thermal zone sets are
    IDENTICAL across the three ROMs (61 zones each — earlier BCL worry
    downgraded); zram configured on all three (1 GB); IO scheduler cfq
    is the kernel default on both custom ROMs (not a post_boot loss);
    GPS/BT/vibrator/IMS-framework states clean; crDroid 13's own
    denials are dominated by the debug tool itself + system_suspend.

**Deliverables added this session:**

- `latent-fixes/doha_amogus_fixes.te` (B1-B5), `latent-fixes/
  doha_qcom_fixes.te` (B6-B10), `latent-fixes/property_contexts.add`
- `scripts/apply-latent-fixes.sh` — portable, idempotent installer
  (content-searched interpreter fix + new-file sepolicy drops +
  marker-checked property_contexts append + typo fix); tested on a mock
  tree, both first and second run correct
- `lineage-16/build.sh` calls it (LATENT_FIXES=0 to skip)
- `scripts/flash-checks.sh` extended to 7 sections (post_boot evidence
  via hispeed_freq, OTG, sensor config + Orientation, denial
  signatures, tombstone check)
- `docs/BUG-REGISTER.md` — the 30-item register (the user's "all the
  bugs I haven't discovered" deliverable)
- docs/ANALYSIS.md §6, CPU-GOVERNOR.md re-root-caused, SIM1-CALLS.md
  updated (two new build-side fixes to test), crdroid-17/README.md
  carries the latent-fixes step + sepolicy-compile caveat

**Honest verification status:** everything above is dump-proven and
mock-tested, still phone-unverified (no build machine). The sepolicy
rules reference types verified to exist on the lineage-23.2-legacy-um
and moto amogus trees (web-checked 2026-10-17); if a type moves on a
future branch, the .te blocks are independent and deletable.

## D3. Session 5 — build.sh path-bug fix + cloud build infra (2026-10-17, chat 4)

**Context:** the user asked whether to build on Google Colab / Kaggle
with GPU instead of CPU (5 TB GDrive available). Answering that surfaced
a real bug in our own tooling.

**Found and fixed a critical path bug in `lineage-16/build.sh`:**
`PATCHDIR` was computed as `$HERE/lineage-16/patches` and the whole
variant layer as `$HERE/variants/...` — both only resolve if the script
sits at the repo ROOT. It ships in `lineage-16/`, so on a real machine
the script would have **silently applied ZERO of the 17 patches and
skipped the entire variant layer** (the earlier mock test had replicated
the wrong layout, which is why it passed). The SIM 1 telephony fixes
from Session 4 would also have been skipped (`apply-latent-fixes.sh`
was, however, referenced correctly via `$HERE/../scripts/`). Fixes:

- `PATCHDIR="$HERE/patches"`; all `$HERE/variants/...` →
  `$HERE/../variants/...` (9 references)
- layout self-check at script start: hard-fails unless
  `lineage-16/patches/`, `variants/`, `latent-fixes/` and
  `scripts/apply-latent-fixes.sh` are all where the script expects them
- patch-discovery assert: refuses to build if 0 patches are found
- **new `scripts/selftest-paths.sh`**: runs the REAL `build.sh` from its
  REAL location against a mock source tree (17 git project stubs,
  pre-stamped so patch contents aren't re-applied) and asserts 15
  path-dependent outcomes — patch discovery, latent-fixes invocation,
  cpugov rc copy, device.mk/product.mk hooks, doha-variants.mk render,
  stamp write, kernel-headers guard. PASSED. Run it after any future
  `build.sh` edit.

**Cloud build infrastructure (the user's question, preserved as docs):**

- `docs/BUILD-INFRA.md` — the full answer: NO GPU compiles AOSP
  (Soong/ninja/clang/lld/javac have no GPU back-ends; Kaggle GPU
  sessions even have FEWER vCPU than CPU sessions; Colab A100 burns
  ~8-11 CU/h for an idle GPU), what the build actually needs
  (cores/RAM/NVMe/ccache), per-platform feasibility table, the Colab
  snapshot-checkpoint workflow, correct vs wrong uses of the 5 TB
  Google Drive (archive: snapshots/ccache/releases — never the live
  build disk, it's a network FUSE bridge), and the ranked plan:
  **Crave (proven for doha — crDroid 13 came from there) → own PC →
  rented VPS → Colab Pro last resort**.
- `cloud/colab_doha.sh` — Colab CPU (High-RAM) session wrapper:
  environment guards (≥4 vCPU, ≥200 GB), deps, source-restore from
  GDrive zstd snapshot else shallow sync (`repo init --depth=1`),
  ccache restore, build via `lineage-16/build.sh SKIP_SYNC=1`, then
  releases + rotating snapshots back to GDrive. `TARGET=kernel` and
  `TARGET=android17-sync` modes for smaller jobs. bash -n clean; it
  needs a real Colab session to be fully exercised (template status:
  paths and flow verified, cloud behaviour not).
- README.md: layout tree + a "Building in the cloud" section pointing
  at both; `selftest-paths.sh` mentioned after the options list.

**Verification status:** selftest-paths.sh PASSED on this machine
(15/15 assertions); colab_doha.sh syntax-checked only (no Colab
session was available); BUILD-INFRA.md numbers are approximate
cloud specs — re-check quotas before relying on them.

## D4. Session 6 — doha.sh, the ultimate interactive entry point (2026-10-17, chat 5)

**Input:** user: "I want an ultimate script that does everything for
me. I don't want to manually run patches — the script must handle
everything. I just use the interactive terminal option."

**Built `doha.sh` (repo root) — one interactive menu for the whole
project.** The design point the user cares about: patches, the
latent-fix layer and the variant layer are applied AUTOMATICALLY by
`lineage-16/build.sh`; the menu only collects choices, then runs it.

- Menu: 1 setup/env-check (also offers `git init` + commit when the
  repo came from a zip — `repo init` requires a committed
  `default.xml`), 2 sync-only (new `STOP_AFTER_SYNC=1` hook in
  build.sh — added this session), 3 BUILD Android 16 (variant →
  debloat → Dolby prompts, then the full automatic pipeline),
  4 kernel-only, 5 Android 17 bring-up (automates crdroid-17/README
  steps 2-4+6-7: pinned or fresh manifest init, local_manifest_doha
  copy, sync, `repo manifest -r` pins, the as-is touch patch, latent
  fixes, optional `mka bacon`; the 16 patch re-targets stay
  documented-manual), 6 ONE-SHOT setup+sync+build, 7 selftest,
  8 flash assistant (sideload with zip picker, fastboot flash boot
  with confirm, post-flash checks, brick-safety notes), 9 debug dump
  (light/full/SIM1-repro modes → debug_device.sh), 10 cloud-build
  facts. 0 = exit.
- Non-interactive equivalents for power users: `status env sync
  build16 kernel build17 oneshot selftest flash dump cloud help`,
  `build16 --variant gapps --debloat safe --dolby --jobs N --src PATH`.
- Settings persist in `.doha.conf` (SRC/SRC17/ZIP_DIR/
  CCACHE_DIR/JOBS/VARIANT/DEBLOAT/DOLBY). Every action is logged to
  `logs/doha-*.log`.
- Fixed while wiring it: a `DEBLOAD`→`DEBLOAT` env-name mismatch in
  the non-interactive `build16` path and in `cloud/colab_doha.sh`
  (build.sh ignores unknown env names, so gapps builds would have
  silently built with the wrong debloat tier). Probed build.sh's own
  validator to confirm the true name, then repaired both scripts and
  grepped the whole repo clean.

**Verification on this machine:** bash -n both scripts; selftest
15/15 PASS (also via menu item 7, piped); `doha.sh status`, `help`,
menu render + cloud + exit (piped) all correct; `build16` dispatch
probe reaches build.sh cleanly (fails only at `repo:` missing here —
expected, this box has no repo tool); `STOP_AFTER_SYNC` hook placed
after the sync block (repo-missing failure proves the path order).
NOT exercised: a real sync/build (needs a build machine), the flash
and dump paths (need a phone), Colab behaviour.

**Repo hygiene:** `.doha.conf`, `logs/`, `.selftest-mock/`,
`crdroid-17/my-pins.xml` are runtime artifacts — excluded from the
shipped zip.

## E. Consolidated bug/feature state

| Item | State | Next step |
|---|---|---|
| Touch | fix shipped (dump-proven) | flash + flash-checks.sh §1 |
| post_boot crash (all tuning lost) | fix shipped (interpreter swap) | flash + flash-checks.sh §2 (hispeed_freq=1305600) |
| SIM 1 (Vi) calls | cause found + 2 new build-side fixes shipped (B6 + prop relabel) | flash new build first, then docs/SIM1-CALLS.md 15-min test |
| CPU governor/heat | ROOT-CAUSED to post_boot crash; guard kept as backup | flash + flash-checks.sh §2 |
| Sensor config empty + Orientation missing | fix shipped (B1) | flash + flash-checks.sh §6 |
| USB OTG role switch | fix shipped (B9) | flash + flash-checks.sh §5 (OTG adapter test) |
| Latent avc denials (B1-B10) | fixes shipped | flash + flash-checks.sh §7 |
| Camera EEPROM/actuator, IPA/SMMU, display DT, CapSense | DOCUMENTED (kernel/DT work, need stock DT data) | capture /proc/device-tree on stock, see BUG-REGISTER #21-23/#27 |
| Dolby | integration shipped, experimental | extract blobs → DOLBY=1 build → listen |
| GApps editions | shipped | build + sideload MindTheGapps |
| Android 16 overall | = base recipe (works) + fixes above | rebuild once, flash, verify |
| Android 17 (crDroid) | bring-up kit only + latent-fixes layer to carry over | follow crdroid-17/README.md steps in order |
| LineageOS pin drift | 44/311 moved (2 patched) | re-pin + rebase nfc & system/core patches when next syncing |

## F. Decisions log (why things are the way they are)

1. **Patch-file approach (not overlay/fork trees)** — the base recipe
   produced a booting build with patches; the overlay approach (research
   session) was verified only in simulation. Simplicity + proof wins.
2. **Touch fix = add 3 modules to modules.load** (not delete
   modules.load) — explicit listing is what LineageOS 23.2's kernel.mk
   supports; loading all 3 touch drivers copies the working ROMs' state;
   mismatched drivers simply don't bind.
3. **GApps = sideload, not embedded** — MindTheGapps updates
   independently; embedding Google code in a distributable zip is a
   licensing problem; GApps integration bugs are the top cause of
   first-boot loops. The recovery literally asks for the extra zip.
4. **Debloat via PRODUCT_PACKAGES filter-out** at the END of
   `lineage_amogus_doha.mk` (via the variant hook) — must run AFTER the
   ROM's common config adds the apps. Wrong module name = app stays =
   safe failure. documentsui/launcher/keyboard/camera/providers are
   never removable (docs/DEBLOAT.md).
5. **Dolby = own-firmware blobs + build-time audio_effects wiring** —
   the device's own stock firmware is the only properly-licensed blob
   source; the wiring script prefers the stock-extracted XML lines over
   remembered UUIDs. DMS service deferred (sepolicy untested).
6. **SIM 1 = no blind fix yet** — the cause is proven but the mechanism
   (selection race vs persistent state) isn't; the 15-minute test
   decides between init-trigger vs qcrild-ordering fix. Wrong guess =
   wasted build.
7. **CPU governor = init guard first** — one rc file, zero risk, fixes
   the symptom even if the HAL misbehaves; the powerhint.json fix is
   documented for when the guard proves insufficient.
8. **crDroid 17 = separate directory, NOT a build target yet** — nothing
   on Android 17 for doha exists anywhere; shipping it as "working"
   would be a lie. The kit + ordered plan + re-target map is the honest
   deliverable. The lineage-16 target is the stable base it builds on.
9. **WORKLOG.md is append-only and honest** — including past errors
   (§B8): the cheapest way to prevent repeats.

## G. Open items (priority order)

0. **Decide the build machine** (docs/BUILD-INFRA.md §7): Crave first
   (the proven free route for doha — adapt the craving recipe to call
   `lineage-16/build.sh`, it is already idempotent/incremental); own PC
   (8+ cores / 32 GB / 500 GB) or a ~$0.3-0.8/h VPS for the iterate-
   flash-dump loop; Colab CPU High-RAM only as last resort
   (`cloud/colab_doha.sh`). Push this repo to GitHub first — `repo init`
   requires the manifest repo to be a git repo with `default.xml`
   committed (see README "Building"). Use the 5 TB GDrive as the
   archive (snapshots/ccache/releases), never the live build disk.
1. **Rebuild lineage-16** with this repo (start: `VARIANT=nogapps`),
   flash, run `scripts/flash-checks.sh` (all 7 sections) → confirm
   touch, post_boot tuning (hispeed_freq), governor, sensor config,
   Orientation sensors, denial signatures gone.
2. **Run the SIM 1 test** (docs/SIM1-CALLS.md) on the NEW build — the
   latent fixes (rild /mnt/vendor + ril.subscription.types) may already
   close it; 15 minutes decides.
3. `VARIANT=gapps` build + MindTheGapps sideload → verify debloat list
   matched (pm list packages vs docs/DEBLOAT.md tables).
4. `variants/dolby/extract-from-stock.sh` on stock (once) → `DOLBY=1`
   build → listen + flash-checks §4.
5. Capture `/proc/device-tree` (camera eeprom/actuator nodes) from
   STOCK with root → enables the BUG-REGISTER #21 kernel DT fix.
6. If governor still pinned after the post_boot fix: powerhint.json
   investigation (docs/CPU-GOVERNOR.md) — now considered unlikely.
7. crDroid 17 bring-up (crdroid-17/README.md steps, incl. step 6:
   latent-fixes) — only after 1-4.
8. When re-syncing: handle the 44 moved LineageOS pins + rebase the
   `hardware/nxp/nfc` and `system/core` patches. (2026-10-18: the nfc patch
   still applies to today's lineage-23.2 head 1459e3f2, and the system/core
   patch applies to crDroid's fork head; LineageOS's own system/core head
   was not checked.)
9. Consider eBPF backports into msm-4.14 (the OnePlus-7-sm8150 route)
   only if BPF feature loss becomes a real problem on 16/17.
10. After first flash of the fixed build: re-grep denials — any NEW
    prop-set denials on Android 16 get the same property_contexts.add
    treatment (pattern documented in BUG-REGISTER #20).
11. **crDroid 12.x (Android 16) first build**: `bash doha.sh buildcr16`
    (crdroid-16/README.md lists what can go wrong; the likeliest first
    failures are Soong/Make differences in crDroid's build/make + build/soong
    forks, then a sepolicy block in latent-fixes/). Do it after item 1 so the
    LineageOS build is the known-good reference, or in parallel on Crave.
12. **Complete the mirror pool**: the chat zip omits the 4 largest
    tarballs (kernel 1.5 GB, Qualcomm proprietary blobs 1.4 GB, clang
    prebuilt 259 MB, Motorola vendor blobs 116 MB). `bash doha.sh vendor`
    (menu 11) re-fetches them in 10-15 min; then archive the FULL set
    (GitHub history or the GDrive). Until then those upstreams are the
    only copy - the clang prebuilt comes from the archived moto-common org.
13. Docs/debloat: confirm after the first gapps flash that the calculator
    is gone (module name fixed to ExactCalculator in Session 9).

## H. Where things live (map for future agents)

- **This repo** (`doha-roms/`): the deliverable — see README.md layout.
- **Workspace** (`/home/z/my-project/` on the build chat machine):
  `dumps/` (the three extracted device dumps + `research/doha-rom-research/`
  with the full October research artifacts), `repo_files/` (fetched
  copies of christiaan's README/build.sh/manifest/patches used as the
  base), `doha-roms/` (this repo pre-packaging), `upload/` (the user's
  originals: dump tarballs, research zip, screenshot, debug_device.sh).
- **Upstream:** christiaan/lineage-23-amogus_doha (base recipe);
  Aldair402/* (kernel, device trees, vendor blobs, crave_aosp_builder);
  moto-common/* (archived device bits); crdroidandroid/android (17.0).
- **The user's phone:** the only test device. The user flashes, runs
  flash-checks.sh, and reports back. Treat it as precious: A/B slot
  discipline, stock firmware always at hand, no experiments without a
  known-good zip on the PC.

## I. Conventions for extending this repo

- Extend `WORKLOG.md` (append a new session section) with every
  substantive change; update §0 (at-a-glance) and §G (open items) in
  place.
- Every claim in docs/ carries its evidence (dump file + what was
  measured). If you verify something on the phone, mark it
  "phone-verified <date>".
- Patches: one file per project under `lineage-16/patches/`; test with
  `git apply` against a mock before shipping; keep the hunk headers
  exact (git apply is strict).
- New variants: env var + template in `variants/` + render in
  `build.sh` `render_variants_mk` + doc in `docs/`. Never remove from
  the never-remove list.
- Be explicit about what is verified vs not. The credibility of this
  repo rests on that distinction.
- ROM-specific patch differences go in `crdroid-16/patches/<project>.patch`
  (an overlay that replaces the same-named lineage-16 patch) — never a
  copy of the whole set. `ROM_TARGET` (lineage16|crdroid16) is the only
  switch build.sh knows about; each ROM gets its OWN source tree.

---

## D5. Session 7 — vendoring ALL 27 device repos into the kit (2026-10-17, chat 6)

**Input:** user: "I want to create a complete kit repo, but all code in
one. This repo is not referenced or pinned. Is it ok to clone all that
pinned source code into a new all-in-one repo or leave it the same as
pinned, and tell me if those pinned repos are still being updated by
the developer constantly or have stopped... Also included those are
archived."

**Live upstream audit (2026-10-17, ls-remote + atom + page probes):**
- all 27 device projects still EXIST; **every pin is the branch tip**
  (`PIN=tip` 27/27 — upstreams have not moved past our pins)
- **15 of 27 are ARCHIVED** — the entire `moto-common` org was archived
  on 2026-04-04 (read-only, owner-deletable at any time)
- still active: Aldair402 (kernel/common last touched 2026-06), AOSPA
  (uvite), ThankYouMario (proprietary qcom, 2026-09-03)
- christiaan's repo: base-recipe credit only, never fetched by builds

**Decision — hybrid self-containment (docs/MIRRORS.md):**
1. the 1,157 platform pins (LineageOS/AOSP) stay pins — permanent infra,
   ~200 GB, monorepo would break the repo-tool/Soong build model
2. the 27 FRAGILE device repos are now cloned INTO the kit as
   self-contained git mirror tarballs at the exact pinned SHAs

**Built and verified this session:**
- `scripts/vendor-mirrors.sh` — fetches each pinned commit + reachable
  history into a bare repo, tars to `mirrors/repos/<name>.tgz`, writes
  per-repo `.fact` + merged `mirrors/MIRRORS.tsv`. Resumable, 3x retry,
  crash-safe (per-repo facts). **Ran it: 27/27 mirrored, 0 failed,
  3.4 GB** (kernel 1483 MB, proprietary qcom blobs 1430 MB, clang 259
  MB, moto blobs 116 MB, 23 small repos ~105 MB).
- `scripts/restore-mirrors.sh` — untars the pool into `mirrors/git/`,
  sets `uploadpack.allowAnySHA1InWant`, generates
  `$SRC/.repo/local_manifests/doha-mirror.xml` (remove-project + re-add
  pointing at `file://` mirrors, same SHAs).
- `lineage-16/build.sh` — auto-calls restore-mirrors between repo init
  and repo sync whenever mirrors exist (zero manual steps; falls back
  to upstream with a warning if restore fails).
- `doha.sh` — new menu 11 `vendor` (+ `vendor` CLI command) + "device
  mirrors" line in status + sync banner.
- **Verification:** mirror-fetch == upstream-fetch bit-for-bit
  (`diff -r` clean) on amogus_doha; kernel mirror serves the exact
  pinned SHA 6509e92 with all 71,143 files. selftest-paths.sh still
  15/15 PASS after the build.sh change. All scripts `bash -n` clean.
- `.gitignore`: `mirrors/git/` (generated) + `mirrors/vendor.log`
  ignored; `mirrors/repos/*.tgz` + `MIRRORS.tsv` ARE committed.
- `docs/MIRRORS.md` — why/how/sizes/legal note (proprietary blobs →
  keep repo private or strip mirrors/), pin-refresh procedure.

**Delivery:** chat zip carries the kit WITHOUT the 4 monster tarballs
(>100 MB each; ~95 MB zip) — `bash doha.sh vendor` regenerates just
those in ~10-15 min. Full set for GitHub: commit mirrors in 3 separate
commits (kernel / proprietary / rest) and push after each (2 GB
per-push pack limit).

**Not verified:** a real `repo sync` against the pool (needs 350 GB
disk + the full platform sync — happens on the build machine); the
GitHub 3-commit push flow (user does it once).

---

## Session 8 (2026-10-18) — the full dry-run battery

**User question:** "have you tested everything on dry run?"

**Honest answer at the time: no.** Covered before: selftest-paths
(15/15), vendor-mirrors (real 27/27 run), restore-mirrors (partial +
bit-for-bit), apply-latent-fixes (mock, idempotent). NOT covered:
colab_doha.sh (bash -n only), flash-checks/debug_device arg paths,
doha.sh subcommand dispatch, and — biggest gap — build.sh's
init→mirror-restore→sync wiring (selftest-paths runs with SKIP_SYNC=1,
so that branch had never executed in a test).

**Built `scripts/selftest-dryrun.sh`** — 97 assertions, 10 sections,
runs with NO network / phone / repo tool / AOSP tree / free disk
(sandbox + repo stub + tarball CRC instead of 3.4 GB extraction):

* S1 syntax (bash -n ×9), S2 all 5 XMLs parse
* S3 mirror store: 27/27 tarballs present, gzip CRC intact, .fact
  shas == default.xml pins, MIRRORS.tsv == .facts (no drift)
* S4 restore-mirrors sandbox: XML generated/well-formed/3+3 entries,
  pinned SHAs present, uploadpack + fetch-by-SHA over file:// works
  (the exact mechanism repo sync uses), idempotent, clean no-.repo
  failure
* S5 build.sh with a `repo` STUB: proves ordering init→restore→sync,
  STOP_AFTER_SYNC exit, and the fallback-to-upstream branch when
  restore fails
* S6 every doha.sh subcommand + menu loop: correct output, graceful
  failures without repo/adb, vendor resume no-op, no data drift
* S7 selftest-paths 15/15 · S8 latent-fixes mock idempotency
* S9 phone scripts fail cleanly without adb · S10 colab guard

**Two real bugs found & fixed:**

1. `doha.sh sync` (and every prompting subcommand) faked success when
   piped: the internal `confirm` hit EOF → "no" → silent skip → exit 0.
   On a real machine that would mask a failed 150 GB sync. Fix: any
   explicit subcommand now runs in batch mode (prompts auto-proceed,
   failures exit non-zero); the interactive menu is unchanged; `flash`
   REFUSES batch mode (destructive → needs a human at a terminal).
2. debug_device.sh created the dump directory before resolving adb —
   a missing adb left a stray empty dir. Adb resolution moved first.

**Wiring:** `doha.sh selftest` (menu 7) now runs BOTH suites; status
line shows both; `.selftest-dryrun/` gitignored.

**Result:** 97/97 PASS. Still not dry-runnable by design: the real
repo sync of 1,157 platform projects, Soong compile, phone flash/dump
paths, and the actual Colab session — those need the build machine,
the phone, and a Colab runtime respectively.


## Session 9 (2026-10-18) — crDroid 12.x (Android 16) as a second ROM base ← CURRENT

**Request:** "i want crdroid android 16 as well" (in addition to the
LineageOS 23.2 target and the crDroid 17 bring-up kit).

**What was found (read from the sources, not assumed):**

- crDroid has a maintained Android 16 branch: `crdroidandroid/android`
  `16.0` (also `16.0-qpr0`, `16.0-qpr1`). Head `7aeb04f9` on 2026-10-18;
  `vendor/crdroid config/version.mk` says v12.13. It uses AOSP
  `android-16.0.0_r4` and default branch `lineage-23.2` — the base of the
  proven LineageOS build. `breakfast <device>` lunches `lineage_<device>`,
  so `lineage_amogus_doha` applies unchanged. `LINEAGE_VERSION` =
  `crDroidAndroid-16.0-<date>-<build>-v12.13`; `bacon` MOVES the zip to
  `$OUT/$LINEAGE_VERSION.zip` and DELETES `target_files_intermediates`.
- Manifest comparison (LineageOS pinned manifest 1,184 projects vs crDroid
  merged 1,182): the only path collision with the 27 doha projects is
  `external/fastrpc` (AOSP's vs the AOSPA fork) → `remove-project`; only 2
  LineageOS-manifest projects are absent from crDroid (`google-sans-flex`,
  `packages/overlays/Lineage`); 26 extras (crDroid apps, newer SoC dirs, darwin
  prebuilts). `vendor/qcom/opensource/data-ipa-cfg-mgr-legacy-um` (LineageOS)
  and the doha `...-legacy` fork both declare a `soong_namespace`, so no
  duplicate-module clash is expected. crDroid forks `build/make`,
  `build/soong`, `system/core`, `packages/modules/Connectivity`,
  `device/lineage/sepolicy` (→ android_device_crdroid_sepolicy), `vendor/lineage`
  (→ android_vendor_crdroid). Only `FaceUnlock` comes from gitlab.com.
  The relative `github` remote (`fetch=".."`) had to become absolute: it
  resolves against the manifest repo URL, which here is a local path.
- **Patches (the key finding):** all 17 `git apply --check` clean on the
  exact commits — EXCEPT `packages/modules/Connectivity` on crDroid's fork
  (NetBpfLoad.cpp, BpfHandler.cpp). Reason: crDroid's fork already contains
  the same kernel-gate relaxations (4.9/4.14/4.19/5.4 as warnings, no gates in
  BpfHandler). Only the BpfNetMaps.java hunks (10) are still needed →
  `crdroid-16/patches/packages/modules/Connectivity.patch`. Full record with
  commits: `crdroid-16/VERIFIED.md`. This also closed a gap for the
  LineageOS target: 9 of its 17 patches had only ever been tried on mocks;
  all 17 now apply to their exact pins (device repos via the mirrors, the
  3 too-large repos via the touched files at the pinned SHA, platform repos
  via codeload at the pinned SHA).

**What was built (all in this repo):**

- `crdroid-16/default.xml` — ONE self-contained manifest generated by
  `crdroid-16/refresh-manifest.sh` (crDroid 16.0 + snippets inlined +
  absolute github remote + the 4 community remotes + the 27 doha projects
  copied verbatim from the root manifest + the fastrpc remove-project);
  1,208 projects; the generator self-checks repo-style processing.
- `lineage-16/build.sh`: `ROM_TARGET=lineage16|crdroid16`, `MANIFEST_FILE`,
  `PATCH_OVERLAY` (union of patch names; overlay file wins), `ZIP_PREFIX`,
  product-dir fallback for boot/dtbo/vbmeta, crDroid debloat addition,
  records `<src>/.repo/doha-crdroid16-pins.xml` after each crDroid sync,
  refuses a manifest that is not committed (`repo init` reads the committed
  branch). Defaults reproduce the old LineageOS behaviour exactly.
- `doha.sh`: `--rom lineage|crdroid`, `buildcr16`, menu 12, separate source
  dir `SRCCR16` (default `~/doha/src-crdroid16`; `save_conf` never overwrites
  the LineageOS `SRC`), status line, setup now checks BOTH manifests are
  committed, selftest runs the new suite. Menu numbers 1-11 unchanged.
- `variants/debloat-crdroid.mk` (Gallery2); `scripts/selftest-crdroid16.sh`
  (25 assertions: manifest soundness, overlay validity, real build.sh with
  `ROM_TARGET=crdroid16` on a mock tree incl. proof the overlay patch is the
  one in effect, debloat rendering both ways, bad ROM_TARGET refused).

**Bugs found in the existing kit and fixed (flagged because they change
documented behaviour):**

1. `restore-mirrors.sh` on a read-only kit (the README's Docker command
   used `-v "$PWD:/manifest:ro"`): it exited 0 having restored ZERO mirrors
   and wrote a local manifest that removed the upstream entries and pointed
   them at folders that do not exist → `repo sync` would have failed for 23
   device repos. Reproduced with a mock (unprivileged user, read-only kit).
   Fix: exit 1 with a clear message when `mirrors/git` is not writable
   (build.sh then falls back to upstream, per its existing handling) and the
   README command no longer uses `:ro`.
2. `variants/debloat.mk` filtered `Calculator2`, but LineageOS 23.2 and
   crDroid add the calculator as `ExactCalculator` (checked in
   vendor/lineage config/common.mk) → the safe tier silently kept the
   calculator although docs/DEBLOAT.md lists it as removed. Both names are
   filtered now. This changes the gapps+safe edition (calculator removed).
3. This file: the `§D6` pointer had no target (past errors are in §B item 8 /
   §F), the CURRENT marker and §0 snapshot were stale, and the mirror-tarball
   caveat lived only in Session 7's delivery note.

**Test status (2026-10-18):** selftest-paths 15/15; selftest-crdroid16 25/25;
dry-run battery **94 passed, 7 failed — identical to the baseline run of the
shipped chat zip before any change**. The 7 are all caused by that zip
omitting 4 mirror tarballs (4 "missing tarball", "27 of 27 present", and the
vendor-resume check that times out re-fetching them); they pass once
`bash doha.sh vendor` has run. The earlier "97/97" was for a full-mirror kit.

**NOT verified:** a real `repo sync` of the crDroid tree, the Soong/Make
compile on crDroid's build forks, the sepolicy compile against
android_device_crdroid_sepolicy, boot, and anything on the phone. A quick web
search found no crDroid 12 build for doha (not exhaustive).

**Next:** §G items 0-4 (LineageOS build + flash + flash-checks) remain the
priority; then item 11 (first crDroid 16 build) and item 12 (complete the
mirror pool).
