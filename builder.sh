#!/bin/bash
set -euo pipefail

rm -rf openwrt
rm -rf mtk-openwrt-feeds

git clone --branch openwrt-25.12 https://git.openwrt.org/openwrt/openwrt.git openwrt
cd openwrt; git checkout ${OPENWRT_COMMIT}; cd -;

tar xzf repo-cache/mtk-openwrt-feeds.tar.gz
mv mtk-clone mtk-openwrt-feeds

#\cp -r my_files/feed_revision mtk-openwrt-feeds/autobuild/unified/

\cp -r my_files/999-sfp-10-additional-quirks.patch mtk-openwrt-feeds/25.12/files/target/linux/mediatek/patches-6.12

### tx_power check Ivan Mironov's patch - for defective BE14 boards with defective eeprom flash
#\cp -r my_files/100-wifi-mt76-mt7996-Use-tx_power-from-default-fw-if-EEP.patch mtk-openwrt-feeds/autobuild/unified/filogic/mac80211/25.12/files/package/kernel/mt76/patches

cd openwrt

bash ../mtk-openwrt-feeds/autobuild/unified/autobuild.sh filogic-mac80211-mt798x_rfb-wifi7_nic prepare


# modemfeed kaynağını ekle (autobuild.sh prepare'dan sonra)
echo 'src-git-full modemfeed https://github.com/koshev-msk/modemfeed.git' >> feeds.conf.default
echo 'src-git-full xmm7360-pci https://github.com/xmm7360/xmm7360-pci.git' >> feeds.conf.default
echo 'src-git-full xmm7360-usb https://github.com/xmm7360/xmm7360-usb-modeswitch.git' >> feeds.conf.default


\cp -r ../my_files/453-w-add-bpi-r4-nvme-dtso.patch target/linux/mediatek/patches-6.12/
\cp -r ../my_files/450-w-nand-mmc-add-bpi-r4.patch package/boot/uboot-mediatek/patches/450-add-bpi-r4.patch
\cp -r ../my_files/451-w-add-bpi-r4-nvme.patch package/boot/uboot-mediatek/patches/451-add-bpi-r4-nvme.patch
\cp ../my_files/452-w-add-bpi-r4-nvme-rfb.patch package/boot/uboot-mediatek/patches/452-add-bpi-r4-nvme-rfb.patch
\cp ../my_files/454-w-add-bpi-r4-nvme-env.patch package/boot/uboot-mediatek/patches/454-add-bpi-r4-nvme-env.patch
\cp -r ../my_files/w-filogic-bpi-r4-universal.mk target/linux/mediatek/image/filogic.mk

# ARM Trusted Firmware Makefile'i feeds güncellendikten sonra kopyala
\cp ../my_files/arm-trusted-firmware-mediatek-Makefile package/boot/arm-trusted-firmware-mediatek/Makefile

# Modemdata ve diğer luci app'leri feeds install sonrası kopyala
\cp -r ../my_files/sms-tool/ feeds/packages/utils/sms-tool
\cp -r ../my_files/modemdata-main/ feeds/packages/utils/modemdata 
\cp -r ../my_files/luci-app-modemdata-main/luci-app-modemdata/ feeds/luci/applications
\cp -r ../my_files/luci-app-lite-watchdog/ feeds/luci/applications
\cp -r ../my_files/luci-app-sms-tool-js-main/luci-app-sms-tool-js/ feeds/luci/applications

echo "CONFIG_BLK_DEV_NVME=y" >> target/linux/mediatek/filogic/config-6.12
echo "CONFIG_MHI_BUS=y" >> target/linux/mediatek/filogic/config-6.12
echo "CONFIG_MHI_BUS_PCI_GENERIC=y" >> target/linux/mediatek/filogic/config-6.12
echo "CONFIG_MHI_BUS_EP=y" >> target/linux/mediatek/filogic/config-6.12
echo "CONFIG_IOSM=y" >> target/linux/mediatek/filogic/config-6.12

\cp -r ../my_files/999-fitblk-02-w-add-bpi-r4-nvme-fitblk.patch target/linux/mediatek/patches-6.12

mkdir -p files/etc/uci-defaults
\cp -r ../my_files/99-set-hostname files/etc/uci-defaults/
chmod +x files/etc/uci-defaults/99-set-hostname

# Tüm feed'leri güncelle ve yükle (modemfeed dahil)
./scripts/feeds update -a
./scripts/feeds install -a

# modemfeed paketlerini yükle (Fibocom L850 dahil)
./scripts/feeds install -p modemfeed modeminfo modeminfo-serial-fibocom modeminfo-serial-xmm
./scripts/feeds install -p modemfeed luci-proto-xmm xmm-modem
./scripts/feeds install -p modemfeed atinout luci-app-atinout
./scripts/feeds install -p modemfeed uqmi comgt comgt-ncm

# xmm7360 PCIe driver'ını yükle (Intel XMM7360 LTE modemi için)
./scripts/feeds install -p xmm7360-pci kmod-xmm7360

# xmm7360 USB modeswitch driver'ını yükle (USB modemler için)
./scripts/feeds install -p xmm7360-usb xmm7360-usb-modeswitch

# iOSM (Intel Open Source Modem) kernel modülü - M.2 modem desteği
# Not: iOSM, OpenWrt'nin ana kernel paketlerinde mevcuttur, ekstra feed gerekmez
./scripts/feeds install kmod-iosm

\cp ../my_files/fit.sh package/utils/fitblk/files/fit.sh

\cp -r ../my_files/qmi.sh package/network/utils/uqmi/files/lib/netifd/proto/
chmod -R 755 package/network/utils/uqmi/files/lib/netifd/proto
chmod -R 755 feeds/luci/applications/luci-app-modemdata/root
chmod -R 755 feeds/luci/applications/luci-app-sms-tool-js/root
chmod -R 755 feeds/packages/utils/modemdata/files/usr/share

\cp -r ../configs/my_defconfig-4gb-poe-wifi .config
make defconfig

### ------------------------------------------------------------
### Modemfeed + Fibocom L850 paketleri (koshev-msk/modemfeed)
### xmm7360 PCIe driver (Intel XMM7360 PCIe LTE modem)
### xmm7360 USB modeswitch (USB modemler için)
### ------------------------------------------------------------
echo ""
echo "========================================"
echo "📶 Modemfeed aktif edildi"
echo "   Kaynak: https://github.com/koshev-msk/modemfeed"
echo "========================================"
echo ""
echo "========================================"
echo "📡 xmm7360 PCIe driver aktif edildi"
echo "   Kaynak: https://github.com/xmm7360/xmm7360-pci"
echo "   Paket: kmod-xmm7360 (Intel XMM7360 PCIe)"
echo "========================================"
echo ""
echo "========================================"
echo "🔌 xmm7360 USB modeswitch driver aktif edildi"
echo "   Kaynak: https://github.com/xmm7360/xmm7360-usb-modeswitch"
echo "   Paket: xmm7360-usb-modeswitch (USB modemler için)"
echo "========================================"
echo ""

# Modemfeed paketlerini zorla =y olarak ayarla
for pkg in modeminfo modeminfo-serial-fibocom modeminfo-serial-xmm \
           luci-proto-xmm xmm-modem atinout luci-app-atinout \
           luci-app-modemdata luci-app-sms-tool-js luci-app-lite-watchdog; do
  echo "CONFIG_PACKAGE_${pkg}=y" >> .config
  echo "   ✅ ${pkg} -> ENABLED"
done

# xmm7360 PCIe driver'ını zorla =y olarak ayarla
echo "CONFIG_PACKAGE_kmod-xmm7360=y" >> .config
echo "   ✅ kmod-xmm7360 (PCIe) -> ENABLED"

# xmm7360 USB modeswitch driver'ını zorla =y olarak ayarla
echo "CONFIG_PACKAGE_xmm7360-usb-modeswitch=y" >> .config
echo "   ✅ xmm7360-usb-modeswitch (USB) -> ENABLED"

# iOSM (Intel M.2 modem) kernel modülünü zorla =y olarak ayarla
echo "CONFIG_PACKAGE_kmod-iosm=y" >> .config
echo "   ✅ kmod-iosm (Intel M.2 modem) -> ENABLED"

echo ""
echo "========================================"
echo "🔐 Trusted Firmware (4GB)"
echo "========================================"
echo ""
echo "========================================"
echo "📱 iOSM (Intel M.2 modem) aktif edildi"
echo "   Kernel modülü: kmod-iosm"
echo "   Desteklenen modemler: Intel M.2 LTE/5G modemler"
echo "========================================"
echo ""
### ------------------------------------------------------------
echo "CONFIG_PACKAGE_trusted-firmware-a-mt7988-emmc-comb-4bg=y" >> .config
echo "CONFIG_PACKAGE_trusted-firmware-a-mt7988-sdmmc-comb-4bg=y" >> .config
echo "CONFIG_PACKAGE_trusted-firmware-a-mt7988-spim-nand-ubi-comb-4bg=y" >> .config

bash ../mtk-openwrt-feeds/autobuild/unified/autobuild.sh filogic-mac80211-mt798x_rfb-wifi7_nic build
