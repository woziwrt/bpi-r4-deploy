#!/bin/bash
set -euo pipefail

# BUMP 2026-06-28 (HW overeno; predchozi: 949487e0 / 42c9ff = 6.12.92):
#   OpenWrt:  6dead2869209f4ff9825f3169c129c5ef04f6273  (openwrt-25.12 HEAD)
#   MTK SDK:  13f39a7448764466f0ab5eb290fdefd9a9d2335b  (github git01 HEAD)

rm -rf openwrt
rm -rf mtk-openwrt-feeds

git clone --branch openwrt-25.12 https://github.com/openwrt/openwrt.git openwrt
cd openwrt; git checkout ${OPENWRT_COMMIT:-6dead2869209f4ff9825f3169c129c5ef04f6273}; cd -;

git clone --branch git01 https://github.com/mediatek/mtk-openwrt-feeds mtk-openwrt-feeds
( cd mtk-openwrt-feeds && git checkout ${MTK_COMMIT:-13f39a7448764466f0ab5eb290fdefd9a9d2335b} )

\cp -r my_files/999-sfp-10-additional-quirks.patch mtk-openwrt-feeds/25.12/files/target/linux/mediatek/patches-6.12
\cp -r my_files/999-sfp-11-rtl8261be-mdio-none.patch mtk-openwrt-feeds/25.12/files/target/linux/mediatek/patches-6.12
\cp -r my_files/999-sfp-22-rtl8261be-boot-1g-reprobe.patch mtk-openwrt-feeds/25.12/files/target/linux/mediatek/patches-6.12
\cp -r my_files/999-eth-21-mtk-gdm-rx-fsm-reset.patch mtk-openwrt-feeds/25.12/files/target/linux/mediatek/patches-6.12
#\cp -r my_files/999-sfp-15-oem-sfp10gt-ignore-los.patch mtk-openwrt-feeds/25.12/files/target/linux/mediatek/patches-6.12
\cp -r my_files/999-fix-00-xfrm-sw-sa-offload-ok.patch mtk-openwrt-feeds/25.12/files/target/linux/mediatek/patches-6.12

### tx_power check Ivan Mironov's patch - for defective BE14 boards with defective eeprom flash
\cp -r my_files/100-wifi-mt76-mt7996-Use-tx_power-from-default-fw-if-EEP.patch mtk-openwrt-feeds/autobuild/unified/filogic/mac80211/25.12/files/package/kernel/mt76/patches

### per-band WiFi LED (MT7996, single-wiphy MLO) + shared tpt trigger - HW verified 2026-06-28
\cp -r my_files/999-wifi-01-mt7996-per-band-leds.patch mtk-openwrt-feeds/autobuild/unified/filogic/mac80211/25.12/files/package/kernel/mt76/patches/9999-w-mt7996-per-band-leds.patch
\cp -r my_files/999-wifi-02-mt76-share-tpt-led-trigger.patch mtk-openwrt-feeds/autobuild/unified/filogic/mac80211/25.12/files/package/kernel/mt76/patches/9999-w-mt76-share-tpt-led-trigger.patch

cd openwrt
bash ../mtk-openwrt-feeds/autobuild/unified/autobuild.sh filogic-mac80211-mt798x_rfb-wifi7_nic prepare

# =====================================================================
# ХАК ДЛЯ SFP МОДУЛЯ BAZIS 1G-T (Игнорирование сбойного PHY-probe)
# =====================================================================
mkdir -p target/linux/mediatek/patches-6.12
cat << 'EOF' > target/linux/mediatek/patches-6.12/999-sfp-ignore-bazis-phy.patch
--- a/drivers/net/phy/sfp.c
+++ b/drivers/net/phy/sfp.c
@@ -2420,6 +2420,12 @@ static int sfp_sm_probe_phy(struct sfp *sfp, bool is_c45)
 {
 	int err;
 
+	/* HACK: BAZIS SFP 1000BASE-T workaround */
+	if (strncasecmp(sfp->id.base.vendor_name, "BAZIS", 5) == 0) {
+		dev_info(sfp->dev, "BAZIS module detected, skipping buggy PHY probe.\n");
+		return -ENODEV;
+	}
+
 	if (!is_c45) {
 		err = sfp_sm_probe_for_phy(sfp, SFP_PHY_ADDR);
 EOF
# =====================================================================

# platform.sh: register bpi-r4-pro-8x in fit_do_upgrade, fit_check_image, platform_copy_config
python3 -c 'f="target/linux/mediatek/filogic/base-files/lib/upgrade/platform.sh"; c=open(f).read(); c=c.replace("\tbananapi,bpi-r4-lite|\\\n\tbazis,ax3000wm","\tbananapi,bpi-r4-lite|\\\n\tbananapi,bpi-r4-pro-8x|\\\n\tbazis,ax3000wm"); c=c.replace("\tbananapi,bpi-r4-lite|\\\n\tcmcc,rax3000m","\tbananapi,bpi-r4-lite|\\\n\tbananapi,bpi-r4-pro-8x|\\\n\tcmcc,rax3000m"); open(f,"w").write(c)'

# BPI-R4 patches
\cp -r ../my_files/453-w-add-bpi-r4-nvme-dtso.patch target/linux/mediatek/patches-6.12/
\cp -r ../my_files/455-w-add-bpi-r4-pro-nvme-dtso.patch target/linux/mediatek/patches-6.12/
\cp -r ../my_files/450-w-nand-mmc-add-bpi-r4.patch package/boot/uboot-mediatek/patches/450-add-bpi-r4.patch
\cp -r ../my_files/451-w-add-bpi-r4-nvme.patch package/boot/uboot-mediatek/patches/451-add-bpi-r4-nvme.patch
\cp ../my_files/452-w-add-bpi-r4-nvme-rfb.patch package/boot/uboot-mediatek/patches/452-add-bpi-r4-nvme-rfb.patch
\cp ../my_files/454-w-add-bpi-r4-nvme-env.patch package/boot/uboot-mediatek/patches/454-add-bpi-r4-nvme-env.patch

# BPI-R4-Pro-8x patches
# Remove MTK feed patches superseded by our ports or already provided by feed
rm -f target/linux/mediatek/patches-6.12/999-eth-06-mtk_eth_soc-support-ethernet-passive-mux.patch
# Remove upstream Frank-W DTS patch — we use Sinovoip-based DTS instead
rm -f target/linux/mediatek/patches-6.12/046-v6.19-arm64-dts-mediatek-mt7988a-bpi-r4-pro-add-dts.patch
\cp -r ../my_files/bpi-r4-pro/patches-kernel/* target/linux/mediatek/patches-6.12/
\cp ../my_files/bpi
