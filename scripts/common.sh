# Build steps shared by both boards, sourced by build.sh.
# $REPO is the repository root; the steps after fetch_sources and
# add_kernel_patches run inside $REPO/openwrt.

# Read pins.conf; a value already in the environment wins.
load_pins() {
	local key value
	while IFS='=' read -r key value; do
		case $key in ''|\#*) continue ;; esac
		[ -n "${!key:-}" ] || export "$key=$value"
	done < "$1"
}

fetch_source() {
	local dir=$1 url=$2 branch=$3 commit=$4 clean_exclude=${5:-}
	local -a clean_args=(-dffx)
	if [ -n "$clean_exclude" ]; then
		clean_args+=(-e "$clean_exclude")
	fi

	if [ ! -d "$dir/.git" ]; then
		rm -rf "$dir"
		git clone --single-branch --branch "$branch" "$url" "$dir"
	else
		git -C "$dir" reset --hard HEAD
		git -C "$dir" clean "${clean_args[@]}"
		# Fetch if the pinned commit is missing locally.
		git -C "$dir" cat-file -e "$commit^{commit}" 2>/dev/null || git -C "$dir" fetch origin "$branch"
	fi
	git -C "$dir" checkout "$commit"
}

fetch_sources() {
	# Keep downloaded sources; remove nested feed repositories and all build state.
	fetch_source openwrt https://github.com/openwrt/openwrt.git openwrt-25.12 "$OPENWRT_COMMIT" /dl
	fetch_source mtk-openwrt-feeds https://github.com/mediatek/mtk-openwrt-feeds main "$MTK_COMMIT"
}

# Kernel patches for both boards go into the MTK feed, so the autobuild
# prepare step puts them next to MediaTek's own.
add_kernel_patches() {
	\cp "$REPO"/common/patches/kernel/*.patch \
		mtk-openwrt-feeds/25.12/files/target/linux/mediatek/patches-6.12/

	# MTK feed 8074fe5b (2026-11-03) replaces the Aeonsemi AS21xxx driver with
	# v2.5.3 (as2xxxx.c). On the BPI-R4 Pro 8X the Combo LAN port (Aeonsemi PHY
	# behind MxL862xx port 5, mxl_lan5) then gets a 1G copper link but passes no
	# frames from the link partner (rx_packets stays 0, in and out of the bridge);
	# the previous driver passes them. Keep the previous driver: drop the update
	# patch. The firmware (as21x1x_fw.bin, now in package as2xxxx-firmware) and
	# CONFIG_AS21XXX_PHY are unchanged, so nothing else has to follow.
	rm -f mtk-openwrt-feeds/25.12/files/target/linux/mediatek/patches-6.12/999-ephy-as21xxx-02-update-driver-to-v2.5.3.patch
}

# Since MTK feed c21f3b36 mt76/mac80211/hostapd come from
# github.com/mediatek/softmac_* and the feed has no patch directories for
# them any more. Pin the sources, then add our patches straight into the
# packages. Each board lists the patches it takes in WIFI_PATCHES.
add_wifi_patches() {
	local p dir

	sh "$REPO/common/softmac-pin.sh"
	mkdir -p package/kernel/mt76/patches package/kernel/mac80211/patches/subsys \
		package/network/services/hostapd/patches
	for p in $WIFI_PATCHES; do
		case $p in
		mt76/*)     dir=package/kernel/mt76/patches ;;
		mac80211/*) dir=package/kernel/mac80211/patches/subsys ;;
		hostapd/*)  dir=package/network/services/hostapd/patches ;;
		esac
		\cp "$REPO/common/patches/wifi/$p" "$dir/"
	done
}

# Patches both boards take from common/patches: the U-Boot NVMe/NAND/MMC
# support and the NVMe DT overlay and fitblk boot.
add_common_tree_patches() {
	\cp "$REPO"/common/patches/uboot/*.patch package/boot/uboot-mediatek/patches/
	\cp "$REPO"/common/patches/target/*.patch target/linux/mediatek/patches-6.12/
}

add_packages() {
	\cp -r "$REPO/common/packages/sms-tool/" feeds/packages/utils/sms-tool
	\cp -r "$REPO/common/packages/modemdata-main/" feeds/packages/utils/modemdata
	\cp -r "$REPO/common/packages/luci-app-modemdata-main/luci-app-modemdata/" feeds/luci/applications
	\cp -r "$REPO/common/packages/luci-app-lite-watchdog/" feeds/luci/applications
	\cp -r "$REPO/common/packages/luci-app-sms-tool-js-main/luci-app-sms-tool-js/" feeds/luci/applications
}

# Files baked into the image: common/files, then the board's files on top.
add_files() {
	mkdir -p files
	\cp -R "$REPO/common/files/." files/
	\cp -R "$REPO/boards/$BOARD/files/." files/
}

add_after_feeds() {
	# Boards without their own fit.sh (BPI-R4 Lite) keep the upstream one.
	if [ -f "$REPO/boards/$BOARD/fit.sh" ]; then
		\cp "$REPO/boards/$BOARD/fit.sh" package/utils/fitblk/files/fit.sh
	fi

	\cp -r "$REPO/common/qmi.sh" package/network/utils/uqmi/files/lib/netifd/proto/
	chmod -R 755 package/network/utils/uqmi/files/lib/netifd/proto
	chmod -R 755 feeds/luci/applications/luci-app-modemdata/root
	chmod -R 755 feeds/luci/applications/luci-app-sms-tool-js/root
	chmod -R 755 feeds/packages/utils/modemdata/files/usr/share
}

add_config() {
	echo "CONFIG_PACKAGE_trusted-firmware-a-mt7988-emmc-comb-4bg=y" >> .config
	echo "CONFIG_PACKAGE_trusted-firmware-a-mt7988-sdmmc-comb-4bg=y" >> .config
	echo "CONFIG_PACKAGE_trusted-firmware-a-mt7988-spim-nand-ubi-comb-4bg=y" >> .config
}
