# doha-roms variant: crDroid 12.x (ROM_TARGET=crdroid16) addition to the DEBLOAT tiers.
# build.sh appends this after debloat.mk when building crDroid.
#
# Module names read from crdroidandroid/android_vendor_crdroid branch 16.0
# (config/common*.mk, crdroid.mk) on 2026-10-18. A wrong name is a SAFE failure:
# the app just stays installed. crDroid-only apps with NO Google equivalent
# (GameSpace, OmniJaws weather, MatLog, AppLocker, ThemeStore, ...) are kept on
# purpose, as are Aperture (only camera), AudioFX, Seedvault and everything
# listed under NEVER in debloat.mk.
#
# Gallery2 is the older gallery crDroid still lists next to Glimpse; Google
# Photos replaces both (Glimpse is already handled in debloat.mk).
PRODUCT_PACKAGES := $(filter-out Gallery2,$(PRODUCT_PACKAGES))
