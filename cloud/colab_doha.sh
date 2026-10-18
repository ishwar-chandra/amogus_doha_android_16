#!/usr/bin/env bash
# =============================================================================
# colab_doha.sh - doha-roms build session for Google Colab (CPU runtime).
#
# GPU NOTE: an Android ROM build uses ZERO GPU. Run this on a CPU -> High-RAM
# runtime. A GPU runtime burns ~8-11 compute units/hour for a chip that stays
# idle, and Kaggle GPU sessions even have FEWER vCPU than CPU sessions.
# Full reasoning: docs/BUILD-INFRA.md.
#
# Notebook usage (three cells):
#   1) from google.colab import drive; drive.mount('/content/drive')
#   2) !git clone https://github.com/<you>/doha-roms /content/doha/doha-roms
#      (or unzip a doha-roms-*.zip from MyDrive/doha/repo/ and set
#       REPO_URL= or place the checkout at /content/doha/doha-roms yourself)
#   3) !bash /content/doha/doha-roms/cloud/colab_doha.sh
#
# Environment:
#   TARGET     android16 (default) | kernel | android17-sync
#              android17-sync = prepare the crDroid 17 tree only (its build
#              recipe is manual for now: crdroid-17/README.md)
#   REPO_URL   git URL of your doha-roms fork, cloned if not present
#   REPO_BRANCH  manifest branch (default: main)
#   VARIANT    nogapps (default) | gapps     } passed through to build.sh
#   DEBLOAT    none | safe | aggressive      } (android16 target only)
#   DOLBY      0 (default) | 1              }
#   JOBS       default nproc
#   GDRIVE     default /content/drive/MyDrive/doha
#   FORCE      1 to bypass the disk-space guard
#   SNAPSHOT_ONLY  1 = only refresh the GDrive snapshot, no build
#   INCLUDE_OUT    1 = include out/ in the source snapshot (much bigger,
#                  but the next session resumes packaging faster)
#
# Session flow (see docs/BUILD-INFRA.md §4):
#   restore source snapshot from GDrive  ->  else shallow repo sync
#   restore ccache archive from GDrive   ->  build with warm cache
#   copy zips to GDrive/releases         ->  snapshot src+ccache back
# =============================================================================
set -euo pipefail

TARGET=${TARGET:-android16}
REPO_URL=${REPO_URL:-}
REPO_BRANCH=${REPO_BRANCH:-main}
GDRIVE=${GDRIVE:-/content/drive/MyDrive/doha}
ROOT=/content/doha                 # local ephemeral NVMe - NEVER the mount
SRC=$ROOT/src
ROMS=$ROOT/doha-roms
SNAP=$GDRIVE/snapshots
REL=$GDRIVE/releases
JOBS=${JOBS:-$(nproc 2>/dev/null || echo 4)}

fail() { echo "colab_doha: $*" >&2; exit 1; }

# ---- 1. environment report + guards -----------------------------------------
echo "== doha-roms Colab session: TARGET=$TARGET =="
echo "   CPU cores : $(nproc)"
echo "   RAM       : $(free -h | awk '/^Mem:/{print $2}')"
echo "   /content  : $(df -h /content | awk 'NR==2{print $4}') free"
[ -d /content/drive ] || fail "Google Drive is not mounted. Run drive.mount() in a cell first (see header)."
if [ -n "$REPO_URL" ] && [ ! -d "$ROMS" ]; then
  git clone -q "$REPO_URL" "$ROMS" || fail "could not clone $REPO_URL"
fi
[ -d "$ROMS/lineage-16" ] || fail "doha-roms checkout not found at $ROMS (clone it or set REPO_URL)."

free_kb=$(df -k /content | awk 'NR==2{print $4}')
if [ "$free_kb" -lt 200000000 ] && [ "${FORCE:-0}" != 1 ]; then
  fail "only $((free_kb/1024/1024)) GB free on /content; a shallow A16 tree + out/ needs ~250 GB. Use a bigger runtime or FORCE=1."
fi
if [ "$(nproc)" -lt 4 ]; then
  echo "   WARNING: fewer than 4 vCPU - a full build will not finish in one session." >&2
  echo "            Consider CPU -> High-RAM, or TARGET=kernel." >&2
fi

# ---- 2. tools ----------------------------------------------------------------
apt-get -qq update >/dev/null 2>&1 || true
apt-get -qq install -y git-core ccache zstd rsync pigz >/dev/null 2>&1 || \
  echo "   (apt install had issues - continuing with what is present)"
command -v repo >/dev/null || {
  curl -sSL https://storage.googleapis.com/git-repo-downloads/repo > /usr/local/bin/repo &&
  chmod +x /usr/local/bin/repo
}
command -v zstd >/dev/null || fail "zstd is required (snapshots) but missing."
command -v repo  >/dev/null || fail "repo tool unavailable."

# ---- 3. restore or create the source tree ------------------------------------
snap_src="$SNAP/src-$TARGET.tar.zstd"
if [ -f "$snap_src" ] && [ ! -d "$SRC/.repo" ]; then
  echo "== restoring source snapshot (15-40 min typical) =="
  mkdir -p "$ROOT"
  tar --use-compress-program=zstd -xf "$snap_src" -C "$ROOT"
  echo "   restored $(du -sh "$SRC" 2>/dev/null | cut -f1)"
elif [ -d "$SRC/.repo" ] && [ "${SNAPSHOT_ONLY:-0}" = 1 ]; then
  echo "== source tree present, snapshot-only mode =="
elif [ ! -d "$SRC/.repo" ]; then
  case $TARGET in
    android16|kernel)
      echo "== shallow sync (1-2 h typical) =="
      mkdir -p "$SRC"
      ( cd "$SRC" &&
        git config --global user.email builder@colab 2>/dev/null || true
        git config --global user.name builder 2>/dev/null || true
        repo init -u "$ROMS" -b "$REPO_BRANCH" -m default.xml --depth=1 --git-lfs -g default,-darwin &&
        repo sync -c -j8 --no-tags --no-clone-bundle --retry-fetches=5 )
      ;;
    android17-sync)
      echo "== shallow sync of the crDroid 17 tree =="
      mkdir -p "$ROOT/src17"
      ( cd "$ROOT/src17" &&
        git config --global user.email builder@colab 2>/dev/null || true
        git config --global user.name builder 2>/dev/null || true
        repo init -u "$ROMS/crdroid-17" -b "$REPO_BRANCH" -m default.xml --depth=1 -g default,-darwin &&
        repo sync -c -j8 --no-tags --no-clone-bundle --retry-fetches=5 )
      echo "   tree ready at $ROOT/src17 - build per crdroid-17/README.md"
      exit 0
      ;;
    *) fail "TARGET must be android16 | kernel | android17-sync" ;;
  esac
fi

# ---- 4. restore ccache --------------------------------------------------------
export CCACHE_DIR=${CCACHE_DIR:-$ROOT/ccache}
snap_cc="$SNAP/ccache-$TARGET.tar.zstd"
if compgen -G "$CCACHE_DIR/*" >/dev/null; then
  echo "== ccache present locally =="
elif [ -f "$snap_cc" ]; then
  echo "== restoring ccache snapshot (makes the build 5-10x faster) =="
  mkdir -p "$ROOT"
  tar --use-compress-program=zstd -xf "$snap_cc" -C "$ROOT"
fi

# ---- 5. build -----------------------------------------------------------------
if [ "${SNAPSHOT_ONLY:-0}" != 1 ]; then
  case $TARGET in
    android16)
      echo "== building LineageOS 23.2 / Android 16 (VARIANT=${VARIANT:-nogapps}) =="
      SKIP_SYNC=1 JOBS="$JOBS" ZIP_DIR=$ROOT/zips \
      VARIANT="${VARIANT:-nogapps}" DEBLOAT="${DEBLOAT:-none}" DOLBY="${DOLBY:-0}" \
        bash "$ROMS/lineage-16/build.sh" "$SRC"
      ;;
    kernel)
      echo "== kernel-only build (fits even a small Colab session) =="
      set +e
      ( cd "$SRC" && source build/envsetup.sh && breakfast amogus_doha userdebug && \
        mka -j"$JOBS" bootimage )
      rc=$?
      set -e
      [ $rc -eq 0 ] || fail "kernel build failed"
      mkdir -p "$ROOT/zips"
      cp "$SRC/out/target/product/amogus_doha/boot.img" "$ROOT/zips/"
      ;;
  esac
fi

# ---- 6. archive back to Google Drive -----------------------------------------
mkdir -p "$REL" "$SNAP"
if compgen -G "$ROOT/zips/*" >/dev/null; then
  echo "== copying releases to $REL =="
  rsync -a "$ROOT/zips/" "$REL/"
fi
echo "== refreshing snapshots (src excludes out/ unless INCLUDE_OUT=1) =="
newsrc="$SNAP/src-$TARGET.tar.zstd.new"
if [ "${INCLUDE_OUT:-0}" = 1 ]; then
  tar --use-compress-program=zstd -cf "$newsrc" -C "$ROOT" src 2>/dev/null \
    && mv "$newsrc" "$SNAP/src-$TARGET.tar.zstd" || rm -f "$newsrc"
else
  tar --use-compress-program=zstd -cf "$newsrc" --exclude='src/out' -C "$ROOT" src 2>/dev/null \
    && mv "$newsrc" "$SNAP/src-$TARGET.tar.zstd" || rm -f "$newsrc"
fi
if compgen -G "$CCACHE_DIR/*" >/dev/null; then
  newcc="$SNAP/ccache-$TARGET.tar.zstd.new"
  tar --use-compress-program=zstd -cf "$newcc" -C "$ROOT" ccache 2>/dev/null \
    && mv "$newcc" "$SNAP/ccache-$TARGET.tar.zstd" || rm -f "$newcc"
fi

echo
echo "== session done =="
echo "   releases : $REL"
echo "   snapshots: $SNAP (restored automatically next session)"
echo "   next session: same 3 cells - it will restore and build incrementally."
