#!/bin/bash
set -euo pipefail
# ============================================================================
# builder-x8-production.sh - BPI-R4 Pro 8X, PRODUCTION image.
#
# Modelled line for line on builder-production-universal.sh, because the point
# is that there is no second way of doing this. Until 2026-08-23 the Pro 8X had
# only a lab builder: the mesh layer went in as =m and arrived by apk, while
# 4g/8g had been baked since the production split. Two variants of one product
# means every question gets asked twice and answered differently, and the two
# are not allowed to meet in one mesh anyway.
#
# So this file is the production builder with the Pro 8X hardware delta grafted
# in, and nothing else. Everything about WiFi, mesh, packages and the image
# model is whatever the production builder does - deliberately not re-decided
# here. What IS Pro 8X: the board registration, its DTS and U-Boot patches, the
# aeon PHY, its own install scripts and flash environment, and clearing the
# netmode variable the July workaround left in NAND.
#
# Not carried over from production, on purpose: the BPI-R4 LED overlay patches
# (470/471) and mtk-led-fix. Those program mt7530 gphy port LEDs on the classic
# board; the Pro 8X has its own DTS (patch 046) and a different switch, and
# letting two descriptions of the same pins meet is how a board stops booting.
# ============================================================================
EASYMESH_SHARED=/home/ipsec/easymesh-shared
. /home/ipsec/easymesh-shared/common-easymesh.sh

# Z ceho se stavi musi jit vyrobit znovu, a neulozenou praci ve sdilenem
# feedu by `git reset --hard` nize beze slova zahodil.
easymesh_require_clean_trees

# BUMP 2026-06-28 (HW overeno na obou routerech; predchozi: 7b8ce1e / 42c9ff = 6.12.93):
#   OpenWrt:  4d0fec5a4845ba166203a782d08217b3f1cf2af9  (openwrt-25.12 HEAD)
#   MTK SDK:  b7873eae800034c05f8f6257b55949d6464eb2e3  (github main HEAD)
OPENWRT_COMMIT=${OPENWRT_COMMIT:-4a5c6b90d21522d2663ce2718c973f9e845f2119}

rm -rf openwrt
rm -rf mtk-openwrt-feeds

# GitHub, ne git.openwrt.org - a je to zamerna volba, ne preklep.
#
# 2026-08-20 vratil git.openwrt.org 504 dvakrat behem hodiny a slozil dva buildy.
# Poprve na feedu luci (klon zustal rozdelany a builder jel dal jeste 60 radku,
# nez spadl uplne jinde - na kopirovani LuCI aplikaci do feeds/luci/applications,
# ktere neexistovalo), podruhe rovnou na openwrt.git. GitHub je oficialni zrcadlo,
# ma tytez commity (overeno tehoz dne: obe strany hlasily 4a5c6b90 jako hlavu
# openwrt-25.12) a jede i ve chvili, kdy .org nejede. MTK feed nize se odtud
# klonuje uz davno a nikdy to nezlobilo.
git clone --branch openwrt-25.12 https://github.com/openwrt/openwrt.git openwrt
cd openwrt; git checkout ${OPENWRT_COMMIT}; cd -;

# A totez pro feedy uvnitr stromu. Prvni z dnesnich dvou padu nebyl na openwrt.git,
# ale prave tady: feeds.conf.default miri z vyroby na git.openwrt.org, takze
# `scripts/feeds update -a` klonuje odtamtud - a kdyz to nejede, nejede build.
sed -i -e "s|https://git.openwrt.org/feed/|https://github.com/openwrt/|g" \
       -e "s|https://git.openwrt.org/project/|https://github.com/openwrt/|g" \
       openwrt/feeds.conf.default

# BUMP TEST 2026-06-23: tarball nahrazen cerstvym clone z MTK GitHub (vetev main = nase linie)
#tar xzf /home/ipsec/mtk-feeds-cache.tar.gz
git clone --branch main https://github.com/mediatek/mtk-openwrt-feeds mtk-openwrt-feeds
( cd mtk-openwrt-feeds && git checkout 4e825214deaafc5cdc5457d66a1a828449f07e69 )


\cp -r my_files/999-sfp-10-additional-quirks.patch mtk-openwrt-feeds/25.12/files/target/linux/mediatek/patches-6.12
\cp -r my_files/999-sfp-11-rtl8261be-mdio-none.patch mtk-openwrt-feeds/25.12/files/target/linux/mediatek/patches-6.12
\cp -r my_files/999-sfp-22-rtl8261be-boot-1g-reprobe.patch mtk-openwrt-feeds/25.12/files/target/linux/mediatek/patches-6.12
\cp -r my_files/999-eth-21-mtk-gdm-rx-fsm-reset.patch mtk-openwrt-feeds/25.12/files/target/linux/mediatek/patches-6.12
\cp -r my_files/999-pcs-10-lynxi-hold-link-down-on-invalid-speed.patch mtk-openwrt-feeds/25.12/files/target/linux/mediatek/patches-6.12
\cp -r my_files/999-ephy-zz-01-fix-aqr-mib-thread-lifetime.patch mtk-openwrt-feeds/25.12/files/target/linux/mediatek/patches-6.12
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

# ==========================================================================
# ---------- Pro-8X HARDWARE DELTA (jedine, cim se x8 lisi od 8g) -----------
# ==========================================================================

# platform.sh: registrovat bpi-r4-pro-8x (fail-closed count check)
python3 - <<'PLATFORM_EOF'
f = "target/linux/mediatek/filogic/base-files/lib/upgrade/platform.sh"
c = open(f).read()
p1 = "\tbananapi,bpi-r4-lite|\\\n\tbazis,ax3000wm"
p2 = "\tbananapi,bpi-r4-lite|\\\n\tcmcc,rax3000m"
assert c.count(p1) == 2 and c.count(p2) == 1, "platform.sh: UPSTREAM SE ZMENIL"
c = c.replace(p1, "\tbananapi,bpi-r4-lite|\\\n\tbananapi,bpi-r4-pro-8x|\\\n\tbazis,ax3000wm")
c = c.replace(p2, "\tbananapi,bpi-r4-lite|\\\n\tbananapi,bpi-r4-pro-8x|\\\n\tcmcc,rax3000m")
open(f, "w").write(c)
assert c.count("bananapi,bpi-r4-pro-8x") == 3
print("platform.sh: bpi-r4-pro-8x registrovan 3x - OK")
PLATFORM_EOF

# NVMe/uboot (sdílené s klasikem, ale board-level)
\cp -r ../my_files/453-w-add-bpi-r4-nvme-dtso.patch target/linux/mediatek/patches-6.12/
\cp -r ../my_files/455-w-add-bpi-r4-pro-nvme-dtso.patch target/linux/mediatek/patches-6.12/
\cp -r ../my_files/450-w-nand-mmc-add-bpi-r4.patch package/boot/uboot-mediatek/patches/450-add-bpi-r4.patch
\cp -r ../my_files/451-w-add-bpi-r4-nvme.patch package/boot/uboot-mediatek/patches/451-add-bpi-r4-nvme.patch
\cp ../my_files/452-w-add-bpi-r4-nvme-rfb.patch package/boot/uboot-mediatek/patches/452-add-bpi-r4-nvme-rfb.patch
\cp ../my_files/454-w-add-bpi-r4-nvme-env.patch package/boot/uboot-mediatek/patches/454-add-bpi-r4-nvme-env.patch

# Pro-8X specifické: odstranit superseded MTK feed patche, nasadit naše
rm -f target/linux/mediatek/patches-6.12/999-eth-06-mtk_eth_soc-support-ethernet-passive-mux.patch
rm -f target/linux/mediatek/patches-6.12/046-v6.19-arm64-dts-mediatek-mt7988a-bpi-r4-pro-add-dts.patch
\cp -r ../my_files/bpi-r4-pro/patches-kernel/* target/linux/mediatek/patches-6.12/
\cp ../my_files/bpi-r4-pro/patches-uboot/471-add-bpi-r4-pro-8x.patch package/boot/uboot-mediatek/patches/
\cp ../my_files/bpi-r4-pro/uboot-mediatek-Makefile package/boot/uboot-mediatek/Makefile
\cp ../my_files/bpi-r4-pro/arm-trusted-firmware-mediatek-Makefile package/boot/arm-trusted-firmware-mediatek/Makefile
\cp -r ../my_files/w-sd-nand-mmc-nvme-ddr4-filogic.mk target/linux/mediatek/image/filogic.mk
mv target/linux/mediatek/image/filogic-extra.mk target/linux/mediatek/image/filogic-extra.mk.disabled
\cp -r ../my_files/999-fitblk-02-w-add-bpi-r4-nvme-fitblk.patch target/linux/mediatek/patches-6.12

# kernel config + Pro-8X ethernet PHY (aeon_as21xxx)
echo "CONFIG_BLK_DEV_NVME=y" >> target/linux/mediatek/filogic/config-6.12
echo "CONFIG_TASK_IO_ACCOUNTING=y" >> target/linux/mediatek/filogic/config-6.12
python3 -c 'c=open("package/kernel/linux/modules/netdevices.mk").read(); open("package/kernel/linux/modules/netdevices.mk","w").write(c.replace("as21xxx.ko","aeon_as21xxx.ko").replace("AutoLoad,18,as21xxx)","AutoLoad,18,aeon_as21xxx)"))'
python3 -c 'c=open("target/linux/mediatek/filogic/config-6.12").read(); open("target/linux/mediatek/filogic/config-6.12","w").write(c.replace("CONFIG_AS21XXX_PHY=y","CONFIG_AS21XXX_PHY=m"))'

# --- image files/: hostname + SDÍLENÉ mld skripty + Pro-8X síť/identita ----
mkdir -p files/etc/uci-defaults
\cp -r ../my_files/99-set-hostname files/etc/uci-defaults/; chmod +x files/etc/uci-defaults/99-set-hostname

# easymesh_install_mld_scripts — ZÁMĚRNĚ NEVOLÁNO (universal to přestal volat 9. 8.)
#
# Kopírovalo mesh skripty do obrazu z my_files-easymesh/etc-files/. Tytéž
# soubory ale dodávají i balíčky easymesh-wifi a easymesh-mesh - a každá kopie
# se udržuje jinde. Změřeno 14. 8.: v obraze byly verze z 24. 7., v balíčcích
# z 12. 8., tři týdny rozdílu.
#
# A apk to nespraví: /usr/sbin přepíše, ale /etc/init.d bere jako konfiguraci
# a nechá starou verzi ležet, novou odloží jako .apk-new. Na čerstvě flashnutém
# x8 tak po instalaci běžely červencové init skripty a mesh-gwd z nich si
# rovnou vzal VIP mesh sítě.
#
# Bez tohohle volání nese obraz nulovou kopii a jediným zdrojem jsou balíčky.

\cp -r ../my_files/99-pro-8x-network files/etc/uci-defaults/; chmod +x files/etc/uci-defaults/99-pro-8x-network
# compat_version fix: pro-8x chybí v board.d/05_compat-version → device by trčel
# na 1.0 vs image 1.1 → keep-config navždy odmítnut. Zapíšeme 1.1 jako klasici.
\cp -r ../my_files/06-x8-compat-version files/etc/uci-defaults/; chmod +x files/etc/uci-defaults/06-x8-compat-version
# netmode/multiap_mode ven z U-Boot prostredi. Zije v NAND, takze prezije
# firstboot i kazdou reinstalaci eMMC - vyhodit ho z builderu spravi jen desky,
# ktere ho nikdy nemely. Viz X8-VADY-A-JAK-JE-OPRAVIT.md, vada 1.
\cp -r ../my_files/07-x8-clear-netmode files/etc/uci-defaults/; chmod +x files/etc/uci-defaults/07-x8-clear-netmode
# Stabilni MAC. Pro-8X ji nema - generuje se nahodne pri kazdem startu, br-lan
# si pak sahne po genericke WiFi MAC (shodne na vsech deskach) a AL-MAC se meni
# kazdy boot. Na controlleru to znamena novy uzel v DB po kazdem restartu a
# nestabilni identitu DHCP serveru. Viz X8-VADY-A-JAK-JE-OPRAVIT.md, vada 2.
\cp -r ../my_files/08-x8-stable-mac files/etc/uci-defaults/; chmod +x files/etc/uci-defaults/08-x8-stable-mac
# identita se NEpeče (žádný 999-x8-identity). Nasazuje se per-uzel přes
# node-config.sh po flashi — stejně jako klasici → jeden image → N x8 bez kolize.
# node-config.sh je board-aware (Pro-8X mgmt=mxl_lan0, AL-MAC z HW). x8 tím padá
# na keep-config workflow klasiků (po jednorázovém -F crossoveru 1.0→1.1).
mkdir -p files/root
\cp ../my_files/node-config.sh files/root/node-config.sh; chmod +x files/root/node-config.sh

# SD auto-expand + Pro-8X flash env + install skripty
mkdir -p files/lib/preinit files/etc files/root/install-dir files/usr/sbin
\cp ../my_files/etc-files/lib/preinit/19-expand-fit-rootfs files/lib/preinit/; chmod +x files/lib/preinit/19-expand-fit-rootfs
\cp ../my_files/fw_env_pro8x_snand.config files/etc/fw_env.config
for i in nand nvme emmc; do
	\cp "../my_files/bpi-r4-install/install-$i-pro8x.sh" "files/root/install-dir/install-$i.sh"
	chmod +x "files/root/install-dir/install-$i.sh"
done
\cp ../my_files/bpi-r4-install/boot-nvme files/usr/sbin/boot-nvme; chmod +x files/usr/sbin/boot-nvme
\cp ../my_files/bpi-r4-pro/files/usr/sbin/boot-nand files/usr/sbin/boot-nand; chmod +x files/usr/sbin/boot-nand

# ==========================================================================
# ---------- konec Pro-8X delty --------------------------------------------
# ==========================================================================


\cp -r ../my_files/453-w-add-bpi-r4-nvme-dtso.patch target/linux/mediatek/patches-6.12/
\cp -r ../my_files/450-w-nand-mmc-add-bpi-r4.patch package/boot/uboot-mediatek/patches/450-add-bpi-r4.patch
\cp -r ../my_files/451-w-add-bpi-r4-nvme.patch package/boot/uboot-mediatek/patches/451-add-bpi-r4-nvme.patch
\cp ../my_files/452-w-add-bpi-r4-nvme-rfb.patch package/boot/uboot-mediatek/patches/452-add-bpi-r4-nvme-rfb.patch
\cp ../my_files/454-w-add-bpi-r4-nvme-env.patch package/boot/uboot-mediatek/patches/454-add-bpi-r4-nvme-env.patch
# OPRAVA 23. 8.: byl tu universal .mk, ktery Pro-8X device VUBEC NEDEFINUJE.
# SMAZANO 23. 8.: tady se filogic.mk PREPISOVAL univerzalni verzi, ktera
# Pro-8X device vubec nedefinuje - a tim se shodila kopie ze radku 118.
# Nasledek: kconfig symbol z defconfigu tise zahodil, vybranych zarizeni
# byla NULA a build uspesne skoncil bez jedineho obrazu (23. 8.).
# Prisel sem i s LED blokem z universal builderu. Do x8 nepatri nic z toho.

### ethernet/board LED (BPI-R4 standard) - leds overlay + uboot LED + filogic device + PHY trigger
# VYPNUTO 23. 8.: tenhle sed pridava -leds overlay do seznamu, ale patch,
# ktery mt7988a-bananapi-bpi-r4-leds.dtso VYRABI (470/471), se do x8
# zamerne neprenasi (viz komentar nahore). Build pak spadl na
#   cc1: fatal error: ...-leds.dtso: No such file or directory
# Prenaset se musi obe pulky, nebo zadna.
#sed -i 's/mt7988a-bananapi-bpi-r4-nvme$/mt7988a-bananapi-bpi-r4-nvme mt7988a-bananapi-bpi-r4-leds/' target/linux/mediatek/image/filogic.mk
# VYPNUTO 23. 8.: patri k LED sade klasicke desky (mt7530 gphy port LEDs),
# ktera se do x8 zamerne neprenasi. Zustalo tu po pulce.
#echo "CONFIG_LED_TRIGGER_PHY=y" >> target/linux/mediatek/filogic/config-6.12

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

\cp ../my_files/etc-files/uci-defaults/97-docker-off files/etc/uci-defaults/
chmod +x files/etc/uci-defaults/97-docker-off

# Oznaceni modelu obrazu. Cte ho 92-easymesh-apk-feed z easymesh-config.
#
# Bez nej si uzel pri prvnim bootu sam nastavi laboratorni apk feed - a to je
# na zapecenem obrazu presne to, co se nesmi stat: jeden `apk upgrade` a vedle
# zapecene kopie stacku pribude laboratorni. Ktera z nich pak bezi, zalezi na
# tom, kdy se deska naposled flashla a kdy naposled upgradovala.
#
# Musi to zapect ten, kdo obraz sklada. Uzel sam nepozna balicek, se kterym se
# narodil, od toho, ktery mu nekdo doinstaloval o minutu pozdeji.
mkdir -p files/etc
echo production > files/etc/easymesh-model

# SD auto-expand: grow production + fitrw f2fs to fill the SD card on first boot (SD-only, guarded)
mkdir -p files/lib/preinit
\cp ../my_files/etc-files/lib/preinit/19-expand-fit-rootfs files/lib/preinit/
chmod +x files/lib/preinit/19-expand-fit-rootfs

# NVMe /data: mount the LABEL=data partition (NVMe installs only) at /data on first boot
\cp ../my_files/etc-files/uci-defaults/96-data-mount files/etc/uci-defaults/
chmod +x files/etc/uci-defaults/96-data-mount

# Instalacni skripty NEkopirovat: Pro-8X si sve (install-*-pro8x.sh) polozil uz
# v delte vyse, a tenhle blok bezi POZDEJI - klasicke verze by je prepsaly.
# Tise, a poznalo by se to az na krabici, ktera se odmitne nainstalovat na NVMe.
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

# Diagnosticke LuCI applety, ktere ve standardnich feedech NEJSOU (vezeme je).
#
# Bez nich se uzivatel na prehledu nedozvi, jak je na tom procesor a jake jsou
# teploty, a nema kde nastavit planovany restart. Jsou to prvni tri veci, na
# ktere se pta kazdy, kdo si takovy router postavi - overeno na Franciscovi,
# ktery si je do svych buildu pridaval sam (deploy-pro8x-customers,
# builder-pro-8x.sh:70-73). Prazdny obraz vyrobi nekonecne dotazy "a neslo by
# tam pridat...", takze levnejsi je mit je uvnitr.
#
# MUSI se zkopirovat PRED `scripts/feeds install`, jinak je feed neindexuje
# a `make defconfig` jejich CONFIG_PACKAGE_ radky TISE zahodi.
for _p in luci-app-autoreboot luci-app-cpu-status luci-app-temp-status; do
	\cp -r "../my_files/$_p" feeds/luci/applications/
	[ -d "feeds/luci/applications/$_p/root" ] && chmod -R 755 "feeds/luci/applications/$_p/root"
done

./scripts/feeds update -a
# Kontrola, ze se feedy opravdu naklonovaly.
#
# 20. 8. vratil git.openwrt.org 504 uprostred klonu feedu luci. `scripts/feeds
# update` selhal, builder jel dal jeste sedesat radku a spadl az na kopirovani
# LuCI aplikaci do feeds/luci/applications, ktere neexistovalo - tedy uplne
# jinde, nez byla pricina. Hledani zaboceni do hooku ftsnap_restore, ktery za
# to nemohl, stalo hodinu.
#
# Stejna pojistka jako u konfigurace nize: kontroluje se to, co doopravdy
# vzniklo, ne to, co jsme si prali.
for _f in packages luci routing; do
	[ -d "feeds/$_f" ] || {
		echo "CHYBA: feeds/$_f neexistuje - klon feedu selhal" >&2
		echo "       (2026-08-20 to byla 504 z git.openwrt.org; od te doby" >&2
		echo "        klonujeme z GitHubu, ale spadnout muze i ten)" >&2
		exit 1
	}
done
echo ">>> kontrola: feedy packages, luci, routing jsou naklonovane"

./scripts/feeds install -a
easymesh_setup_iopsys_feed
grep -q "src-link easymeshr6" feeds.conf.default || echo "src-link easymeshr6 /home/ipsec/easymesh-shared/easymesh-r6-feed" >> feeds.conf.default
./scripts/feeds update easymeshr6
./scripts/feeds install easymesh easymesh-config easymesh-mesh easymesh-wifi easymesh-api luci-app-easymesh easymesh-trace

\cp ../my_files/fit.sh package/utils/fitblk/files/fit.sh

### wifi-scripts: `config.wpa_psk = key` is a typo for `config.key`, and it
### costs an entire radio.
###
### The branch runs only when the passphrase is EXACTLY 64 characters long.
### ucode then throws "Reference error: access to undeclared variable key",
### the radio's whole configuration fails, and netifd gives up with
### retry_setup_failed. Whichever radios carry that credential simply never
### come up: measured 2026-08-19, a backhaul key from `openssl rand -hex 32`
### took 5 GHz and 6 GHz down together, so the fronthaul AP-MLD came up with
### one link out of three and the backhaul AP-MLD never appeared at all.
###
### It looks exactly like a driver fault and it is a one-word bug. Very likely
### the explanation for several "MLD has 0 of 3 links" days in this project.
###
### Guarded, not blind: if upstream fixes it the sed becomes a no-op and says
### so, and if the line changes shape the build stops rather than shipping an
### image where the fix silently did nothing.
_apuc=package/network/config/wifi-scripts/files-ucode/usr/share/ucode/wifi/ap.uc
if grep -q 'config\.wpa_psk = key;' "$_apuc"; then
	sed -i 's/config\.wpa_psk = key;/config.wpa_psk = config.key;/' "$_apuc"
	echo ">>> wifi-scripts: ap.uc opraveno (config.wpa_psk = key -> config.key)"
elif grep -q 'config\.wpa_psk = config\.key;' "$_apuc"; then
	echo ">>> wifi-scripts: ap.uc uz je spravne, nas zasah neni potreba"
else
	echo "CHYBA: ap.uc nema ani tu vadu ani opravu - upstream se zmenil" >&2
	echo "       zkontrolovat $_apuc kolem radku 140" >&2
	exit 1
fi

\cp -r ../my_files/qmi.sh package/network/utils/uqmi/files/lib/netifd/proto/
chmod -R 755 package/network/utils/uqmi/files/lib/netifd/proto
chmod -R 755 feeds/luci/applications/luci-app-modemdata/root
chmod -R 755 feeds/luci/applications/luci-app-sms-tool-js/root
chmod -R 755 feeds/packages/utils/modemdata/files/usr/share

# OPRAVA 23. 8.: `my_defconfig-8x-full` je DELTA PRO DESKU, ne produkcni sada.
# Sam o sobe dal obraz se 449 balicky a 6 luci-app - chybel adblock, ddns,
# upnp, nlbwmon, wireguard, exfat, ntfs3, collectd, strongswan... (Petr, 23. 8.)
# Ty dva defconfigy nejsou nadmnozina jeden druheho: 8x ma 73 balicku navic
# (i2c-tools, gpiod-tools, aeonsemi PHY), univerzal 67 jinych. Potreba OBOJI.
# Poradi je zamerne - kconfig pocita POSLEDNI vyskyt, takze delta desky vyhrava.
_BASE=/home/ipsec/universal-new/configs/my_defconfig-production-universal
[ -f "$_BASE" ] || { echo "CHYBA: chybi produkcni defconfig $_BASE" >&2; exit 1; }
\cp "$_BASE" .config                          # produkcni sada balicku (zaklad)
cat ../configs/my_defconfig-8x-full >> .config  # Pro-8X delta (device + HW balicky)
make defconfig
easymesh_apply_defconfig

# PRODUCTION IMAGE: the mesh IS baked in (2026-08-16).
#
# This is the opposite decision to the lab builder, and it is deliberate.
#
# The lab image ships nothing and installs the whole stack from the apk feed,
# so a node is exactly what its package list says it is. That is what makes
# measurements between boards comparable, and it is why the mesh was taken out
# of the lab image on 2026-08-09.
#
# A user has no feed and no reason to run apk. For them the image has to work
# the moment it boots, so here everything is =y and the upgrade path is
# sysupgrade, not apk.
#
# The two models must not be mixed. Baking the stack in AND installing it from
# apk on top is exactly what made no two boards in the lab alike: which copy a
# node actually ran depended on when it was last flashed and last upgraded.
#
# easymesh_apply_defconfig above already set the iopsys stack to =y. These
# lines add our own packages, which that shared helper does not know about.
cat >> .config <<'BAKE_EOF'
# Not a package: 1905 frames must carry the AL-MAC as source address.
# easymesh_apply_defconfig does NOT set this one.
CONFIG_IEEE1905_CMDU_SA_IS_ALMAC=y
# Ty dva zijí v produkčním DEVICE defconfigu (my_defconfig-production-universal),
# který tenhle builder nepoužívá - má vlastní, Pro-8X. Patří sem, ne tam: pak je
# jedno, s jakým device defconfigem se builder spustí, a pojistka níž je najde.
# Bez nich spadla první produkční stavba x8 (2026-08-23) přesně na té pojistce.
CONFIG_PACKAGE_conntrack=y
CONFIG_PACKAGE_ieee1905-topology-plugin=y
CONFIG_PACKAGE_easymesh=y
CONFIG_PACKAGE_easymesh-api=y
CONFIG_PACKAGE_easymesh-config=y
CONFIG_PACKAGE_easymesh-mesh=y
CONFIG_PACKAGE_easymesh-wifi=y
# Measurement scaffolding, deliberately baked in for now.
#
# The hooks live inside other packages' scripts, so they cannot be added after
# a flash without missing the one boot that matters - the first one. Built in,
# a factory-fresh box records its own onboarding from its own first second,
# which is how the OpenWrt-MLD fallback was found on 2026-08-19 and how the
# next one will be.
#
# It is off by default in cost terms: /etc/easymesh-trace.conf ships with
# ET_ENABLE=1 for the lab, and a single word turns it into a few milliseconds
# per script. Take this line out before an image goes to anyone who is not us.
CONFIG_PACKAGE_easymesh-trace=y
CONFIG_PACKAGE_luci-app-easymesh=y
CONFIG_PACKAGE_kmod-mdio-netlink=y
CONFIG_PACKAGE_mdio-tools=y
CONFIG_PACKAGE_luci-app-wifimgr=y
BAKE_EOF

# PRIDANO 23. 8.: zavislosti se musi dopocitat i pro to, co pribylo AZ TEDY.
# Bez tohohle se balicek do .config jen PRIPISE, jeho zavislosti nikdo nedoplni
# a build spadne az v package/compile. Presne tak nas 23. 8. slozil conntrack:
#   Package conntrack is missing dependencies: libnetfilter_conntrack.so.3
# Kontroly niz pak testuji stav PO dopocitani, ne nase prani.
make defconfig


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
           hostapd-utils wpa-cli \
           easymesh easymesh-api easymesh-config easymesh-mesh easymesh-wifi \
           easymesh-trace \
           luci-app-easymesh \
           conntrack ieee1905-topology-plugin; do
	_v=$(grep -E "^(# )?CONFIG_PACKAGE_${_s}[= ]" .config | tail -1)
	case "$_v" in
		*"=y") ;;
		*) echo "CHYBA: CONFIG_PACKAGE_${_s} neni =y (je: ${_v:-CHYBI})" >&2
		   echo "       produkcni obraz by mesh vrstvu NEobsahoval" >&2
		   exit 1 ;;
	esac
done
echo ">>> kontrola: mesh vrstva je =y, zapece se do obrazu"
# conntrack je v te smycce zamerne: mesh-gwd ho vola, kdyz se prestehuje brana,
# aby klientum strhl toky postavene pro starou cestu. Bez nej to jen poctive
# zapise do logu, ze nema cim, a klient si 30-90 s pocka, nez mu vyprsi samy
# (zmereno 2026-08-20, oba smery). Overeno, ze se dnes prelozi: conntrack-1.4.8.

# ieee1905-topology-plugin je v te smycce taky. Bez nej se do /usr/lib/ieee1905
# neprelozi topology.so, ieee1905d mlcky nacte jen map.so - a nikdo se nikdy
# nezepta na jmeno, vyrobce, model ani IP uzlu, takze obrazek topologie umi
# ukazat jen MAC adresy. Config si ho pritom uz dnes zada (extmodule map
# topology), jen ta binarka chybela. Overeno na zeleze 2026-08-20: po nacteni
# vraci ubus call ieee1905.topology dump jmeno, vyrobce, model i ipv4 kazdeho uzlu.

# mwan3 se do obrazu nesmi vratit (Petr, 17. 8. 2026).
#
# Deleji s nim problemy strongswan a dalsi balicky. Vyskrtnout ho z defconfigu
# ale NESTACI: zpatky ho pritahne kterakoli zavislost, a jedna existuje -
# prometheus-node-exporter-lua-mwan3 ho ma v DEPENDS. Proto se kontroluje az to,
# co z make defconfig doopravdy vyleze, ne to, co jsme si prali.
for _s in mwan3 luci-app-mwan3; do
	_v=$(grep -E "^(# )?CONFIG_PACKAGE_${_s}[= ]" .config | tail -1)
	case "$_v" in
		*"=y") echo "CHYBA: CONFIG_PACKAGE_${_s} je =y - neco si mwan3 pritahlo zpet" >&2
		       exit 1 ;;
	esac
done
echo ">>> kontrola: mwan3 v obrazu neni"

# Doplnky pro uzivatele se nesmi ztratit tise.
#
# `make defconfig` zahodi kazdy CONFIG_PACKAGE_ radek, na ktery nenajde
# balicek nebo jehoz zavislost neni splnena - a NEREKNE o tom ani slovo.
# Presne tak by se stalo, ze obraz zase neprecte exFAT disk a nikdo by
# nevedel proc. Nezastavuje to build, jen to rekne nahlas.
# ppp/pppoe v tom seznamu nejsou doplnek, ale pojistka: v defconfigu se
# neuvadeji, pritahne je profil cile - takze je nikdo nehlida, a pritom je
# PPPoE u nas nejbeznejsi zpusob pripojeni. Kdyby vypadly, poznal by to az
# uzivatel, kteremu nenabehne internet.
_chybi=""
for _s in kmod-fs-exfat kmod-fs-ntfs3 ddns-scripts luci-app-ddns \
          miniupnpd-nftables luci-app-upnp nlbwmon luci-app-nlbwmon \
          luci-app-wol adblock luci-app-adblock luci-proto-wireguard \
          luci-app-autoreboot luci-app-cpu-status luci-app-temp-status \
          kmod-macvlan kmod-usb-storage-uas kmod-usb-net-ipheth usbmuxd \
          hd-idle luci-app-hd-idle \
          kmod-usb-printer p910nd luci-app-p910nd minidlna luci-app-minidlna \
          tailscale zerotier kmod-vxlan kmod-bonding \
          ppp ppp-mod-pppoe kmod-pppoe; do
	_v=$(grep -E "^(# )?CONFIG_PACKAGE_${_s}[= ]" .config | tail -1)
	case "$_v" in
		*"=y") ;;
		*) _chybi="$_chybi $_s" ;;
	esac
done
if [ -n "$_chybi" ]; then
	echo "" >&2
	echo "!!! POZOR: tyhle doplnky se do obrazu NEDOSTALY:$_chybi" >&2
	echo "    (chybejici balicek ve feedu nebo nesplnena zavislost)" >&2
	echo "" >&2
else
	echo ">>> kontrola: vsechny uzivatelske doplnky jsou v obrazu"
fi


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

# PRIDANO 23. 8.: posledni dopocitani zavislosti - tyhle tri radky lezi az
# ZA kontrolnim blokem, takze na ne prvni `make defconfig` nedosahl.
make defconfig

# POJISTKA 23. 8.: build bez vybraneho zarizeni skonci HLASENIM O USPECHU
# a nevyrobi jediny obraz. Stalo se: filogic.mk se prepsal universal verzi,
# Pro-8X device zmizel, kconfig symbol z defconfigu TISE zahodil a autobuild
# rekl "OpenWrt built successfully". Radsi spadnout tady nez za hodinu naprazdno.
_dev=$(grep -c "^CONFIG_TARGET_DEVICE_.*=y" .config)
if [ "$_dev" -eq 0 ]; then
	echo "CHYBA: zadne zarizeni neni vybrane - build by nevyrobil jediny obraz." >&2
	echo "       Zkontroluj, ze filogic.mk definuje bananapi_bpi-r4-pro-8x." >&2
	exit 1
fi
echo ">>> kontrola: vybranych zarizeni: $_dev"

### OpenWrt SDK (per-target = covers all variants incl. Pro 8X) - published as release-sdk
#echo "CONFIG_SDK=y" >> .config

bash ../mtk-openwrt-feeds/autobuild/unified/autobuild.sh filogic-mac80211-mt798x_rfb-wifi7_nic build


cp /home/ipsec/x8-new/openwrt/bin/targets/mediatek/filogic/openwrt-mediatek-filogic-bananapi_bpi-r4-pro-8x-squashfs-sysupgrade.itb /home/ipsec/latest-sysupgrade-x8.itb 2>/dev/null || true

# Tenhle adresar sdili obe varianty a kazdy build zacina `rm -rf openwrt`,
# takze za chvili tu po tomhle vysledku nezbude nic. Odlozit vystup i recept.
easymesh_archive_build production-x8 /home/ipsec/x8-new
