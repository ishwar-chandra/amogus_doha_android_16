#!/usr/bin/env bash
# =============================================================================
# doha-roms / lineage-16 build script
# Moto G8 Plus (doha / amogus_doha) - LineageOS 23.2 (Android 16)
#
# Base: christiaan/lineage-23-amogus_doha build.sh (proven: the 2026-09-26
# build from that repo boots and runs on the phone). This version adds:
#
#   * the runtime-verified TOUCH fix (3 touch drivers in modules.load,
#     see patches/device/motorola/amogus_doha.patch and docs/TOUCH.md)
#   * the LATENT-BUG fix layer from the 2026-10 dump triage
#     (scripts/apply-latent-fixes.sh, docs/BUG-REGISTER.md): the post_boot
#     FORTIFY crash fix (restores ALL trinket post-boot tuning), 10 avc
#     denial fixes, legacy prop re-labelling. LATENT_FIXES=0 disables it.
#   * a boot-time CPU governor guard (docs/CPU-GOVERNOR.md)
#   * build variants, selected with environment variables:
#       VARIANT=gapps|nogapps   (default nogapps)
#       DEBLOAT=none|safe|aggressive (default: safe for gapps, none else)
#       DOLBY=1                 (default 0; needs variants/dolby/blobs/,
#                               see docs/DOLBY.md)
#
# Usage: ./build.sh [SOURCE_DIR]      (default: ./lineage)
#
# Environment:
#   JOBS          parallel build jobs (default: nproc)
#   SYNC_JOBS     parallel repo sync jobs (default: 4)
#   MANIFEST_URL  manifest repo to init from (default: this checkout)
#   MANIFEST_BRANCH  manifest branch (default: this checkout's current
#                 branch, or main when MANIFEST_URL is set)
#   CCACHE_SIZE   ccache size limit (default: 50G)
#   SKIN_THROTTLE_C  skin temperature (C) at which the thermal HAL reports
#                 throttling (default: 40)
#   ZIP_DIR       where finished builds are copied (default: zips/ next to
#                 SOURCE_DIR)
#   SKIP_SYNC=1   don't run repo init or repo sync
#   VARIANT       nogapps (default) or gapps
#   DEBLOAT       none | safe | aggressive (default: safe when VARIANT=gapps)
#   DOLBY         0 (default) or 1 - bundle the stock Dolby blobs
#   LATENT_FIXES  1 (default) or 0 - skip the latent-bug fix layer
#
# GApps note: the ROM zip itself never contains Google code. For the gapps
# edition, sideload MindTheGapps (Play services + Play Store only) right
# after the ROM zip, at the recovery "Install additional zip?" prompt.
# See docs/DEBLOAT.md for exactly what each edition removes and keeps.
# =============================================================================
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SRC=$(mkdir -p "${1:-$PWD/lineage}" && cd "${1:-$PWD/lineage}" && pwd)
JOBS=${JOBS:-$(nproc)}
# Most projects come from android.googlesource.com, which answers too many
# parallel fetches with HTTP 429 / RESOURCE_EXHAUSTED. repo then retries each
# failed fetch as a full fetch of every branch, which makes it worse.
SYNC_JOBS=${SYNC_JOBS:-4}
# repo reads the manifest (default.xml) from the ROOT of this repo, exactly
# like the base recipe. The patches live under lineage-16/patches/.
# build.sh itself lives in lineage-16/, so the manifest repo root is one
# directory up from HERE. (The repo must be a git repo with default.xml
# committed - repo init needs that.)
REPOROOT=$(cd "$HERE/.." && pwd)
MANIFEST_URL=${MANIFEST_URL:-$REPOROOT}
DEVICE=amogus_doha

# Layout self-check: this script lives in lineage-16/, so the patches are
# at $HERE/patches and the variants/scripts/latent-fixes dirs are at the
# repo root, one level up. A wrong assumption here would silently apply
# zero patches, so refuse to run rather than build an unpatched ROM.
for _d in "$HERE/patches" \
          "$REPOROOT/variants" \
          "$REPOROOT/latent-fixes" \
          "$REPOROOT/scripts/apply-latent-fixes.sh"; do
  [ -e "$_d" ] || {
    echo "build.sh layout check failed: $_d not found." >&2
    echo "Run this script from a full doha-roms checkout (bash lineage-16/build.sh)." >&2
    exit 1
  }
done
unset _d
# Projects patched by the last run, as "<project> <patch blob> <tree>" lines.
STAMP=$SRC/.repo/doha-patches
SKIN_THROTTLE_C=${SKIN_THROTTLE_C:-40}
case $SKIN_THROTTLE_C in
  ''|*[!0-9]*) echo "SKIN_THROTTLE_C must be a whole number of C" >&2; exit 1 ;;
esac

# ---- variants ---------------------------------------------------------------
VARIANT=${VARIANT:-nogapps}
case $VARIANT in
  nogapps|gapps) ;;
  *) echo "VARIANT must be nogapps or gapps (got: $VARIANT)" >&2; exit 1 ;;
esac
DEBLOAT=${DEBLOAT:-$([ "$VARIANT" = gapps ] && echo safe || echo none)}
case $DEBLOAT in
  none|safe|aggressive) ;;
  *) echo "DEBLOAT must be none, safe or aggressive (got: $DEBLOAT)" >&2; exit 1 ;;
esac
DOLBY=${DOLBY:-0}
case $DOLBY in
  0|1) ;;
  *) echo "DOLBY must be 0 or 1 (got: $DOLBY)" >&2; exit 1 ;;
esac
VARIANT_SUFFIX=""
[ "$VARIANT" = gapps ] && VARIANT_SUFFIX="$VARIANT_SUFFIX-gapps"
[ "$DEBLOAT" != none ] && VARIANT_SUFFIX="$VARIANT_SUFFIX-$DEBLOAT"
[ "$DOLBY" = 1 ] && VARIANT_SUFFIX="$VARIANT_SUFFIX-dolby"

# repo needs a git identity, and git refuses to read a checkout owned by
# another user (common when this runs in a container). Pass both as
# command-line config so nothing is written to ~/.gitconfig.
name=$(git config user.name || echo builder)
email=$(git config user.email || echo builder@localhost)
export GIT_CONFIG_COUNT=3
export GIT_CONFIG_KEY_0=safe.directory GIT_CONFIG_VALUE_0='*'
export GIT_CONFIG_KEY_1=user.name GIT_CONFIG_VALUE_1="$name"
export GIT_CONFIG_KEY_2=user.email GIT_CONFIG_VALUE_2="$email"

cd "$SRC"

if [ "${SKIP_SYNC:-0}" != 1 ]; then
  # repo reads the manifest from a committed branch, while the patches come
  # from the working tree. Sync the branch that is checked out here, and refuse
  # to run with an uncommitted default.xml, so the two always match.
  if [ "$MANIFEST_URL" = "$REPOROOT" ]; then
    if [ -z "${MANIFEST_BRANCH:-}" ]; then
      MANIFEST_BRANCH=$(git -C "$REPOROOT" symbolic-ref -q --short HEAD) || {
        echo "$REPOROOT has a detached HEAD; check out a branch or set MANIFEST_BRANCH" >&2
        exit 1
      }
    fi
    if ! git -C "$REPOROOT" diff --quiet HEAD -- default.xml; then
      echo "default.xml has uncommitted changes; repo would not see them. Commit them first." >&2
      exit 1
    fi
  fi
  MANIFEST_BRANCH=${MANIFEST_BRANCH:-main}

  # Run init every time so a changed MANIFEST_URL or branch takes effect.
  repo init -u "$MANIFEST_URL" -b "$MANIFEST_BRANCH" -m default.xml --git-lfs -g default,-darwin

  # If the kit carries vendored device mirrors (scripts/vendor-mirrors.sh was
  # run once), repoint the 27 device-specific projects at them so this sync
  # NEVER contacts Aldair402 / moto-common / AOSPA / ThankYouMario - half of
  # those upstreams are already archived (Apr 2026) and could vanish.
  if [ -s "$REPOROOT/mirrors/MIRRORS.tsv" ] && \
     ls "$REPOROOT"/mirrors/repos/*.tgz >/dev/null 2>&1; then
    echo "== vendored device mirrors present: restoring local mirror pool =="
    if bash "$REPOROOT/scripts/restore-mirrors.sh" "$SRC"; then
      echo "== repo sync will take the 27 device projects from the local mirror =="
    else
      echo "WARNING: mirror restore failed - falling back to upstream sync" >&2
    fi
  fi

  # --force-checkout lets a pin bump replace a project that still carries
  # the previous run's patch. Projects already at their pin aren't touched.
  repo sync -c -j"$SYNC_JOBS" --retry-fetches=5 --force-sync --force-checkout \
    --no-tags --no-clone-bundle
fi

# doha.sh sync-only mode: stop after the sync, before patches/build.
if [ "${STOP_AFTER_SYNC:-0}" = 1 ]; then
  echo "STOP_AFTER_SYNC=1 - source synced; stopping before patches and build."
  exit 0
fi

# The tree object of a project's working tree, including untracked files, so
# we can tell whether it is still exactly as the last run left it.
worktree_id() {
  local index
  index=$(mktemp)
  (cd "$1" && cp "$(git rev-parse --git-path index)" "$index")
  GIT_INDEX_FILE=$index git -C "$1" add -A
  GIT_INDEX_FILE=$index git -C "$1" write-tree
  rm -f "$index"
}

reset_project() {
  git -C "$1" reset -q --hard
  git -C "$1" clean -q -fd
}

declare -A old_patch old_tree
if [ -f "$STAMP" ]; then
  while read -r proj blob tree; do
    old_patch[$proj]=$blob
    old_tree[$proj]=$tree
  done < "$STAMP"
fi

# Each lineage-16/patches/<project path>.patch applies to that project.
# (Patches live under lineage-16/ in this repo so a future crdroid-17 tree
# can carry its own patch set without clashing.)
PATCHDIR="$HERE/patches"
mapfile -t projects < <(cd "$PATCHDIR" && find . -name '*.patch' | sed 's|^\./||; s|\.patch$||' | sort)
[ "${#projects[@]}" -gt 0 ] || {
  echo "No patches found in $PATCHDIR - refusing to build an unpatched ROM." >&2
  exit 1
}
echo "${#projects[@]} patch(es) discovered in $PATCHDIR"
declare -A patched
for proj in "${projects[@]}"; do
  patched[$proj]=1
done

# Undo patches that were removed or renamed since the last run.
for proj in "${!old_patch[@]}"; do
  if [ -z "${patched[$proj]:-}" ] && [ -d "$proj" ]; then
    reset_project "$proj"
    echo "reverted $proj (its patch is gone)"
  fi
done

# Leave a project alone when its patch hasn't changed and its tree is
# exactly as the last run left it: rewriting the files would change their
# mtimes and make the build redo work. Otherwise reset it and apply the
# patch again, so a patch is never applied twice.
# Patches can contain @NAME@ placeholders for build settings. The recorded
# blob is that of the filled-in patch, so changing a setting counts as a
# changed patch.
render_patch() {
  sed "s/@SKIN_THROTTLE_MC@/$((SKIN_THROTTLE_C * 1000))/g" "$PATCHDIR/$1.patch"
}

for proj in "${projects[@]}"; do
  if [ "$(render_patch "$proj" | git hash-object --stdin)" = "${old_patch[$proj]:-}" ] &&
     [ "$(worktree_id "$proj")" = "${old_tree[$proj]:-}" ]; then
    echo "unchanged patches/$proj.patch"
    continue
  fi
  reset_project "$proj"
  render_patch "$proj" | git -C "$proj" apply --whitespace=nowarn
  echo "applied patches/$proj.patch"
done

# An empty *file* at this path stops AOSP from treating
# device/motorola/amogus_doha/kernel-headers as the device's kernel header
# directory (it is added to the include path whenever the path exists, and
# there's no opt-out). The real headers come from
# PRODUCT_VENDOR_KERNEL_HEADERS, set in patches/device/motorola/targets.patch.
[ -e device/motorola/amogus_doha/kernel-headers ] ||
  : > device/motorola/amogus_doha/kernel-headers

# =============================================================================
# Latent-bug fix layer (doha-roms addition, 2026-10 dump triage).
# Fixes the post_boot FORTIFY SIGABRT (BUG #6 - the real cause behind the
# performance-governor bug), 10 avc denials and the legacy prop labels.
# Idempotent; see docs/BUG-REGISTER.md. Runs before the variant layer so
# the stamp below records the tree exactly as this run leaves it.
# =============================================================================
if [ "${LATENT_FIXES:-1}" = 1 ]; then
  bash "$HERE/../scripts/apply-latent-fixes.sh" "$SRC" ||
    echo "WARNING: apply-latent-fixes reported problems - see docs/BUG-REGISTER.md" >&2
else
  echo "LATENT_FIXES=0 - latent-bug fix layer skipped"
fi

# =============================================================================
# Variant layer (doha-roms addition). Runs after the patches, before the
# stamp, so the stamp records the tree exactly as this run leaves it.
# =============================================================================
DEVDIR=device/motorola/amogus_doha

# 1) CPU governor guard (always on). See docs/CPU-GOVERNOR.md: the stock
#    Android 16 build of 2026-09-26 was measured with every CPU pinned to
#    the performance governor. This rc re-selects schedutil after boot.
if [ ! -f "$DEVDIR/init.doha.cpugov.rc" ]; then
  cp "$HERE/../variants/init.doha.cpugov.rc" "$DEVDIR/init.doha.cpugov.rc"
fi
if ! grep -q "doha-roms variant hook" "$DEVDIR/device.mk" 2>/dev/null; then
  cat >> "$DEVDIR/device.mk" << 'EOF'

# doha-roms variant hook (appended by build.sh; keep last).
# init.doha.cpugov.rc: schedutil guard, see docs/CPU-GOVERNOR.md
PRODUCT_COPY_FILES += \
    device/motorola/amogus_doha/init.doha.cpugov.rc:$(TARGET_COPY_OUT_VENDOR)/etc/init/init.doha.cpugov.rc
EOF
fi

# 1b) The variants include goes at the END of the product makefile
#     (device/motorola/targets/devices/amogus_doha/lineage_amogus_doha.mk)
#     so that PRODUCT_PACKAGES filter-outs run AFTER the ROM's common
#     config and the AOSP base product have added their apps.
PRODUCTMK=device/motorola/targets/devices/amogus_doha/lineage_amogus_doha.mk
if [ -f "$PRODUCTMK" ] && ! grep -q "doha-roms variant hook" "$PRODUCTMK"; then
  printf '\n# doha-roms variant hook (appended by build.sh; keep last).\n-include device/motorola/amogus_doha/doha-variants.mk\n' >> "$PRODUCTMK"
fi

# 2) Render doha-variants.mk for this run's VARIANT/DEBLOAT/DOLBY.
render_variants_mk() {
  {
    echo "# Generated by doha-roms build.sh on $(date -u +%Y-%m-%dT%H:%M:%SZ). Do not edit."
    echo "# VARIANT=$VARIANT DEBLOAT=$DEBLOAT DOLBY=$DOLBY"
    echo
    if [ "$DEBLOAT" != none ]; then
      cat "$HERE/../variants/debloat.mk"
      if [ "$DEBLOAT" = aggressive ]; then
        cat "$HERE/../variants/debloat-aggressive.mk"
      fi
    fi
    if [ "$DOLBY" = 1 ]; then
      cat "$HERE/../variants/dolby/dolby.mk"
    fi
  } > "$DEVDIR/doha-variants.mk"
}
render_variants_mk
echo "rendered $DEVDIR/doha-variants.mk (VARIANT=$VARIANT DEBLOAT=$DEBLOAT DOLBY=$DOLBY)"

# 3) Dolby blob wiring. The blobs come from the phone's own stock firmware
#    (see variants/dolby/extract-from-stock.sh and docs/DOLBY.md).
if [ "$DOLBY" = 1 ]; then
  BLOBS="$HERE/../variants/dolby/blobs"
  if [ ! -f "$BLOBS/vendor/lib64/soundfx/libswdap.so" ]; then
    echo "DOLBY=1 but $BLOBS is not populated." >&2
    echo "Run variants/dolby/extract-from-stock.sh with the stock ROM booted" >&2
    echo "(or extract from your stock firmware zip). See docs/DOLBY.md." >&2
    exit 1
  fi
  # Copy blobs into the moto vendor blob tree at the exact install paths.
  VENDORBLOB=vendor/motorola/amogus/proprietary
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    mkdir -p "$VENDORBLOB/$(dirname "$rel")"
    cp "$BLOBS/$rel" "$VENDORBLOB/$rel"
  done < "$HERE/../variants/dolby/blobs-list.txt"
  # Append the copy entries to amogus-vendor.mk (marker-checked, so
  # repeated runs with reset trees still work). One complete assignment
  # per line: no line continuations, no trailing-backslash edge cases.
  VMK=vendor/motorola/amogus/amogus-vendor.mk
  if ! grep -q "dolby blobs (doha-roms)" "$VMK"; then
    {
      echo
      echo "# dolby blobs (doha-roms), copied from stock firmware by build.sh DOLBY=1"
      while IFS= read -r rel; do
        [ -n "$rel" ] || continue
        echo "PRODUCT_COPY_FILES += $VENDORBLOB/$rel:\$\(TARGET_COPY_OUT_VENDOR\)/${rel#vendor/}"
      done < "$HERE/../variants/dolby/blobs-list.txt"
    } >> "$VMK"
  fi
  # Wire the effect into every audio_effects.xml/.conf in the tree.
  bash "$HERE/../variants/dolby/wire-audio-effects.sh" "$SRC" \
    || echo "WARNING: Dolby audio_effects wiring skipped - check docs/DOLBY.md" >&2
fi

# Record the result only now, after kernel-headers and the variant layer
# exist, so the next run sees the same trees.
for proj in "${projects[@]}"; do
  echo "$proj $(render_patch "$proj" | git hash-object --stdin) $(worktree_id "$proj")"
done > "$STAMP.new"
mv "$STAMP.new" "$STAMP"

export ALLOW_MISSING_DEPENDENCIES=true
if command -v ccache >/dev/null; then
  export USE_CCACHE=1 CCACHE_EXEC=$(command -v ccache)
  # ccache's own default is 5 GB, far too small for this build.
  ccache -M "${CCACHE_SIZE:-50G}" >/dev/null
fi

# envsetup.sh, breakfast and mka aren't errexit/nounset-clean, so check
# their results by hand.
set +eu
source build/envsetup.sh
breakfast "$DEVICE" userdebug || exit 1
mka -j"$JOBS" target-files-package bacon || exit 1
version=$(get_build_var LINEAGE_VERSION) || exit 1
set -eu

# bacon hard-links the dated zip to lineage_<device>-ota.zip, which the next
# build rewrites in place, so every earlier zip in out/ ends up holding the
# newest build. Keep a real copy of each build, with its images.
product=$SRC/out/target/product/$DEVICE
images=$product/obj/PACKAGING/target_files_intermediates/lineage_$DEVICE-target_files/IMAGES
dest=${ZIP_DIR:-$(dirname "$SRC")/zips}
name=lineage-$version$VARIANT_SUFFIX
mkdir -p "$dest"
cp "$product/$version.zip" "$dest/$name.zip" 2>/dev/null ||
  cp "$product/$(get_build_var LINEAGE_VERSION).zip" "$dest/$name.zip"
for img in boot dtbo vbmeta; do
  cp "$images/$img.img" "$dest/$name-$img.img"
done
(cd "$dest" && sha256sum "$name.zip" "$name"-{boot,dtbo,vbmeta}.img > "$name.sha256sum")

echo
echo "Done. Build copied to $dest:"
ls -1 "$dest/$name"*
echo
echo "Variant: VARIANT=$VARIANT DEBLOAT=$DEBLOAT DOLBY=$DOLBY"
if [ "$VARIANT" = gapps ]; then
  echo "Next: at the recovery 'Install additional zip?' prompt after sideloading"
  echo "the ROM, choose YES and 'adb sideload' MindTheGapps (Play services +"
  echo "Play Store only). Everything else installs from the Play Store."
fi
