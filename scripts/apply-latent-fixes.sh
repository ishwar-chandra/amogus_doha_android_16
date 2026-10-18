#!/usr/bin/env bash
# =============================================================================
# apply-latent-fixes.sh - installs the "latent bug" fix layer discovered in
# the 2026-10 3-ROM dump triage (docs/BUG-REGISTER.md) into a synced AOSP
# build tree.
#
# Called by lineage-16/build.sh after the repo patches, before the variant
# layer. Also reusable for the crDroid 17 bring-up: same device trees, same
# vendor, same bugs.
#
# What it does (all steps idempotent, marker- or content-checked):
#   1. post_boot interpreter fix (BUG #6, the FORTIFY SIGABRT):
#      /vendor/bin/sh (Android-10-era mksh) crashes inside c_print on
#      Android 16 bionic every boot -> the whole trinket post-boot tuning
#      (schedutil, core_ctl, DDR bw_hwmon, memory params, readahead...)
#      is lost. Re-point every post_boot service definition (and the
#      aospa perf script shebang, if shipped) at /system/bin/sh.
#   2. Drops latent-fixes/doha_amogus_fixes.te into the Motorola amogus
#      sepolicy dir (avc fixes B1-B5).
#   3. Drops latent-fixes/doha_qcom_fixes.te into the qcom legacy-um
#      sepolicy dir (avc fixes B6-B10).
#   4. Appends latent-fixes/property_contexts.add to the qcom legacy-um
#      property_contexts (legacy prop re-labelling).
#   5. Fixes the ro.product.bevice typo in build_doha.prop (BUG #19).
#
# Escape hatch: LATENT_FIXES=0 ./build.sh skips this script entirely.
# =============================================================================
set -uo pipefail

SRC=${1:?usage: apply-latent-fixes.sh <synced-source-tree>}
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)   # repo root
FIX="$HERE/latent-fixes"

[ -d "$SRC/device" ] || { echo "apply-latent-fixes: $SRC does not look like a synced tree" >&2; exit 1; }

echo "== apply-latent-fixes: installing latent-bug fix layer =="

# ---------------------------------------------------------------------------
# 1. post_boot interpreter: /vendor/bin/sh -> /system/bin/sh
#
# The service is defined in an init rc shipped by the device or vendor
# tree (exact repo varies by branch), so find it by content. Both of
# these forms exist in the wild:
#   service <name> /vendor/bin/sh /vendor/bin/init.qcom.post_boot.sh
#   exec ... /vendor/bin/sh /vendor/bin/init.qcom.post_boot.sh
count=0
while IFS= read -r -d '' f; do
  if grep -q '/vendor/bin/sh.*init\.qcom\.post_boot\.sh' "$f"; then
    sed -i 's|/vendor/bin/sh\(.*init\.qcom\.post_boot\.sh\)|/system/bin/sh\1|' "$f"
    echo "   post_boot interpreter fixed in $f"
    count=$((count + 1))
  fi
done < <(grep -rl --null -E 'init\.qcom\.post_boot\.sh' "$SRC/device" "$SRC/vendor" 2>/dev/null || true)

# The script itself ships in some trees; fix its shebang too (matters when
# something execs it directly).
while IFS= read -r -d '' f; do
  if head -1 "$f" | grep -q '^#! */vendor/bin/sh'; then
    sed -i '1s|^#! */vendor/bin/sh.*|#!/system/bin/sh|' "$f"
    echo "   shebang fixed in $f"
    count=$((count + 1))
  fi
done < <(find "$SRC/device" "$SRC/vendor" -name 'init.qcom.post_boot.sh' -print0 2>/dev/null || true)

# Same treatment for the crDroid/AOSPA perf script that runs on
# vendor.post_boot.parsed (same old-mksh risk).
while IFS= read -r -d '' f; do
  if grep -q '/vendor/bin/sh.*init\.aospa\.perf\.common\.sh' "$f"; then
    sed -i 's|/vendor/bin/sh\(.*init\.aospa\.perf\.common\.sh\)|/system/bin/sh\1|' "$f"
    echo "   aospa perf interpreter fixed in $f"
    count=$((count + 1))
  fi
done < <(grep -rl --null -E 'init\.aospa\.perf\.common\.sh' "$SRC/device" "$SRC/vendor" 2>/dev/null || true)

if [ "$count" -eq 0 ]; then
  # Distinguish "already fixed on a previous run" from "not found at all".
  already=$(grep -rl '/system/bin/sh.*init\.qcom\.post_boot\.sh' "$SRC/device" "$SRC/vendor" 2>/dev/null | wc -l)
  if [ "$already" -gt 0 ]; then
    echo "   post_boot interpreter already on /system/bin/sh ($already file(s)) - OK"
  else
    echo "   WARNING: no post_boot service definition found in device/ or vendor/." >&2
    echo "   The FORTIFY crash fix could not be applied (BUG #6). The cpugov.rc" >&2
    echo "   guard from variants/ remains as fallback. Check BUG-REGISTER.md #6." >&2
  fi
else
  echo "   post_boot interpreter fix: $count file(s) updated"
fi

# ---------------------------------------------------------------------------
# 2. Motorola amogus sepolicy drop-in (B1-B5)
SEPOLICY_MOTO="$SRC/device/motorola/amogus/sepolicy"
if [ -d "$SEPOLICY_MOTO" ]; then
  cp "$FIX/doha_amogus_fixes.te" "$SEPOLICY_MOTO/doha_amogus_fixes.te"
  echo "   sepolicy: $SEPOLICY_MOTO/doha_amogus_fixes.te installed"
else
  # fallback: older branch layout
  installed=0
  for alt in "$SRC/device/motorola/trinket/sepolicy" "$SRC/device/motorola/sm6150-common/sepolicy"; do
    if [ -d "$alt" ]; then
      cp "$FIX/doha_amogus_fixes.te" "$alt/doha_amogus_fixes.te"
      echo "   sepolicy: $alt/doha_amogus_fixes.te installed (fallback dir)"
      installed=1
      break
    fi
  done
  if [ "$installed" -eq 0 ]; then
    echo "   WARNING: no Motorola sepolicy dir found; amogus fixes NOT installed" >&2
  fi
fi

# ---------------------------------------------------------------------------
# 3. qcom legacy-um sepolicy drop-in (B6-B10)
SEPOLICY_QCOM="$SRC/device/qcom/sepolicy_vndr/generic/vendor/common"
if [ -d "$SEPOLICY_QCOM" ]; then
  cp "$FIX/doha_qcom_fixes.te" "$SEPOLICY_QCOM/doha_qcom_fixes.te"
  echo "   sepolicy: $SEPOLICY_QCOM/doha_qcom_fixes.te installed"
else
  echo "   WARNING: $SEPOLICY_QCOM not found; qcom fixes NOT installed" >&2
fi

# ---------------------------------------------------------------------------
# 4. property_contexts additions (marker-checked append)
MARKER="# doha-roms latent-fixes property_contexts (B20)"
if [ -d "$SEPOLICY_QCOM" ] && [ -f "$SEPOLICY_QCOM/property_contexts" ]; then
  if ! grep -q "$MARKER" "$SEPOLICY_QCOM/property_contexts"; then
    {
      echo ""
      echo "$MARKER"
      grep -v '^#' "$FIX/property_contexts.add" | grep -v '^$'
    } >> "$SEPOLICY_QCOM/property_contexts"
    echo "   property_contexts: legacy prop re-labels appended"
  else
    echo "   property_contexts: already patched"
  fi
elif [ -d "$SEPOLICY_MOTO" ]; then
  # older layout: device sepolicy dir has its own property_contexts
  if [ -f "$SEPOLICY_MOTO/property_contexts" ]; then
    if ! grep -q "$MARKER" "$SEPOLICY_MOTO/property_contexts"; then
      { echo ""; echo "$MARKER"; grep -v '^#' "$FIX/property_contexts.add" | grep -v '^$'; } \
        >> "$SEPOLICY_MOTO/property_contexts"
      echo "   property_contexts: appended (moto dir)"
    fi
  else
    { echo "# $MARKER"; grep -v '^#' "$FIX/property_contexts.add" | grep -v '^$'; } \
      > "$SEPOLICY_MOTO/property_contexts"
    echo "   property_contexts: created (moto dir)"
  fi
fi

# ---------------------------------------------------------------------------
# 5. ro.product.bevice typo fix (B19) in build_doha.prop sources
typo_files=$(grep -rl 'ro\.product\.bevice' "$SRC/device" "$SRC/vendor" 2>/dev/null || true)
if [ -n "$typo_files" ]; then
  echo "$typo_files" | while IFS= read -r f; do
    sed -i 's/ro\.product\.bevice/ro.product.device/' "$f"
    echo "   typo fixed (ro.product.bevice -> ro.product.device) in $f"
  done
else
  echo "   typo check: no ro.product.bevice in tree (already clean)"
fi

echo "== apply-latent-fixes: done =="
