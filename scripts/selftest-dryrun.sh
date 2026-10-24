#!/usr/bin/env bash
# =============================================================================
# selftest-dryrun.sh - full DRY-RUN test battery for the whole doha-roms kit.
#
# Runs EVERY script in a way that needs NO network, NO phone, NO `repo`
# tool, NO AOSP tree and NO extra disk (works on a 90%-full laptop):
#
#   S1  syntax:        bash -n on all 9 shell scripts
#   S2  XML validity:  every shipped manifest parses
#   S3  mirror store:  27 tarballs present, gzip-intact, .fact shas ==
#                      default.xml pins (no extraction needed)
#   S4  restore-       sandbox run with the 3 smallest tarballs: XML
#       mirrors.sh     generated + well-formed, pinned SHAs present,
#                      fetch-by-SHA works, idempotent, no-.repo failure
#   S5  build.sh       run with a `repo` STUB: proves repo init ->
#       wiring         mirror-restore -> repo sync ordering, the
#                      STOP_AFTER_SYNC exit, and the upstream-fallback
#                      branch when restore fails
#   S6  doha.sh        every non-interactive subcommand + menu loop:
#                      correct output, graceful failures (no adb/repo
#                      on this box), vendor resume no-op, invalid input
#   S7  selftest-      the existing build.sh path regression (15 checks)
#       paths.sh
#   S8  apply-latent-  mock tree: first run applies everything, second
#       fixes.sh       run is a clean no-op (idempotency)
#   S9  phone scripts  flash-checks.sh / debug_device.sh fail cleanly
#                      when adb is missing
#   S10 colab guard    colab_doha.sh refuses to run off Colab with a
#                      clear message
#
# Usage:  bash scripts/selftest-dryrun.sh       (from anywhere)
# Exit:   0 = all sections passed, 1 = failures (listed at the end)
# =============================================================================
set -uo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)   # doha-roms repo root
TMP="$HERE/.selftest-dryrun"
PASS=0; FAIL=0; FAILED_TESTS=()

ok()   { echo "   ok: $1"; PASS=$((PASS+1)); }
bad()  { echo "   FAIL: $1" >&2; FAIL=$((FAIL+1)); FAILED_TESTS+=("$1"); }
section() { echo; echo "== $1 =="; }

check() { # check <description> <condition-cmd>
  if eval "$2" >/dev/null 2>&1; then ok "$1"; else bad "$1"; fi
}
try()   { # try <description> <expected-rc:0| nonzero> <command...>
  local desc=$1 want=$2; shift 2
  local out rc=0
  out=$(timeout 180 "$@" 2>&1) || rc=$?
  LAST_OUT="$out"
  if [ "$want" = 0 ] && [ $rc -ne 0 ]; then bad "$desc (exit $rc)"; return 1; fi
  if [ "$want" = nonzero ] && [ $rc -eq 0 ]; then bad "$desc (expected failure, got success)"; return 1; fi
  ok "$desc"; return 0
}
out_has() { # out_has <text>  (against LAST_OUT)
  echo "$LAST_OUT" | grep -q "$1"
}

cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

# ===================================================================== S1 ====
section "S1 syntax (bash -n) on all shipped scripts"
for f in doha.sh lineage-16/build.sh cloud/colab_doha.sh \
         scripts/vendor-mirrors.sh scripts/restore-mirrors.sh \
         scripts/apply-latent-fixes.sh scripts/flash-checks.sh \
         scripts/debug_device.sh scripts/selftest-paths.sh; do
  check "bash -n $f" "bash -n '$HERE/$f'"
done

# ===================================================================== S2 ====
section "S2 every shipped XML manifest parses"
# python3 may be absent (or a non-functional Windows Store stub); fall back to a
# structural check so the suite still validates the manifests offline.
xml_ok() { # xml_ok <file>
  if command -v python3 >/dev/null 2>&1 &&
     python3 -c 'import xml.etree.ElementTree' >/dev/null 2>&1; then
    python3 -c 'import xml.etree.ElementTree as ET,sys; ET.parse(sys.argv[1])' "$1"
  else
    [ -s "$1" ] && [ "$(head -1 "$1" | tr -d '\r')" = '<?xml version="1.0" encoding="UTF-8"?>' ] &&
      [ "$(tail -1 "$1" | tr -d '\r')" = '</manifest>' ] &&
      grep -q '<manifest>' "$1"
  fi
}
XMLS=(default.xml crdroid-17/default.xml crdroid-17/snippets_crdroid.xml \
      crdroid-17/snippets_lineage.xml crdroid-17/local_manifest_doha.xml)
for x in "${XMLS[@]}"; do
  check "$x well-formed" "xml_ok '$HERE/$x'"
done

# ===================================================================== S3 ====
section "S3 vendored mirror store integrity (no extraction)"
# pins straight from the manifest (same parse as vendor-mirrors.sh)
mapfile -t PINS < <(
  grep 'local::doha' "$HERE/default.xml" |
  sed -E 's/.*name="([^"]*)".*path="([^"]*)".*remote="([^"]*)".*revision="([0-9a-f]{40})".*/\1|\2|\3|\4/')
check "default.xml carries 27 local::doha projects" "[ '${#PINS[@]}' -eq 27 ]"
n_tgz=0; n_gzip_bad=0
for spec in "${PINS[@]}"; do
  IFS='|' read -r name path remote rev <<<"$spec"
  fact="$HERE/mirrors/repos/$name.fact"
  tgz="$HERE/mirrors/repos/$name.tgz"
  if [ -s "$fact" ] && [ -s "$tgz" ]; then
    n_tgz=$((n_tgz+1))
    # .fact row must agree with the manifest pin (name|path|remote|sha|...)
    grep -q "^$name|$path|$remote|$rev|" "$fact" || bad "$name .fact disagrees with default.xml pin"
    gzip -t "$tgz" 2>/dev/null || { n_gzip_bad=$((n_gzip_bad+1)); bad "$name.tgz fails gzip CRC"; }
  else
    bad "missing tarball or .fact for $name"
  fi
done
check "27 of 27 tarballs + .facts present" "[ $n_tgz -eq 27 ]"
check "all tarballs pass gzip -t" "[ $n_gzip_bad -eq 0 ]"
n_rows=$(grep -vc '^#' "$HERE/mirrors/MIRRORS.tsv")
check "MIRRORS.tsv has 27 data rows" "[ '$n_rows' -eq 27 ]"
# every MIRRORS.tsv sha must match its .fact (no drift between the two lists)
drift=0
while IFS='|' read -r name path remote rev rest; do
  case "$name" in \#*|"") continue ;; esac
  grep -q "^$name|$path|$remote|$rev|" "$HERE/mirrors/repos/$name.fact" || drift=$((drift+1))
done < "$HERE/mirrors/MIRRORS.tsv"
check "MIRRORS.tsv shas == .fact shas (no drift)" "[ $drift -eq 0 ]"

# ===================================================================== S4 ====
section "S4 restore-mirrors.sh sandbox (3 smallest tarballs, symlinked)"
mkdir -p "$TMP/rs-kit/scripts" "$TMP/rs-kit/mirrors/repos" "$TMP/src1/.repo" "$TMP/src-bad"
cp "$HERE/scripts/restore-mirrors.sh" "$TMP/rs-kit/scripts/"
cp "$HERE/mirrors/MIRRORS.tsv"       "$TMP/rs-kit/mirrors/"
mapfile -t SMALL < <(cd "$HERE/mirrors/repos" && ls -S *.tgz | tail -3)
SB="$TMP/rs-kit"
for t in "${SMALL[@]}"; do ln -s "$HERE/mirrors/repos/$t" "$SB/mirrors/repos/$t"; done
SMALL_NAMES=("${SMALL[@]/.tgz/}")

try "restore-mirrors run #1 (sandbox)" 0 bash "$SB/scripts/restore-mirrors.sh" "$TMP/src1"
echo "$LAST_OUT" | grep -q "3 usable mirrors" && ok "reported '3 usable mirrors'" || bad "did not report 3 usable mirrors"
echo "$LAST_OUT" | grep -q "missing tarball"   && ok "skips absent tarballs gracefully" || bad "no skip message for absent tarballs"

XML="$TMP/src1/.repo/local_manifests/doha-mirror.xml"
check "doha-mirror.xml written" "[ -s '$XML' ]"
check "doha-mirror.xml well-formed" "python3 -c \"import xml.etree.ElementTree as ET; ET.parse('$XML')\""
check "3 <remove-project> entries" "[ \$(grep -c 'remove-project' '$XML') -eq 3 ]"
check "3 <project> entries"       "[ \$(grep -c '<project ' '$XML') -eq 3 ]"
check "remote is file:// into the sandbox pool" "grep -q 'fetch=\"file://$SB/mirrors/git\"' '$XML'"
for t in "${SMALL_NAMES[@]}"; do
  check "$t re-added with dohamirror remote + groups=local::doha" \
    "grep -q 'name=\"$t\".*remote=\"dohamirror\".*local::doha' '$XML'"
done
# bare pool: pinned SHA present + fetch-by-SHA enabled
for spec in "${PINS[@]}"; do
  IFS='|' read -r name path remote rev <<<"$spec"
  for t in "${SMALL_NAMES[@]}"; do
    if [ "$t" = "$name" ]; then
      check "$name bare repo contains pinned SHA" \
        "[ \"\$(git -C '$SB/mirrors/git/$name' cat-file -t '$rev')\" = commit ]"
      check "$name allows fetch-by-SHA" \
        "[ \"\$(git -C '$SB/mirrors/git/$name' config uploadpack.allowAnySHA1InWant)\" = true ]"
      # the actual mechanism repo sync will use: fetch an exact SHA over file://
      rm -rf "$TMP/fetchtest"; git init -q "$TMP/fetchtest"
      check "$name: git fetch file://... \$SHA works (repo sync mechanism)" \
        "git -C '$TMP/fetchtest' fetch -q 'file://$SB/mirrors/git/$name' '$rev' && \
         [ \"\$(git -C '$TMP/fetchtest' cat-file -t '$rev')\" = commit ]"
    fi
  done
done
try "restore-mirrors run #2 (idempotent)" 0 bash "$SB/scripts/restore-mirrors.sh" "$TMP/src1"
echo "$LAST_OUT" | grep -q "3 usable mirrors" && ok "second run identical (idempotent)" || bad "second run changed outcome"
try "restore-mirrors without .repo fails cleanly" nonzero bash "$SB/scripts/restore-mirrors.sh" "$TMP/src-bad"
echo "$LAST_OUT" | grep -q "not a repo-initialized tree" && ok "clear error for non-repo tree" || bad "unclear error for non-repo tree"

# ===================================================================== S5 ====
section "S5 build.sh sync wiring (repo stub, STOP_AFTER_SYNC)"
KIT="$TMP/kit"   # sandbox copy of the whole kit minus the heavy tarballs
mkdir -p "$KIT"
tar -C "$HERE" -cf - \
    --exclude='./mirrors/repos' --exclude='./.git' --exclude='./logs' \
    --exclude='./.selftest-mock' --exclude='./.selftest-dryrun' \
    --exclude='./.doha.conf' --exclude='./mirrors/git' . | tar -C "$KIT" -xf -
mkdir -p "$KIT/mirrors/repos"
for t in "${SMALL[@]}"; do ln -s "$HERE/mirrors/repos/$t" "$KIT/mirrors/repos/$t"; done
git -C "$KIT" init -q
git -C "$KIT" add -A >/dev/null
git -C "$KIT" -c user.name=selftest -c user.email=st@st commit -qm kit >/dev/null

mkdir -p "$TMP/bin"
cat > "$TMP/bin/repo" <<'STUB'
#!/usr/bin/env bash
echo "repo: $*"                      # lands in build output -> proves ordering
case "$1" in
  init) [ "${REPO_INIT_NO_DIR:-0}" = 1 ] || mkdir -p "$PWD/.repo" ;;
  sync) : ;;
esac
exit 0
STUB
chmod +x "$TMP/bin/repo"
export PATH="$TMP/bin:$PATH"

SRC2="$TMP/src2"; mkdir -p "$SRC2"
try "build.sh with mirrors + STOP_AFTER_SYNC=1 (repo stub)" 0 \
  env MANIFEST_URL="$KIT" STOP_AFTER_SYNC=1 VARIANT=nogapps DEBLOAT=none DOLBY=0 \
  JOBS=1 SKIP_SYNC= bash "$KIT/lineage-16/build.sh" "$SRC2"
out=$LAST_OUT
pos() { echo "$out" | grep -n "$1" | head -1 | cut -d: -f1; }
p_init=$(pos "repo: init");   p_rest=$(pos "restoring local mirror pool")
p_sync=$(pos "repo: sync");   p_stop=$(pos "STOP_AFTER_SYNC")
check "repo init ran"                    "[ -n '$p_init' ]"
check "mirror pool restore ran"          "[ -n '$p_rest' ]"
check "repo sync ran"                    "[ -n '$p_sync' ]"
check "stopped after sync"               "[ -n '$p_stop' ]"
if [ -n "$p_init" ] && [ -n "$p_rest" ] && [ -n "$p_sync" ]; then
  check "ordering: init -> restore -> sync" \
    "[ $p_init -lt $p_rest ] && [ $p_rest -lt $p_sync ]"
fi
check "local_manifest written into the source tree" "[ -s '$SRC2/.repo/local_manifests/doha-mirror.xml' ]"

# fallback branch: restore must fail (no .repo) -> build.sh warns and syncs upstream anyway
SRC3="$TMP/src3"; mkdir -p "$SRC3"
try "build.sh when mirror restore fails (falls back to upstream)" 0 \
  env REPO_INIT_NO_DIR=1 MANIFEST_URL="$KIT" STOP_AFTER_SYNC=1 \
  VARIANT=nogapps DEBLOAT=none DOLBY=0 JOBS=1 SKIP_SYNC= \
  bash "$KIT/lineage-16/build.sh" "$SRC3"
echo "$LAST_OUT" | grep -q "falling back to upstream sync" && ok "warns and falls back to upstream" || bad "no fallback warning on restore failure"
echo "$LAST_OUT" | grep -q "repo: sync" && ok "sync still runs after failed restore" || bad "sync skipped after failed restore"
export PATH="${PATH#"$TMP/bin:"}"   # drop the repo stub for the remaining tests

# ===================================================================== S6 ====
section "S6 doha.sh subcommands + menu (graceful without repo/adb)"
try "doha.sh status"            0 bash "$HERE/doha.sh" status
echo "$LAST_OUT" | grep -q "doha-roms status" && ok "status reports" || bad "status output wrong"
try "doha.sh help"              0 bash "$HERE/doha.sh" help
echo "$LAST_OUT" | grep -qi "usage\|selftest\|vendor" && ok "help prints usage" || bad "help empty"
try "doha.sh cloud"             0 bash "$HERE/doha.sh" cloud
echo "$LAST_OUT" | grep -q "Colab" && ok "cloud facts print" || bad "cloud output wrong"
try "doha.sh bogus subcommand"  nonzero bash "$HERE/doha.sh" bogus
echo "$LAST_OUT" | grep -q "unknown command" && ok "unknown subcommand rejected" || bad "no error for bogus subcommand"
try "doha.sh flash (batch mode must refuse)" nonzero bash "$HERE/doha.sh" flash
echo "$LAST_OUT" | grep -q "interactive-only" && ok "flash refuses batch mode (destructive, needs a human)" || bad "flash did not refuse batch mode"
try "doha.sh dump (no adb)"     nonzero bash "$HERE/doha.sh" dump
echo "$LAST_OUT" | grep -q "adb not found" && ok "dump fails cleanly without adb" || bad "dump failure not clean"
try "doha.sh sync (no repo tool)" nonzero bash "$HERE/doha.sh" sync
echo "$LAST_OUT" | grep -q "command not found\|sync failed" && ok "sync fails cleanly without repo (batch mode propagates)" || bad "sync failure not clean"
try "doha.sh build16 (no repo tool)" nonzero bash "$HERE/doha.sh" build16
echo "$LAST_OUT" | grep -q "command not found\|build failed" && ok "build16 fails cleanly without repo" || bad "build16 failure not clean"
timeout 60 bash "$HERE/doha.sh" build17 </dev/null >/dev/null 2>&1
rc=$?
check "build17 never hangs without repo (exit $rc, no input)" "[ \$rc -ne 124 ]"
# batch-mode regression: a piped subcommand must never fake success by
# silently answering "no" to its own confirm (the bug this caught for real)
out=$(printf 'n\n' | timeout 90 bash "$HERE/doha.sh" sync 2>&1) || true
echo "$out" | grep -q "sync failed\|command not found" && ok "piped sync with 'n' still attempts + fails loudly (no silent skip)" || bad "piped sync still fakes success"

# menu: invalid option then exit
out=$(printf '99\n0\n' | timeout 60 bash "$HERE/doha.sh" 2>&1) || true
echo "$out" | grep -q "unknown option: 99" && ok "menu rejects unknown option" || bad "menu ignores unknown option"
echo "$out" | grep -q "11) Vendor device repos" && ok "menu shows vendor entry" || bad "menu missing vendor entry"
out=$(printf '0\n' | timeout 60 bash "$HERE/doha.sh" 2>&1) || true
echo "$out" | grep -q "bye" && ok "menu exits cleanly" || bad "menu does not exit cleanly"

# vendor resume: everything already mirrored -> pure no-op, data must not drift.
# Only meaningful (and only safe) with the complete set: on an incomplete
# checkout, "doha.sh vendor" would really fetch the missing repos from GitHub.
tgz_present=$(ls "$HERE"/mirrors/repos/*.tgz 2>/dev/null | wc -l | tr -d ' ')
if [ "$tgz_present" -eq 27 ]; then
  cp "$HERE/mirrors/MIRRORS.tsv" "$TMP/TSV.before"
  try "doha.sh vendor (resume no-op)" 0 bash -c "printf 'y\\n' | '$HERE/doha.sh' vendor"
  echo "$LAST_OUT" | grep -q "27 mirrored, 0 failed" && ok "vendor resume: 27 have / 0 failed" || bad "vendor resume outcome wrong"
  try "MIRRORS.tsv data rows unchanged by resume" 0 \
    bash -c "diff <(grep -v '^#' '$TMP/TSV.before') <(grep -v '^#' '$HERE/mirrors/MIRRORS.tsv')"
else
  echo "   skip: vendor resume no-op (needs 27 tarballs, found $tgz_present; skipping avoids a network fetch)"
fi

# ===================================================================== S7 ====
section "S7 build.sh path regression (selftest-paths.sh, 15 checks)"
try "selftest-paths.sh" 0 bash "$HERE/scripts/selftest-paths.sh"
echo "$LAST_OUT" | grep -q "SELFTEST PASSED" && ok "path selftest passed" || bad "path selftest did not pass"

# ===================================================================== S8 ====
section "S8 apply-latent-fixes.sh on a mock tree (idempotency)"
LF="$TMP/lfsrc"
mkdir -p "$LF/device/motorola/amogus/sepolicy" \
         "$LF/device/qcom/sepolicy_vndr/generic/vendor/common"
printf 'service vendor.post_boot /vendor/bin/sh /vendor/bin/init.qcom.post_boot.sh\n' \
  > "$LF/device/motorola/amogus/init.qcom.rc"
printf '#!/vendor/bin/sh\n# tuning\n' > "$LF/device/motorola/amogus/init.qcom.post_boot.sh"
printf 'ro.product.bevice=doha\n'      > "$LF/device/motorola/amogus/build_doha.prop"
printf '# existing contexts\n'         > "$LF/device/qcom/sepolicy_vndr/generic/vendor/common/property_contexts"

try "apply-latent-fixes run #1" 0 bash "$HERE/scripts/apply-latent-fixes.sh" "$LF"
check "post_boot service re-pointed to /system/bin/sh" \
  "grep -q '/system/bin/sh /vendor/bin/init.qcom.post_boot.sh' '$LF/device/motorola/amogus/init.qcom.rc'"
check "post_boot script shebang fixed" \
  "head -1 '$LF/device/motorola/amogus/init.qcom.post_boot.sh' | grep -q '^#!/system/bin/sh'"
check "doha_amogus_fixes.te installed" \
  "cmp -s '$HERE/latent-fixes/doha_amogus_fixes.te' '$LF/device/motorola/amogus/sepolicy/doha_amogus_fixes.te'"
check "doha_qcom_fixes.te installed" \
  "cmp -s '$HERE/latent-fixes/doha_qcom_fixes.te' '$LF/device/qcom/sepolicy_vndr/generic/vendor/common/doha_qcom_fixes.te'"
check "property_contexts marker appended once" \
  "[ \$(grep -c 'doha-roms latent-fixes property_contexts' '$LF/device/qcom/sepolicy_vndr/generic/vendor/common/property_contexts') -eq 1 ]"
check "ro.product.bevice typo fixed" \
  "grep -q 'ro.product.device=doha' '$LF/device/motorola/amogus/build_doha.prop'"

try "apply-latent-fixes run #2 (idempotency)" 0 bash "$HERE/scripts/apply-latent-fixes.sh" "$LF"
echo "$LAST_OUT" | grep -q "already on /system/bin/sh" && ok "run #2 recognizes fixed interpreter" || bad "run #2 re-does interpreter fix"
check "property_contexts still exactly one marker after run #2" \
  "[ \$(grep -c 'doha-roms latent-fixes property_contexts' '$LF/device/qcom/sepolicy_vndr/generic/vendor/common/property_contexts') -eq 1 ]"
echo "$LAST_OUT" | grep -q "already clean\|already patched" && ok "run #2 is a clean no-op" || bad "run #2 not recognized as done"

# ===================================================================== S9 ====
section "S9 phone scripts without adb (must fail cleanly)"
try "flash-checks.sh without adb" nonzero bash "$HERE/scripts/flash-checks.sh"
echo "$LAST_OUT" | grep -q "adb not found" && ok "flash-checks clean failure" || bad "flash-checks failure not clean"
try "debug_device.sh without adb" nonzero bash "$HERE/scripts/debug_device.sh" "$TMP/unused-dump"
echo "$LAST_OUT" | grep -q "adb not found" && ok "debug_device clean failure" || bad "debug_device failure not clean"
check "debug_device did not leave a stray dump dir behind" "[ ! -e '$TMP/unused-dump' ]"

# ==================================================================== S10 ====
section "S10 colab_doha.sh environment guard (off Colab)"
try "colab_doha.sh off Colab must refuse" nonzero bash "$HERE/cloud/colab_doha.sh"
echo "$LAST_OUT" | grep -q "Google Drive is not mounted" && ok "colab guard message correct" || bad "colab guard message wrong"

# ===================================================================== ====
echo
echo "=================================================="
echo "DRY-RUN BATTERY: $PASS passed, $FAIL failed"
if [ $FAIL -gt 0 ]; then
  echo "failed:" >&2
  for t in "${FAILED_TESTS[@]}"; do echo "  - $t" >&2; done
  exit 1
fi
echo "ALL SECTIONS PASSED"
