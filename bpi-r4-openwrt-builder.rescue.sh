#!/bin/bash
set -euo pipefail

rm -rf openwrt
rm -rf mtk-openwrt-feeds

git clone --branch openwrt-25.12 https://github.com/openwrt/openwrt.git openwrt
cd openwrt; git checkout 0bfaaa65d5bb75462bcbcde542b7f7e750ebaf36; cd -;		#realtek: fix D-Link fan control script
#cd openwrt; git checkout f3a9a42c335714b43615ad14ca76e342d8ff791a; cd -;		#OpenWrt v25.12.1: revert to branch defaults

git clone --branch master https://git01.mediatek.com/openwrt/feeds/mtk-openwrt-feeds
cd mtk-openwrt-feeds; git checkout 1b8eca6a400abc2c9a2b02ce57b2b7ec4c6a3d17; cd -;	#[openwrt-25][MAC80211][WiFi6][kernel 6.12][Add autobuild folder and firmwares for Wi-Fi 6 release]

#cd mtk-openwrt-feeds; git checkout 24595844f63aebb6ccb9bcd28d9690dbfc541a46; cd -;	#[MAC80211][kernel-6.12][wed][Refactor wed msdu page ring init for next generation wifi chip compatible]

#\cp -r my_files/feed_revision mtk-openwrt-feeds/autobuild/unified/

\cp -r my_files/999-sfp-10-additional-quirks.patch mtk-openwrt-feeds/25.12/files/target/linux/mediatek/patches-6.12

#\cp -r my_files/9999-image-bpi-r4-sdcard.patch mtk-openwrt-feeds/25.12/patches-base

### tx_power check Ivan Mironov's patch - for defective BE14 boards with defective eeprom flash
\cp -r my_files/100-wifi-mt76-mt7996-Use-tx_power-from-default-fw-if-EEP.patch mtk-openwrt-feeds/autobuild/unified/filogic/mac80211/25.12/files/package/kernel/mt76/patches

#\cp -r ../my_files/w-Makefile package/libs/musl-fts/Makefile
#\cp -r ../my_files/wsdd2-Makefile feeds/packages/net/wsdd2/Makefile

cd openwrt
bash ../mtk-openwrt-feeds/autobuild/unified/autobuild.sh filogic-mac80211-mt798x_rfb-wifi7_nic prepare log_file=prepare

\cp -r ../my_files/sms-tool/ feeds/packages/utils/sms-tool
\cp -r ../my_files/modemdata-main/ feeds/packages/utils/modemdata 
\cp -r ../my_files/luci-app-modemdata-main/luci-app-modemdata/ feeds/luci/applications
\cp -r ../my_files/luci-app-lite-watchdog/ feeds/luci/applications
\cp -r ../my_files/luci-app-sms-tool-js-main/luci-app-sms-tool-js/ feeds/luci/applications

./scripts/feeds update -a
./scripts/feeds install -a

\cp -r ../my_files/qmi.sh package/network/utils/uqmi/files/lib/netifd/proto/
chmod -R 755 package/network/utils/uqmi/files/lib/netifd/proto
chmod -R 755 feeds/luci/applications/luci-app-modemdata/root
chmod -R 755 feeds/luci/applications/luci-app-sms-tool-js/root
chmod -R 755 feeds/packages/utils/modemdata/files/usr/share

\cp -r ../my_files/450-w-nand-mmc-add-bpi-r4.patch package/boot/uboot-mediatek/patches/450-add-bpi-r4.patch
\cp -r ../my_files/w-nand-mmc-filogic.mk target/linux/mediatek/image/filogic.mk

#mkdir -p files/root/bpi-r4-install
\cp ../my_files/bpi-r4-install/snand-img.bin files/root/bpi-r4-install/
\cp ../my_files/bpi-r4-install/install-nand.sh files/root/bpi-r4-install/
#\cp ../my_files/bpi-r4-install/install-emmc.sh files/root/bpi-r4-install/
chmod +x files/root/bpi-r4-install/install-nand.sh
#chmod +x files/root/bpi-r4-install/install-emmc.sh

# Set hostname for rescue system
mkdir -p files/etc/uci-defaults
cat > files/etc/uci-defaults/99-hostname << 'EOF'
uci set system.@system[0].hostname='OpenWrt-SD'
uci commit system
EOF

\cp -r ../my_files/my_final_defconfig .config
make defconfig



bash ../mtk-openwrt-feeds/autobuild/unified/autobuild.sh filogic-mac80211-mt798x_rfb-wifi7_nic build log_file=build


