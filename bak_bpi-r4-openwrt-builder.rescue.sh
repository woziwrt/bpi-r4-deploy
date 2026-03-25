#!/bin/bash
set -euo pipefail

rm -rf openwrt
rm -rf mtk-openwrt-feeds

git clone --branch openwrt-25.12 https://github.com/openwrt/openwrt.git openwrt

if [ -n "$OPENWRT_COMMIT" ] && [ "$OPENWRT_COMMIT" != "latest" ]; then
    cd openwrt; git checkout "$OPENWRT_COMMIT"; cd -;
else
    cd openwrt; git checkout c2fe6ca16d0e6c9ec31da709d44263efdf12a3c1; cd -;  #OpenWrt v25.12.0: revert to branch defaults
fi

git clone --branch master https://git01.mediatek.com/openwrt/feeds/mtk-openwrt-feeds

if [ -n "$MTK_COMMIT" ] && [ "$MTK_COMMIT" != "latest" ]; then
    cd mtk-openwrt-feeds; git checkout "$MTK_COMMIT"; cd -;
else
    cd mtk-openwrt-feeds; git checkout b0fefe65a28d5a5b938c9c197d6bbe729484ffef; cd -;  #[kernel-5.4/6.12][mt7988][eth][linux-firmware: mediatek: Revert firmware wrongly updated]
fi

cd openwrt
bash ../mtk-openwrt-feeds/autobuild/unified/autobuild.sh filogic prepare

scripts/feeds uninstall crypto-eip pce tops-tool

\cp -r ../my_files/450-w-nand-mmc-add-bpi-r4.patch package/boot/uboot-mediatek/patches/450-add-bpi-r4.patch
\cp -r ../my_files/w-nand-mmc-filogic.mk target/linux/mediatek/image/filogic.mk

mkdir -p files/root/bpi-r4-install
#\cp ../my_files/bpi-r4-install/snand-img.bin files/root/bpi-r4-install/
#\cp ../my_files/bpi-r4-install/install-nand.sh files/root/bpi-r4-install/
\cp ../my_files/bpi-r4-install/install-emmc.sh files/root/bpi-r4-install/
#chmod +x files/root/bpi-r4-install/install-nand.sh
chmod +x files/root/bpi-r4-install/install-emmc.sh

# Set hostname for rescue system
mkdir -p files/etc/uci-defaults
cat > files/etc/uci-defaults/99-hostname << 'EOF'
uci set system.@system[0].hostname='OpenWrt-NAND-rescue'
uci commit system
EOF

\cp -r ../configs/rescue.defconfig .config
make defconfig

bash ../mtk-openwrt-feeds/autobuild/unified/autobuild.sh filogic build
