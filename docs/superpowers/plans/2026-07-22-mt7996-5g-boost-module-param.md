# MT7996 5 GHz Boost Module Parameter Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the vendored 7,680-byte EEPROM blob that carries the +4 dB 5 GHz boost with a `mt7996e` module parameter, keeping runtime behaviour identical.

**Architecture:** A second mt76 patch, `101-w-mt7996-5g-tx-power-boost.patch`, applies after Ivan Mironov's `100-…` patch and adds a module parameter to the 5 GHz branch of `mt7996_eeprom_fixup_tx_power()`. The builder copies it next to the base patch; the blob, its installer and its test are deleted. A POSIX-shell test verifies the patch shape and, critically, the dependency between the two patches.

**Tech Stack:** POSIX shell, unified diff / quilt, OpenWrt package patch directory, mt76 `mt7996/eeprom.c`.

**Spec:** [2026-07-22-mt7996-5g-boost-module-param-design.md](../specs/2026-07-22-mt7996-5g-boost-module-param-design.md)

## Global Constraints

- **Do not run any `git commit` at any point in Tasks 1-4.** Every task ends at `git add`. The gate is not merely permission: nothing may be committed until Task 4 has completed a real image build **and** the on-hardware acceptance checks have passed **and** the user has confirmed. A green static test is explicitly not sufficient — it cannot prove the patch compiles or that the driver applies the value. If a task's steps appear to call for a commit, stage and stop.
- The user intends to rewrite `f220657` to keep history clean, so keep the whole change squash-friendly and do not build on that commit's SHA.
- Patch filename is exactly `101-w-mt7996-5g-tx-power-boost.patch`, so it sorts after `100-wifi-mt76-mt7996-Use-tx_power-from-default-fw-if-EEP.patch`.
- `my_files/100-wifi-mt76-mt7996-Use-tx_power-from-default-fw-if-EEP.patch` must remain **byte-identical**. Do not edit it.
- The new patch modifies **only** `mt7996/eeprom.c`.
- Parameter: `static int tx_power_5g_boost_db = 4;` — whole dB, multiplied by 2 because the EEPROM unit is 0.5 dB.
- Bounds: `clamp(tx_power_5g_boost_db, 0, 10)` and wrap guard `min_t(int, def[i] + boost, 0x3f)`.
- Only the 5 GHz loop changes. The 2.4 GHz assignment and the 6 GHz loop keep using bare `def[i]`.
- Scope is `builder-wifimgr-universal.sh` only. Do not touch the other six builders that carry the base patch.
- Tests are POSIX `sh`, run as `sh tests/<name>.sh`, exit 0 = pass.
- Hunk line numbers in a hand-written patch need not be exact; `patch`/quilt match by context with offset tolerance.

---

### Task 1: The boost patch and its static test

**Files:**
- Create: `my_files/101-w-mt7996-5g-tx-power-boost.patch`
- Create: `tests/test-mt7996-5g-txpower-boost.sh`

**Interfaces:**
- Consumes: `my_files/100-wifi-mt76-mt7996-Use-tx_power-from-default-fw-if-EEP.patch`, which adds `mt7996_eeprom_fixup_tx_power(struct mt7996_dev *dev, const u8 *def)` to `mt7996/eeprom.c`. Its 5 GHz branch is the only part this task changes.
- Produces: a module parameter `tx_power_5g_boost_db` (int, `0444`), readable at runtime as `/sys/module/mt7996e/parameters/tx_power_5g_boost_db`, and a test script later tasks append to.

- [ ] **Step 1: Write the failing test**

Create `tests/test-mt7996-5g-txpower-boost.sh`:

```sh
#!/bin/sh
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
base_patch="$repo_dir/my_files/100-wifi-mt76-mt7996-Use-tx_power-from-default-fw-if-EEP.patch"
boost_patch="$repo_dir/my_files/101-w-mt7996-5g-tx-power-boost.patch"

fail() { echo "FAIL: $*" >&2; exit 1; }

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM

# 1. Both patches exist.
[ -f "$base_patch" ]  || fail "missing base patch $base_patch"
[ -f "$boost_patch" ] || fail "missing boost patch $boost_patch"

# 2. The boost patch sorts after the base patch, so quilt applies 100- first.
first=$(printf '%s\n%s\n' "$(basename "$base_patch")" "$(basename "$boost_patch")" \
        | sort | head -1)
[ "$first" = "$(basename "$base_patch")" ] \
    || fail "boost patch does not sort after the base patch"

# 3. The boost patch touches only mt7996/eeprom.c.
targets=$(grep -E '^(---|\+\+\+) [ab]/' "$boost_patch" \
          | sed -E 's#^(---|\+\+\+) [ab]/##' | sort -u)
[ "$targets" = "mt7996/eeprom.c" ] \
    || fail "boost patch touches unexpected files: $targets"

# 4. Ordering dependency: every line the boost patch REMOVES must be a line the
#    base patch ADDS. Hunk context legitimately includes pristine source, so only
#    removed lines are checked. If 100- is ever edited, 101- silently stops
#    applying and the image quietly regresses to stock power; this catches that.
grep '^-' "$boost_patch" | grep -v '^---' | sed 's/^-//' > "$work/removed"
grep '^+' "$base_patch"  | grep -v '^+++' | sed 's/^+//' > "$work/added"
while IFS= read -r line; do
    [ -n "$line" ] || continue
    grep -Fxq "$line" "$work/added" \
        || fail "boost patch removes a line the base patch never adds: $line"
done < "$work/removed"

# 5. Declared default and safety bounds.
grep -Fq 'static int tx_power_5g_boost_db = 4;' "$boost_patch" \
    || fail "default is not 4"
grep -Fq 'clamp(tx_power_5g_boost_db, 0, 10)' "$boost_patch" \
    || fail "clamp bounds are not 0..10"
grep -Fq 'min_t(int, def[i] + boost, 0x3f)' "$boost_patch" \
    || fail "wrap guard missing"

echo "PASS"
```

Make it executable:

```bash
chmod +x tests/test-mt7996-5g-txpower-boost.sh
```

- [ ] **Step 2: Run the test and verify RED**

Run: `sh tests/test-mt7996-5g-txpower-boost.sh`

Expected: exit 1 with `FAIL: missing boost patch /home/master/work/bpi-r4-deploy/my_files/101-w-mt7996-5g-tx-power-boost.patch`

- [ ] **Step 3: Write the patch**

Create `my_files/101-w-mt7996-5g-tx-power-boost.patch`:

```diff
Subject: [PATCH] wifi: mt76: mt7996: make the substituted 5 GHz tx_power boost tunable

Depends on 100-wifi-mt76-mt7996-Use-tx_power-from-default-fw-if-EEP.patch, which
adds mt7996_eeprom_fixup_tx_power(). That function substitutes MediaTek's
reference defaults for target-power bytes that some BPI-R4-NIC-BE14 modules ship
as zeros.

This adds a module parameter raising only the substituted 5 GHz targets. Modules
with populated target bytes are still never touched, and the 2.4 GHz and 6 GHz
branches keep using the reference defaults unmodified.

Tune by appending tx_power_5g_boost_db=N to /etc/modules.d/mt7996e and rebooting.
Read back at /sys/module/mt7996e/parameters/tx_power_5g_boost_db

--- a/mt7996/eeprom.c
+++ b/mt7996/eeprom.c
@@ -96,10 +96,21 @@
 
+/* Included here, not in the file's include block, so this patch depends only on
+ * context that 100-*.patch introduces. Header guards make a repeat harmless.
+ */
+#include <linux/moduleparam.h>
+
+static int tx_power_5g_boost_db = 4;
+module_param(tx_power_5g_boost_db, int, 0444);
+MODULE_PARM_DESC(tx_power_5g_boost_db,
+		 "Extra 5 GHz tx_power in dB, applied only to substituted defaults (0-10, default 4)");
+
 static void
 mt7996_eeprom_fixup_tx_power(struct mt7996_dev *dev, const u8 *def)
 {
 	u8 *eeprom = dev->mt76.eeprom.data;
+	int boost = clamp(tx_power_5g_boost_db, 0, 10) * 2;	/* EEPROM unit is 0.5 dB */
 	int i;
 	bool zeros_detected = false;
 
@@ -110,7 +121,7 @@
 	for (i = MT_EE_TX0_POWER_5G; i < MT_EE_TX0_POWER_5G + 5; ++i) {
 		if (!eeprom[i]) {
-			eeprom[i] = def[i];
+			eeprom[i] = min_t(int, def[i] + boost, 0x3f);
 			zeros_detected = true;
 		}
 	}
@@ -124,7 +135,9 @@
 	if (zeros_detected)
-		dev_warn(dev->mt76.dev, "eeprom tx_power zeros detected, using defaults\n");
+		dev_warn(dev->mt76.dev,
+			 "eeprom tx_power zeros detected, using defaults (5g boost +%d dB)\n",
+			 boost / 2);
 }
```

Two things to preserve exactly. The `eeprom[i] = def[i];` line appears in both the 5 GHz and the 6 GHz loop; the hunk context (`MT_EE_TX0_POWER_5G`) is what selects the right one, so do not shorten it. And indentation in the patch body is **tabs**, matching kernel style and the base patch — a space/tab mismatch makes the patch fail to apply.

- [ ] **Step 4: Run the test and verify GREEN**

Run: `sh tests/test-mt7996-5g-txpower-boost.sh`

Expected: exit 0, prints `PASS`

- [ ] **Step 5: Stage (do not commit — see Global Constraints)**

```bash
git add my_files/101-w-mt7996-5g-tx-power-boost.patch tests/test-mt7996-5g-txpower-boost.sh
git status --short
```

---

### Task 2: Wire the patch into the builder

**Files:**
- Modify: `builder-wifimgr-universal.sh:29-30`
- Modify: `tests/test-mt7996-5g-txpower-boost.sh`

**Interfaces:**
- Consumes: `my_files/101-w-mt7996-5g-tx-power-boost.patch` from Task 1.
- Produces: both patches staged in `mtk-openwrt-feeds/autobuild/unified/filogic/mac80211/25.12/files/package/kernel/mt76/patches`, where OpenWrt's quilt applies them in sorted order.

- [ ] **Step 1: Add the failing assertion to the test**

Append to `tests/test-mt7996-5g-txpower-boost.sh`, immediately **before** the final `echo "PASS"` line:

```sh
# 6. The builder copies both patches into mt76's patch directory.
builder="$repo_dir/builder-wifimgr-universal.sh"
patch_dir='mtk-openwrt-feeds/autobuild/unified/filogic/mac80211/25.12/files/package/kernel/mt76/patches'
grep -Fq "my_files/100-wifi-mt76-mt7996-Use-tx_power-from-default-fw-if-EEP.patch $patch_dir" "$builder" \
    || fail "builder does not copy the base patch"
grep -Fq "my_files/101-w-mt7996-5g-tx-power-boost.patch $patch_dir" "$builder" \
    || fail "builder does not copy the boost patch"
```

- [ ] **Step 2: Run the test and verify RED**

Run: `sh tests/test-mt7996-5g-txpower-boost.sh`

Expected: exit 1 with `FAIL: builder does not copy the boost patch`

- [ ] **Step 3: Add the builder copy**

In `builder-wifimgr-universal.sh`, directly after the existing line 30 (the base-patch copy) and before the blank line preceding the LED patches, insert:

```sh
### +4 dB on the repaired 5 GHz targets; retune via /etc/modules.d/mt7996e
\cp -r my_files/101-w-mt7996-5g-tx-power-boost.patch mtk-openwrt-feeds/autobuild/unified/filogic/mac80211/25.12/files/package/kernel/mt76/patches
```

This sits **before** `cd openwrt` (line 36), so the path is unprefixed, matching line 30. Do not use `../my_files/`.

- [ ] **Step 4: Run the test and verify GREEN**

Run: `sh tests/test-mt7996-5g-txpower-boost.sh`

Expected: exit 0, prints `PASS`

- [ ] **Step 5: Verify the builder still parses**

Run: `sh -n builder-wifimgr-universal.sh`

Expected: exit 0, no output

- [ ] **Step 6: Stage (do not commit)**

```bash
git add builder-wifimgr-universal.sh tests/test-mt7996-5g-txpower-boost.sh
git status --short
```

---

### Task 3: Remove the superseded blob mechanism

> **Skip this task entirely if `f220657` has been rewritten to drop its draft artifacts.** Everything removed here was introduced by that commit. Confirm with `git log --oneline -- my_files/mt7996_eeprom_233_5g_plus4.bin` before starting: no output means the artifacts are already gone and only assertion 7 below is still worth adding.

**Files:**
- Delete: `my_files/mt7996_eeprom_233_5g_plus4.bin`
- Delete: `my_files/install-mt7996-eeprom-5g-boost.sh`
- Delete: `tests/test-mt7996-eeprom-5g-boost.sh`
- Delete: `docs/superpowers/specs/2026-07-22-5ghz-txpower-boost-design.md`
- Modify: `builder-wifimgr-universal.sh:39-42`
- Modify: `tests/test-mt7996-5g-txpower-boost.sh`

**Interfaces:**
- Consumes: the working builder wiring from Task 2. The boost must already come from the patch before the blob is removed, or the image ships stock power.
- Produces: a tree where the only 5 GHz boost mechanism is the module parameter.

- [ ] **Step 1: Add the failing assertion to the test**

Append to `tests/test-mt7996-5g-txpower-boost.sh`, immediately **before** the final `echo "PASS"` line:

```sh
# 7. The superseded blob mechanism is fully gone.
for gone in \
    "$repo_dir/my_files/mt7996_eeprom_233_5g_plus4.bin" \
    "$repo_dir/my_files/install-mt7996-eeprom-5g-boost.sh" \
    "$repo_dir/tests/test-mt7996-eeprom-5g-boost.sh"
do
    [ ! -e "$gone" ] || fail "superseded artifact still present: $gone"
done
if grep -Fq 'install-mt7996-eeprom-5g-boost.sh files' "$builder"; then
    fail "builder still calls the superseded installer"
fi
```

The `grep` is written as an `if` block rather than `grep … && fail`, because under `set -e` a failing `grep` in an `&&` list would abort the script instead of passing the assertion.

- [ ] **Step 2: Run the test and verify RED**

Run: `sh tests/test-mt7996-5g-txpower-boost.sh`

Expected: exit 1 with `FAIL: superseded artifact still present: …/my_files/mt7996_eeprom_233_5g_plus4.bin`

- [ ] **Step 3: Delete the blob, the installer and the old test**

```bash
git rm my_files/mt7996_eeprom_233_5g_plus4.bin \
       my_files/install-mt7996-eeprom-5g-boost.sh \
       tests/test-mt7996-eeprom-5g-boost.sh
```

- [ ] **Step 4: Remove the builder's installer call**

Delete these four lines from `builder-wifimgr-universal.sh` (lines 39-42, between the `autobuild.sh … prepare` call and the NVMe patch copies):

```sh
# Defective BE14 modules have zero 5 GHz power targets. Install the live-verified
# +4 dB fallback into the rootfs overlay; the existing mt7996 repair uses it only
# for zero target bytes and leaves physical efuse data untouched.
../my_files/install-mt7996-eeprom-5g-boost.sh files
```

- [ ] **Step 5: Delete the superseded old design doc**

The old spec exclusively documents the blob mechanism (its "Image Persistence" and "Live
Verification" sections describe the very approach this change removes). Its still-relevant
content — the double-boost rollback and the honest RF caveats — now lives in this plan's
Migration section and the new spec's Risks. Delete it:

```bash
git rm docs/superpowers/specs/2026-07-22-5ghz-txpower-boost-design.md
```

- [ ] **Step 6: Run the test and verify GREEN**

Run: `sh tests/test-mt7996-5g-txpower-boost.sh`

Expected: exit 0, prints `PASS`

- [ ] **Step 7: Verify the builder still parses**

Run: `sh -n builder-wifimgr-universal.sh`

Expected: exit 0, no output

- [ ] **Step 8: Stage (do not commit)**

```bash
git add -A builder-wifimgr-universal.sh tests/ my_files/ docs/superpowers/specs/
git status --short
```

---

### Task 4: Build the image and verify on hardware

> This is the completion gate. Tasks 1-3 prove wiring and patch consistency; **none of them prove the patch compiles or that the driver applies the value.** Do not report this work as done before this task passes.

**Files:** none modified. This task builds and verifies.

**Interfaces:**
- Consumes: the staged tree from Tasks 1-3.
- Produces: a sysupgrade image at `local-build/standard/openwrt/bin/targets/mediatek/filogic/`, and four passing on-device checks.

- [ ] **Step 1: Build the image**

Run: `./local-build.sh standard`

Needs roughly 50 GB free disk and takes a few hours. Expected: exit 0, with `openwrt-mediatek-filogic-bananapi_bpi-r4-squashfs-sysupgrade.itb` present in `local-build/standard/openwrt/bin/targets/mediatek/filogic/`.

If the build fails inside the mt76 package, read the quilt output. `Hunk #N FAILED` means the patch context is wrong — recheck tabs and the `MT_EE_TX0_POWER_5G` context in Task 1 Step 3. A compile error naming `clamp` or `min_t` means the file needs `#include <linux/minmax.h>` added next to the `moduleparam.h` include in the same hunk.

- [ ] **Step 2: Restore stock firmware files on the router before flashing**

The live router still has the boosted `.bin` files in its overlay. Left in place, the driver would read them as `def[]` and add the parameter **on top**, giving +8 dB into an internal PA.

```bash
ssh root@192.168.1.1 '
cp /root/txpower-5g-backup/mt7996_eeprom_233.bin.stock        /lib/firmware/mediatek/mt7996/mt7996_eeprom_233.bin
cp /root/txpower-5g-backup/mt7996_eeprom_233_2i5i6i.bin.stock /lib/firmware/mediatek/mt7996/mt7996_eeprom_233_2i5i6i.bin
sync
sha256sum /lib/firmware/mediatek/mt7996/mt7996_eeprom_233.bin
'
```

Expected: `d4e2c032657c35d79f651d7e3b6af2e05f6a498228be31394d032640851a9643`

- [ ] **Step 3: Flash the image**

Ask the user how they want to flash it. Do not pick a flashing method unprompted.

- [ ] **Step 4: Run the acceptance checks**

```bash
ssh root@192.168.1.1 '
cat /sys/module/mt7996e/parameters/tx_power_5g_boost_db
dmesg | grep "tx_power zeros"
dd if=/sys/kernel/debug/ieee80211/phy0/mt76/eeprom bs=1 skip=4864 count=6 2>/dev/null | hexdump -C
sha256sum /lib/firmware/mediatek/mt7996/mt7996_eeprom_233.bin
iw dev phy0.1-ap0 info | grep txpower
'
```

Expected, all five:

```
4
... eeprom tx_power zeros detected, using defaults (5g boost +4 dB)
00000000  29 2f 2f 2f 2f 2d                                 |)////-|
d4e2c032657c35d79f651d7e3b6af2e05f6a498228be31394d032640851a9643
	txpower 30.00 dBm
```

Match the hexdump on the **byte values** `29 2f 2f 2f 2f 2d`, not on column spacing, which varies by `hexdump` build. Byte 0 (`29`) is the 2.4 GHz target and must stay unchanged; the five that follow are the boosted 5 GHz targets.

The third and fourth lines together are the real check: a **stock** firmware hash alongside `2f` in the runtime EEPROM is only possible if the boost came from the parameter and was applied exactly once.

- [ ] **Step 5: Verify the runtime knob works**

```bash
ssh root@192.168.1.1 '
sed -i "s/^mt7996e wed_enable=1$/mt7996e wed_enable=1 tx_power_5g_boost_db=0/" /etc/modules.d/mt7996e
cat /etc/modules.d/mt7996e
'
```

Reboot, then confirm the runtime EEPROM reads `29 27 27 27 27 25` and `iw` reports 26.00 dBm. Then revert the file to `mt7996e wed_enable=1` and reboot again, confirming 30.00 dBm returns. This proves retuning works without a rebuild, which is the whole point of the change.

- [ ] **Step 6: Report results and ask about committing**

Report the actual command output, including anything that did not match — if a check failed, say so with the output rather than summarising it as passed. Only once every check in Steps 4 and 5 has genuinely passed may committing be raised at all; then ask the user whether to commit, and whether they want this squashed with the `f220657` rewrite they mentioned.

This is the first point in the whole plan where a commit is permissible, and only with explicit confirmation.

---

## Self-Review

**Spec coverage:** parameter and bounds → Task 1; runtime retuning via `/etc/modules.d/mt7996e` → Task 4 Step 5; builder integration → Task 2; deletions → Task 3; all five test assertions → Tasks 1-3; migration double-boost hazard → Task 4 Step 2; live acceptance → Task 4 Step 4; base patch left byte-identical → Global Constraints.

**Deliberate spec deviation:** the spec's "no pinned files" goal is met, but Task 3 is conditional on `f220657` surviving. If it is rewritten first, the deletions are already done and only assertion 7 is added.

**Not covered by any task, by design:** the spec's Risks section is documentation, not work. The unexplained uplink deficit in Deferred is explicitly out of scope.
