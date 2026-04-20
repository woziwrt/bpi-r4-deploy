#!/bin/bash
set -euo pipefail

rm -rf openwrt
rm -rf mtk-openwrt-feeds

git clone --branch openwrt-25.12 https://github.com/openwrt/openwrt.git openwrt
#cd openwrt; git checkout 00dcdd7451487dfb63c6c3bbd649a547c76e1a13; cd -;		#firmware: Add support for Airoha EN7581/AN7583 NPU variant firmware
cd openwrt; git checkout 865229fad90af85989bbcdd294424a6f2d2723b3; cd -;		#mediatek: filogic: fix EAX17 rootfs hash in FIT node for per-device rootfs builds

git clone --branch master https://git01.mediatek.com/openwrt/feeds/mtk-openwrt-feeds
#cd mtk-openwrt-feeds; git checkout c55064d7aa0125264b8e42e1bdb045f8da96f29e; cd -;	#[kernel-6.12][mt7988][pcie][Fix MT7988 4-PCIE mode]
cd mtk-openwrt-feeds; git checkout e703a4ca118969d9d3f0ee2d10d61599c0db7148; cd -;	#[openwrt-24][MAC80211][Change mac80211 configuration]

cd openwrt
bash ../mtk-openwrt-feeds/autobuild/unified/autobuild.sh filogic prepare

scripts/feeds uninstall crypto-eip pce tops-tool

\cp -r ../my_files/450-w-nand-mmc-add-bpi-r4.patch package/boot/uboot-mediatek/patches/450-add-bpi-r4.patch
\cp -r ../my_files/451-w-add-bpi-r4-nvme.patch package/boot/uboot-mediatek/patches/451-add-bpi-r4-nvme.patch
\cp ../my_files/452-w-add-bpi-r4-nvme-rfb.patch package/boot/uboot-mediatek/patches/452-add-bpi-r4-nvme-rfb.patch
\cp -r ../my_files/453-w-add-bpi-r4-nvme-dtso.patch target/linux/mediatek/patches-6.12/
\cp ../my_files/454-w-add-bpi-r4-nvme-env.patch package/boot/uboot-mediatek/patches/454-add-bpi-r4-nvme-env.patch
#\cp -r ../my_files/w-nand-mmc-filogic.mk target/linux/mediatek/image/filogic.mk
\cp -r ../my_files/w-sd-nand-mmc-nvme-ddr4-filogic.mk target/linux/mediatek/image/filogic.mk


echo "CONFIG_BLK_DEV_NVME=y" >> target/linux/mediatek/filogic/config-6.12

\cp -r ../my_files/999-fitblk-02-w-add-bpi-r4-nvme-fitblk.patch target/linux/mediatek/patches-6.12

mkdir -p files/root/bpi-r4-install
\cp ../my_files/bpi-r4-install/snand-img.bin files/root/bpi-r4-install/
\cp ../my_files/bpi-r4-install/install-nand.sh files/root/bpi-r4-install/
#\cp ../my_files/bpi-r4-install/install-emmc.sh files/root/bpi-r4-install/
chmod +x files/root/bpi-r4-install/install-nand.sh
#chmod +x files/root/bpi-r4-install/install-emmc.sh
#\cp ../my_files/bpi-r4-install/install-nvme.sh files/root/bpi-r4-install/
#chmod +x files/root/bpi-r4-install/install-nvme.sh

# Set hostname for rescue system
mkdir -p files/etc/uci-defaults
cat > files/etc/uci-defaults/99-hostname << 'EOF'
uci set system.@system[0].hostname='BPI-R4-rescue-SD'
uci commit system
EOF

\cp -r ../configs/rescue.defconfig .config
make defconfig

mkdir -p staging_dir/target-aarch64_cortex-a53_musl/image/
\cp ../my_files/bootloader-mt7988-ddr4/mt7988-spim-nand-ddr4-bl2.img staging_dir/target-aarch64_cortex-a53_musl/image/
\cp ../my_files/bootloader-mt7988-ddr4/mt7988-spim-nand-ddr4-bl31.bin staging_dir/target-aarch64_cortex-a53_musl/image/
\cp ../my_files/bootloader-mt7988-ddr4/mt7988-emmc-ddr4-bl2.img staging_dir/target-aarch64_cortex-a53_musl/image/
\cp ../my_files/bootloader-mt7988-ddr4/mt7988-emmc-ddr4-bl31.bin staging_dir/target-aarch64_cortex-a53_musl/image/
\cp ../my_files/bootloader-mt7988-ddr4/mt7988-sdmmc-ddr4-bl2.img staging_dir/target-aarch64_cortex-a53_musl/image/
\cp ../my_files/bootloader-mt7988-ddr4/mt7988-sdmmc-ddr4-bl31.bin staging_dir/target-aarch64_cortex-a53_musl/image/



bash ../mtk-openwrt-feeds/autobuild/unified/autobuild.sh filogic build

exit