#!/bin/bash
set -euo pipefail
EASYMESH_SHARED=/home/ipsec/easymesh-shared
. /home/ipsec/easymesh-shared/common-easymesh.sh

# Z ceho se stavi musi jit vyrobit znovu, a neulozenou praci ve sdilenem
# feedu by `git reset --hard` nize beze slova zahodil.
easymesh_require_clean_trees

# BUMP 2026-06-28 (HW overeno na obou routerech; predchozi: 7b8ce1e / 42c9ff = 6.12.93):
#   OpenWrt:  6dead2869209f4ff9825f3169c129c5ef04f6273  (openwrt-25.12 HEAD)
#   MTK SDK:  13f39a7448764466f0ab5eb290fdefd9a9d2335b  (github git01 HEAD)
OPENWRT_COMMIT=${OPENWRT_COMMIT:-4d0fec5a4845ba166203a782d08217b3f1cf2af9}

rm -rf openwrt
rm -rf mtk-openwrt-feeds

git clone --branch openwrt-25.12 https://git.openwrt.org/openwrt/openwrt.git openwrt
cd openwrt; git checkout ${OPENWRT_COMMIT}; cd -;

# BUMP TEST 2026-06-23: tarball nahrazen cerstvym clone z MTK GitHub (vetev git01 = nase linie)
#tar xzf /home/ipsec/mtk-feeds-cache.tar.gz
git clone --branch main https://github.com/mediatek/mtk-openwrt-feeds mtk-openwrt-feeds
( cd mtk-openwrt-feeds && git checkout b7873eae800034c05f8f6257b55949d6464eb2e3 )


\cp -r my_files/999-sfp-10-additional-quirks.patch mtk-openwrt-feeds/25.12/files/target/linux/mediatek/patches-6.12
\cp -r my_files/999-sfp-11-rtl8261be-mdio-none.patch mtk-openwrt-feeds/25.12/files/target/linux/mediatek/patches-6.12
\cp -r my_files/999-sfp-22-rtl8261be-boot-1g-reprobe.patch mtk-openwrt-feeds/25.12/files/target/linux/mediatek/patches-6.12
\cp -r my_files/999-eth-21-mtk-gdm-rx-fsm-reset.patch mtk-openwrt-feeds/25.12/files/target/linux/mediatek/patches-6.12
\cp -r my_files/999-pcs-10-lynxi-hold-link-down-on-invalid-speed.patch mtk-openwrt-feeds/25.12/files/target/linux/mediatek/patches-6.12
\cp -r my_files/999-fix-01-mac80211-btwt-ap-mode.patch mtk-openwrt-feeds/autobuild/unified/filogic/mac80211/25.12/files/package/kernel/mac80211/patches/subsys/0139-fix-mac80211-btwt-ap-mode-he-btwt-supported.patch
\cp -r my_files/999-fix-00-xfrm-propagate-einprogress.patch mtk-openwrt-feeds/25.12/files/target/linux/mediatek/patches-6.12
\cp -r my_files/0264-wpa_s-add-btwt-join-command.patch mtk-openwrt-feeds/autobuild/unified/filogic/mac80211/25.12/files/package/network/services/hostapd/patches/0264-wpa_s-add-btwt-join-command.patch

### tx_power check Ivan Mironov's patch - for defective BE14 boards with defective eeprom flash
#\cp -r my_files/100-wifi-mt76-mt7996-Use-tx_power-from-default-fw-if-EEP.patch mtk-openwrt-feeds/autobuild/unified/filogic/mac80211/25.12/files/package/kernel/mt76/patches

### per-band WiFi LED (MT7996, single-wiphy MLO) + shared tpt trigger - HW verified 2026-06-28
\cp -r my_files/999-wifi-01-mt7996-per-band-leds.patch mtk-openwrt-feeds/autobuild/unified/filogic/mac80211/25.12/files/package/kernel/mt76/patches/9999-w-mt7996-per-band-leds.patch
\cp -r my_files/999-wifi-02-mt76-share-tpt-led-trigger.patch mtk-openwrt-feeds/autobuild/unified/filogic/mac80211/25.12/files/package/kernel/mt76/patches/9999-w-mt76-share-tpt-led-trigger.patch

easymesh_apply_wifi_patches
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


# The mesh runtime is NOT baked into the image any more (2026-08-09).
#
# easymesh_install_mld_scripts used to copy eleven workers, their init scripts
# and rc.d symlinks, plus mlo-backhaul-setup, mesh-role, mesh-env, bssid-pin
# and eight uci-defaults straight into files/. The easymesh-wifi package ships
# the same files. Every node therefore carried the mesh layer from two sources
# at once, and which one won depended on when it was flashed and when it was
# last upgraded - so no two nodes in the lab were alike, and "identical after
# an apk install" could not even be measured.
#
# It also baked /etc/mesh-node-names, a hardcoded list of the four lab boards,
# into what is meant to be a product image.
#
# The split is now: the image carries the base system and the user interface
# (LuCI, wifimgr, the EasyMesh dashboard), and apk carries the whole mesh
# runtime. A node is then exactly what its packages say it is, which is the
# only version of this that can be tested.
#
# easymesh_install_mld_scripts
easymesh_install_wifimgr
./scripts/feeds update -a
./scripts/feeds install -a
easymesh_setup_iopsys_feed
grep -q "src-link easymeshr6" feeds.conf.default || echo "src-link easymeshr6 /home/ipsec/easymesh-shared/easymesh-r6-feed" >> feeds.conf.default
./scripts/feeds update easymeshr6
./scripts/feeds install easymesh easymesh-config easymesh-mesh easymesh-wifi easymesh-api luci-app-easymesh

\cp ../my_files/fit.sh package/utils/fitblk/files/fit.sh

\cp -r ../my_files/qmi.sh package/network/utils/uqmi/files/lib/netifd/proto/
chmod -R 755 package/network/utils/uqmi/files/lib/netifd/proto
chmod -R 755 feeds/luci/applications/luci-app-modemdata/root
chmod -R 755 feeds/luci/applications/luci-app-sms-tool-js/root
chmod -R 755 feeds/packages/utils/modemdata/files/usr/share

\cp -r ../configs/my_defconfig-wifimgr-easymesh-universal .config
make defconfig
easymesh_apply_defconfig

# Nothing of the mesh goes into the image (2026-08-09).
#
# easymesh_apply_defconfig is shared with the lab builders and sets the whole
# stack to =y, so the image carried map-agent, ieee1905, libwifi, wifimngr and
# the rest inside it - and apk then installed the same packages on top. Which
# copy a node was actually running depended on when it had last been flashed
# and when it had last been upgraded, which is why no two boards in the lab
# were alike and why "identical after an apk install" could not be measured at
# all.
#
# These lines come after that function on purpose: the last assignment in
# .config wins, so this overrides without touching the shared helper that the
# other builders still depend on.
#
# =m still builds every package - they end up in bin/packages and go into the
# apk repository. They just are not part of the firmware. A node is then
# exactly what its packages say it is.
#
# kmod-ebtables stays =y: kernel modules belong in the image, because apk
# cannot add one to a running kernel. Userspace is what apk is for.
cat >> .config <<'NOBAKE_EOF'
CONFIG_PACKAGE_libeasy=m
CONFIG_PACKAGE_libwifi=m
CONFIG_PACKAGE_libwifiutils=m
CONFIG_PACKAGE_libieee1905=m
CONFIG_PACKAGE_ieee1905=m
CONFIG_PACKAGE_ieee1905-map-plugin=m
CONFIG_PACKAGE_wifimngr=m
CONFIG_PACKAGE_map-agent=m
CONFIG_PACKAGE_map-controller=m
CONFIG_PACKAGE_hostapd-utils=m
CONFIG_PACKAGE_wpa-cli=m
CONFIG_PACKAGE_easymesh=m
CONFIG_PACKAGE_easymesh-config=m
CONFIG_PACKAGE_easymesh-mesh=m
CONFIG_PACKAGE_easymesh-wifi=m
CONFIG_PACKAGE_easymesh-api=m
CONFIG_PACKAGE_luci-app-easymesh=m
NOBAKE_EOF


# Poslední kontrola před buildem: opravdu se mesh vrstva nezapéká?
#
# .config se tu skládá ve vrstvách, každá přepisuje předchozí, a která vyhraje
# pozná jen ten, kdo je přečte ve správném pořadí. Přesně tak se 9. srpna
# rozešly buildery a devět dní si toho nikdo nevšiml: jeden dostal blok =m,
# druhý ne, a jediné, co to prozradilo, byla čerstvě virginizovaná krabice,
# na které běžel mapcontroller.
#
# tail -1, ne head -1: symbol je v .config dvakrát a kconfig počítá POSLEDNÍ.
# (Na tohle jsem naletěl při ověřování téhle opravy a málem kvůli tomu zastavil
# hodinový build.)
for _s in libeasy libwifi libwifiutils libieee1905 ieee1905 \
          ieee1905-map-plugin wifimngr map-agent map-controller \
          hostapd-utils wpa-cli; do
	_v=$(grep -E "^(# )?CONFIG_PACKAGE_${_s}[= ]" .config | tail -1)
	case "$_v" in
		*"=m") ;;
		*) echo "CHYBA: CONFIG_PACKAGE_${_s} neni =m (je: ${_v:-CHYBI})" >&2
		   echo "       mesh vrstva by se zapekla do obrazu" >&2
		   exit 1 ;;
	esac
done
echo ">>> kontrola: mesh vrstva je =m, do obrazu se nezapece"


# --- Ladeni SMP/RPS a LuCI pro tailscale (doplneno 2026-08-30) ---
#
# smp_util: MTK balicek, ktery po startu rozdeli ethernetova preruseni mezi
# jadra. Bez nej sedi VSECHNA na cpu0 a krabice da na 10G lince ~5,4 misto
# ~9,4 Gbit/s (zmereno iperf3 mezi dvema BPI-R4 pres SFP, 30. 8. 2026).
# Vypadl 21. 8. z commitu "bring the package set in line" a nikdo si toho
# nevsiml, protoze se to projevi jen pri mereni pres 5 Gbit/s.
#
# luci-app-tailscale-community: samotny démon uz zapnuty byl, ale bez teto
# stranky se tailscale neda nastavit z webu.
echo "CONFIG_PACKAGE_smp_util=y" >> .config
echo "CONFIG_PACKAGE_luci-app-tailscale-community=y" >> .config

# Kontrola, ze to prezilo `make defconfig` - stejny princip jako u mesh vrstvy.
for _s in smp_util luci-app-tailscale-community; do
	_v=$(grep -E "^(# )?CONFIG_PACKAGE_${_s}[= ]" .config | tail -1)
	case "$_v" in
		*"=y") ;;
		*) echo "CHYBA: CONFIG_PACKAGE_${_s} neni =y (je: ${_v:-CHYBI})" >&2
		   exit 1 ;;
	esac
done
echo ">>> kontrola: smp_util a luci-app-tailscale-community jsou =y"

echo "CONFIG_PACKAGE_trusted-firmware-a-mt7988-emmc-comb-4bg=y" >> .config
echo "CONFIG_PACKAGE_trusted-firmware-a-mt7988-sdmmc-comb-4bg=y" >> .config
echo "CONFIG_PACKAGE_trusted-firmware-a-mt7988-spim-nand-ubi-comb-4bg=y" >> .config

### OpenWrt SDK (per-target = covers all variants incl. Pro 8X) - published as release-sdk
#echo "CONFIG_SDK=y" >> .config

bash ../mtk-openwrt-feeds/autobuild/unified/autobuild.sh filogic-mac80211-mt798x_rfb-wifi7_nic build


cp /home/ipsec/universal-new/openwrt/bin/targets/mediatek/filogic/openwrt-mediatek-filogic-bananapi_bpi-r4-squashfs-sysupgrade.itb /home/ipsec/latest-sysupgrade.itb 2>/dev/null || true

# Tenhle adresar sdili obe varianty a kazdy build zacina `rm -rf openwrt`,
# takze za chvili tu po tomhle vysledku nezbude nic. Odlozit vystup i recept.
easymesh_archive_build lab-apk /home/ipsec/universal-new
