# Banana Pi BPI-R4 Lite (MT7987A), sourced by build.sh.
#
# Unlike the BPI-R4 and Pro 8X this board uses the OpenWrt/MTK filogic.mk,
# U-Boot and TF-A as they are; it has no M.2 key-M (no NVMe) and no MT7530
# port LED fix. Wi-Fi is the BE14 card (mt7996e), like on the BPI-R4.

# common/patches/wifi/ patches this board takes (standard variant only).
WIFI_PATCHES="
	mac80211/0999-fix-mac80211-btwt-ap-mode-he-btwt-supported.patch
	hostapd/0264-wpa_s-add-btwt-join-command.patch
	mt76/9999-w-mt7996-per-band-leds.patch
	mt76/9999-w-mt76-share-tpt-led-trigger.patch
"

board_tree() {
	# No add_common_tree_patches: those are the BPI-R4 U-Boot and NVMe
	# (DT overlay, fitblk) patches.

	# MTK patches-base 1132 removes the SD card, eMMC, SPI-NAND and NOR
	# artifacts from the upstream bananapi_bpi-r4-lite device. Put the
	# upstream ones back, without the initramfs-recovery stage in the SD
	# image: ours does not fit the 12M-44M slot (the BPI-R4 SD images leave
	# it out too).
	python3 "$REPO/boards/bpi-r4-lite/lite-artifacts.py" target/linux/mediatek/image/filogic.mk

	# MTK patches-base 1120 adds an &hnat node to the OpenWrt copy of the Lite
	# DTS; the hnat label only exists with MTK's Logan HNAT driver, which we do
	# not use. Since 1132 the DTB is built from the kernel tree instead, so
	# this only matters if that copy is used again.
	local dts=target/linux/mediatek/dts/mt7987a-bananapi-bpi-r4-lite.dts
	[ -f "$dts" ] && sed -i '/^&hnat {$/,/^};$/d' "$dts"
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
	return 0
}
