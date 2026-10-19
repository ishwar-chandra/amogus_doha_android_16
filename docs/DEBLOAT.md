# Editions & debloat: exactly what gets removed and what never will

## The two editions

| | **nogapps** (default) | **gapps** (`VARIANT=gapps`) |
|---|---|---|
| ROM zip contents | pure LineageOS + AOSP apps, nothing Google | same ROM zip — still nothing Google inside |
| Google apps | none | you sideload **MindTheGapps** at the "Install additional zip?" prompt right after the ROM: exactly **Play services + Play Store**, nothing else |
| Other Google apps | — | you install from Play Store as needed (Chrome, Files, Phone, Messages, Contacts, Clock, Photos…) |
| AOSP/Lineage apps | all kept | **safe debloat** by default: the duplicates listed below are removed from the build |

Build commands:

```sh
bash lineage-16/build.sh                          # nogapps, everything kept
VARIANT=gapps bash lineage-16/build.sh            # gapps, DEBLOAT=safe
VARIANT=gapps DEBLOAT=aggressive bash lineage-16/build.sh
VARIANT=gapps DOLBY=1 bash lineage-16/build.sh    # gapps + Dolby
```

The GApps zip is not embedded on purpose: MindTheGapps updates on its own
schedule, embedding Google code in a redistributable zip is a licensing
problem, and a failed GApps integration is the #1 cause of first-boot
loops. Sideload order (ROM → additional-zip prompt → MindTheGapps) is the
supported, boring, reliable path.

## DEBLOAD=safe (default for gapps) — removed, with the replacement you install

| Removed package | Module name | Replace with (Play Store) |
|---|---|---|
| org.lineageos.jelly (Jelly browser) | Jelly | Chrome / any browser |
| org.lineageos.twelve (Twelve music) | Twelve | YouTube Music / Spotify |
| org.lineageos.etar (Etar calendar) | Etar | Google Calendar |
| org.lineageos.glimpse (Glimpse gallery) | Glimpse | Google Photos |
| org.lineageos.recorder (Recorder) | Recorder | Google Recorder / any recorder |
| com.android.calculator2 (Calculator) | ExactCalculator (Calculator2 on plain AOSP) | Google Calculator |
| org.lineageos.audiofx (AudioFX) | AudioFX | (removed only when DOLBY=1 — replaced by the Dolby effect) |

A wrong module name is a SAFE failure: the app simply stays installed.
`scripts/flash-checks.sh` + `adb shell pm list packages` after first boot
shows exactly what happened.

## DEBLOAT=aggressive — additionally removed

| Removed package | Module name | Replace with | Risk if you don't |
|---|---|---|---|
| com.android.deskclock (Clock) | DeskClock | Google Clock | no alarms |
| com.android.messaging (Messaging) | messaging | Google Messages (needed for Jio/Vi RCS anyway) | no SMS app |
| com.android.contacts (Contacts app) | Contacts | Google Contacts | no contacts UI |
| com.android.dialer (Dialer) | Dialer | Google Phone | **no dialer UI** — install Google Phone BEFORE flashing an aggressive build, or keep DEBLOAT=safe |

Recommended order for aggressive: flash a `safe` build, sideload
MindTheGapps, install the four Google apps from the Play Store, THEN flash
the aggressive build over it (same ROM family, no wipe needed).

## NEVER removed (and why) — do not add these to any tier

| Package | Why it stays |
|---|---|
| com.android.documentsui (Files) | it is the **system file picker** (SAF). Every save/open dialog, every backup app, Seedvault, uses it. "Files by Google" is a viewer, not a replacement. |
| com.android.launcher3 / Trebuchet | the only launcher in the ROM. Removing it = boot to a black screen. |
| com.android.inputmethod.latin / LatinIME | the only keyboard. MindTheGapps does NOT include Gboard. No keyboard = cannot type on first boot. |
| org.lineageos.aperture | the only camera app. GCam ports need per-device configs; the vendor camera stack is tuned for the in-tree app. |
| com.android.providers.* (calendar, contacts, media, blockednumber…) | data storage for the whole system. Apps, not UI. |
| com.android.phone, systemui, settings, permissioncontroller | the framework. |
| com.android.emergency | emergency info + lock-screen emergency call. Safety. |
| org.lineageos.updater | your OTA updates — including this repo's next builds. |
| org.lineageos.setupwizard, lineageparts | first boot + device hardware settings (buttons, gestures, double-tap-to-wake…). |
| com.android.soundpicker | ringtone/notification sound picker used by Settings. |
| org.lineageos.backgrounds, profiles, camelot, stats, … | LineageOS system glue; not Google-replaceable. |

## Notes from the actual installed-package dump (lineage16, 2026-10-15)

The AOSP/Lineage app inventory measured on the running build (for
reference): `com.android.calculator2, com.android.deskclock, com.android.dialer,
com.android.documentsui (+overlay), com.android.messaging, com.android.contacts,
com.android.launcher3 (+overlay), com.android.inputmethod.latin,
com.android.htmlviewer, com.android.bookmarkprovider, com.android.dreams.*,
com.android.egg, com.android.emergency, com.android.intentresolver,
com.android.keychain, com.android.packageinstaller, com.android.printservice.recommendation,
com.android.providers.*, com.android.soundpicker, com.android.webview (via WebView provider),
org.lineageos.aperture, audiofx, backgrounds, camelot, etar, glimpse, jelly,
lineageparts, profiles, recorder, setupwizard, twelve, updater`.
Everything not in the removal tables above stays in every edition.

## crDroid 12.x (ROM_TARGET=crdroid16) additions

`variants/debloat-crdroid.mk` is appended after `debloat.mk` when building
crDroid. Module names were read from `android_vendor_crdroid` branch `16.0`
(2026-10-18). Removed in addition to the table above: **Gallery2** (older
gallery crDroid lists next to Glimpse; Google Photos replaces both). Kept on
purpose: Aperture, AudioFX, Seedvault, ThemePicker/Backgrounds and the
crDroid-only apps with no Google equivalent (GameSpace, OmniJaws weather,
MatLog, AppLocker, ThemeStore, LMOFreeform, ...).

Note (2026-10-18): the calculator row used to name only `Calculator2`, which
is not what LineageOS 23.2 or crDroid add (they add `ExactCalculator`), so the
calculator silently stayed installed. Both names are now filtered.
