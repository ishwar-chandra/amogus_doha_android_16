#!/usr/bin/env bash
# =============================================================================
# selftest-paths.sh - regression test for build.sh's internal path resolution.
#
# Why this exists: build.sh originally computed PATCHDIR as
# $HERE/lineage-16/patches and the variant layer as $HERE/variants/..., both
# of which only resolve if the script sits at the REPO ROOT. It actually
# ships in lineage-16/, so on a real machine it would have silently applied
# ZERO patches and skipped the whole variant layer. The earlier mock test
# replicated the wrong layout and so passed. This test runs the REAL
# lineage-16/build.sh from its REAL location against a mock source tree and
# asserts every path-dependent step happens.
#
# What it covers:
#   * the layout self-check passes with the shipped repo layout
#   * all patches under lineage-16/patches/ are discovered
#   * the patch-application loop is reached with the right project list
#     (patch CONTENTS are not re-tested here; they were validated against
#     realistic mock bases earlier - see repo WORKLOG.md Session 3)
#   * apply-latent-fixes.sh is invoked at the right path
#   * the variant layer copies init.doha.cpugov.rc, appends the device.mk
#     and product .mk hooks, and renders doha-variants.mk
#   * the stamp file is written
#
# The run is EXPECTED to fail at `source build/envsetup.sh` (the mock is not
# an AOSP tree). Everything before that point must succeed.
# =============================================================================
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)   # doha-roms repo root
BUILD="$HERE/lineage-16/build.sh"
PATCHDIR="$HERE/lineage-16/patches"
MOCK="$HERE/.selftest-mock"
SRC="$MOCK/src"

[ -x "$BUILD" ] || { echo "missing $BUILD" >&2; exit 1; }

# ---- 1. discover the patch set (same method as build.sh) --------------------
mapfile -t projects < <(cd "$PATCHDIR" && find . -name '*.patch' |
  sed 's|^\./||; s|\.patch$||' | sort)
[ "${#projects[@]}" -ge 17 ] || { echo "FAIL: only ${#projects[@]} patches found (expected >= 17)" >&2; exit 1; }
echo "1. discovered ${#projects[@]} patches"

# ---- 2. build the mock source tree -------------------------------------------
rm -rf "$MOCK"
mkdir -p "$SRC/.repo"

for proj in "${projects[@]}"; do
  mkdir -p "$SRC/$proj"
  git -C "$SRC/$proj" init -q
  # one committed file so reset --hard never hits an unborn branch
  ( cd "$SRC/$proj" && echo "# selftest" > .selftest &&
    git -C . add .selftest >/dev/null &&
    git -C . -c user.name=t -c user.email=t@t commit -qm init .selftest >/dev/null ) ||
    git -C "$SRC/$proj" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
done

# Files the variant layer and latent-fixes layer touch. amogus_doha and
# targets are patch projects (created above); add their inner files.
mkdir -p "$SRC/device/motorola/targets/devices/amogus_doha"
echo "# mock product makefile" > "$SRC/device/motorola/targets/devices/amogus_doha/lineage_amogus_doha.mk"
( cd "$SRC/device/motorola/targets" && git add -A >/dev/null &&
  git -c user.name=t -c user.email=t@t commit -qm productmk >/dev/null ) || true
echo "# mock device makefile" > "$SRC/device/motorola/amogus_doha/device.mk"
( cd "$SRC/device/motorola/amogus_doha" && git add -A >/dev/null &&
  git -c user.name=t -c user.email=t@t commit -qm devicemk >/dev/null ) || true
mkdir -p "$SRC/vendor/motorola/amogus/proprietary"
echo "# mock vendor makefile" > "$SRC/vendor/motorola/amogus/amogus-vendor.mk"

# ---- 3. pre-stamp the patch state --------------------------------------------
# Write a stamp whose blob+tree match the freshly synced mock worktrees, so
# build.sh prints "unchanged" and does NOT run `git apply` (the mock bases
# are empty; patch content applicability was validated separately).
worktree_id() {
  local index
  index=$(mktemp)
  (cd "$SRC/$1" && cp "$(git rev-parse --git-path index)" "$index")
  GIT_INDEX_FILE=$index git -C "$SRC/$1" add -A
  GIT_INDEX_FILE=$index git -C "$SRC/$1" write-tree
  rm -f "$index"
}
stamp="$SRC/.repo/doha-patches"
: > "$stamp"
for proj in "${projects[@]}"; do
  blob=$(sed "s/@SKIN_THROTTLE_MC@/40000/g" "$PATCHDIR/$proj.patch" | git hash-object --stdin)
  tree=$(worktree_id "$proj")
  echo "$proj $blob $tree" >> "$stamp"
done
echo "2. mock tree + stamp ready ($(wc -l < "$stamp") projects)"

# ---- 4. run the real build.sh -------------------------------------------------
# SKIN_THROTTLE_C=40 must match the 40000 rendered into the stamp above.
out=$(SKIP_SYNC=1 VARIANT=nogapps DEBLOAT=none DOLBY=0 \
      SKIN_THROTTLE_C=40 JOBS=1 \
      bash "$BUILD" "$SRC" 2>&1) || true

echo "$out" | sed 's/^/    | /'

fails=0
check() { # check <description> <condition-cmd>
  if eval "$2" >/dev/null 2>&1; then echo "   ok: $1"; else
    echo "   FAIL: $1" >&2; fails=$((fails+1)); fi
}

echo "3. assertions"
check "layout self-check passed (no layout failure message)" \
  '! echo "$out" | grep -q "layout check failed"'
check "patch discovery reported ${#projects[@]} patches" \
  "echo \"\$out\" | grep -q \"${#projects[@]} patch(es) discovered\""
check "no 'No patches found' abort" \
  '! echo "$out" | grep -q "No patches found"'
check "patch loop reached (first project reported unchanged)" \
  'echo "$out" | grep -q "unchanged patches/"'
check "latent-fixes layer was invoked" \
  'echo "$out" | grep -q "apply-latent-fixes"'
check "variant layer rendered doha-variants.mk" \
  'echo "$out" | grep -q "rendered device/motorola/amogus_doha/doha-variants.mk"'
check "run reached envsetup (stopped exactly where a mock must stop)" \
  'echo "$out" | grep -q "envsetup" || echo "$out" | grep -q "breakfast"'

DEVDIR="$SRC/device/motorola/amogus_doha"
check "cpugov rc copied into device tree" \
  '[ -f "$DEVDIR/init.doha.cpugov.rc" ]'
check "device.mk variant hook appended" \
  'grep -q "doha-roms variant hook" "$DEVDIR/device.mk"'
check "product makefile includes doha-variants.mk" \
  'grep -q "doha-variants.mk" "$SRC/device/motorola/targets/devices/amogus_doha/lineage_amogus_doha.mk"'
check "doha-variants.mk generated" \
  '[ -s "$DEVDIR/doha-variants.mk" ]'
check "doha-variants.mk records the variant" \
  'grep -q "VARIANT=nogapps" "$DEVDIR/doha-variants.mk"'
check "stamp rewritten with ${#projects[@]} projects" \
  '[ "$(wc -l < "$stamp")" -eq "${#projects[@]}" ]'
check "stamp moved into place (no .new leftover)" \
  '[ ! -f "$SRC/.repo/doha-patches.new" ]'
check "kernel-headers guard file created" \
  '[ -e "$SRC/device/motorola/amogus_doha/kernel-headers" ]'

rm -rf "$MOCK"
if [ "$fails" -eq 0 ]; then
  echo "SELFTEST PASSED (build.sh path resolution is correct)"
else
  echo "SELFTEST FAILED: $fails assertion(s)" >&2
  exit 1
fi
