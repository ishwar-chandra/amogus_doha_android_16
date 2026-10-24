# Patch re-targeting notes: lineage-16 → crdroid-17

The 17 patches in `../lineage-16/patches/` were written against LineageOS
23.2 projects. In a crDroid 17.0 tree, several projects are crDroid forks
instead, and the code is Android 17. This file maps every patch to what
must happen with it.

| lineage-16 patch | crDroid 17.0 target | Action |
|---|---|---|
| `packages/modules/Connectivity` | `crdroidandroid/android_packages_modules_Connectivity` (replaces LineageOS's) | **re-target + rebase**: relax the kernel-version gates in NetBpfLoad/BpfHandler/BpfNetMaps on the Android 17 code. Expect at least one NEW gate tier above 25Q4's 5.10 check. Same spirit: error → warning. |
| `system/core` | `crdroidandroid/android_system_core` (replaces LineageOS's) | re-target. It is the SafetyNet/lock-state patch inherited from docker-lineage-cicd — check whether crDroid already carries something similar before porting it. |
| `kernel/motorola/msm-4.14` | same repo (Aldair402) | applies as-is (WPA3-SAE, upstream nl80211, **IPA v4.2 WDI force-clear skip**). The IPA hunk fixes the hotspot modem SSR and must stay on 17 (same kernel pin). |
| `device/motorola/amogus_doha` | same repo (Aldair402, pin in local manifest) | applies as-is; it contains the touch modules fix — THE critical one. Also verify `PRODUCT_OTA_ENFORCE_VINTF_KERNEL_REQUIREMENTS := false` is still needed (Android 17 matrices certainly still lack 4.14 at FCM 5). |
| `device/motorola/amogus` | same (moto-common) | likely applies; sepolicy hunks may shift |
| `device/motorola/common` | same (Aldair402, branch 16) | applies as-is; it now also restores the stock Motorola QCRIL/MCFG props (`no_wait_for_card` etc.) that fix SIM-1 VoLTE. Do not drop that hunk on 17. |
| `device/motorola/targets` | same (Aldair402) | likely applies (kernel headers export) |
| `device/qcom/common` | AOSPA `uvite` fork | re-verify each sepolicy removal against Android 17's trees |
| `device/qcom/sepolicy_vndr/legacy-um` | LineageOS project, still in crDroid tree | apply, then fix new neverallow violations on top |
| `device/lineage/sepolicy` | exists in crDroid (snippets/lineage.xml) | apply, verify |
| `hardware/motorola` | same (moto-common) | likely applies |
| `hardware/nxp/nfc` | LineageOS, still in tree | apply, rebase if the usleep code moved |
| `vendor/motorola/amogus` | same (Aldair402) | applies as-is (libqsap_sdk copies) |
| `vendor/qcom/common` | ThankYouMario fork | apply, verify QCC removal still needed |
| `vendor/qcom/opensource/audio/sm8150` | Aldair402 fork | apply (C23 thread signature fix) |
| `vendor/qcom/opensource/interfaces` | LineageOS, still in tree | apply (fm@1.0 HIDL) — check crDroid hasn't added it |
| `vendor/qcom/opensource/thermal` | moto-common fork | apply (xo_therm sensor names, @SKIN_THROTTLE_MC@) |

## Extra Android 17 work beyond the patches

- **BPF gates**: a new tier exists above the 25Q4 (5.10) gate — find it in
  `NetBpfLoad.cpp`'s `isAtLeast` chain and downgrade the failure the same
  way as the others.
- **VINTF**: `PRODUCT_OTA_ENFORCE_VINTF_KERNEL_REQUIREMENTS := false` stays.
- **Sepolicy for API-29 vendors**: if `checkpolicy`/`secilc` reject the
  legacy vendor policy, look at what RestlessOS 17 did ("restored 29.0 and
  30.0 SEPolicy support") for the compat matrix side.
- **HIDL removals**: AOSP 17 removes more HIDL interfaces; any that doha's
  prebuilt HALs still declare must be restored the way RestlessOS restored
  the HIDL light interface.
- **GApps/Dolby/debloat variants**: the same `variants/` layer works —
  crDroid also uses `vendor/lineage` product config, so `doha-variants.mk`
  and the debloat filter-outs apply unchanged in principle.
