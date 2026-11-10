# Banana Pi BPI-R4 (4 GB, 8 GB, PoE), sourced by build.sh.

# common/patches/wifi/ patches this board takes (standard variant only).
# Ivan Mironov's mt76 tx_power patch (for BE14 cards with a bad EEPROM) is
# left out here.
WIFI_PATCHES="
	mac80211/0999-fix-mac80211-btwt-ap-mode-he-btwt-supported.patch
	hostapd/0264-wpa_s-add-btwt-join-command.patch
	mt76/9999-w-mt7996-per-band-leds.patch
	mt76/9999-w-mt76-share-tpt-led-trigger.patch
"

board_tree() {
	local b=$REPO/boards/bpi-r4 p

	add_common_tree_patches
	for p in "$b"/patches/build/*.patch; do
		[ -f "$p" ] || continue
		patch --batch -p1 < "$p"
	done
	\cp "$b"/patches/uboot/*.patch package/boot/uboot-mediatek/patches/
	\cp "$b"/patches/target/*.patch target/linux/mediatek/patches-6.12/
	\cp "$b/filogic.mk" target/linux/mediatek/image/filogic.mk

	# Ethernet/board LEDs: leds overlay on top of the NVMe one, PHY LED trigger
	sed -i 's/mt7988a-bananapi-bpi-r4-nvme$/mt7988a-bananapi-bpi-r4-nvme mt7988a-bananapi-bpi-r4-leds/' target/linux/mediatek/image/filogic.mk
	echo "CONFIG_LED_TRIGGER_PHY=y" >> target/linux/mediatek/filogic/config-6.12

	\cp "$b/arm-trusted-firmware-mediatek-Makefile" package/boot/arm-trusted-firmware-mediatek/Makefile

	echo "CONFIG_BLK_DEV_NVME=y" >> target/linux/mediatek/filogic/config-6.12
	[ "$VARIANT" = wired ] && echo "CONFIG_TASK_IO_ACCOUNTING=y" >> target/linux/mediatek/filogic/config-6.12
	return 0
}

board_packages() {
	[ "$VARIANT" = standard ] || return 0
	\cp -r "$REPO/common/packages/luci-app-wifimgr" feeds/luci/applications/luci-app-wifimgr
}

board_after_feeds() {
	return 0
}

board_config() {
	# The OpenWrt SDK is per target, so it covers the Pro 8X too
	# (published as release-sdk).
	[ "$VARIANT" = standard ] && echo "CONFIG_SDK=y" >> .config
	return 0
}
