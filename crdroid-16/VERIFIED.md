# crdroid-16 verification record (2026-10-18)

**Method.** `git apply --check` of the exact patch text build.sh applies
(`lineage-16/patches/*`, with `crdroid-16/patches/*` replacing same-named files;
`@SKIN_THROTTLE_MC@` rendered at the default 40 C) against the exact upstream
commit of each project. Device-side projects: from the vendored mirror
tarballs, or - for the three too large to ship - by fetching only the files the
patch touches at the pinned commit. Nothing was synced, compiled or booted.
**Not covered:** compile, sepolicy build, boot, behaviour.

## crDroid 16.0 target - platform projects (crDroid forks / LineageOS heads)

| Patch (project path) | Applied to | Commit | Result |
|---|---|---|---|
| `device/lineage/sepolicy` | crdroidandroid/android_device_crdroid_sepolicy `16.0` | e369b2be | applies |
| `device/qcom/sepolicy_vndr/legacy-um` | LineageOS/android_device_qcom_sepolicy_vndr `lineage-23.2-legacy-um` | 0dbc76e4 | applies |
| `hardware/nxp/nfc` | LineageOS/android_hardware_nxp_nfc `lineage-23.2` | 1459e3f2 | applies (also at the older LineageOS pin ad16c5c9) |
| `packages/modules/Connectivity` | crdroidandroid/android_packages_modules_Connectivity `16.0` | 6abc5cd5 | **crdroid-16 variant applies; the lineage-16 patch does NOT** (NetBpfLoad.cpp, BpfHandler.cpp: crDroid already relaxes those gates) |
| `system/core` | crdroidandroid/android_system_core `16.0` | e8fc25fd | applies |
| `vendor/qcom/opensource/interfaces` | LineageOS/android_vendor_qcom_opensource_interfaces `lineage-23.2` | eb976d9d | applies |

## Both targets - device-side projects (identical pins in both manifests)

| Patch (project path) | Pinned commit | Result |
|---|---|---|
| `device/motorola/amogus` | de72dd4f | applies |
| `device/motorola/amogus_doha` (touch fix) | 2638aeb9 | applies |
| `device/motorola/common` | 8baff88c | applies |
| `device/motorola/targets` | ce106e50 | applies |
| `device/qcom/common` | 4898502a | applies |
| `hardware/motorola` | f805e9ef | applies |
| `vendor/qcom/opensource/audio/sm8150` | d0dbea0f | applies |
| `vendor/qcom/opensource/thermal` | d90b0d8f | applies |
| `kernel/motorola/msm-4.14` | 6509e92e | applies (2 files fetched at the pin) |
| `vendor/qcom/common` | 50d32904 | applies (2 files fetched at the pin) |
| `vendor/motorola/amogus` | 85187ccf | applies (1 file fetched at the pin) |

## LineageOS 23.2 target (root `default.xml`)

The six platform patches above also apply to their exact pins in the root
manifest: device/lineage/sepolicy 0a9e7529, legacy-um 0dbc76e4, hardware/nxp/nfc
ad16c5c9, Connectivity c9f3e779, system/core 0e96ff13, interfaces eb976d9d.
Together with the table above that is **all 17 patches verified** for the
LineageOS target too (before this check the content of 9 of them had only been
tried against mocks).

## Why the Connectivity patch differs on crDroid

crDroid's fork already contains, in `bpf/loader/NetBpfLoad.cpp`, the 4.9/4.14/
4.19/5.4 gates as warnings (and loosened `bpf_jit_*` returns) and, in
`bpf/netd/BpfHandler.cpp`, no kernel-version gates at all. Only the
`BpfNetMaps.java` part (local-network-blocking maps optional instead of
`IllegalStateException` at boot on a kernel without them) is still needed.

## Re-checking later

Heads move. To redo the check, fetch each project at its commit (codeload or
the manifest pin), and run `git apply --check` with the patch text through
`sed "s/@SKIN_THROTTLE_MC@/40000/g"`; use the `crdroid-16/patches` file when
one exists for the path.
