# doha-roms variant: DEBLOAT "safe" tier (rendered into doha-variants.mk).
#
# Removes ONLY apps that (a) have a direct Google equivalent on the Play
# Store, (b) nothing in the system depends on, and (c) whose absence cannot
# break boot or first-run setup. The user installs the Google replacement
# from the Play Store (MindTheGapps gives you the Store to do it with).
#
# Module names are what vendor/lineage/config/common*.mk and
# build/make/target/product/handheld_product.mk actually add to
# PRODUCT_PACKAGES. A wrong name here is a SAFE failure: the app simply
# stays installed. Verify after flashing with scripts/flash-checks.sh.
#
# NEVER add to this list without reading docs/DEBLOAT.md first:
#   documentsui (system file picker!), launcher3/Trebuchet (only launcher),
#   inputmethod.latin/LatinIME (only keyboard), Aperture (only camera),
#   all com.android.providers.* (data storage), com.android.phone,
#   systemui, settings, permissioncontroller, emergency (safety!),
#   setupwizard, lineageparts, updater, soundpicker.

# --- LineageOS suite: Google/Play Store replacements exist for each ---
PRODUCT_PACKAGES := $(filter-out Jelly Twelve Etar Glimpse Recorder,$(PRODUCT_PACKAGES))

# --- AOSP apps with direct Google equivalents ---
PRODUCT_PACKAGES := $(filter-out Calculator2,$(PRODUCT_PACKAGES))
