#!/bin/bash
set -euo pipefail

# BUMP 2026-07-06 (main migration; predchozi git01 base: 13f39a74):
#   OpenWrt:  6dead2869209f4ff9825f3169c129c5ef04f6273  (openwrt-25.12 HEAD, BEZE ZMENY)
#   MTK SDK:  822c2f0603614e47ec8496571043431494fd2841  (MAIN HEAD; git01 mrazi -> MTK doporucil main)
OPENWRT_COMMIT=${OPENWRT_COMMIT:-6dead2869209f4ff9825f3169c129c5ef04f6273}

rm -rf openwrt
rm -rf mtk-openwrt-feeds

git clone --branch openwrt-25.12 https://git.openwrt.org/openwrt/openwrt.git openwrt
cd openwrt; git checkout ${OPENWRT_COMMIT}; cd -;

# 2026-07-06: migrated git01 -> main (git01 frozen; MTK recommends main). Single source of truth.
git clone --branch main https://github.com/mediatek/mtk-openwrt-feeds mtk-openwrt-feeds
( cd mtk-openwrt-feeds && git checkout 822c2f0603614e47ec8496571043431494fd2841 )


\cp -r my_files/999-sfp-10-additional-quirks.patch mtk-openwrt-feeds/25.12/files/target/linux/mediatek/patches-6.12
\cp -r my_files/999-sfp-11-rtl8261be-mdio-none.patch mtk-openwrt-feeds/25.12/files/target/linux/mediatek/patches-6.12
\cp -r my_files/999-sfp-22-rtl8261be-boot-1g-reprobe.patch mtk-openwrt-feeds/25.12/files/target/linux/mediatek/patches-6.12
\cp -r my_files/999-eth-21-mtk-gdm-rx-fsm-reset.patch mtk-openwrt-feeds/25.12/files/target/linux/mediatek/patches-6.12
\cp -r my_files/999-pcs-10-lynxi-hold-link-down-on-invalid-speed.patch mtk-openwrt-feeds/25.12/files/target/linux/mediatek/patches-6.12
\cp -r my_files/999-fix-01-mac80211-btwt-ap-mode.patch mtk-openwrt-feeds/autobuild/unified/filogic/mac80211/25.12/files/package/kernel/mac80211/patches/subsys/0139-fix-mac80211-btwt-ap-mode-he-btwt-supported.patch
\cp -r my_files/999-fix-00-xfrm-propagate-einprogress.patch mtk-openwrt-feeds/25.12/files/target/linux/mediatek/patches-6.12
\cp -r my_files/0264-wpa_s-add-btwt-join-command.patch mtk-openwrt-feeds/autobuild/unified/filogic/mac80211/25.12/files/package/network/services/hostapd/patches/0264-wpa_s-add-btwt-join-command.patch

### tx_power check Ivan Mironov's patch - for defective BE14 boards with defective eeprom flash
\cp -r my_files/100-wifi-mt76-mt7996-Use-tx_power-from-default-fw-if-EEP.patch mtk-openwrt-feeds/autobuild/unified/filogic/mac80211/25.12/files/package/kernel/mt76/patches

### +4 dB on the repaired 5 GHz targets; retune via /etc/modules.d/mt7996e
\cp -r my_files/101-w-mt7996-5g-tx-power-boost.patch mtk-openwrt-feeds/autobuild/unified/filogic/mac80211/25.12/files/package/kernel/mt76/patches

### per-band WiFi LED (MT7996, single-wiphy MLO) + shared tpt trigger - HW verified 2026-06-28
\cp -r my_files/999-wifi-01-mt7996-per-band-leds.patch mtk-openwrt-feeds/autobuild/unified/filogic/mac80211/25.12/files/package/kernel/mt76/patches/9999-w-mt7996-per-band-leds.patch
\cp -r my_files/999-wifi-02-mt76-share-tpt-led-trigger.patch mtk-openwrt-feeds/autobuild/unified/filogic/mac80211/25.12/files/package/kernel/mt76/patches/9999-w-mt76-share-tpt-led-trigger.patch

cd openwrt
bash ../mtk-openwrt-feeds/autobuild/unified/autobuild.sh filogic-mac80211-mt798x_rfb-wifi7_nic prepare


\cp -r ../my_files/453-w-add-bpi-r4-nvme-dtso.patch target/linux/mediatek/patches-6.12/
\cp -r ../my_files/450-w-nand-mmc-add-bpi-r4.patch package/boot/uboot-mediatek/patches/450-add-bpi-r4.patch
\cp -r ../my_files/451-w-add-bpi-r4-nvme.patch package/boot/uboot-mediatek/patches/451-add-bpi-r4-nvme.patch
\cp ../my_files/452-w-add-bpi-r4-nvme-rfb.patch package/boot/uboot-mediatek/patches/452-add-bpi-r4-nvme-rfb.patch
\cp ../my_files/454-w-add-bpi-r4-nvme-env.patch package/boot/uboot-mediatek/patches/454-add-bpi-r4-nvme-env.patch
\cp -r ../my_files/w-filogic-bpi-r4-universal.mk target/linux/mediatek/image/filogic.mk

### ethernet/board LED (BPI-R4 standard) - leds overlay + uboot LED + filogic device + PHY trigger
\cp -r ../my_files/470-w-add-bpi-r4-leds-overlay.patch target/linux/mediatek/patches-6.12/
\cp ../my_files/471-w-bpi-r4-led-uboot.patch package/boot/uboot-mediatek/patches/471-bpi-r4-led-uboot.patch
sed -i 's/mt7988a-bananapi-bpi-r4-nvme$/mt7988a-bananapi-bpi-r4-nvme mt7988a-bananapi-bpi-r4-leds/' target/linux/mediatek/image/filogic.mk
echo "CONFIG_LED_TRIGGER_PHY=y" >> target/linux/mediatek/filogic/config-6.12

\cp ../my_files/arm-trusted-firmware-mediatek-Makefile package/boot/arm-trusted-firmware-mediatek/Makefile

echo "CONFIG_BLK_DEV_NVME=y" >> target/linux/mediatek/filogic/config-6.12
#echo "CONFIG_DYNAMIC_DEBUG=y" >> target/linux/mediatek/filogic/config-6.12
#echo "CONFIG_DYNAMIC_DEBUG_CORE=y" >> target/linux/mediatek/filogic/config-6.12

\cp -r ../my_files/999-fitblk-02-w-add-bpi-r4-nvme-fitblk.patch target/linux/mediatek/patches-6.12

# 2.5GbE/PoE jack: rename netdev lan4 -> poe-wan (bpi-r4-2g5 dts)
\cp -r ../my_files/999-dts-40-bpi-r4-2g5-poe-wan-netdev-name.patch target/linux/mediatek/patches-6.12/

\cp -r ../my_files/sms-tool/ feeds/packages/utils/sms-tool
\cp -r ../my_files/modemdata-main/ feeds/packages/utils/modemdata 
\cp -r ../my_files/luci-app-modemdata-main/luci-app-modemdata/ feeds/luci/applications
\cp -r ../my_files/luci-app-lite-watchdog/ feeds/luci/applications
\cp -r ../my_files/luci-app-sms-tool-js-main/luci-app-sms-tool-js/ feeds/luci/applications

\cp -r ../my_files/luci-app-wifimgr feeds/luci/applications/luci-app-wifimgr

mkdir -p files/etc/uci-defaults
\cp -r ../my_files/99-set-hostname files/etc/uci-defaults/
chmod +x files/etc/uci-defaults/99-set-hostname

# LAN LED: mtk-led-fix programs mt7530 gphy port-LED registers at boot (link + tx/rx activity)
mkdir -p files/etc/init.d
\cp ../my_files/etc-files/init.d/mtk-led-fix files/etc/init.d/
chmod +x files/etc/init.d/mtk-led-fix
\cp ../my_files/etc-files/uci-defaults/95-mtk-led-fix-enable files/etc/uci-defaults/
chmod +x files/etc/uci-defaults/95-mtk-led-fix-enable

# LAN carrier watchdog: bounce copper ports stuck with no carrier after a reboot
# (some partner NICs, e.g. Realtek RTL8125, deadlock autoneg when the router side
# restarts; a brief down/up revives the link in ~3s)
\cp ../my_files/etc-files/init.d/lan-carrier-watchdog files/etc/init.d/
chmod +x files/etc/init.d/lan-carrier-watchdog
mkdir -p files/usr/sbin
\cp ../my_files/etc-files/sbin/lan-carrier-watchdogd files/usr/sbin/
chmod +x files/usr/sbin/lan-carrier-watchdogd
\cp ../my_files/etc-files/uci-defaults/97-lan-carrier-watchdog-enable files/etc/uci-defaults/
chmod +x files/etc/uci-defaults/97-lan-carrier-watchdog-enable

# WAN on the 2.5GbE/PoE jack: stock defaults still bridge it (as "lan4") into
# br-lan, so an uplink plugged there links up but never gets a WAN lease; drop
# stale lan4 entries and put the renamed poe-wan port in br-wan
# (bpi-r4-2g5/poe boards only, no-op elsewhere)
\cp ../my_files/etc-files/uci-defaults/98-poe-wan-port files/etc/uci-defaults/
chmod +x files/etc/uci-defaults/98-poe-wan-port
# ...and fix the port map at its source: patch the stock board defaults so
# board.json (config_generate input + LuCI status-page ports strip) carries
# poe-wan as a wan member instead of LAN "lan4" on bpi-r4-2g5/poe.
# grep guard: fail the build loudly if upstream reshapes this line.
grep -q 'ucidef_set_interfaces_lan_wan "lan1 lan2 lan3 lan4" "wan sfp-wan"' target/linux/mediatek/filogic/base-files/etc/board.d/02_network
sed -i 's/ucidef_set_interfaces_lan_wan "lan1 lan2 lan3 lan4" "wan sfp-wan"/ucidef_set_interfaces_lan_wan "lan1 lan2 lan3" "wan sfp-wan poe-wan"/' target/linux/mediatek/filogic/base-files/etc/board.d/02_network

# SD auto-expand: grow production + fitrw f2fs to fill the SD card on first boot (SD-only, guarded)
mkdir -p files/lib/preinit
\cp ../my_files/etc-files/lib/preinit/19-expand-fit-rootfs files/lib/preinit/
chmod +x files/lib/preinit/19-expand-fit-rootfs

# NVMe /data: mount the LABEL=data partition (NVMe installs only) at /data on first boot
\cp ../my_files/etc-files/uci-defaults/96-data-mount files/etc/uci-defaults/
chmod +x files/etc/uci-defaults/96-data-mount

mkdir -p files/root/install-dir
\cp ../my_files/bpi-r4-install/install-nand.sh files/root/install-dir/install-nand.sh
chmod +x files/root/install-dir/install-nand.sh
\cp ../my_files/bpi-r4-install/install-nvme.sh files/root/install-dir/install-nvme.sh
chmod +x files/root/install-dir/install-nvme.sh
\cp ../my_files/bpi-r4-install/install-emmc.sh files/root/install-dir/install-emmc.sh
chmod +x files/root/install-dir/install-emmc.sh
\cp ../my_files/bpi-r4-install/install-nvme-unifi.sh files/root/install-dir/install-nvme-unifi.sh
chmod +x files/root/install-dir/install-nvme-unifi.sh
#mkdir -p files/usr/sbin
#\cp ../my_files/bpi-r4-install/boot-nvme files/usr/sbin/boot-nvme
#chmod +x files/usr/sbin/boot-nvme
#\cp ../my_files/bpi-r4-pro/files/usr/sbin/boot-nand files/usr/sbin/boot-nand
#chmod +x files/usr/sbin/boot-nand


./scripts/feeds update -a
./scripts/feeds install -a

\cp ../my_files/fit.sh package/utils/fitblk/files/fit.sh

\cp -r ../my_files/qmi.sh package/network/utils/uqmi/files/lib/netifd/proto/
chmod -R 755 package/network/utils/uqmi/files/lib/netifd/proto
chmod -R 755 feeds/luci/applications/luci-app-modemdata/root
chmod -R 755 feeds/luci/applications/luci-app-sms-tool-js/root
chmod -R 755 feeds/packages/utils/modemdata/files/usr/share

\cp -r ../configs/my_defconfig-wifimgr-universal .config
make defconfig

echo "CONFIG_PACKAGE_trusted-firmware-a-mt7988-emmc-comb-4bg=y" >> .config
echo "CONFIG_PACKAGE_trusted-firmware-a-mt7988-sdmmc-comb-4bg=y" >> .config
echo "CONFIG_PACKAGE_trusted-firmware-a-mt7988-spim-nand-ubi-comb-4bg=y" >> .config

### OpenWrt SDK (per-target = covers all variants incl. Pro 8X) - published as release-sdk
echo "CONFIG_SDK=y" >> .config

bash ../mtk-openwrt-feeds/autobuild/unified/autobuild.sh filogic-mac80211-mt798x_rfb-wifi7_nic build


cp openwrt/bin/targets/mediatek/filogic/openwrt-mediatek-filogic-bananapi_bpi-r4-squashfs-sysupgrade.itb /home/ipsec/latest-sysupgrade.itb 2>/dev/null || true
