# doha-roms: stable custom ROMs for the Motorola Moto G8 Plus (doha)

> **Just want to build? Run ONE command:** `bash doha.sh`
>
> It opens the interactive menu - setup, source sync, build (with all 17
> patches, latent-bug fixes and variants applied AUTOMATICALLY - you never
> run a patch manually), kernel-only builds, the crDroid 12.x (Android 16)
> build, the Android 17 bring-up,
> self-tests, the flash assistant, post-flash checks, debug dumps and
> cloud-build guidance. Everything is menu-driven; every action is logged
> to `logs/`. Power users: `bash doha.sh help` for the non-interactive
> commands (`build16 --variant gapps`, `buildcr16`, `sync`, `selftest`, ...).

Everything needed to build, verify and improve **LineageOS 23.2 (Android 16)**
and **crDroid 12.x (Android 16)**, and to start a **crDroid 17 (Android 17)**
port for the Moto G8 Plus
(`doha`, XT2019-1/2, Snapdragon 665/trinket, `amogus_doha` build target),
based on a proven recipe and **runtime-verified fixes** from three device
dumps.

Base credit: **christiaan/lineage-23-amogus_doha** — the pinned manifest +
patches + build script that produced the working 2026-09-26 Android 16
build. Device trees, kernel and blobs: **Aldair402** and **moto-common**.
This repo keeps that recipe intact and adds the fixes and features below.
Full history: `WORKLOG.md`.

**Self-contained device code:** all 27 device-specific repos the manifest
pins are also cloned INTO this kit (`mirrors/`, 3.4 GB full set — 15 of
those upstreams are already ARCHIVED and deletable). After the one-time
`bash doha.sh vendor`, sync and build never need those upstreams at all.
See `docs/MIRRORS.md`.

## What this repo fixes / adds over the base recipe

| # | Change | Evidence | Where |
|---|---|---|---|
| 1 | **Touch works** — the 3 touch drivers are now loaded at boot (the base build shipped them in `/vendor/lib/modules` but never loaded them; this unit has a FocalTech FT8719 panel) | 3-ROM differential analysis, 2026-10-15 dumps — **proven** | `lineage-16/patches/device/motorola/amogus_doha.patch`, docs/ANALYSIS.md §1 |
| 2 | **post_boot FORTIFY crash fixed** — the base build's `/vendor/bin/sh` (Android-10-era mksh) crashes on Android 16 bionic at EVERY boot, killing the ENTIRE trinket post-boot tuning (schedutil, hispeed/min freqs, core_ctl, sched migrations, DDR bw_hwmon, memory params, readahead). Root cause of the governor bug AND the heat/battery gap | tombstone + crash buffer, 2026-10-17 triage — **proven** | `scripts/apply-latent-fixes.sh`, docs/BUG-REGISTER.md #6 |
| 3 | **CPU governor guard** — belt-and-braces: schedutil restored after boot even if anything else flips it | same dumps — measured | `variants/init.doha.cpugov.rc`, docs/CPU-GOVERNOR.md |
| 4 | **10 avc-denial fixes** — sensor variant config bind-mount (empty `/vendor/etc/sensors/config` = missing Orientation sensors + zero tuning), USB OTG role switch, rild/persist access (SIM-relevant), vold, fsck on modem/prodpersist, BT + camera HAL prop reads, modprobe cmdline, and more | 343 denials triaged, 2026-10-17 | `latent-fixes/*.te`, docs/BUG-REGISTER.md |
| 5 | **Legacy prop re-labelling** — `ril.subscription.types` (qcrild per-slot subscription config — possibly the SIM 1 missing piece) + `persist.debug.wfd.enable` were silently denied at every boot | property denials, 2026-10-17 | `latent-fixes/property_contexts.add` |
| 6 | **SIM 1 call diagnosis** — root cause found (qcrild loads NO modem carrier config for slot 0 / Vi: `mcfg_version=null`), confirmation test matrix ready, two new build-side fixes shipped | same dumps — proven | docs/SIM1-CALLS.md, scripts/flash-checks.sh §3 |
| 7 | **Dolby Atmos** from this phone's own stock firmware (libswdap + dax-default.xml), wired into audio_effects at build time | stock dump inventory | `variants/dolby/`, docs/DOLBY.md |
| 8 | **Editions**: `nogapps` (default, all apps) and `gapps` (debloated ROM + MindTheGapps sideload = Play services + Play Store only) | design doc | variants/, docs/DEBLOAT.md |
| 9 | **crDroid 17 bring-up kit** (manifests, local manifest, patch re-target map, ordered plan) | research, Oct 2026 | `crdroid-17/` |
| 10 | **flash-checks.sh** — 60-second post-flash verification of everything above (7 sections) | new | `scripts/flash-checks.sh` |
| 11 | **crDroid 12.x on Android 16 as a second ROM base** — crDroid's own 16.0 manifest + the same 27 doha projects, the same patches (Connectivity swapped for a crDroid variant), latent fixes and variants. **All 17 patches verified** with `git apply --check` against the exact upstream commits (both ROMs). Not built or flashed yet | research + patch checks, 2026-10-18 | `crdroid-16/`, `bash doha.sh buildcr16` |

## Repo layout

```
doha-roms/
├── doha.sh                 ⭐ THE interactive entry point (menu: build/flash/dump/everything)
├── README.md                this file
├── default.xml              ⭐ the pinned manifest (1,184 projects) - repo reads it from the root
├── mirrors/                 ⭐ vendored device code - ALL 27 device repos cloned INTO this kit
│   ├── repos/*.tgz          self-contained git mirrors at the exact pinned SHAs (3.4 GB full set)
│   └── MIRRORS.tsv          the 27 pins: name|path|sha|date|url|size
│                            (after `bash doha.sh vendor`: sync+build NEVER contact Aldair402 /
│                             moto-common / AOSPA / ThankYouMario - 15 of 27 are already ARCHIVED
│                             upstream; see docs/MIRRORS.md) - mirrors/repos IS committed,
│                             mirrors/git/ is generated and ignored
├── WORKLOG.md               COMPLETE project history & context (read this first!)
├── lineage-16/              ⭐ the proven target: LineageOS 23.2 + fixes
│   ├── build.sh             sync + patch + latent-fixes + variants + build
│   └── patches/             17 patches (16 carried from base + touch fix extended)
├── crdroid-16/              second ROM base: crDroid 12.x on Android 16 (NOT built yet)
│   ├── default.xml          crDroid 16.0 + the 27 doha projects, self-contained (1,208 projects)
│   ├── refresh-manifest.sh  regenerates default.xml from crDroid's branch (needs network)
│   ├── patches/             per-project overrides of lineage-16/patches (Connectivity only)
│   ├── README.md            how to build, what differs, what is unknown
│   └── VERIFIED.md          all 17 patches checked against the exact upstream commits
├── latent-fixes/            the 2026-10 latent-bug fix layer
│   ├── doha_amogus_fixes.te        sepolicy B1-B5 (sensor mount, HALs, modprobe)
│   ├── doha_qcom_fixes.te          sepolicy B6-B10 (rild, vold, fsck, USB OTG)
│   └── property_contexts.add       legacy prop re-labels (ril.subscription.types)
├── crdroid-17/              bring-up kit for Android 17 (NOT built yet)
│   ├── default.xml          crDroid 17.0 pinned manifest (1,067 projects)
│   ├── snippets_*.xml       crDroid + LineageOS snippet manifests
│   ├── local_manifest_doha.xml   the doha projects to layer on top
│   └── patches/README.md    which patches go where on Android 17
├── variants/
│   ├── init.doha.cpugov.rc  CPU governor guard (installed by every build)
│   ├── debloat.mk           safe-tier removals (gapps edition)
│   ├── debloat-aggressive.mk
│   ├── debloat-crdroid.mk   crDroid-only additions to the debloat tiers
│   └── dolby/               blob list, extract + wiring scripts, dolby.mk
├── cloud/
│   └── colab_doha.sh      Google Colab session wrapper (CPU runtime; see docs/BUILD-INFRA.md)
├── scripts/
│   ├── vendor-mirrors.sh    clone the 27 device repos into mirrors/ (one-time, resumable)
│   ├── restore-mirrors.sh   auto-called by build.sh: repoint repo sync at the local mirrors
│   ├── flash-checks.sh      post-flash verification (7 sections)
│   ├── apply-latent-fixes.sh installs the latent-fixes layer into the tree
│   ├── selftest-paths.sh    regression test: build.sh path resolution (15 checks)
│   ├── selftest-crdroid16.sh offline test of the crDroid 16 target (manifest, overlay, mock build; 25 checks)
│   ├── selftest-dryrun.sh   ⭐ 97-check dry-run battery over EVERY script (no prerequisites)
│   └── debug_device.sh      the full diagnostic dumper (v3, made the 3 dumps)
└── docs/
    ├── BUILD-INFRA.md       ⭐ where to build: GPU/Colab/Kaggle/GDrive facts + ranked plan
    ├── ANALYSIS.md          the three-ROM differential analysis (the evidence)
    ├── BUG-REGISTER.md      ⭐ ALL 30 findings: evidence, fix status, verify
    ├── SIM1-CALLS.md        Vi/Jio SIM 1 diagnosis + 15-minute test
    ├── CPU-GOVERNOR.md      the performance-pin bug (root cause: post_boot crash)
    ├── MIRRORS.md           ⭐ the 27 vendored device repos: why + how + sizes
    ├── DOLBY.md             the Dolby integration guide
    └── DEBLOAT.md           editions, removal tiers, the never-remove list
```

## Building (Android 16, the proven target)

Requirements (from the base recipe, measured): x86-64 Linux with Docker,
~350 GB disk, 32 GB RAM + 32 GB swap, ~100 GB download, ~3 h clean build
(~7 min with warm ccache).

```sh
git clone <this-repo> doha-roms && cd doha-roms
# (extracted from the zip instead? make it a git repo first - repo init
#  requires the manifest repo to be a git repository with default.xml
#  committed:
#    git init && git add -A && git commit -m "doha-roms initial" )
mkdir -p ~/doha/src ~/doha/ccache ~/doha/zips

# nogapps (default)
docker run --rm -it --user "$(id -u):$(id -g)" -e HOME=/tmp \
  -v "$PWD:/manifest" -v ~/doha/src:/src \
  -v ~/doha/ccache:/ccache -e CCACHE_DIR=/ccache \
  -v ~/doha/zips:/zips -e ZIP_DIR=/zips \
  --entrypoint /manifest/lineage-16/build.sh \
  lineageos4microg/docker-lineage-cicd:latest /src

# gapps + Dolby edition
#   -e VARIANT=gapps -e DOLBY=1   (Dolby needs variants/dolby/blobs/ first:
#                                  bash variants/dolby/extract-from-stock.sh
#                                  with stock booted, once, on the phone)

# crDroid 12.x (Android 16) instead of LineageOS: its OWN source dir + ROM_TARGET
#   -e ROM_TARGET=crdroid16 -v ~/doha/src-crdroid16:/src     (see crdroid-16/README.md)
```

Without Docker: install the LineageOS build deps + `repo`, then
`bash lineage-16/build.sh ~/doha/src`.

The kit is mounted read-write on purpose: build.sh unpacks the vendored
mirrors into `mirrors/git/` inside it. (With `:ro` the unpack silently did
nothing; `restore-mirrors.sh` now fails loudly and the sync falls back to
upstream instead.)

### Building crDroid 12.x (Android 16) instead of / as well as LineageOS

`bash doha.sh buildcr16` (menu 12; same as `build16 --rom crdroid`). Own
source tree (`~/doha/src-crdroid16`), same patches, fixes and editions.
**Not built or flashed yet** - read `crdroid-16/README.md` first (what
differs, what can go wrong) and keep your LineageOS zip as the fallback.

Options: `JOBS`, `SYNC_JOBS=4`, `SKIP_SYNC=1` (rebuilds), `CCACHE_SIZE`,
`SKIN_THROTTLE_C`, `ZIP_DIR`, `VARIANT`, `DEBLOAT`, `DOLBY`.
HTTP 429 during sync: wait a few minutes, rerun — it resumes.
After any edit to `build.sh`, run `bash scripts/selftest-paths.sh` — it
regression-tests the script's path resolution against a mock tree.

### Self-tests (run anywhere — no network, phone, repo tool or AOSP tree needed)

`bash doha.sh selftest` (menu 7) runs all three:

* `scripts/selftest-paths.sh` — 15 assertions: build.sh discovers all 17
  patches, applies latent fixes, renders the variant layer, writes the stamp
  (regression test for the path bug that would have silently built an
  unpatched ROM).
* `scripts/selftest-crdroid16.sh` — 25 assertions: the crDroid 16 manifest is
  consistent (the 27 doha pins identical to the LineageOS manifest), the patch
  overlay is valid, and the real build.sh with `ROM_TARGET=crdroid16` runs its
  patch / fix / variant layers against a mock tree.
* `scripts/selftest-dryrun.sh` — 97-assertion dry-run battery over every
  script in the kit: syntax, manifest XML validity, mirror-store integrity
  (27 tarballs gzip-CRC-checked, pins == manifest), a sandboxed
  restore-mirrors run (XML generation, pinned-SHA presence, fetch-by-SHA,
  idempotency, failure modes), build.sh's init→restore→sync ordering with a
  `repo` stub plus the upstream-fallback branch, every `doha.sh` subcommand
  and the menu, batch-mode behavior (a piped subcommand can never fake
  success), latent-fixes idempotency on a mock tree, clean adb-less failures
  of the phone scripts, and the Colab guard. Found and fixed two real bugs
  on its first run: `doha.sh sync` faking success when piped, and
  debug_device.sh leaving a stray dump dir when adb is missing.

  The mirror-store checks expect all 27 tarballs. A kit zip that leaves out
  the 4 largest (kernel, qcom blobs, clang, Motorola blobs - about 3.2 GB)
  fails 7 of the battery's checks until `bash doha.sh vendor` has fetched
  them; everything else passes.

### Building in the cloud (Colab / Crave / Kaggle / GDrive)?

Short version: **no GPU helps — ROM builds are pure CPU + RAM + disk**,
Colab is a last resort, Kaggle is not viable, Crave (what crDroid 13 used)
is the proven free route, and your 5 TB Google Drive is the *archive*
(snapshots/ccache/releases), never the live build disk. Full facts, quota
math and the ranked plan: **docs/BUILD-INFRA.md**. The Colab session
wrapper (CPU High-RAM runtime, GDrive snapshot restore → build → snapshot
back) is `cloud/colab_doha.sh`.

## Flashing

Unlocked bootloader; A/B device; recovery lives in `boot`.

1. `fastboot flash boot lineage-...-boot.img` (only coming from stock/another ROM)
2. Recovery → factory reset when coming from another ROM →
   **Apply update → Apply from ADB** → `adb sideload lineage-23.2-*.zip`
   (crDroid build: `crDroidAndroid-16.0-*.zip`)
3. GApps edition: at the **"Install additional zip?"** prompt answer
   **Yes** and `adb sideload MindTheGapps-*.zip` (Play services + Play
   Store only — everything else from the Play Store afterwards)
4. First boot, then: **`bash scripts/flash-checks.sh`** — it verifies the
   touch driver, the CPU governor, both SIMs' carrier configs and the
   Dolby files in one pass.

A/B notes from the base recipe: sideload installs to the inactive slot and
switches; keep a known-good slot active before experimenting; the transfer
slows around 47% (tap the screen); the vbmeta anti-rollback warning on
this device is expected and harmless.

## Status

| Feature | nogapps/gapps |
|---|---|
| boot, Wi-Fi (WPA3), BT (A2DP/HID), NFC, GPS, fingerprint, vibration, camera, audio, charging | ✅ (base recipe, user-tested) |
| **Touch** | ✅ expected fixed by the modules.load fix (needs one flash to confirm) |
| **VoLTE + calls, Jio (SIM 2)** | ✅ works (user-tested) |
| **Calls on Vi (SIM 1)** | ⚠️ root cause found, run the docs/SIM1-CALLS.md test and report |
| **CPU governor / heat / battery** | ✅ expected fixed by the guard (verify with flash-checks) |
| **Dolby** | 🧪 experimental (DOLBY=1, first build+listen test pending) |
| Android 16 on crDroid 12.x | 🚧 inputs verified (manifest + all 17 patches), NOT yet built or flashed — see crdroid-16/README.md |
| Android 17 (crDroid) | 🚧 bring-up kit only — see crdroid-17/README.md |

## Brick safety

Building cannot brick the phone; flashing can. The flow writes `boot` and
sideloads a zip — it never touches the bootloader, radio or partition
table. Typical failure = bootloop, recovered by reflashing stock firmware
over fastboot. Before flashing any new build: stock firmware for XT2019
downloaded, battery >50%, Power+VolDown fastboot route known, data backed
up, and the previously-working zip kept on the PC.

## License / attribution

- Base recipe: github.com/christiaan/lineage-23-amogus_doha (no license file)
- Device/kernel/vendor trees: Aldair402, moto-common, AOSPA, ThankYouMario
  (mostly unlicensed community trees; blobs are proprietary Motorola code)
- Dolby blobs: NOT in this repo; extracted by the user from their own
  stock firmware into `variants/dolby/blobs/` (add that dir to .gitignore
  if you fork and publish)
- The lineage-16 patches are christiaan's work + the touch/governor
  additions documented in WORKLOG.md
