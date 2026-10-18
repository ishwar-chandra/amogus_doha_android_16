# crDroid 17 (Android 17) for the Moto G8 Plus (doha) — bring-up target

**Status: NOT BUILT. NOT TESTED. This is a bring-up kit, not a working ROM.**

Nobody has published a doha build on Android 17 (checked 2026-10-07 through
2026-10-17, LineageOS or crDroid). What exists in this directory is
everything needed to *start* the port with maximum odds, and an ordered
plan. Expect several failed builds before one boots; each costs hours.

## Why crDroid for Android 17?

- crDroid `17.0` (branch of `crdroidandroid/android`) is based on
  `android-17.0.0_r1` and follows `lineage-24.0` daily (last merge seen
  2026-10-07). LineageOS 24.0 itself released 2026-10-11.
- crDroid's `breakfast <device>` lunches `lineage_<device>-...-userdebug`,
  so the existing `lineage_amogus_doha` product applies unchanged — no new
  product file, no ROM switch needed (untested, but verified by reading
  crDroid's `vendor/lineage/build/envsetup.sh`).
- crDroid is what the phone ran on Android 13 (crDroid 9.20 from XDA, the
  ROM the owner reports as the most stable ever on this device). Same
  family of sources: Aldair402's doha stack.

## What is in this directory

| File | What it is |
|---|---|
| `default.xml` | crDroid 17.0 top-level manifest (1,067 projects), pinned copy fetched 2026-10-07 from `crdroidandroid/android` branch `17.0` |
| `snippets_crdroid.xml` | crDroid's 61 forked projects (incl. `build/make`, `build/soong`, `art`, `system/core`, `packages/modules/Connectivity`, `vendor/lineage` → `crdroidandroid/android_vendor_crdroid`) |
| `snippets_lineage.xml` | the LineageOS snippet (175 projects) crDroid layers on top |
| `local_manifest_doha.xml` | the doha projects to add via `.repo/local_manifests/` (kernel, device trees, blobs, with the pins proven by the working Android 16 build) |
| `patches/README.md` | which of the lineage-16 patches must be re-targeted where |

## The kernel stays 4.14

Same answer as the Android 16 build: the 4.14 msm kernel is the last kernel
this device's vendor blobs can talk to. Android 17 userspace will be
convinced the same way Android 16 was: by relaxing the BPF kernel-version
gates and the VINTF kernel requirement. Community evidence that this still
works on 17: RestlessOS 17.0.0 (a Treble GSI, 2026-09-22) carries Android 17
versions of exactly these relaxations, plus restored HIDL and API-29 sepolicy
support. Official LineageOS 24.0 does NOT accept 4.14 kernels without 1:1
eBPF backports (Changelog 32, 2026-10-11) — this port is unofficial and
relaxes the checks instead; expect BPF-dependent features (local network
blocking, some offload paths) to be missing or degraded, same as the
Android 16 build.

## Steps (in this order)

1. **Baseline first.** Build and flash the lineage-16 target of this repo
   (with the touch fix) and confirm touch + both SIMs + governor checks
   pass `scripts/flash-checks.sh`. Do not start this port before that.
2. `repo init -u https://github.com/crdroidandroid/android -b 17.0` — or,
   for a frozen start, init against this directory's pinned `default.xml`.
3. Copy `local_manifest_doha.xml` to `$SRC/.repo/local_manifests/doha.xml`,
   extend it with the remaining `local::doha` projects copied from
   `../lineage-16/default.xml`.
4. `repo sync`, then **pin everything**: `repo manifest -r > my-pins.xml`,
   and build from pins from now on (crDroid's branch moves daily).
5. Apply the re-targeted patches from `patches/README.md` (start with:
   Connectivity BPF gates → crDroid's Connectivity fork; thermal sensor
   names; modules.load touch fix — that one applies as-is).
6. **Run the latent-fixes layer**: `bash ../scripts/apply-latent-fixes.sh $SRC`
   (or copy the call from lineage-16/build.sh into your build script). Every
   finding in docs/BUG-REGISTER.md applies to the 17 build too — same device
   trees, same vendor, same kernel — and the fixes are tree-layout-agnostic
   (content-searched + new-file drops). The post_boot FORTIFY crash (#6) is
   even more important on 17: the Android 17 libc will be at least as strict
   as 16's. Re-check BUG-REGISTER #20's prop list after the first boot —
   Android 17 may add new legacy-prop denials (same fix pattern).
7. `source build/envsetup.sh && breakfast amogus_doha userdebug &&
   mka target-files-package bacon`
8. When it builds: flash with the same A/B slot discipline as lineage-16,
   stock firmware downloaded, battery >50%, fastboot route known.
9. First-boot checklist = `scripts/flash-checks.sh` (all 7 sections: touch
   modules, governor + post_boot tuning, both-SIM MCFG, OTG, sensor config,
   denial signatures). The Android 16 fixes carry over: this repo's
   touch fix is in `patches/device/motorola/amogus_doha.patch` and applies
   to the same device tree commit.

## Known unknowns (from the research session, still open)

- whether crDroid's `vendor/lineage` needs extra variables for an
  unofficial device;
- crDroid's zip naming vs the `lineage-$LINEAGE_VERSION.zip` copy step;
- how many of the 17 patches survive on Android 17 unchanged;
- sepolicy: Android 17 may drop more legacy HAL types the doha stack uses
  (RestlessOS had to restore "29.0/30.0 SEPolicy support" — doha is API 29);
- **sepolicy compile on 17**: the latent-fixes .te drop-ins reference types
  that exist on the 23.2 trees (verified against the LineageOS branches,
  2026-10-17); if a type is renamed/dropped on the 17 branch, delete that
  block from `latent-fixes/*.te` and rebuild — blocks are independent
  (documented in the file headers and BUG-REGISTER).

## The full bug register applies here too

docs/BUG-REGISTER.md (30 items, evidence + fix + verify) was derived from
the Android 16 build but the underlying device trees, vendor and kernel
are identical for the 17 build — carry `latent-fixes/` and
`scripts/apply-latent-fixes.sh` over unchanged, then re-run
`scripts/flash-checks.sh` on the first boot.

## Fallback

The lineage-16 target in this repo is the stable one. Keep its zip. If
crDroid 17 bootloops, reflash boot, factory reset, sideload the lineage-16
zip again — building cannot brick the phone, only flashing can, and the
flow never touches the bootloader or partition table.
