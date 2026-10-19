#!/usr/bin/env bash
# =============================================================================
# selftest-crdroid16.sh - offline regression test for the crDroid 12.x
# (Android 16) target. No network, repo tool, phone or AOSP tree needed.
#
#  1. crdroid-16/default.xml is a sound repo manifest: parses, no <include>,
#     no relative remotes, unique paths, every remove-project target exists,
#     every remote defined, the crDroid forks are in, and the 27 doha device
#     projects are present with EXACTLY the pins of the LineageOS manifest.
#  2. crdroid-16/patches/ only overrides patches that exist in lineage-16/ and
#     parses as unified diffs.
#  3. The REAL lineage-16/build.sh with ROM_TARGET=crdroid16 against a mock
#     tree: patch discovery (union), overlay chosen for Connectivity (proved by
#     the pre-stamped blob matching), latent fixes, variant layer incl. the
#     crDroid debloat addition, and a bad ROM_TARGET is refused.
#
# (That the patches APPLY to the real sources was checked against the exact
#  upstream commits - see crdroid-16/VERIFIED.md.)
# =============================================================================
set -euo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
BUILD="$HERE/lineage-16/build.sh"
PATCHDIR="$HERE/lineage-16/patches"
OVERLAY="$HERE/crdroid-16/patches"
MANIFEST="$HERE/crdroid-16/default.xml"
MOCK="$HERE/.selftest-mock-cr16"
SRC="$MOCK/src"
fails=0
check() { # check <description> <condition-cmd>
  if eval "$2" >/dev/null 2>&1; then echo "   ok: $1"; else echo "   FAIL: $1" >&2; fails=$((fails+1)); fi
}
command -v python3 >/dev/null || { echo "selftest-crdroid16: python3 is required" >&2; exit 1; }
[ -x "$BUILD" ] && [ -f "$MANIFEST" ] || { echo "missing build.sh or crdroid-16/default.xml" >&2; exit 1; }

echo "1. crdroid-16/default.xml"
set +e
python3 - "$MANIFEST" "$HERE" <<'PY'
import sys, collections
import xml.etree.ElementTree as ET
man, root = sys.argv[1:3]
bad = 0
def ok(m): print('   ok: ' + m)
def fail(m):
    global bad; bad += 1; print('   FAIL: ' + m, file=sys.stderr)
try:
    r = ET.parse(man).getroot(); ok('manifest parses')
except Exception as e:
    fail(f'manifest does not parse: {e}'); sys.exit(1)
(fail if r.findall('include') else ok)('no <include> left (self-contained)' if not r.findall('include') else 'unresolved <include>')
rem = {x.get('name'): x for x in r.findall('remote')}
rel = [n for n, x in rem.items() if x.get('fetch', '').startswith('.')]
(fail if rel else ok)(f'relative remote(s): {rel}' if rel else 'all remotes are absolute URLs')
table = collections.OrderedDict(); err = []
for el in r:
    if el.tag == 'project':
        p = el.get('path', el.get('name'))
        if p in table: err.append(f'duplicate path {p}')
        table[p] = el
    elif el.tag == 'remove-project':
        hit = [k for k, v in table.items() if v.get('name') == el.get('name')]
        if not hit: err.append(f'remove-project of unknown {el.get("name")}')
        for k in hit: del table[k]
(fail if err else ok)('; '.join(err) if err else f'repo-style processing clean ({len(table)} projects)')
und = [e.get('name') for e in table.values() if e.get('remote') and e.get('remote') not in rem]
(fail if und else ok)(f'undefined remote(s) used: {und}' if und else 'every project remote is defined')
(fail if len(table) < 1100 else ok)(f'project count {len(table)}')
forks = {'system/core': 'crdroidandroid/android_system_core',
         'packages/modules/Connectivity': 'crdroidandroid/android_packages_modules_Connectivity',
         'vendor/lineage': 'crdroidandroid/android_vendor_crdroid'}
miss = [p for p, n in forks.items() if p not in table or table[p].get('name') != n]
(fail if miss else ok)(f'crDroid fork(s) missing: {miss}' if miss else 'crDroid forks present (system/core, Connectivity, vendor/lineage)')
tsv = [l.rstrip('\n').split('|') for l in open(f'{root}/mirrors/MIRRORS.tsv') if l.strip() and not l.startswith('#')]
kit = {p.get('name'): p for p in ET.parse(f'{root}/default.xml').getroot().findall('project')}
byname = {e.get('name'): e for e in table.values()}
gone = [t[0] for t in tsv if t[0] not in byname]
(fail if gone else ok)(f'doha project(s) missing: {gone}' if gone else f'all {len(tsv)} doha projects present')
drift = [t[0] for t in tsv if t[0] in byname and byname[t[0]].get('revision') != kit[t[0]].get('revision')]
(fail if drift else ok)(f'pin differs from the LineageOS manifest: {drift}' if drift else 'doha pins identical to the LineageOS manifest')
sys.exit(bad)
PY
fails=$((fails + $?))
set -e

echo "2. patch overlay"
mapfile -t over < <(cd "$OVERLAY" && find . -name '*.patch' | sed 's|^\./||; s|\.patch$||' | sort)
check "overlay holds at least one patch (${#over[@]})" '[ "${#over[@]}" -ge 1 ]'
for o in "${over[@]}"; do
  check "overlay $o.patch replaces an existing lineage-16 patch" '[ -f "$PATCHDIR/$o.patch" ]'
  check "overlay $o.patch parses as a unified diff" 'git apply --stat "$OVERLAY/$o.patch"'
done

echo "3. build.sh with ROM_TARGET=crdroid16 against a mock tree"
mapfile -t projects < <({ (cd "$PATCHDIR" && find . -name '*.patch'); (cd "$OVERLAY" && find . -name '*.patch'); } |
  sed 's|^\./||; s|\.patch$||' | sort -u)
rm -rf "$MOCK"; mkdir -p "$SRC/.repo"
for proj in "${projects[@]}"; do
  mkdir -p "$SRC/$proj"; git -C "$SRC/$proj" init -q
  ( cd "$SRC/$proj" && echo "# selftest" > .selftest && git add .selftest >/dev/null &&
    git -c user.name=t -c user.email=t@t commit -qm init >/dev/null )
done
mkdir -p "$SRC/device/motorola/targets/devices/amogus_doha"
echo "# mock product makefile" > "$SRC/device/motorola/targets/devices/amogus_doha/lineage_amogus_doha.mk"
echo "# mock device makefile" > "$SRC/device/motorola/amogus_doha/device.mk"
for d in device/motorola/targets device/motorola/amogus_doha; do
  ( cd "$SRC/$d" && git add -A >/dev/null && git -c user.name=t -c user.email=t@t commit -qm mk >/dev/null ) || true
done
mkdir -p "$SRC/vendor/motorola/amogus/proprietary"; echo "# mock vendor makefile" > "$SRC/vendor/motorola/amogus/amogus-vendor.mk"
worktree_id() { local index; index=$(mktemp)
  (cd "$SRC/$1" && cp "$(git rev-parse --git-path index)" "$index")
  GIT_INDEX_FILE=$index git -C "$SRC/$1" add -A; GIT_INDEX_FILE=$index git -C "$SRC/$1" write-tree; rm -f "$index"; }
eff() { if [ -f "$OVERLAY/$1.patch" ]; then echo "$OVERLAY/$1.patch"; else echo "$PATCHDIR/$1.patch"; fi; }
stamp="$SRC/.repo/doha-patches"; : > "$stamp"
for proj in "${projects[@]}"; do   # pre-stamp with the EFFECTIVE (overlay-aware) patch
  echo "$proj $(sed "s/@SKIN_THROTTLE_MC@/40000/g" "$(eff "$proj")" | git hash-object --stdin) $(worktree_id "$proj")" >> "$stamp"
done
run() { ROM_TARGET=crdroid16 SKIP_SYNC=1 SKIN_THROTTLE_C=40 JOBS=1 DOLBY=0 "$@" bash "$BUILD" "$SRC" 2>&1 || true; }
out=$(run env VARIANT=gapps DEBLOAT=safe)
echo "$out" | sed 's/^/    | /'
DEVDIR="$SRC/device/motorola/amogus_doha"
check "layout self-check passed" '! echo "$out" | grep -q "layout check failed"'
check "union of patches discovered (${#projects[@]})" 'echo "$out" | grep -q "${#projects[@]} patch(es) discovered"'
check "overlay reported (${#over[@]} replaced)" 'echo "$out" | grep -q "replaces ${#over[@]} of them (ROM_TARGET=crdroid16)"'
check "overlay patch is the one in effect (stamp blob matched, no apply attempted)" \
  'echo "$out" | grep -q "unchanged patches/packages/modules/Connectivity.patch" && ! echo "$out" | grep -qi "error: "'
check "latent-fixes layer invoked" 'echo "$out" | grep -q "apply-latent-fixes"'
check "variant layer rendered doha-variants.mk" 'echo "$out" | grep -q "rendered device/motorola/amogus_doha/doha-variants.mk"'
check "gapps+safe: base debloat (Jelly) rendered" 'grep -q "Jelly" "$DEVDIR/doha-variants.mk"'
check "gapps+safe: crDroid debloat addition (Gallery2) rendered" 'grep -q "Gallery2" "$DEVDIR/doha-variants.mk"'
check "gapps+safe: calculator filtered by its real module name (ExactCalculator)" 'grep -q "ExactCalculator" "$DEVDIR/doha-variants.mk"'
check "run reached envsetup (stops where a mock must)" 'echo "$out" | grep -q "envsetup" || echo "$out" | grep -q "breakfast"'
check "stamp rewritten with ${#projects[@]} projects" '[ "$(wc -l < "$stamp")" -eq "${#projects[@]}" ]'
out2=$(run env VARIANT=nogapps DEBLOAT=none)
check "nogapps/none: no debloat lines rendered" '! grep -q "Gallery2" "$DEVDIR/doha-variants.mk"'
check "nogapps/none: records the variant" 'grep -q "VARIANT=nogapps" "$DEVDIR/doha-variants.mk"'
bad_out=$(ROM_TARGET=bogus SKIP_SYNC=1 bash "$BUILD" "$SRC" 2>&1) && bad_rc=0 || bad_rc=$?
check "unknown ROM_TARGET is refused" '[ "$bad_rc" -ne 0 ] && echo "$bad_out" | grep -q "ROM_TARGET must be"'

rm -rf "$MOCK"
if [ "$fails" -eq 0 ]; then echo "SELFTEST PASSED (crDroid 16 target is consistent)"; else
  echo "SELFTEST FAILED: $fails assertion(s)" >&2; exit 1; fi
