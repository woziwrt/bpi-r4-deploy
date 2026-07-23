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

# 6. The builder copies both patches into mt76's patch directory.
builder="$repo_dir/builder-wifimgr-universal.sh"
patch_dir='mtk-openwrt-feeds/autobuild/unified/filogic/mac80211/25.12/files/package/kernel/mt76/patches'
grep -Fq "my_files/100-wifi-mt76-mt7996-Use-tx_power-from-default-fw-if-EEP.patch $patch_dir" "$builder" \
    || fail "builder does not copy the base patch"
grep -Fq "my_files/101-w-mt7996-5g-tx-power-boost.patch $patch_dir" "$builder" \
    || fail "builder does not copy the boost patch"

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

echo "PASS"
