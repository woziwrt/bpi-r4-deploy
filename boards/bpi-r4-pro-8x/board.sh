# Banana Pi BPI-R4 Pro 8X, sourced by build.sh.

# common/patches/wifi/ patches this board takes (standard variant only).
WIFI_PATCHES="
	mt76/100-wifi-mt76-mt7996-Use-tx_power-from-default-fw-if-EEP.patch
	mt76/9999-w-mt7996-per-band-leds.patch
	mt76/9999-w-mt76-share-tpt-led-trigger.patch
"

board_tree() {
	local b=$REPO/boards/bpi-r4-pro-8x p

	# platform.sh: register bpi-r4-pro-8x in fit_do_upgrade, fit_check_image, platform_copy_config
	python3 -c 'f="target/linux/mediatek/filogic/base-files/lib/upgrade/platform.sh"; c=open(f).read(); c=c.replace("\tbananapi,bpi-r4-lite|\\\n\tbazis,ax3000wm","\tbananapi,bpi-r4-lite|\\\n\tbananapi,bpi-r4-pro-8x|\\\n\tbazis,ax3000wm"); c=c.replace("\tbananapi,bpi-r4-lite|\\\n\tcmcc,rax3000m","\tbananapi,bpi-r4-lite|\\\n\tbananapi,bpi-r4-pro-8x|\\\n\tcmcc,rax3000m"); open(f,"w").write(c)'

	add_common_tree_patches
	for p in "$b"/patches/build/*.patch; do
		[ -f "$p" ] || continue
		patch --batch -p1 < "$p"
	done
	\cp "$b"/patches/uboot/*.patch package/boot/uboot-mediatek/patches/

	# MTK feed patches superseded by ours:
	# - 999-eth-06: the passive mux, ported by us as 999-eth-01/02.
	# - 999-dsa-08 (MTK e6696884c, 2026-09-09): the same SerDes port1 mux we
	#   carry as 999-dsa-07. Patches apply in alphabetical order, so ours goes
	#   first and theirs then fails on the changed file.
	# - 046-v6.19: upstream Frank-W DTS; we use the Sinovoip-based one (our 046).
	#   Not in the feed at the current pin, kept in case it comes back.
	rm -f target/linux/mediatek/patches-6.12/999-eth-06-mtk_eth_soc-support-ethernet-passive-mux.patch
	rm -f target/linux/mediatek/patches-6.12/999-dsa-08-add-mxl862xx-serdes-port1-mux-selection.patch
	rm -f target/linux/mediatek/patches-6.12/046-v6.19-arm64-dts-mediatek-mt7988a-bpi-r4-pro-add-dts.patch
	\cp "$b"/patches/target/*.patch target/linux/mediatek/patches-6.12/

	\cp "$b/uboot-mediatek-Makefile" package/boot/uboot-mediatek/Makefile
	\cp "$b/arm-trusted-firmware-mediatek-Makefile" package/boot/arm-trusted-firmware-mediatek/Makefile
	\cp "$b/filogic.mk" target/linux/mediatek/image/filogic.mk
	mv target/linux/mediatek/image/filogic-extra.mk target/linux/mediatek/image/filogic-extra.mk.disabled

	echo "CONFIG_BLK_DEV_NVME=y" >> target/linux/mediatek/filogic/config-6.12
	echo "CONFIG_TASK_IO_ACCOUNTING=y" >> target/linux/mediatek/filogic/config-6.12

	# Aeonsemi AS21xxx: the vendor driver from the MTK SDK (aeon_as21xxx.ko), as a module
	python3 -c 'content=open("package/kernel/linux/modules/netdevices.mk").read(); content=content.replace("  KCONFIG:=CONFIG_AS21XXX_PHY\n  FILES:= \\\n   $(LINUX_DIR)/drivers/net/phy/as21xxx.ko\n  AUTOLOAD:=$(call AutoLoad,18,as21xxx)", "  KCONFIG:=CONFIG_AS21XXX_PHY\n  FILES:= \\\n   $(LINUX_DIR)/drivers/net/phy/aeon_as21xxx.ko\n  AUTOLOAD:=$(call AutoLoad,18,aeon_as21xxx)"); open("package/kernel/linux/modules/netdevices.mk","w").write(content)'
	python3 -c 'content=open("target/linux/mediatek/filogic/config-6.12").read(); content=content.replace("CONFIG_AS21XXX_PHY=y", "CONFIG_AS21XXX_PHY=m"); open("target/linux/mediatek/filogic/config-6.12","w").write(content)'
}

board_packages() {
	[ "$VARIANT" = standard ] || return 0
	\cp -r "$REPO/common/packages/luci-app-wifimgr/" package/luci-app-wifimgr/
}

board_after_feeds() {
	[ "$VARIANT" = standard ] || return 0
	chmod -R 755 package/luci-app-wifimgr/root
}

board_config() {
	return 0
}
