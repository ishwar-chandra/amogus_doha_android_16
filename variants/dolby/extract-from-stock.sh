#!/usr/bin/env bash
# Extract the Dolby blobs (and the exact audio_effects wiring) from the
# phone booted into STOCK Android 10, into variants/dolby/blobs/.
#
# Run this ONCE, with the phone on stock:
#   adb reboot            # make sure it is booted and unlocked
#   bash variants/dolby/extract-from-stock.sh
#
# Everything below is world-readable on stock (no root needed). If adb
# pull is refused for a path, the script falls back to cat.
#
# If you no longer have stock booted, extract the same paths from your
# stock firmware zip instead (the payload needs payload dumper; ask in the
# thread or re-flash stock first - it is the easier route).
set -u

BLOBDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/blobs"
SNIPPET="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/audio_effects.dolby-stock.xml"
mkdir -p "$BLOBDIR"

have_adb() { command -v adb >/dev/null 2>&1; }
have_adb || { echo "adb not found in PATH" >&2; exit 1; }
state=$(adb get-state 2>/dev/null || echo none)
[ "$state" = device ] || { echo "No device connected/authorized ($state)" >&2; exit 1; }

get() {  # get <device_path> <local_relpath>
  local dev="$1" rel="$2"
  mkdir -p "$BLOBDIR/$(dirname "$rel")"
  if adb pull "$dev" "$BLOBDIR/$rel" >/dev/null 2>&1; then
    echo "  pulled $dev"
  else
    adb shell "cat $dev" > "$BLOBDIR/$rel" 2>/dev/null \
      && echo "  cat-ed $dev" \
      || echo "  MISSING $dev (skipped)"
  fi
}

echo "Extracting Dolby blobs from stock into $BLOBDIR:"
get /vendor/lib/soundfx/libswdap.so     vendor/lib/soundfx/libswdap.so
get /vendor/lib64/soundfx/libswdap.so   vendor/lib64/soundfx/libswdap.so
get /vendor/etc/dolby/dax-default.xml   vendor/etc/dolby/dax-default.xml
# Optional extras (grabbed if present, build does not require them):
get /vendor/lib/libstagefrightdolby.so vendor/lib/libstagefrightdolby.so

# The authoritative Dolby wiring: stock's own audio_effects.xml. The
# build merges its <library>/<effect> lines for libswdap into our tree
# (wire-audio-effects.sh prefers this file when present).
adb shell cat /vendor/etc/audio_effects.xml 2>/dev/null \
  | tr -d '\r' > "$SNIPPET" \
  && echo "  saved stock audio_effects.xml -> $SNIPPET" \
  || echo "  could not read /vendor/etc/audio_effects.xml"

echo
echo "Core check:"
[ -s "$BLOBDIR/vendor/lib64/soundfx/libswdap.so" ] \
  && echo "  OK: libswdap.so (64-bit) present" \
  || echo "  PROBLEM: 64-bit libswdap.so missing - DOLBY=1 will refuse to build"
[ -s "$BLOBDIR/vendor/etc/dolby/dax-default.xml" ] \
  && echo "  OK: dax-default.xml present" \
  || echo "  PROBLEM: dax-default.xml missing"
grep -q libswdap "$SNIPPET" 2>/dev/null \
  && echo "  OK: stock audio_effects.xml contains the dolby entry (saved)" \
  || echo "  NOTE: dolby entry not found in stock audio_effects.xml; the"
echo "       build will use the standard Moto dolby effect entry instead."
echo
echo "Done. Now build with: DOLBY=1 ./build.sh"
