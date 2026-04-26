#!/bin/bash
set -euo pipefail

rm -rf openwrt
rm -rf mtk-openwrt-feeds

git clone --branch openwrt-25.12 https://git.openwrt.org/openwrt/openwrt.git openwrt
cd openwrt; git checkout 6cbb072b57e9d72d07097902d975f8a13b768e72; cd -;	#qualcommax: ipq50xx: ax6000: enable pcie1 for QCA9887	

tar xzf /home/ipsec/mtk-feeds-cache.tar.gz

cd openwrt
bash ../mtk-openwrt-feeds/autobuild/unified/autobuild.sh filogic prepare

scripts/feeds uninstall crypto-eip pce tops-tool

\cp -r ../my_files/450-w-nand-mmc-add-bpi-r4.patch package/boot/uboot-mediatek/patches/450-add-bpi-r4.patch
\cp -r ../my_files/451-w-add-bpi-r4-nvme.patch package/boot/uboot-mediatek/patches/451-add-bpi-r4-nvme.patch
\cp ../my_files/452-w-add-bpi-r4-nvme-rfb.patch package/boot/uboot-mediatek/patches/452-add-bpi-r4-nvme-rfb.patch
\cp -r ../my_files/453-w-add-bpi-r4-nvme-dtso.patch target/linux/mediatek/patches-6.12/
\cp ../my_files/454-w-add-bpi-r4-nvme-env.patch package/boot/uboot-mediatek/patches/454-add-bpi-r4-nvme-env.patch
\cp -r ../my_files/w-sd-nand-mmc-nvme-filogic.mk target/linux/mediatek/image/filogic.mk


echo "CONFIG_BLK_DEV_NVME=y" >> target/linux/mediatek/filogic/config-6.12

\cp -r ../my_files/999-fitblk-02-w-add-bpi-r4-nvme-fitblk.patch target/linux/mediatek/patches-6.12

mkdir -p files/root/bpi-r4-install
#\cp ../my_files/bpi-r4-install/snand-img.bin files/root/bpi-r4-install/
#\cp ../my_files/bpi-r4-install/install-nand.sh files/root/bpi-r4-install/
\cp ../my_files/bpi-r4-install/install-emmc.sh files/root/bpi-r4-install/
#chmod +x files/root/bpi-r4-install/install-nand.sh
chmod +x files/root/bpi-r4-install/install-emmc.sh
\cp ../my_files/bpi-r4-install/install-nvme.sh files/root/bpi-r4-install/
chmod +x files/root/bpi-r4-install/install-nvme.sh

# Set hostname for rescue system
mkdir -p files/etc/uci-defaults
cat > files/etc/uci-defaults/99-hostname << 'EOF'
uci set system.@system[0].hostname='BPI-R4-NAND-rescue '
uci commit system
EOF

\cp -r ../configs/rescue.defconfig .config
make defconfig


bash ../mtk-openwrt-feeds/autobuild/unified/autobuild.sh filogic build
