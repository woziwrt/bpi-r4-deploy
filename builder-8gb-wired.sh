#!/bin/bash
set -euo pipefail

rm -rf openwrt
rm -rf mtk-openwrt-feeds

tar -xzf repo-cache/openwrt.tar.gz --strip-components=1 -C . --one-top-level=openwrt
tar -xzf repo-cache/mtk-openwrt-feeds.tar.gz --strip-components=1 -C . --one-top-level=mtk-openwrt-feeds

#\cp -r my_files/feed_revision mtk-openwrt-feeds/autobuild/unified/

\cp -r my_files/999-sfp-10-additional-quirks.patch mtk-openwrt-feeds/25.12/files/target/linux/mediatek/patches-6.12

### tx_power check Ivan Mironov's patch - for defective BE14 boards with defective eeprom flash
\cp -r my_files/100-wifi-mt76-mt7996-Use-tx_power-from-default-fw-if-EEP.patch mtk-openwrt-feeds/autobuild/unified/filogic/mac80211/25.12/files/package/kernel/mt76/patches

cd openwrt
bash ../mtk-openwrt-feeds/autobuild/unified/autobuild.sh filogic prepare

\cp -r ../my_files/453-w-add-bpi-r4-nvme-dtso.patch target/linux/mediatek/patches-6.12/
\cp -r ../my_files/450-w-nand-mmc-add-bpi-r4.patch package/boot/uboot-mediatek/patches/450-add-bpi-r4.patch
\cp -r ../my_files/451-w-add-bpi-r4-nvme.patch package/boot/uboot-mediatek/patches/451-add-bpi-r4-nvme.patch
\cp ../my_files/452-w-add-bpi-r4-nvme-rfb.patch package/boot/uboot-mediatek/patches/452-add-bpi-r4-nvme-rfb.patch
\cp ../my_files/454-w-add-bpi-r4-nvme-env.patch package/boot/uboot-mediatek/patches/454-add-bpi-r4-nvme-env.patch
\cp -r ../my_files/w-sd-nand-mmc-nvme-ddr4-filogic.mk target/linux/mediatek/image/filogic.mk

echo "CONFIG_BLK_DEV_NVME=y" >> target/linux/mediatek/filogic/config-6.12

\cp -r ../my_files/999-fitblk-02-w-add-bpi-r4-nvme-fitblk.patch target/linux/mediatek/patches-6.12

\cp -r ../my_files/sms-tool/ feeds/packages/utils/sms-tool
\cp -r ../my_files/modemdata-main/ feeds/packages/utils/modemdata 
\cp -r ../my_files/luci-app-modemdata-main/luci-app-modemdata/ feeds/luci/applications
\cp -r ../my_files/luci-app-lite-watchdog/ feeds/luci/applications
\cp -r ../my_files/luci-app-sms-tool-js-main/luci-app-sms-tool-js/ feeds/luci/applications

mkdir -p files/etc/uci-defaults
\cp -r ../my_files/99-set-hostname files/etc/uci-defaults/
chmod +x files/etc/uci-defaults/99-set-hostname

./scripts/feeds update -a
./scripts/feeds install -a

\cp ../my_files/fit.sh package/utils/fitblk/files/fit.sh

\cp -r ../my_files/qmi.sh package/network/utils/uqmi/files/lib/netifd/proto/
chmod -R 755 package/network/utils/uqmi/files/lib/netifd/proto
chmod -R 755 feeds/luci/applications/luci-app-modemdata/root
chmod -R 755 feeds/luci/applications/luci-app-sms-tool-js/root
chmod -R 755 feeds/packages/utils/modemdata/files/usr/share

\cp -r ../configs/my_defconfig-wired .config
make defconfig

mkdir -p staging_dir/target-aarch64_cortex-a53_musl/image/
\cp ../my_files/bootloader-mt7988-comb-8g/mt7988-spim-nand-comb-8g-bl2.img staging_dir/target-aarch64_cortex-a53_musl/image/
\cp ../my_files/bootloader-mt7988-comb-8g/mt7988-spim-nand-comb-8g-bl31.bin staging_dir/target-aarch64_cortex-a53_musl/image/
\cp ../my_files/bootloader-mt7988-comb-8g/mt7988-emmc-comb-8g-bl2.img staging_dir/target-aarch64_cortex-a53_musl/image/
\cp ../my_files/bootloader-mt7988-comb-8g/mt7988-emmc-comb-8g-bl31.bin staging_dir/target-aarch64_cortex-a53_musl/image/
\cp ../my_files/bootloader-mt7988-comb-8g/mt7988-sdmmc-comb-8g-bl2.img staging_dir/target-aarch64_cortex-a53_musl/image/
\cp ../my_files/bootloader-mt7988-comb-8g/mt7988-sdmmc-comb-8g-bl31.bin staging_dir/target-aarch64_cortex-a53_musl/image/

bash ../mtk-openwrt-feeds/autobuild/unified/autobuild.sh filogic build


