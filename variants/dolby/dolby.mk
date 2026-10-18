# doha-roms variant: Dolby Atmos from THIS device's own stock firmware.
# Rendered into doha-variants.mk when DOLBY=1.
#
# What runs where:
#   vendor/lib[64]/soundfx/libswdap.so  - the Dolby post-processing effect
#   vendor/etc/dolby/dax-default.xml    - the default Dolby profile (same
#                                         file stock Android 10 ships)
#   /vendor/etc/audio_effects.xml + .conf - wired by
#     variants/dolby/wire-audio-effects.sh during the build
#
# The blob files themselves are NOT in git (they are Motorola proprietary
# and licensed to this device). build.sh copies them from
# variants/dolby/blobs/ into the vendor tree; you fill that directory once
# with variants/dolby/extract-from-stock.sh. See docs/DOLBY.md.
#
# AudioFX is removed when Dolby is enabled: two effect-control UIs fighting
# over the same audio session is worse than one. If you prefer LineageOS
# AudioFX, build with DOLBY=0.

PRODUCT_PACKAGES := $(filter-out AudioFX,$(PRODUCT_PACKAGES))

# The stock-tuned Dolby path. Kept off: qcom's DS2 flags are for the old
# libstagefrightdolby decoder path, not the swdap effect we ship.
# (lineage16 stock value: vendor.audio.dolby.ds2.enabled=false)
PRODUCT_VENDOR_PROPERTIES += \
    vendor.audio.dolby.ds2.enabled=false

# Phase 2 (NOT enabled yet, see docs/DOLBY.md): the DMS service
# vendor/bin/hw/vendor.dolby.hardware.dms@1.0-service + its .rc. It needs
# sepolicy (file label + allow rules) that has not been written and tested
# yet. The swdap effect works without it; DMS adds EC3 decode handling.
