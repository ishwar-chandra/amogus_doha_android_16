# Dolby Atmos on doha — from this phone's own stock firmware

## The situation

The Moto G8 Plus **ships Dolby in its stock vendor partition** (measured
in the 2026-10-15 stock dump):

```
vendor/bin/hw/vendor.dolby.hardware.dms@1.0-service     HAL service (phase 2)
vendor/etc/dolby/dax-default.xml                        61.4 KB default profile
vendor/lib/soundfx/libswdap.so    vendor/lib64/soundfx/libswdap.so   the effect
vendor/lib/libstagefrightdolby.so                       old DS2 decoder path
vendor/etc/media_codecs_dolby_audio.xml                 codec entries (phase 2)
```

The community ROMs (crDroid 13, LineageOS 16) ship **none** of these, and
their `audio_effects.xml` has no dolby entry. The blobs are Motorola
proprietary — that is why no open repo carries them. Since this phone's
own firmware is licensed for this phone, extracting them from YOUR OWN
stock install/firmware for YOUR OWN build is the standard approach every
Dolby port uses.

## What this repo does (DOLBY=1)

1. **You extract once** (stock booted, no root needed):
```sh
bash variants/dolby/extract-from-stock.sh
```
This fills `variants/dolby/blobs/` (libswdap 32+64-bit, dax-default.xml)
and saves your stock `audio_effects.xml` as the authoritative wiring
reference (`audio_effects.dolby-stock.xml`).

2. **At build time** (`DOLBY=1 bash lineage-16/build.sh`):
   - `build.sh` refuses to build DOLBY=1 if the blobs are missing (tells
     you exactly what to run);
   - copies the blobs into `vendor/motorola/amogus/proprietary/` at their
     install paths and appends the `PRODUCT_COPY_FILES` entries;
   - `variants/dolby/wire-audio-effects.sh` inserts the dolby
     `<library name="dap" path="libswdap.so"/>` + `<effect .../>` entry
     into every `audio_effects.xml`/`.conf` in the synced tree — using the
     lines from YOUR stock file when available, else the standard Moto
     entry (`dolby`/`dap`, uuid `9d4921da-8225-4f29-aefa-39537a2b8235`);
   - `doha-variants.mk` removes LineageOS AudioFX (two effect UIs fighting
     over the same session is worse than one) and keeps the qcom DS2
     flags off.

3. **After flashing** — listen. Music/YouTube with the effect is the
   obvious test; `scripts/flash-checks.sh` section 4 verifies the files
   landed and the effect is wired.

## What is deliberately NOT in v1

- **The DMS service** (`vendor.dolby.hardware.dms@1.0-service`): starting
  a new vendor service needs SELinux policy (file label + allow rules)
  that has not been written or tested. The swdap effect — the part you
  hear — works without it. Phase 2, after v1 is confirmed audible.
- **media_codecs_dolby_audio.xml**: EC3/AC-4 decode support; merging
  codec XMLs is its own adventure. Not needed for the post-processing
  effect.
- **A settings UI**: stock's default profile (`dax-default.xml`) applies
  automatically. There is no Dolby settings app on stock for this device
  (it was controlled by Moto Audio's simple on/off, which lived in the
  stock system app we don't ship).

## Risk notes (be honest with yourself)

- First build with Dolby is marked **experimental**: if audio fails to
  start or the effect crashes the audio HAL, rebuild with DOLBY=0 and
  report. Failure mode is "no audio enhancements", not "no audio" (the
  effect library is optional at runtime).
- If audio is broken with DOLBY=1: `adb root; adb shell setenforce 0`,
  restart audio, and check `logcat | grep -i swdap` for denials to
  include in the report.
- The blobs are 32+64-bit from Android 10 firmware — these specific
  libraries are known to keep working on much newer Android userspace in
  other Moto ports, but on THIS combination it is unverified until the
  first build boots and someone listens.
