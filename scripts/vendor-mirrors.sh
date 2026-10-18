#!/usr/bin/env bash
# =============================================================================
# vendor-mirrors.sh - clone every DEVICE-SPECIFIC pinned repo INTO this kit
#
# What it does (for all 27 projects marked local::doha in default.xml):
#   1. fetches the exact pinned commit (+ its full reachable history) from
#      the upstream GitHub repo - MINIMAL mirror: no pull-refs, no noise
#   2. stores it as a self-contained git mirror tarball: mirrors/repos/<name>.tgz
#      (a bare git repo containing the pinned SHA + complete history)
#   3. records name/path/sha/size in mirrors/MIRRORS.tsv
#
# Result: after this one-time run, the kit no longer NEEDS Aldair402 /
# moto-common / AOSPA / ThankYouMario to exist. restore-mirrors.sh repoints
# repo sync at these local copies (file://), so even if every upstream repo
# is deleted tomorrow, the build still syncs and compiles bit-identical.
#
# If a fetch FAILS: the pinned commit has disappeared upstream - that is
# exactly the disaster this mirrors; the output tells you which one.
#
# Usage:  bash scripts/vendor-mirrors.sh          (run once; resumable)
#         VERBOSE=1 bash scripts/vendor-mirrors.sh
# =============================================================================
set -uo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
MAN="$HERE/default.xml"
OUT="$HERE/mirrors/repos"
LIST="$HERE/mirrors/MIRRORS.tsv"
mkdir -p "$OUT"
LOG="$HERE/mirrors/vendor.log"
: > "$LOG"

say()  { echo "$*" | tee -a "$LOG"; }

# ---- parse remotes from the manifest -----------------------------------------
declare -A REMOTES
while IFS='|' read -r n f; do REMOTES[$n]+="$f"; done < <(
  grep -oE '<remote name="[^"]*" fetch="[^"]*"' "$MAN" |
  sed -E 's/<remote name="([^"]*"?) fetch="([^"]*")/\1|\2/; s/"//g; s/\|$//' |
  awk -F'|' '{print $1"|"$2}')

# ---- parse the device projects ------------------------------------------------
mapfile -t PROJS < <(
  grep 'local::doha' "$MAN" |
  sed -E 's/.*name="([^"]*)".*path="([^"]*)".*remote="([^"]*)".*revision="([0-9a-f]{40})".*/\1|\2|\3|\4/')

say "vendor-mirrors: ${#PROJS[@]} device projects from default.xml"
say "output: $OUT"
say ""

total_ok=0 total_fail=0 total_mb=0
for spec in "${PROJS[@]}"; do
  IFS='|' read -r name path remote rev <<<"$spec"
  base="${REMOTES[$remote]:-}"
  if [ -z "$base" ]; then say "SKIP $name (unknown remote '$remote')"; continue; fi
  url="${base%/}/$name"
  tgz="$OUT/$name.tgz"

  # resumable: already vendored?
  if [ -s "$tgz" ]; then
    say "have  $name (existing $(du -h "$tgz" | cut -f1))"
    # make sure the .fact file exists (repos vendored by an older script
    # version may have a tgz but no fact)
    if [ ! -s "$OUT/$name.fact" ]; then
      fw=$(mktemp -d); mkdir -p "$fw/m"
      tar -xzf "$tgz" -C "$fw/m" --strip-components=1 2>>"$LOG"
      d=$(git -C "$fw/m" show -s --format=%cs refs/heads/doha-pin 2>/dev/null || echo "?")
      mb=$(du -m "$tgz" | cut -f1)
      printf '%s|%s|%s|%s|%s|%s|%s\n' "$name" "$path" "$remote" "$rev" "$d" "$url" "${mb}MB" \
        > "$OUT/$name.fact"
      rm -rf "$fw"
    fi
    total_ok=$((total_ok+1)); total_mb=$(( total_mb + $(du -m "$tgz" | cut -f1) ))
    continue
  fi

  say "fetch $name @ ${rev:0:10} <- $url"
  w=$(mktemp -d)
  ok=0
  for attempt in 1 2 3; do
    rm -rf "$w"; mkdir -p "$w"
    if git init -q --bare "$w/m" 2>>"$LOG" \
       && git -C "$w/m" remote add origin "$url" 2>>"$LOG" \
       && timeout 2400 git -C "$w/m" fetch -q origin "$rev" 2>>"$LOG" \
       && [ "$(git -C "$w/m" cat-file -t "$rev" 2>/dev/null)" = commit ]; then
      ok=1; break
    fi
    say "  retry $attempt/3 for $name (fetch failed - network?)"
    sleep $((attempt*20))
  done
  if [ "$ok" = 1 ]; then
    git -C "$w/m" update-ref refs/heads/doha-pin "$rev" 2>>"$LOG"
    d=$(git -C "$w/m" show -s --format=%cs "$rev")
    tar -C "$w" -czf "$tgz" m 2>>"$LOG"
    mb=$(du -m "$tgz" | cut -f1)
    say "  ok   $name  $(printf '%6s' "${mb}MB")  pinned $d"
    total_ok=$((total_ok+1)); total_mb=$((total_mb+mb))
    printf '%s|%s|%s|%s|%s|%s|%s\n' "$name" "$path" "$remote" "$rev" "$d" "$url" "${mb}MB" \
      > "$OUT/$name.fact"
  else
    say "  FAIL $name - fetch failed after 3 tries (repo deleted? commit unreachable?)"
    total_fail=$((total_fail+1))
  fi
  rm -rf "$w"
done

# ---- write the authoritative MIRRORS.tsv from per-repo .fact files ----------
{
  echo "# doha-roms vendored device mirrors - generated $(date +%F)"
  echo "# format: name|source-path|remote|pinned-sha|pinned-date|upstream-url|size"
  cat "$OUT"/*.fact 2>/dev/null
} | sort -t'|' -k1,1 > "$LIST.new" && mv "$LIST.new" "$LIST"
rm -f "$HERE/mirrors/.vendored.tmp"

say ""
say "DONE: $total_ok mirrored, $total_fail failed, ~${total_mb}MB total"
[ "$total_fail" -gt 0 ] && exit 1 || exit 0
