# crDroid 12.x (Android 16) for the Moto G8 Plus (doha) - second ROM base

**Status: NOT BUILT, NOT FLASHED.** Everything that can be checked without a
350 GB build machine has been checked (`VERIFIED.md`): the manifest is
consistent and all 17 patches apply to the exact upstream sources. Whether
crDroid's own build system compiles the doha trees is the open question -
nobody has run that yet. Keep your LineageOS zip as the fallback.

## Build it

```sh
bash doha.sh buildcr16     # = menu 12 = bash doha.sh build16 --rom crdroid
bash doha.sh buildcr16 --variant gapps --debloat safe     # editions work as for LineageOS
```

It uses its OWN source tree (default `~/doha/src-crdroid16`, about 150 GB more
disk - never point it at the LineageOS tree), the same mirror pool, ccache and
zips dir. With the Docker command from the README add
`-e ROM_TARGET=crdroid16 -v ~/doha/src-crdroid16:/src`.

Sync, all 17 patches (16 unchanged + the crDroid Connectivity variant), the
latent-bug fixes, the variants and the build run exactly as for LineageOS:
`lineage-16/build.sh` with `ROM_TARGET=crdroid16`. Output in the zips dir:
`crDroidAndroid-16.0-<date>-<device>-v12.x[-gapps-safe].zip`, the matching
`-boot/-dtbo/-vbmeta.img` and a `.sha256sum`. Flash it like the LineageOS zip
(README "Flashing"), then run `bash scripts/flash-checks.sh`.

## Why this should work (facts read from crDroid's sources, 2026-10-18)

- Same Android base: crDroid `16.0` uses AOSP `android-16.0.0_r4` and the
  default branch `lineage-23.2` - the base of the proven LineageOS build.
  The branch head reports crDroid v12.13 (`vendor/crdroid config/version.mk`).
- Same product: crDroid's `breakfast <device>` lunches `lineage_<device>-...`
  (`vendor/crdroid build/envsetup.sh`), so `lineage_amogus_doha` applies unchanged.
- Same device code: the 27 doha projects are copied verbatim, with the same
  pinned SHAs, from the LineageOS manifest (`scripts/selftest-crdroid16.sh`
  asserts they are identical).
- Same patches: 16 apply unchanged. The 17th, Connectivity, needs only its
  `BpfNetMaps.java` part: crDroid's own Connectivity fork already turns the
  same kernel-version gates into warnings (`crdroid-16/patches/`).
- Same latent-fix layer and variants (content-searched, tree-layout agnostic).

## What differs - and what can go wrong

1. **Build system.** crDroid forks `build/make` and `build/soong` (plus
   `system/core`, `packages/modules/Connectivity`, `device/lineage/sepolicy`,
   `vendor/lineage`). The doha trees have only ever been compiled against
   LineageOS's build system, so Soong/Make incompatibilities are the biggest
   unknown. Expect to read a build log; each attempt costs hours.
2. **sepolicy.** `device/lineage/sepolicy` is crDroid's fork. The latent-fix
   `.te` blocks use types that exist on the LineageOS trees; if the crDroid
   compile rejects one, delete that block from `latent-fixes/*.te`
   (the blocks are independent - see BUG-REGISTER).
3. **FaceUnlock** is the one project fetched from gitlab.com; if its fetch
   fails, rerun the sync. Do not remove it - `crdroid.mk` lists it in
   `PRODUCT_PACKAGES`.
4. **Packaging.** crDroid's `bacon` moves the zip and deletes
   `target_files_intermediates`; build.sh therefore takes boot/dtbo/vbmeta
   from the product dir when the intermediates are gone, and does not add the
   `lineage-` prefix to the output name.
5. **BPF.** Same as LineageOS: the 4.14 kernel stays, features that need
   newer BPF (local-network blocking, some offload paths) are degraded.
6. **Debloat (gapps edition).** crDroid's app set differs.
   `variants/debloat-crdroid.mk` adds Gallery2; crDroid-only apps without a
   Google equivalent (GameSpace, OmniJaws, MatLog, ...) are kept. Unofficial
   builds get no OTA updates from crDroid's updater.
7. A quick search on 2026-10-18 found no crDroid 12 build for this phone
   (not exhaustive).

## Reproducibility

crDroid's branches move daily and `default.xml` is not SHA-pinned (same as
`crdroid-17/`). After every sync build.sh records the exact commit of every
project in `<src>/.repo/doha-crdroid16-pins.xml` - keep it next to the zip.
To freeze a tree that built well:

```sh
cp ~/doha/src-crdroid16/.repo/doha-crdroid16-pins.xml crdroid-16/my-pins.xml
git add crdroid-16/my-pins.xml && git commit -m "crdroid-16 pins"
MANIFEST_FILE=crdroid-16/my-pins.xml bash doha.sh buildcr16
```

To refresh from crDroid's branch: `bash crdroid-16/refresh-manifest.sh`, then
`bash scripts/selftest-crdroid16.sh`, then re-check the patches (method and
last results in `VERIFIED.md`) - heads move, so a later sync may need a
rebase of one patch.

## Files

| File | What it is |
|---|---|
| `default.xml` | one self-contained manifest: crDroid 16.0 + snippets inlined + the 27 doha projects (1,208 projects) |
| `refresh-manifest.sh` | regenerates `default.xml` from crDroid's branch (needs network) |
| `patches/packages/modules/Connectivity.patch` | crDroid variant (replaces the lineage-16 patch of the same path) |
| `VERIFIED.md` | patch-by-patch `git apply --check` record with the exact commits |

## Fallback

`lineage-16` stays the stable target. If crDroid bootloops: reflash boot,
factory reset, sideload the LineageOS zip again. Building cannot brick the
phone; the flashing flow never touches the bootloader or partition table.
