#!/usr/bin/env bash
# =============================================================================
# doha.sh - THE ultimate interactive script for doha-roms
# Moto G8 Plus (doha) - Android 16 (LineageOS 23.2 or crDroid 12.x) + Android 17 (crDroid)
#
# One entry point. Everything is automated - you never run a patch, a
# fix layer or a make command manually:
#
#   * repo sync, all 17 patches, the latent-bug fix layer, the variant
#     layer (gapps/debloat/dolby) and the build itself are handled by
#     lineage-16/build.sh - this menu just asks WHAT you want.
#   * flashing guidance, post-flash verification and full debug dumps
#     are menu items too.
#
# Usage:
#   bash doha.sh                  interactive menu (the normal way)
#   bash doha.sh <command>        non-interactive, for power users:
#     status | env | sync | build16 | buildcr16 | kernel | build17 | oneshot
#     selftest | flash | dump | cloud | vendor | help
#   build16 flags: --variant nogapps|gapps --debloat none|safe|aggressive
#                  --dolby --jobs N --src /path/to/src --rom lineage|crdroid
#   buildcr16 = build16 --rom crdroid: crDroid 12.x on Android 16, its own
#   source tree (default ~/doha/src-crdroid16), same patches + fixes + variants
#
# First run: choose menu item 1 (setup). It checks your machine and
# remembers your paths in .doha.conf. After that: item 6 does everything
# (setup -> sync -> build) in one go, or 2 + 3 step by step.
#
# Logs of every action: logs/doha-*.log
# Full docs: README.md, docs/BUILD-INFRA.md, docs/BUG-REGISTER.md
# =============================================================================
set -u

REPOROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
CONF="$REPOROOT/.doha.conf"
LOGDIR="$REPOROOT/logs"
BUILD="$REPOROOT/lineage-16/build.sh"
SELFTEST="$REPOROOT/scripts/selftest-paths.sh"
DRYTEST="$REPOROOT/scripts/selftest-dryrun.sh"
CR16TEST="$REPOROOT/scripts/selftest-crdroid16.sh"
FLASHCHECKS="$REPOROOT/scripts/flash-checks.sh"
DUMPSCRIPT="$REPOROOT/scripts/debug_device.sh"
LATENT="$REPOROOT/scripts/apply-latent-fixes.sh"
LOG=""

# ---------- defaults (overridden by .doha.conf / flags) ----------------------
SRC="$HOME/doha/src"
SRC17="$HOME/doha/src17"
SRCCR16="$HOME/doha/src-crdroid16"   # crDroid 12.x (Android 16): never share a tree with LineageOS
ROM_TARGET=lineage16                 # lineage16 | crdroid16 (set by --rom, buildcr16, menu 12)
ZIP_DIR="$HOME/doha/zips"
CCACHE_DIR="$HOME/doha/ccache"
JOBS=$(nproc 2>/dev/null || echo 4)
VARIANT=nogapps
DEBLOAT=none
DOLBY=0
DUMPS_DIR="$HOME/doha-dumps"

[ -f "$CONF" ] && . "$CONF"   # remembered settings survive re-runs
SRC_LINEAGE=$SRC              # the LineageOS tree, kept apart from the crDroid one

# ---------- cosmetics ---------------------------------------------------------
if [ -t 1 ]; then
  B=$(tput bold 2>/dev/null || true); N=$(tput sgr0 2>/dev/null || true)
  G=$(tput setaf 2 2>/dev/null || true); R=$(tput setaf 1 2>/dev/null || true)
  Y=$(tput setaf 3 2>/dev/null || true); C=$(tput setaf 6 2>/dev/null || true)
else B=""; N=""; G=""; R=""; Y=""; C=""; fi
hr() { echo "${C}================================================================${N}"; }
say() { echo "${B}$*${N}"; }
note() { echo "${Y}  note:${N} $*"; }
die() { echo "${R}doha.sh: $*${N}" >&2; exit 1; }
rom_label() { case "$ROM_TARGET" in crdroid16) echo "crDroid 12.x" ;; *) echo "LineageOS 23.2" ;; esac; }

# ---------- logging -----------------------------------------------------------
log_init() {
  mkdir -p "$LOGDIR"
  LOG="$LOGDIR/doha-$(date +%Y%m%d-%H%M%S).log"
  : > "$LOG"
  echo "doha.sh run: $(date)" >> "$LOG"
  echo "args: $*" >> "$LOG"
}
log_line() { [ -n "$LOG" ] && echo "$*" >> "$LOG"; }
run_logged() {  # run_logged <label> <command...>  - prints AND logs
  local label=$1; shift
  echo
  say "== $label =="
  echo "--- $label: \$ $*" >> "$LOG"
  "$@" 2>&1 | tee -a "$LOG"
  return "${PIPESTATUS[0]}"
}

# ---------- tiny interactive helpers (work piped or on a terminal) -----------
confirm() {  # confirm [prompt]  -> 0=yes
  # Subcommand (batch) mode: auto-proceed so `bash doha.sh sync` piped from
  # a script/CI can NEVER silently skip work and report success (a bare EOF
  # on stdin used to answer "no" and exit 0). Destructive actions (flash)
  # refuse batch mode instead - see action_flash.
  if [ "${DOHA_BATCH:-0}" = 1 ]; then
    echo "  (batch mode: auto-yes) $*" >&2
    return 0
  fi
  local p="${1:-Proceed?}" ans=""
  printf '%s' "$p [y/N]: " >&2
  read -r ans || true
  case "$ans" in y|Y|yes|YES|Yes) return 0 ;; *) return 1 ;; esac
}
choose() {  # choose <varname> <title> "value1|description1" "value2|..."
  local __var=$1 __title=$2; shift 2
  local vals=() descs=() o sel i
  for o in "$@"; do vals+=("${o%%|*}"); descs+=("${o#*|}"); done
  echo "$__title" >&2
  for i in "${!descs[@]}"; do echo "  $((i+1))) ${descs[$i]}" >&2; done
  while :; do
    printf 'Select 1-%s (Enter=1): ' "${#vals[@]}" >&2
    read -r sel || { sel=1; break; }
    [ -z "$sel" ] && sel=1
    case $sel in *[!0-9]*) echo "  numbers only" >&2; continue ;; esac
    [ "$sel" -ge 1 ] && [ "$sel" -le "${#vals[@]}" ] && break
    echo "  out of range" >&2
  done
  printf -v "$__var" '%s' "${vals[$((sel-1))]}"
}
save_conf() {
  local lsrc=$SRC crsrc=$SRCCR16
  if [ "$ROM_TARGET" = crdroid16 ]; then lsrc=$SRC_LINEAGE; crsrc=$SRC; fi
  {
    echo "SRC=$lsrc"; echo "SRC17=$SRC17"; echo "SRCCR16=$crsrc"; echo "ZIP_DIR=$ZIP_DIR"
    echo "CCACHE_DIR=$CCACHE_DIR"; echo "JOBS=$JOBS"
    echo "VARIANT=$VARIANT"; echo "DEBLOAT=$DEBLOAT"; echo "DOLBY=$DOLBY"
    echo "DUMPS_DIR=$DUMPS_DIR"
  } > "$CONF"
  echo "(settings remembered in .doha.conf)"
}

# ---------- status ------------------------------------------------------------
git_ok() { git -C "$REPOROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; }
manifest_committed() {
  # both manifests build.sh can init from must be in HEAD and unmodified
  local f
  for f in default.xml crdroid-16/default.xml; do
    [ -f "$REPOROOT/$f" ] || continue
    git -C "$REPOROOT" cat-file -e "HEAD:$f" >/dev/null 2>&1 || return 1
    git -C "$REPOROOT" diff --quiet HEAD -- "$f" >/dev/null 2>&1 || return 1
  done
  return 0
}
action_status() {
  hr; say "doha-roms status"; hr
  local synced=no zips=0 stamps=0
  [ -d "$SRC/.repo" ] && synced="yes ($(du -sh "$SRC" 2>/dev/null | cut -f1))"
  [ -d "$SRC/.repo" ] && [ -f "$SRC/.repo/doha-patches" ] && \
    stamps=$(wc -l < "$SRC/.repo/doha-patches" | tr -d ' ')
  [ -d "$ZIP_DIR" ] && zips=$(find "$ZIP_DIR" -name '*.zip' 2>/dev/null | wc -l)
  echo "  source (A16)     : $SRC - synced: $synced"
  echo "  source (A17)     : $SRC17 - $([ -d "$SRC17/.repo" ] && echo synced || echo not synced)"
  echo "  source (crDroid16): $SRCCR16 - $([ -d "$SRCCR16/.repo" ] && echo synced || echo not synced)"
  echo "  patches applied  : $stamps of 17 (0 = fresh tree; build applies them)"
  echo "  zips built       : $zips in $ZIP_DIR"
  echo "  ccache           : $([ -d "$CCACHE_DIR" ] && du -sh "$CCACHE_DIR" 2>/dev/null | cut -f1 || echo none)"
  echo "  dolby blobs      : $([ -f "$REPOROOT/variants/dolby/blobs/vendor/lib64/soundfx/libswdap.so" ] && echo present || echo 'not extracted (see docs/DOLBY.md)')"
  echo "  device mirrors   : $(ls "$REPOROOT"/mirrors/repos/*.tgz 2>/dev/null | wc -l) of 27 vendored $([ -s "$REPOROOT/mirrors/MIRRORS.tsv" ] && echo "(sync uses LOCAL mirror)" || echo "(sync uses upstream - run menu 11)")"
  echo "  repo is git repo : $(git_ok && echo yes || echo 'NO - run menu 1 (setup)')"
  echo "  build.sh selftest: $([ -x "$SELFTEST" ] && echo available || echo missing) | dry-run battery: $([ -x "$DRYTEST" ] && echo available || echo missing)"
  hr
}

# ---------- 1) setup + environment check --------------------------------------
action_env() {
  hr; say "Environment check (menu 1)"; hr
  local problems=0
  chk() { # chk <label> <test-cmd...>
    if "$@" >/dev/null 2>&1; then echo "  ${G}OK${N}    $1"; else
      echo "  ${R}MISS${N}  $1"; problems=$((problems+1)); fi
  }
  echo "machine:"
  echo "  CPUs      : $(nproc)"
  echo "  RAM       : $(free -h | awk '/^Mem:/{print $2}') total"
  free_gb=$(df -BG "$(dirname "$SRC")" 2>/dev/null | awk 'NR==2{print $4}' | tr -dc '0-9')
  [ -z "$free_gb" ] && free_gb=$(df -BG "$HOME" | awk 'NR==2{print $4}' | tr -dc '0-9')
  echo "  disk free : ${free_gb:-?} GB at $(dirname "$SRC") (need 350+ GB to build)"
  if [ "${free_gb:-0}" -lt 350 ]; then
    note "under 350 GB - the full sync+build will not fit. See docs/BUILD-INFRA.md"
    note "(bigger disk, external SSD, or cloud options)"
  fi
  [ "$(nproc)" -lt 8 ] && note "fewer than 8 CPUs: builds will be slow but will finish"
  ram_gb=$(free -m | awk '/^Mem:/{print $2}'); ram_gb=$((ram_gb/1024))
  [ "$ram_gb" -lt 16 ] && note "under 16 GB RAM: add swap (README 'Building') or build in Docker per README"
  echo; echo "tools:"
  chk "git"      command git
  chk "repo"     command repo
  chk "ccache"   command ccache
  chk "zstd"     command zstd
  chk "rsync"    command rsync
  chk "adb (flashing/debug)"  command adb
  chk "fastboot (flashing)"   command fastboot
  echo; echo "repo state:"
  if git_ok; then
    echo "  ${G}OK${N}    git repository"
    if manifest_committed; then echo "  ${G}OK${N}    manifests committed (default.xml, crdroid-16/default.xml)"
    else echo "  ${R}MISS${N}  default.xml / crdroid-16/default.xml not committed or modified (build.sh refuses to run)"; problems=$((problems+1)); fi
  else
    echo "  ${R}MISS${N}  not a git repository - repo init needs this"; problems=$((problems+1))
  fi
  echo
  if [ "$problems" -gt 0 ]; then
    say "$problems problem(s) found."
    if git_ok; then
      if confirm "Commit the repo state now (git add -A + commit)?"; then
        ( cd "$REPOROOT" && git add -A &&
          git -c user.name=doha -c user.email=doha@local \
            commit -qm "doha.sh setup $(date +%F)" ) && echo "committed."
      fi
    elif confirm "Make this directory a git repository and commit everything (needed for repo init)?"; then
      git -C "$REPOROOT" init -q
      ( cd "$REPOROOT" && git add -A &&
        git -c user.name=doha -c user.email=doha@local \
          commit -qm "doha-roms snapshot $(date +%F)" ) && echo "committed."
    fi
    command -v repo >/dev/null || cat <<'EOF'
  Install the repo tool:
    sudo apt-get install repo
  or: mkdir -p ~/.local/bin &&
      curl -o ~/.local/bin/repo https://storage.googleapis.com/git-repo-downloads/repo &&
      chmod +x ~/.local/bin/repo   (then re-open the terminal)
  No native build deps? Build in Docker instead - README.md shows the
  exact docker run command, or use cloud/colab_doha.sh / Crave
  (docs/BUILD-INFRA.md).
EOF
  else
    say "Everything looks good. Menu 6 (one-shot build) can take it from here."
  fi
  save_conf
}

# ---------- 2) sync only ------------------------------------------------------
action_sync() {
  log_init sync
  mkdir -p "$SRC" "$ZIP_DIR" "$CCACHE_DIR"
  hr; say "Syncing the Android 16 source tree - $(rom_label) (patches apply later, at build time)"
  echo "  target: $SRC"
  echo "  first sync: ~150-200 GB, 1-2 h. Interrupted? just run it again - it resumes."
  echo "  device repos: $([ -s "$REPOROOT/mirrors/MIRRORS.tsv" ] && echo "from LOCAL vendored mirror (offline-safe)" || echo "from upstream GitHub (run menu 11 once to vendor them locally)")"
  hr
  if confirm "Start sync now?"; then
    if run_logged "repo sync" env STOP_AFTER_SYNC=1 ROM_TARGET="$ROM_TARGET" ZIP_DIR="$ZIP_DIR" \
        CCACHE_DIR="$CCACHE_DIR" CCACHE_SIZE="${CCACHE_SIZE:-50G}" \
        bash "$BUILD" "$SRC"; then
      say "Sync done. Build any time with menu 3."
    else
      die "sync failed - see $LOG (HTTP 429? wait a few minutes and rerun - it resumes)"
    fi
  fi
}

# ---------- 3) build Android 16 (the proven target) --------------------------
action_build16() {
  log_init build16
  mkdir -p "$ZIP_DIR" "$CCACHE_DIR"
  hr
  if [ "$ROM_TARGET" = crdroid16 ]; then
    say "BUILD: Android 16 / crDroid 12.x (second ROM base - NOT yet built or flashed)"
  else
    say "BUILD: Android 16 / LineageOS 23.2 (the proven target)"
  fi
  hr
  cat <<'EOF'
  How it works - NOTHING is manual:
    1. repo sync (incremental, skipped if fresh, resumable)
    2. all 17 patches apply automatically (touch fix, BPF gates, ...)
    3. latent-bug fixes install automatically (post_boot crash fix,
       10 sepolicy fixes, prop relabels)
    4. the variant layer renders (gapps/debloat/dolby)
    5. mka bacon builds; zips land in your zips dir
EOF
  if [ "$ROM_TARGET" = crdroid16 ]; then
    echo "  crDroid notes: its own source tree (below, ~150 GB more disk); 16 of the 17"
    echo "  patches apply as-is and Connectivity uses the crDroid variant"
    echo "  (crdroid-16/patches). Keep your LineageOS zip as the fallback."
    echo "  Details: crdroid-16/README.md"
  fi
  echo
  choose VARIANT "ROM edition:" \
    "nogapps|Pure AOSP apps, no Google code (default, safest)" \
    "gapps|Debloated ROM + sideload MindTheGapps after flash (Play services + Store only)"
  if [ "$VARIANT" = gapps ]; then
    choose DEBLOAT "Debloat tier (gapps edition):" \
      "safe|Remove only what docs/DEBLOAT.md proves safe (recommended)" \
      "aggressive|Also remove the aggressive list (read docs first)"
  else DEBLOAT=none; fi
  DOLBY=0
  if [ -f "$REPOROOT/variants/dolby/blobs/vendor/lib64/soundfx/libswdap.so" ]; then
    confirm "Dolby blobs are extracted - include Dolby Atmos (DOLBY=1)?" && DOLBY=1
  else
    note "Dolby blobs not extracted yet (optional): boot stock once and run"
    note "  bash variants/dolby/extract-from-stock.sh   - see docs/DOLBY.md"
  fi
  echo
  echo "  jobs        : $JOBS"
  echo "  source      : $SRC"
  echo "  zips ->     : $ZIP_DIR"
  echo "  ccache      : $CCACHE_DIR (warm cache = much faster rebuilds)"
  hr
  confirm "Start the build now?" || { echo "aborted."; return 0; }
  if run_logged "build Android 16 / $(rom_label) (VARIANT=$VARIANT DEBLOAT=$DEBLOAT DOLBY=$DOLBY)" \
      env ROM_TARGET="$ROM_TARGET" VARIANT="$VARIANT" DEBLOAT="$DEBLOAT" DOLBY="$DOLBY" JOBS="$JOBS" \
      ZIP_DIR="$ZIP_DIR" CCACHE_DIR="$CCACHE_DIR" \
      CCACHE_SIZE="${CCACHE_SIZE:-50G}" bash "$BUILD" "$SRC"; then
    save_conf
    hr; say "BUILD DONE"; hr
    echo "  zips and images: $ZIP_DIR"
    echo "  next: menu 8 (flash assistant), then menu 8 -> post-flash checks"
    if [ "$VARIANT" = gapps ]; then
      echo "  gapps: at the recovery 'Install additional zip?' prompt, answer Yes"
      echo "        and: adb sideload MindTheGapps-*.zip (Play services + Store only)"
    fi
  else
    die "build failed - see $LOG (and logs/ for the full history)"
  fi
}

# ---------- 12) Android 16 on crDroid 12.x (second ROM base) -------------------
action_buildcr16() {
  local prev_rom=$ROM_TARGET prev_src=$SRC
  ROM_TARGET=crdroid16
  [ "${SRC_GIVEN:-0}" = 1 ] || SRC=$SRCCR16
  action_build16
  ROM_TARGET=$prev_rom; SRC=$prev_src
}

# ---------- 4) kernel only ----------------------------------------------------
action_kernel() {
  log_init kernel
  [ -d "$SRC/.repo" ] || die "no synced source at $SRC - run menu 2 (sync) first"
  hr; say "BUILD: kernel only (fast test loop, ~30-60 min)"; hr
  echo "  builds boot.img only - good for testing kernel patches quickly"
  confirm "Start kernel build?" || return 0
  if run_logged "kernel only" bash -c "
    set +e
    cd '$SRC' &&
    source build/envsetup.sh &&
    breakfast amogus_doha userdebug &&
    mka -j'$JOBS' bootimage
    rc=\$?; [ \$rc -ne 0 ] && exit \$rc
    mkdir -p '$ZIP_DIR'
    cp out/target/product/amogus_doha/boot.img '$ZIP_DIR/' &&
    echo 'kernel image copied to $ZIP_DIR/boot.img'
  "; then
    say "kernel done: $ZIP_DIR/boot.img"
  else
    die "kernel build failed - see $LOG"
  fi
}

# ---------- 5) Android 17 (crDroid bring-up) ----------------------------------
action_build17() {
  log_init build17
  hr; say "BUILD: Android 17 / crDroid 17.0 (BRING-UP - advanced)"; hr
  cat <<'EOF'
  WARNING: this is the Android 17 bring-up kit, NOT a proven build.
   * nobody has published a doha Android 17 build yet
   * expect failed builds - each costs hours; the lineage-16 target
     (menu 3) is the stable one, build THAT first
   * what this automates: tree sync + local doha manifest + pins +
     the as-is touch patch + latent fixes + breakfast + mka bacon
   * what stays manual: re-targeting the other 16 patches
     (crdroid-17/patches/README.md tells you exactly where each goes)
EOF
  echo
  confirm "Continue with the Android 17 bring-up anyway?" || { echo "aborted."; return 0; }
  local srcsel=""
  choose srcsel "Manifest source:" \
    "pinned|Frozen snapshot in this repo (reproducible - recommended)" \
    "fresh|crdroidandroid/android branch 17.0 (moves daily)"
  mkdir -p "$SRC17"
  local branch
  branch=$(git -C "$REPOROOT" symbolic-ref -q --short HEAD 2>/dev/null || echo main)
  if [ "$srcsel" = pinned ]; then
    if ! run_logged "repo init (pinned crDroid 17 manifest)" bash -c "
      cd '$SRC17' &&
      repo init -u '$REPOROOT' -b '$branch' \
        -m crdroid-17/default.xml --depth=1 -g default,-darwin"; then
      die "repo init failed - see $LOG"
    fi
  else
    if ! run_logged "repo init (crDroid 17.0 branch)" bash -c "
      cd '$SRC17' && repo init -u https://github.com/crdroidandroid/android -b 17.0 -g default,-darwin"; then
      die "repo init failed - see $LOG"
    fi
  fi
  mkdir -p "$SRC17/.repo/local_manifests"
  cp "$REPOROOT/crdroid-17/local_manifest_doha.xml" "$SRC17/.repo/local_manifests/doha.xml"
  run_logged "repo sync (first time ~1-2 h; rerun to resume)" \
    bash -c "cd '$SRC17' && repo sync -c -j8 --no-tags --no-clone-bundle --retry-fetches=5" \
    || die "sync failed - see $LOG (rerun to resume)"
  # pin what we synced so the next run is reproducible
  ( cd "$SRC17" && repo manifest -r > "$REPOROOT/crdroid-17/my-pins.xml" 2>/dev/null ) &&
    echo "pins saved: crdroid-17/my-pins.xml (build from pins from now on)" || true
  # the touch fix applies as-is to the same device tree commit (README)
  if [ -d "$SRC17/device/motorola/amogus_doha" ]; then
    run_logged "apply touch patch (as-is on 17)" \
      git -C "$SRC17/device/motorola/amogus_doha" apply --whitespace=nowarn \
        "$REPOROOT/lineage-16/patches/device/motorola/amogus_doha.patch" \
      || note "touch patch did not apply as-is (tree moved) - see crdroid-17/patches/README.md"
  fi
  run_logged "latent-fixes layer (same device, same bugs)" \
    bash "$LATENT" "$SRC17" \
    || note "latent fixes reported problems - check docs/BUG-REGISTER.md"
  echo
  note "16 remaining patches need re-targeting: crdroid-17/patches/README.md"
  note "then build: cd $SRC17 && source build/envsetup.sh && breakfast amogus_doha userdebug && mka bacon"
  confirm "Attempt the build now (mka bacon)?" || { echo "tree ready at $SRC17."; return 0; }
  if run_logged "build Android 17" bash -c "
    set +e
    cd '$SRC17' &&
    source build/envsetup.sh &&
    breakfast amogus_doha userdebug &&
    mka -j'$JOBS' target-files-package bacon
  "; then
    mkdir -p "$ZIP_DIR"
    find "$SRC17/out/target/product/amogus_doha" -maxdepth 1 -name '*.zip' \
      -newer "$SRC17/.repo/local_manifests/doha.xml" 2>/dev/null \
      -exec cp {} "$ZIP_DIR/" \; && echo "zips copied to $ZIP_DIR"
    say "Android 17 build attempt finished - flash with A/B discipline (menu 8)"
  else
    die "build failed (expected during bring-up) - see $LOG"
  fi
}

# ---------- 6) one-shot --------------------------------------------------------
action_oneshot() {
  log_init oneshot
  hr; say "ONE-SHOT: setup -> sync -> build (nogapps)"; hr
  echo "  runs everything with safe defaults; you only watch."
  echo "  (use menu 3 to pick gapps/debloat/dolby instead)"
  confirm "Run the full pipeline now?" || { echo "aborted."; return 0; }
  action_env
  if ! run_logged "full build (one-shot)" \
      env VARIANT=nogapps DEBLOAT=none DOLBY=0 JOBS="$JOBS" \
      ZIP_DIR="$ZIP_DIR" CCACHE_DIR="$CCACHE_DIR" \
      CCACHE_SIZE="${CCACHE_SIZE:-50G}" bash "$BUILD" "$SRC"; then
    die "failed - see $LOG (rerun: everything is incremental and resumes)"
  fi
  hr; say "ONE-SHOT DONE - zips in $ZIP_DIR"; hr
  echo "  next: menu 8 (flash assistant)"
}

# ---------- 7) selftest --------------------------------------------------------
action_selftest() {
  log_init selftest
  hr; say "Self-tests: (1) build.sh path regression  (2) crDroid 16 target  (3) full dry-run battery"; hr
  local rc=0
  if [ -x "$SELFTEST" ]; then
    run_logged "build.sh path regression self-test" bash "$SELFTEST" || rc=1
  else
    echo "missing $SELFTEST" >&2; rc=1
  fi
  echo
  if [ -x "$CR16TEST" ]; then
    run_logged "crDroid 16 target self-test (manifest + overlay + mock build)" bash "$CR16TEST" || rc=1
  else
    echo "missing $CR16TEST" >&2; rc=1
  fi
  echo
  if [ -x "$DRYTEST" ]; then
    # exercises EVERY kit script with no network / phone / repo tool / AOSP
    # tree: syntax, manifests, mirror store + restore, build.sh sync wiring,
    # all doha.sh subcommands, latent-fixes idempotency, adb-less guards,
    # colab guard. ~2 min.
    run_logged "full dry-run battery (all scripts, no prerequisites)" bash "$DRYTEST" || rc=1
  else
    echo "missing $DRYTEST" >&2; rc=1
  fi
  [ $rc -eq 0 ] && say "ALL SELF-TESTS PASSED" || die "self-tests FAILED - see the output above"
}

# ---------- 8) flash assistant -------------------------------------------------
action_flash() {
  hr; say "Flash assistant (phone connected via USB)"; hr
  # Flashing is destructive: it must be confirmed by a human at a terminal.
  # Piped/batch invocation would auto-yes every confirm - refuse instead.
  [ "${DOHA_BATCH:-0}" = 1 ] && die "flash is interactive-only: run 'bash doha.sh' and pick menu 8 in a terminal"
  command -v adb >/dev/null || die "adb not found (sudo apt-get install adb / platform-tools)"
  local state; state=$(adb get-state 2>/dev/null || echo none)
  echo "  device state: $state"
  local what="checks"
  choose what "What do you want to do?" \
    "sideload|Flash a ROM zip via recovery (the normal way)" \
    "boot|fastboot flash boot (only when coming from stock/another ROM)" \
    "checks|Run the 7 post-flash verification checks (after first boot)" \
    "help|Brick-safety notes + the exact flash order"
  case $what in
    sideload)
      local zips=() pick zi
      mapfile -t zips < <(find "$ZIP_DIR" -name '*.zip' 2>/dev/null | sort)
      [ "${#zips[@]}" -eq 0 ] && die "no zips in $ZIP_DIR - build first (menu 3)"
      echo "available zips:"
      i=1; for zi in "${zips[@]}"; do echo "  $i) $zi"; i=$((i+1)); done
      choose pick "Which zip?" "${zips[@]}"
      echo "  rebooting to recovery... (choose Apply update -> Apply from ADB)"
      echo "  WARNING: coming from another ROM? factory reset in recovery FIRST."
      confirm "Reboot to recovery now and wait for sideload?" || return 0
      adb reboot recovery; sleep 5
      echo "  select 'Apply update from ADB' on the phone, then press Enter here..."
      read -r _
      run_logged "adb sideload $pick" adb sideload "$pick"
      echo "  transfer slows around 47% - that is normal (tap the screen)."
      echo "  gapps edition: answer YES at 'Install additional zip?' then"
      echo "    adb sideload MindTheGapps-*.zip"
      ;;
    boot)
      command -v fastboot >/dev/null || die "fastboot not found"
      local imgs=() pick
      mapfile -t imgs < <(find "$ZIP_DIR" -name '*boot.img' 2>/dev/null | sort)
      [ "${#imgs[@]}" -eq 0 ] && die "no boot.img in $ZIP_DIR"
      choose pick "Which boot image?" "${imgs[@]}"
      echo "  only needed when recovery (boot partition) still runs the old ROM."
      confirm "fastboot flash boot $pick - sure?" || return 0
      run_logged "fastboot flash boot" fastboot flash boot "$pick"
      echo "  now reboot to recovery and sideload the ROM zip (option sideload)."
      ;;
    checks)
      run_logged "post-flash checks (7 sections)" bash "$FLASHCHECKS"
      ;;
    help)
      cat <<'EOF'
  Brick safety (this flow NEVER touches the bootloader or partition table):
   1. keep the phone >50% charged, stock firmware zip downloaded on the PC
   2. keep a known-good slot active before experimenting (A/B device)
   3. first flash from stock: fastboot flash boot boot.img -> recovery ->
      factory reset -> Apply update from ADB -> adb sideload <rom>.zip
   4. updates later: just sideload (no fastboot, no reset)
   5. bootloop? reflash boot, factory reset, sideload the last good zip
   6. the vbmeta anti-rollback warning on this device is expected + harmless
   7. after first boot: run the post-flash checks (option checks)
EOF
      ;;
  esac
}

# ---------- 9) debug dump -------------------------------------------------------
action_dump() {
  log_init dump
  hr; say "Debug dump (full device diagnostics)"; hr
  [ -x "$DUMPSCRIPT" ] || die "missing $DUMPSCRIPT"
  command -v adb >/dev/null || die "adb not found"
  local out="$DUMPS_DIR/dump-$(date +%Y%m%d-%H%M%S)"
  local mode="light"
  choose mode "Dump size:" \
    "light|Skip the giant dumpsys sections (faster, usually enough)" \
    "full|Everything incl. all services (10-25 min, 50-300 MB)" \
    "sim1|Focused SIM 1 call debugging (clears logs, you place a call, captures)"
  mkdir -p "$DUMPS_DIR"
  echo "  output: $out"
  confirm "Start the dump now?" || return 0
  case $mode in
    light) run_logged "debug dump (light)" bash "$DUMPSCRIPT" "$out" ;;
    full)  run_logged "debug dump (full)"  env LIGHT=0 ALL_SERVICES=1 bash "$DUMPSCRIPT" "$out" ;;
    sim1)  run_logged "debug dump (SIM1)"  env REPRO_SIM1=1 LIGHT=1 bash "$DUMPSCRIPT" "$out" ;;
  esac
  echo "  done: $out  (share only the -redacted tar.gz, if any)"
}

# ---------- 10) cloud info ------------------------------------------------------
action_cloud() {
  hr; say "Building in the cloud - the facts (docs/BUILD-INFRA.md)"; hr
  cat <<'EOF'
  * NO GPU compiles Android ROMs - the toolchain has no GPU back-end.
    Kaggle GPU sessions even have FEWER CPU cores than CPU sessions.
  * What matters: CPU cores + RAM + fast disk + a warm ccache.
  * Your 5 TB Google Drive = the ARCHIVE (source snapshots, ccache,
    releases) - never the live build disk (it is a network bridge).
  * Ranked plan:
      1. Crave (free, proven for doha - your crDroid 13 came from there;
         adapt the recipe to call lineage-16/build.sh)
      2. own PC / rented VPS (16-32 vCPU, 64 GB, 2x1 TB NVME)
      3. Colab Pro CPU High-RAM last resort: cloud/colab_doha.sh
         (3 notebook cells; snapshots to GDrive between sessions)
  Full details + quota math: docs/BUILD-INFRA.md
EOF
}

# ---------- 11) vendor device mirrors -----------------------------------------
action_vendor() {
  log_init vendor
  hr; say "Vendor the 27 device-specific repos INTO this kit (one-time)"; hr
  cat <<'EOF'
  Why: 15 of the 27 upstream device repos are ALREADY ARCHIVED (Apr 2026,
  read-only) and any of them can be deleted one day. This clones the exact
  pinned commits (device trees, kernel, vendor blobs, qcom opensource) into
  mirrors/repos/*.tgz inside this kit. After that, sync + build never NEED
  those upstreams again - restore-mirrors.sh repoints repo sync at the
  local copies automatically (build.sh calls it by itself).

  Size: ~0.5-1.5 GB one-time download, stored inside the kit.
  Resumable: interrupted? just run it again - finished repos are skipped.
EOF
  echo
  echo "  current: $(ls "$REPOROOT"/mirrors/repos/*.tgz 2>/dev/null | wc -l) of 27 tarballs, $(du -sh "$REPOROOT/mirrors/repos" 2>/dev/null | cut -f1 || echo 0)"
  confirm "Start vendoring now?" || { echo "aborted."; return 0; }
  if run_logged "vendor device mirrors" bash "$REPOROOT/scripts/vendor-mirrors.sh"; then
    hr; say "VENDOR DONE - the kit is now self-contained for all device code"; hr
    echo "  $(ls "$REPOROOT"/mirrors/repos/*.tgz 2>/dev/null | wc -l) tarballs in mirrors/repos/"
    echo "  commit them (git add mirrors/) so they are inside the repo history."
    echo "  NOTE: vendor blob tarballs contain proprietary Motorola code - keep"
    echo "        the repo private or strip mirrors/ before publishing."
  else
    die "vendor-mirrors failed - see $LOG (network? rerun to resume)"
  fi
}

# ---------- menu -----------------------------------------------------------------
menu() {
  while :; do
    hr
    say " doha-roms ULTIMATE builder - Moto G8 Plus (doha)"
    hr
    local synced="-" zcount=0
    [ -d "$SRC/.repo" ] && synced="synced"
    [ -d "$ZIP_DIR" ] && zcount=$(find "$ZIP_DIR" -name '*.zip' 2>/dev/null | wc -l)
    echo "  source: $synced | zips built: $zcount | variant: $VARIANT"
    echo
    echo "   1) Setup + environment check (run this first)"
    echo "   2) Sync Android 16 source (~150-200 GB, resumable)"
    echo "   3) BUILD: Android 16 ROM  (everything automatic)   <- main goal"
    echo "   4) BUILD: kernel only (quick loop)"
    echo "   5) BUILD: Android 17 crDroid (bring-up, advanced)"
    echo "   6) ONE-SHOT: setup + sync + build (nogapps)"
    echo "   7) Self-test (path regression + full dry-run battery)"
    echo "   8) Flash assistant + post-flash checks"
    echo "   9) Debug dump (full device diagnostics)"
    echo "  10) Cloud build info (Colab / Crave / GDrive)"
    echo "  11) Vendor device repos into the kit (offline-proof, one-time)"
    echo "  12) BUILD: Android 16 crDroid 12.x (second ROM, same fixes, own source tree)"
    echo "   0) Exit"
    echo
    printf 'doha> '
    local sel=""; read -r sel || break
    case "$sel" in
      1) action_env ;;
      2) action_sync ;;
      3) action_build16 ;;
      4) action_kernel ;;
      5) action_build17 ;;
      6) action_oneshot ;;
      7) action_selftest ;;
      8) action_flash ;;
      9) action_dump ;;
      10) action_cloud ;;
      11) action_vendor ;;
      12) action_buildcr16 ;;
      0|q|Q|exit) break ;;
      *) echo "unknown option: $sel" ;;
    esac
    echo
  done
  say "bye - logs in $LOGDIR"
}

# ---------- non-interactive dispatch ---------------------------------------------
help() {
  sed -n '2,40p' "${BASH_SOURCE[0]}" | grep '^#' | sed 's/^# \{0,1\}//'
}
CMD=${1:-menu}; shift 2>/dev/null || true
# Any explicit subcommand = batch mode: prompts auto-proceed and failures
# exit non-zero (so `doha.sh sync | ...` can never fake success). The
# interactive menu keeps full prompting. flash refuses batch mode.
[ "$CMD" != menu ] && DOHA_BATCH=1
# build16 flags
while [ $# -gt 0 ]; do
  case "$1" in
    --variant) VARIANT=$2; shift 2 ;;
    --debloat) DEBLOAT=$2; shift 2 ;;
    --dolby)   DOLBY=1; shift ;;
    --jobs)    JOBS=$2; shift 2 ;;
    --src)     SRC=$2; SRC_GIVEN=1; shift 2 ;;
    --rom)     case "${2:-}" in
                 lineage|lineage16) ROM_TARGET=lineage16 ;;
                 crdroid|crdroid16) ROM_TARGET=crdroid16 ;;
                 *) echo "unknown --rom '${2:-}' (use lineage or crdroid)" >&2; exit 1 ;;
               esac; shift 2 ;;
    *) echo "unknown flag: $1" >&2; exit 1 ;;
  esac
done
[ "$CMD" = buildcr16 ] && ROM_TARGET=crdroid16
if [ "$ROM_TARGET" = crdroid16 ] && [ "${SRC_GIVEN:-0}" != 1 ]; then SRC=$SRCCR16; fi
case "$CMD" in
  menu)   menu ;;
  status) action_status ;;
  env)    action_env ;;
  sync)   action_sync ;;
  build16|buildcr16)
    log_init "$CMD"
    mkdir -p "$ZIP_DIR" "$CCACHE_DIR"
    run_logged "build Android 16 / $(rom_label) (VARIANT=$VARIANT DEBLOAT=$DEBLOAT DOLBY=$DOLBY)" \
      env ROM_TARGET="$ROM_TARGET" VARIANT="$VARIANT" DEBLOAT="$DEBLOAT" DOLBY="$DOLBY" JOBS="$JOBS" \
      ZIP_DIR="$ZIP_DIR" CCACHE_DIR="$CCACHE_DIR" \
      CCACHE_SIZE="${CCACHE_SIZE:-50G}" bash "$BUILD" "$SRC" \
      || die "build failed - see $LOG"
    ;;
  kernel)   action_kernel ;;
  build17)  action_build17 ;;
  oneshot)  action_oneshot ;;
  selftest) action_selftest ;;
  flash)    action_flash ;;
  dump)     action_dump ;;
  cloud)    action_cloud ;;
  vendor)   action_vendor ;;
  help|-h|--help) help ;;
  *) die "unknown command '$CMD' - try: bash doha.sh help" ;;
esac

