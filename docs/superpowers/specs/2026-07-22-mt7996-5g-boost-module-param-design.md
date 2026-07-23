# MT7996 5 GHz Boost as a Module Parameter

Date: 2026-07-22
Status: Implemented and verified on hardware (8GB PoE BE14)
Replaces an earlier draft that persisted the boost by vendoring a modified copy of
MediaTek's reference EEPROM; that approach was squashed out of history in favour of this
module parameter.

## Context

Commit `f220657` persists a +4 dB 5 GHz transmit-power boost into the WiFi Manager
universal image. It does so by vendoring a 7,680-byte copy of MediaTek's reference
EEPROM, `my_files/mt7996_eeprom_233_5g_plus4.bin`, whose only difference from stock is
five bytes at `0x1301..0x1305`, and installing that copy over both MT7996 233 fallback
filenames in the rootfs overlay.

The mechanism was verified end to end and works. `cmp -l` against the stock file
confirms exactly five differing bytes, `0x27 -> 0x2f` and `0x25 -> 0x2d`, which is
+8 half-dB units. On the live router the OTP shows zeros at `0x1300..0x1305` while the
runtime EEPROM reads `29 2f 2f 2f 2f 2d`, and `iw dev phy0.1-ap0 info` reports 30 dBm.

Two properties of that approach are undesirable in a long-lived repository:

The repository now pins a June-2026 snapshot of MediaTek's reference EEPROM. That file
is not consumed only by the tx_power repair. `mt7996_eeprom_variant_valid()` reads it to
decide whether the module's own EEPROM matches the expected front-end variant, and the
driver falls back to it wholesale when the device EEPROM is invalid. Overwriting it in
the rootfs means every future mt76 update to that file is silently discarded, for all
three of its consumers, on every image built from this repository.

The boost amount is encoded in a binary blob guarded by three hardcoded SHA-256 literals.
Changing +4 dB to +2 dB means regenerating the blob, updating the hashes in the installer,
the test, and the plan, and rebuilding an image.

This design keeps the runtime behaviour identical and moves the boost from data to code.

## Goals

- Preserve today's behaviour exactly: +4 dB by default, applied only to 5 GHz target-power
  bytes that the existing repair already substitutes, only on modules whose EEPROM has
  zeros there.
- Stop overwriting `mt7996_eeprom_233.bin` and `mt7996_eeprom_233_2i5i6i.bin`.
- Express the boost as one reviewable integer visible in a diff.
- Allow retuning on a running router without rebuilding an image.
- Make the applied value observable in `dmesg` and in sysfs.
- Prevent the overlay files left on the live router from stacking with the new mechanism.

## Non-goals

- Changing how much power is applied. The parameter defaults to the same +4 dB.
- Changing 2.4 GHz or 6 GHz behaviour. They keep using bare `def[i]`.
- Changing radio or MLO configuration.
- Extending the boost to the other six builders that carry the Mironov repair.
- Writing the physical OTP or efuse.
- Claiming the reported transmit power equals measured RF output.

## Design

### The parameter

A new patch, `my_files/101-w-mt7996-5g-tx-power-boost.patch`, applies after
`my_files/100-wifi-mt76-mt7996-Use-tx_power-from-default-fw-if-EEP.patch` and modifies the
loop that patch introduces in `mt7996_eeprom_fixup_tx_power()`.

```c
static int tx_power_5g_boost_db = 4;
module_param(tx_power_5g_boost_db, int, 0444);
MODULE_PARM_DESC(tx_power_5g_boost_db,
		 "Extra 5 GHz tx_power in dB, applied only to substituted defaults (0-10, default 4)");
```

```c
	int boost = clamp(tx_power_5g_boost_db, 0, 10) * 2;	/* EEPROM unit is 0.5 dB */

	for (i = MT_EE_TX0_POWER_5G; i < MT_EE_TX0_POWER_5G + 5; ++i) {
		if (!eeprom[i]) {
			eeprom[i] = min_t(int, def[i] + boost, 0x3f);
			zeros_detected = true;
		}
	}
```

The parameter is whole dB. Half-dB granularity is deliberately not offered, because a
parameter named `_db` that silently means half-dB is the exact confusion this design
avoids.

Three scoping properties carry over unchanged from the current behaviour. The boost sits
inside `if (!eeprom[i])`, so a module with populated 5 GHz targets is never touched. Only
the five 5 GHz bytes are affected; the 2.4 GHz assignment above the loop and the 6 GHz
loop below it are untouched. And the repair still runs at driver initialisation against
the in-memory EEPROM, never against the physical efuse.

`clamp(..., 0, 10)` bounds operator error. `min_t(int, def[i] + boost, 0x3f)` is a wrap
guard, because `eeprom[i]` is a `u8` and `def[]` comes from a firmware file this design
deliberately stops controlling. Both are defensive bounds on the byte written into the
in-memory EEPROM image, not statements about resulting output power. The driver and the
stack above it continue to apply their own limits after this fixup runs, exactly as they
do today.

Mironov's existing warning is extended so the applied value is provable from the log:

```c
	if (zeros_detected)
		dev_warn(dev->mt76.dev,
			 "eeprom tx_power zeros detected, using defaults (5g boost +%d dB)\n",
			 boost / 2);
```

`100-...patch` is left byte-identical to the upstream submission. Keeping the follow-on
change in a separate file preserves that patch's provenance, so it can be dropped
unchanged if it lands in mt76.

### Retuning without a rebuild

`mt7996e` is a loadable module and OpenWrt's kmodloader reads options directly from
`/etc/modules.d/mt7996e`, which currently contains `mt7996e wed_enable=1`. Appending
`tx_power_5g_boost_db=N` to that line and rebooting changes the boost. The file lives
under `/etc`, so the edit survives sysupgrade. The current value is readable at
`/sys/module/mt7996e/parameters/tx_power_5g_boost_db`.

The repository ships no override for that file. Doing so would reintroduce the pinning
problem in miniature, shadowing any parameter mt76 adds later. The default lives in the
patch; the router-side edit is the escape hatch.

### Builder integration

`builder-wifimgr-universal.sh` gains one copy next to the existing Mironov copy at line 30,
before `cd openwrt`, so it uses the same unprefixed path:

```sh
### +4 dB on the repaired 5 GHz targets; retune via /etc/modules.d/mt7996e
\cp -r my_files/101-w-mt7996-5g-tx-power-boost.patch mtk-openwrt-feeds/autobuild/unified/filogic/mac80211/25.12/files/package/kernel/mt76/patches
```

Both patches land in mt76's quilt directory and apply in sorted order, `100-` then `101-`.
The `9999-w-` LED patches continue to sort last.

Lines 39 to 42, the comment and the `../my_files/install-mt7996-eeprom-5g-boost.sh files`
call, are removed.

Scope stays `builder-wifimgr-universal.sh`. The other six builders that carry the Mironov
repair are not modified, so no other image's behaviour changes.

### Deletions

- `my_files/mt7996_eeprom_233_5g_plus4.bin`
- `my_files/install-mt7996-eeprom-5g-boost.sh`
- `tests/test-mt7996-eeprom-5g-boost.sh`, replaced by the test below

## Testing

CI has no kernel tree at the point these patches are staged, so the regression test
verifies the patch and its wiring statically. `tests/test-mt7996-5g-txpower-boost.sh`
asserts:

1. `101-w-mt7996-5g-tx-power-boost.patch` exists and modifies only `mt7996/eeprom.c`.
2. Ordering consistency: every line `101-` **removes** is a line `100-` **adds**. Removed
   lines are the hard dependency between the two patches; hunk context unavoidably
   includes pristine source and is not constrained. This is the failure mode a naive test
   misses. If `100-` is ever edited, `101-` silently stops applying and the image
   regresses to stock power with no other signal.
3. The declared default is `4` and the clamp bounds are `0` and `10`.
4. `builder-wifimgr-universal.sh` copies both `100-` and `101-` into mt76's patch
   directory.
5. `my_files/mt7996_eeprom_233_5g_plus4.bin`, `my_files/install-mt7996-eeprom-5g-boost.sh`
   and the `install-mt7996-eeprom-5g-boost.sh files` builder call are all absent.

Assertion 2 needs no vendored mt76 source. `100-`'s added lines are exactly the lines
`101-` builds on, so the test reads both patch files and checks that relationship
directly, which keeps the fixture in sync by construction.

The static test cannot prove the patch compiles or that the driver applies the value. That
is what the live acceptance below is for, and it is the gate for calling this done.

## Migration: the double-boost hazard

The live router currently has the boosted fallback files in its overlay at
`/lib/firmware/mediatek/mt7996/`. Under the new mechanism the driver reads those files as
`def[]` and adds the parameter on top, giving +8 dB into an internal PA. The two mechanisms
must never coexist.

Before flashing an image built from this design, restore the stock files on the router:

```sh
cp /root/txpower-5g-backup/mt7996_eeprom_233.bin.stock        /lib/firmware/mediatek/mt7996/mt7996_eeprom_233.bin
cp /root/txpower-5g-backup/mt7996_eeprom_233_2i5i6i.bin.stock /lib/firmware/mediatek/mt7996/mt7996_eeprom_233_2i5i6i.bin
sync
```

A clean flash that discards the overlay also resolves this, but the restore is cheap and
does not depend on remembering which kind of flash was performed.

## Live acceptance

After flashing, all four must hold:

```sh
cat /sys/module/mt7996e/parameters/tx_power_5g_boost_db
# 4

dmesg | grep "tx_power zeros"
# ... eeprom tx_power zeros detected, using defaults (5g boost +4 dB)

dd if=/sys/kernel/debug/ieee80211/phy0/mt76/eeprom bs=1 skip=4864 count=6 2>/dev/null | hexdump -C
# 29 2f 2f 2f 2f 2d

sha256sum /lib/firmware/mediatek/mt7996/mt7996_eeprom_233.bin
# d4e2c032657c35d79f651d7e3b6af2e05f6a498228be31394d032640851a9643
```

The last two together are the real check. A stock firmware hash alongside `2f` in the
runtime EEPROM proves the boost came from the parameter and was applied exactly once.

`iw dev phy0.1-ap0 info` should continue to report 30.00 dBm, unchanged from the blob
mechanism.

## Risks

- The boost itself is unchanged and so are its risks. 0x2f is 23.5 dBm per chain. This
  module's own calibrated 6 GHz targets are 17 to 18 dBm per chain and the 2.4 GHz default
  is 20.5, on internal PAs in all three cases. 23.5 dBm per chain is outside the range this
  silicon is calibrated for anywhere, so PA compression and degraded EVM at high MCS remain
  plausible. No before-and-after retry-rate baseline was captured when the boost was first
  applied, so there is no evidence either way.
- If mt76 renames or restructures `mt7996_eeprom_fixup_tx_power()`, `101-` fails to apply
  and the build breaks loudly. That is the intended failure mode and is preferable to the
  blob's silent staleness.
- The static test cannot catch a compile error in the patch. A full image build is the
  first place that surfaces.
- The +4 dB default applies to any BE14 with a zeroed EEPROM that runs the WiFi Manager
  universal image, exactly as it does today. This design does not change that; it only
  makes the value visible and adjustable.

## Deferred

The measurement that motivated the boost, rockpi-tv at -75 dBm, is the AP receiving the
station's uplink, which AP transmit power cannot affect. Whether that link is limited by
the station's own radio, by antenna placement, or by the AP's 5 GHz receive path is an
open question this design does not address and cannot be settled from AP-side statistics
alone. Channel and antenna work is out of scope for this design and is left for a later
session.
