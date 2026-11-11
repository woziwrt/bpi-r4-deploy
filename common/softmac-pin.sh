#!/bin/sh
# Run from the openwrt directory, after the MTK autobuild prepare step.
#
# Since MTK feed c21f3b36 (2026-10-22) mt76, mac80211, hostapd, iw and
# wifi-scripts are fetched from github.com/mediatek/softmac_* at the branch
# mp4.3-6.12, with no source hash. A branch moves, so two builds a day apart would get different drivers.
# Pin each package to a commit, and put the commit into PKG_VERSION as well:
# the source tarball in dl/ is named after PKG_VERSION, so a tarball of an older
# commit is never reused, and the version on the router shows the commit.
: "${SOFTMAC_MT76:?set in pins.conf}"
: "${SOFTMAC_MAC80211:?set in pins.conf}"
: "${SOFTMAC_HOSTAPD:?set in pins.conf}"
: "${SOFTMAC_IW:?set in pins.conf}"
: "${SOFTMAC_WIFI_SCRIPTS:?set in pins.conf}"

softmac_pin() {
	mk=$1/Makefile
	sed -i -e "s/^PKG_SOURCE_VERSION:=mp4\.3-6\.12$/PKG_SOURCE_VERSION:=$2/" \
	       -e "s/^PKG_VERSION:=4\.3\.6\.12$/PKG_VERSION:=4.3.6.12~$(echo "$2" | cut -c1-8)/" "$mk"
	if ! grep -q "^PKG_SOURCE_VERSION:=$2$" "$mk"; then
		echo "softmac-pin: $mk has no mp4.3-6.12 source to pin" >&2
		exit 1
	fi
	# The tarball has no hash, so its name in dl/ is the only thing that keeps an
	# older commit from being reused: the commit must be in PKG_VERSION too.
	if ! grep -q "^PKG_VERSION:=4\.3\.6\.12~$(echo "$2" | cut -c1-8)$" "$mk"; then
		echo "softmac-pin: $mk has no PKG_VERSION 4.3.6.12 to tag with the commit" >&2
		exit 1
	fi
}

softmac_pin package/kernel/mt76 "$SOFTMAC_MT76"
softmac_pin package/kernel/mac80211 "$SOFTMAC_MAC80211"
softmac_pin package/network/services/hostapd "$SOFTMAC_HOSTAPD"
softmac_pin package/network/utils/iw "$SOFTMAC_IW"
softmac_pin package/network/config/wifi-scripts "$SOFTMAC_WIFI_SCRIPTS"
