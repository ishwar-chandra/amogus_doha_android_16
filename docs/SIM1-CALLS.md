# SIM 1 calls: diagnosis and the 15-minute confirmation test

## UPDATE (2026-10-17 triage): two build-side fixes now shipped for this

The deep dump triage found two Android-16-tree-specific failures that
land in exactly the boot window where qcrild provisions the SIMs, both
now FIXED by the latent-fixes layer:

1. **rild (qcrild) is denied traversal of `/mnt/vendor`** (avc denial,
    5 occurrences, right at radio bring-up) - the gateway to
    /mnt/vendor/persist where the modem keeps EFS files. Fix:
    `doha_qcom_fixes.te` B6.
2. **`ril.subscription.types` is never set** - vendor_init is denied
    writing this legacy qcom prop (radio_prop label) at every boot, so
    qcrild never receives the per-slot subscription config the vendor
    prop file tries to give it. Fix: re-labelled to `vendor_radio_prop`
    (latent-fixes/property_contexts.add) + rild read allow (B5).

Both are exactly the class of silent, per-boot provisioning failure
that could produce `mcfg_version = null,RJIO_IND` on slot 0 while stock
(whose sepolicy/prop setup the vendor built for) selects
`VODAFONE_IND_VOLTE` fine. **Flash the new build first, then re-run the
15-minute test below** - the result table has been updated for it.

Also confirmed this session: the IMS dumpsys shows exactly ONE IMS data
bearer (phoneId 1 / Jio, with P-CSCF addresses) and nothing for phoneId
0 - consistent with the MCFG failure, not contradicting it.

## The finding (2026-10-15 dumps)

- SIM 1 = **Vi India** (Vodafone Idea, 404/15, carrierId 2378).
- SIM 2 = **Jio** (405/871, carrierId 2018).
- On LineageOS 23.2: `persist.vendor.radio.mcfg_version = null,RJIO_IND`
  — **the modem carrier config (MCFG) for slot 0 failed to load**.
  Consequences: Vi falls back to EDGE (`gsm.network.type = EDGE,LTE`),
  Vi's cellular PS data goes OUT_OF_SERVICE, IMS only registers on the Jio
  sub (`vendor.ims.activesub=1`), and Vi calls fail.
- On stock Android 10 (same phone, same SIMs, same slot order, same modem
  firmware): `VODAFONE_IND_VOLTE,RJIO_IND`, both slots on LTE, calls work.
- On crDroid 13: `LTE,LTE`, voice=LTE IN_SERVICE, calls work.

The MCFG database is inside the modem partition (`mcfg_hw.mbn`,
`mcfg_sw.mbn` — identical across the dumps). ROM flashes never touch it.
So the selection, not the data, fails: qcrild (dual-instance on this ROM)
picks the per-slot carrier policy when it detects the SIM, and on this
build slot 0's selection came up empty and was never retried.

## Why "VoLTE is working" was half true

The VoLTE indicator the user saw belongs to Jio (SIM 2): Jio is LTE-only,
so its calls are VoLTE and work. Vi never got its LTE/VoLTE policy, so it
fell to 2G, where this circle's Vi 2G no longer completes calls reliably.
Signal + data: both fine (Vi data limps on EDGE or the user mostly used
the Jio data SIM).

## The 15-minute test (do this, in order, and note each result)

Run from a PC with `adb`:

```sh
# 0. Current state
adb shell getprop persist.vendor.radio.mcfg_version   # expect: null,RJIO_IND
adb shell getprop gsm.network.type                    # expect: EDGE,LTE

# 1. Airplane mode round-trip (forces a radio re-init)
adb shell cmd connectivity airplane-mode enable; sleep 8
adb shell cmd connectivity airplane-mode disable; sleep 20
adb shell getprop persist.vendor.radio.mcfg_version   # did slot 0 change?
adb shell getprop gsm.network.type                    # did SIM 1 go to LTE?
# If SIM 1 is on LTE now: place a Vi call.

# 2. If still null: reboot and re-check
adb reboot; sleep 120
adb shell getprop persist.vendor.radio.mcfg_version
adb shell getprop gsm.network.type

# 3. If still null: boot with ONE SIM (remove SIM 2)
#    - power off, remove Jio, boot, wait 2 min, check the props
#    - reinsert Jio, reboot, check again
#    (tests whether slot 1's init races slot 0's MCFG selection)

# 4. The slot-vs-card test: physically SWAP the two SIMs
#    - problem follows the SLOT  -> software (qcrild slot-0 handling)
#    - problem follows the CARD  -> carrier/provisioning (unlikely: stock works)
```

Log capture for the thread (only if 1-3 don't fix it):

```sh
adb logcat -b radio -d > radio-boot.txt
adb shell dumpsys telephony.registry > telephony.txt
adb shell getprop | grep -iE "radio|ims|volte" > ril-props.txt
```

## What the results mean

- **If the new build alone fixes it** (mcfg slot 0 != null on first boot
  after flash): the sepolicy/prop fixes above were the missing piece.
  Close the bug; flash-checks.sh keeps watching it.
- **If airplane-mode or reboot fixes it**: a re-selection race. The
  build-side fix becomes an init trigger (re-forcing MCFG selection after
  SIM state settles), and the first build to carry it can close this bug.
- **If single-SIM boot fixes it**: slot-1 init starves slot 0's selection.
  Fix direction: qcrild init ordering in the device tree, or a delayed
  refresh service.
- **If nothing fixes it**: capture the logs below — the answer is inside
  qcrild's MCFG selection lines, which the standard radio buffer logs.

## Related data points from the dumps

- stock baseband `M6125_43.45.03.48R`, crDroid ran with `.45R`, the ROM
  flashes never change the modem partition — same firmware for all tests.
- `persist.radio.multisim.config = dsds` on all three ROMs — correct.
- The framework-side carrier configs (com.android.carrierconfig) load fine
  for BOTH carriers on LineageOS 16 (cache files exist for 2378 and 2018) —
  this is purely the modem-side (qcrild/MCFG) selection.

`scripts/flash-checks.sh` prints the MCFG state on every future build, so
this can never silently regress again.
