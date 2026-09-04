#!/bin/bash
set -euo pipefail

# BUMP 2026-07-05 (main migration; predchozi git01 base: 13f39a74 = wed-refactor 06-25):
#   OpenWrt:  6dead2869209f4ff9825f3169c129c5ef04f6273  (openwrt-25.12 HEAD, BEZE ZMENY)
#   MTK SDK:  822c2f0603614e47ec8496571043431494fd2841  (MAIN HEAD; git01 mrazi -> MTK doporucil main)

rm -rf openwrt
rm -rf mtk-openwrt-feeds

git clone --branch openwrt-25.12 https://github.com/openwrt/openwrt.git openwrt
cd openwrt; git checkout ${OPENWRT_COMMIT:-6dead2869209f4ff9825f3169c129c5ef04f6273}; cd -;

git clone --branch main https://github.com/mediatek/mtk-openwrt-feeds mtk-openwrt-feeds
( cd mtk-openwrt-feeds && git checkout ${MTK_COMMIT:-822c2f0603614e47ec8496571043431494fd2841} )

\cp -r my_files/999-sfp-10-additional-quirks.patch mtk-openwrt-feeds/25.12/files/target/linux/mediatek/patches-6.12
\cp -r my_files/999-sfp-11-rtl8261be-mdio-none.patch mtk-openwrt-feeds/25.12/files/target/linux/mediatek/patches-6.12
\cp -r my_files/999-sfp-22-rtl8261be-boot-1g-reprobe.patch mtk-openwrt-feeds/25.12/files/target/linux/mediatek/patches-6.12
\cp -r my_files/999-eth-21-mtk-gdm-rx-fsm-reset.patch mtk-openwrt-feeds/25.12/files/target/linux/mediatek/patches-6.12
#\cp -r my_files/999-sfp-15-oem-sfp10gt-ignore-los.patch mtk-openwrt-feeds/25.12/files/target/linux/mediatek/patches-6.12
\cp -r my_files/999-fix-00-xfrm-sw-sa-offload-ok.patch mtk-openwrt-feeds/25.12/files/target/linux/mediatek/patches-6.12

### tx_power check Ivan Mironov's patch - for defective BE14 boards with defective eeprom flash
#\cp -r my_files/100-wifi-mt76-mt7996-Use-tx_power-from-default-fw-if-EEP.patch mtk-openwrt-feeds/autobuild/unified/filogic/mac80211/25.12/files/package/kernel/mt76/patches

cd openwrt
bash ../mtk-openwrt-feeds/autobuild/unified/autobuild.sh filogic prepare

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
\cp -r ../my_files/bpi-r4-pro/patches-kernel/* target/linux/mediatek/patches-6.12/
\cp ../my_files/bpi-r4-pro/patches-uboot/471-add-bpi-r4-pro-8x.patch package/boot/uboot-mediatek/patches/
#\cp ../my_files/bpi-r4-pro/patches-uboot/472-add-bpi-r4-pro-8x-makefile.patch package/boot/uboot-mediatek/patches/
\cp ../my_files/bpi-r4-pro/uboot-mediatek-Makefile package/boot/uboot-mediatek/Makefile
\cp ../my_files/bpi-r4-pro/arm-trusted-firmware-mediatek-Makefile package/boot/arm-trusted-firmware-mediatek/Makefile
\cp -r ../my_files/w-sd-nand-mmc-nvme-ddr4-filogic.mk target/linux/mediatek/image/filogic.mk
mv target/linux/mediatek/image/filogic-extra.mk target/linux/mediatek/image/filogic-extra.mk.disabled

echo "CONFIG_BLK_DEV_NVME=y" >> target/linux/mediatek/filogic/config-6.12
echo "CONFIG_TASK_IO_ACCOUNTING=y" >> target/linux/mediatek/filogic/config-6.12
python3 -c 'content=open("package/kernel/linux/modules/netdevices.mk").read(); content=content.replace("  KCONFIG:=CONFIG_AS21XXX_PHY\n  FILES:= \\\n   $(LINUX_DIR)/drivers/net/phy/as21xxx.ko\n  AUTOLOAD:=$(call AutoLoad,18,as21xxx)", "  KCONFIG:=CONFIG_AS21XXX_PHY\n  FILES:= \\\n   $(LINUX_DIR)/drivers/net/phy/aeon_as21xxx.ko\n  AUTOLOAD:=$(call AutoLoad,18,aeon_as21xxx)"); open("package/kernel/linux/modules/netdevices.mk","w").write(content)'
python3 -c 'content=open("target/linux/mediatek/filogic/config-6.12").read(); content=content.replace("CONFIG_AS21XXX_PHY=y", "CONFIG_AS21XXX_PHY=m"); open("target/linux/mediatek/filogic/config-6.12","w").write(content)'

\cp -r ../my_files/999-fitblk-02-w-add-bpi-r4-nvme-fitblk.patch target/linux/mediatek/patches-6.12

\cp -r ../my_files/sms-tool/ feeds/packages/utils/sms-tool
\cp -r ../my_files/modemdata-main/ feeds/packages/utils/modemdata
\cp -r ../my_files/luci-app-modemdata-main/luci-app-modemdata/ feeds/luci/applications
\cp -r ../my_files/luci-app-lite-watchdog/ feeds/luci/applications
\cp -r ../my_files/luci-app-sms-tool-js-main/luci-app-sms-tool-js/ feeds/luci/applications
mkdir -p files/etc/uci-defaults
\cp -r ../my_files/99-set-hostname files/etc/uci-defaults/
chmod +x files/etc/uci-defaults/99-set-hostname
\cp -r ../my_files/99-pro-8x-network files/etc/uci-defaults/
chmod +x files/etc/uci-defaults/99-pro-8x-network

# SD auto-expand: grow production + fitrw f2fs to fill the SD card on first boot
# (SD-only, fail-closed gate inside the hook; no-op on eMMC/NVMe/NAND)
mkdir -p files/lib/preinit
\cp ../my_files/etc-files/lib/preinit/19-expand-fit-rootfs files/lib/preinit/
chmod +x files/lib/preinit/19-expand-fit-rootfs

mkdir -p files/etc
\cp ../my_files/fw_env_pro8x_snand.config files/etc/fw_env.config


mkdir -p files/root/install-dir
\cp ../my_files/bpi-r4-install/install-nand-pro8x.sh files/root/install-dir/install-nand.sh
chmod +x files/root/install-dir/install-nand.sh
\cp ../my_files/bpi-r4-install/install-nvme-pro8x.sh files/root/install-dir/install-nvme.sh
chmod +x files/root/install-dir/install-nvme.sh
\cp ../my_files/bpi-r4-install/install-emmc-pro8x.sh files/root/install-dir/install-emmc.sh
chmod +x files/root/install-dir/install-emmc.sh
\cp ../my_files/bpi-r4-install/install-nvme-unifi.sh files/root/install-dir/install-nvme-unifi.sh
chmod +x files/root/install-dir/install-nvme-unifi.sh
mkdir -p files/usr/sbin
\cp ../my_files/bpi-r4-install/boot-nvme files/usr/sbin/boot-nvme
chmod +x files/usr/sbin/boot-nvme
\cp ../my_files/bpi-r4-pro/files/usr/sbin/boot-nand files/usr/sbin/boot-nand
chmod +x files/usr/sbin/boot-nand

#\cp -r ../my_files/luci-app-wifimgr/ package/luci-app-wifimgr/

./scripts/feeds update -a
./scripts/feeds install -a



\cp ../my_files/fit.sh package/utils/fitblk/files/fit.sh

\cp -r ../my_files/qmi.sh package/network/utils/uqmi/files/lib/netifd/proto/
chmod -R 755 package/network/utils/uqmi/files/lib/netifd/proto
chmod -R 755 feeds/luci/applications/luci-app-modemdata/root
chmod -R 755 feeds/luci/applications/luci-app-sms-tool-js/root
#chmod -R 755 package/luci-app-wifimgr/root
chmod -R 755 feeds/packages/utils/modemdata/files/usr/share

\cp -r ../configs/my_defconfig-8x-wired .config
make defconfig
echo "CONFIG_PACKAGE_trusted-firmware-a-mt7988-emmc-comb-4bg=y" >> .config
echo "CONFIG_PACKAGE_trusted-firmware-a-mt7988-sdmmc-comb-4bg=y" >> .config
echo "CONFIG_PACKAGE_trusted-firmware-a-mt7988-spim-nand-ubi-comb-4bg=y" >> .config


bash ../mtk-openwrt-feeds/autobuild/unified/autobuild.sh filogic build
