#!/usr/bin/env bash
# Wire the Dolby effect into every audio_effects.xml / audio_effects.conf
# in the synced source tree. Called by build.sh when DOLBY=1.
#
# How it decides what to insert:
#   1. If variants/dolby/audio_effects.dolby-stock.xml exists and contains
#      a libswdap entry (extracted from this phone's own stock ROM by
#      extract-from-stock.sh), its exact <library> and <effect> lines are
#      used. That is the authoritative wiring for THIS device.
#   2. Otherwise the standard Motorola/qcom Dolby entry is used:
#        library dap  -> libswdap.so
#        effect dolby -> uuid 9d4921da-8225-4f29-aefa-39537a2b8235
#      (the same entry public Moto-series Dolby ports carry).
#
# The script is idempotent: files that already mention libswdap are left
# alone. It never touches anything under .repo, .git or out/.
set -u

SRC="${1:?usage: wire-audio-effects.sh <source-tree>}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STOCK="$HERE/audio_effects.dolby-stock.xml"

LIB_LINE_XML='<library name="dap" path="libswdap.so"/>'
EFF_LINE_XML='<effect name="dolby" library="dap" uuid="9d4921da-8225-4f29-aefa-39537a2b8235"/>'
LIB_LINE_CONF='  dap {
    path /vendor/lib/soundfx/libswdap.so
  }'
EFF_LINE_CONF='  dolby {
    library dap
    uuid 9d4921da-8225-4f29-aefa-39537a2b8235
  }'

# Prefer the stock-extracted lines when present.
if [ -f "$STOCK" ] && grep -q libswdap "$STOCK" 2>/dev/null; then
  l=$(grep -oE '<library[^>]*libswdap[^>]*/>' "$STOCK" | head -1)
  e=$(grep -oE '<effect[^>]*dap[^>]*/>' "$STOCK" | grep -i libswdap | head -1)
  [ -z "$e" ] && e=$(grep -B1 -A0 '' "$STOCK" | grep -oE '<effect[^>]*library="dap"[^>]*/>' | head -1)
  # fall back to pairing: effect whose library= matches the name in $l
  if [ -n "$l" ] && [ -z "$e" ]; then
    libname=$(printf '%s' "$l" | sed -n 's/.*name="\([^"]*\)".*/\1/p')
    e=$(grep -oE "<effect[^>]*library=\"$libname\"[^>]*/>" "$STOCK" | head -1)
  fi
  [ -n "$l" ] && LIB_LINE_XML="$l"
  [ -n "$e" ] && EFF_LINE_XML="$e"
  echo "  using stock-extracted dolby wiring"
fi

python3 - "$SRC" "$LIB_LINE_XML" "$EFF_LINE_XML" "$LIB_LINE_CONF" "$EFF_LINE_CONF" << 'PYEOF'
import os, re, sys

src, lib_xml, eff_xml, lib_conf, eff_conf = sys.argv[1:6]
lib_conf, eff_conf = lib_conf.replace("\\n","\n"), eff_conf.replace("\\n","\n")

targets = []
for root_dir in ("vendor", "device", "hardware"):
    base = os.path.join(src, root_dir)
    if not os.path.isdir(base):
        continue
    for dirpath, dirnames, filenames in os.walk(base):
        dirnames[:] = [d for d in dirnames if d not in (".git", ".repo", "out")]
        for fn in filenames:
            if fn in ("audio_effects.xml", "audio_effects.conf"):
                targets.append(os.path.join(dirpath, fn))

changed = skipped = 0
for path in targets:
    with open(path, "r", errors="surrogateescape") as f:
        text = f.read()
    if "libswdap" in text:
        skipped += 1
        continue
    orig = text
    if path.endswith(".xml"):
        # insert the library line right after the <libraries> opening tag,
        # the effect line right after <effects>.
        text = re.sub(r'(<libraries[^>]*>)', r'\1\n    ' + lib_xml, text, count=1)
        text = re.sub(r'(<effects[^>]*>)',  r'\1\n    ' + eff_xml, text, count=1)
    else:  # .conf
        text = re.sub(r'(libraries\s*\{)', r'\1\n' + lib_conf, text, count=1)
        text = re.sub(r'(effects\s*\{)',   r'\1\n' + eff_conf, text, count=1)
    if text != orig and "libswdap" in text:
        with open(path, "w", errors="surrogateescape") as f:
            f.write(text)
        changed += 1
        print("  wired: " + os.path.relpath(path, src))
    else:
        skipped += 1

print(f"audio_effects wiring: {changed} file(s) modified, {skipped} untouched")
sys.exit(0 if changed > 0 or skipped > 0 else 1)
PYEOF
