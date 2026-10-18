# doha-roms variant: DEBLOAT "aggressive" tier.
# Rendered in addition to debloat.mk when DEBLOAT=aggressive.
#
# Each entry below removes a DEFAULT app. Only use this if you actually
# install the Google replacement immediately after first boot, or you lose
# that function until you do:
#
#   DeskClock  (com.android.deskclock)  -> install Google Clock first
#   messaging  (com.android.messaging)  -> install Google Messages first
#                 (Jio/Vi RCS in India needs Google Messages anyway)
#   Contacts   (com.android.contacts)   -> install Google Contacts first
#                 (com.android.providers.contacts STAYS: that is the
#                  storage, not the app)
#   Dialer     (com.android.dialer)     -> install Google Phone first.
#                 NOTE: if you flash this build and skip Google Phone,
#                 you have NO dialer UI (emergency call from lock screen
#                 still works). The safest order: install the ROM, install
#                 Google Phone from the Play Store, THEN flash an
#                 aggressive build.
#
# Kept on purpose even in aggressive mode (see docs/DEBLOAT.md):
#   LatinIME (keyboard), Trebuchet (launcher), Aperture (camera),
#   DocumentsUI (system picker), every provider, Emergency, SoundPicker.

PRODUCT_PACKAGES := $(filter-out DeskClock messaging Contacts Dialer,$(PRODUCT_PACKAGES))
