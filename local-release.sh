#!/bin/bash
# Local port of the workflow's "Prepare release artifacts" step
# (.github/workflows/build-bpi-r4-deploy.yml). Run after ./local-build.sh.
#
#   ./local-release.sh [standard|wired|pro|pro-wired]    (default: standard)
#
# Produces the same rel-* directories the workflow attaches to releases,
# under local-build/<variant>/release/.
set -euo pipefail

VARIANT="${1:-standard}"
REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
WORK_DIR="${REPO_DIR}/local-build/${VARIANT}"
FILOGIC="${WORK_DIR}/openwrt/bin/targets/mediatek/filogic"
OUT="${WORK_DIR}/release"

[ -d "$FILOGIC" ] || { echo "No build output at $FILOGIC — run ./local-build.sh $VARIANT first" >&2; exit 1; }
rm -rf "$OUT"
mkdir -p "$OUT"
cd "$OUT"

# Args: dir, itb_src, itb_dst, nvme, sdcard, emmc, snand [, recovery_itb]
# (same as the workflow; recovery_itb is copied only when the build produced it)
make_release_dir() {
  local DIR="$1" ITB_SRC="$2" ITB_DST="$3" NVME="$4" SDCARD="$5" EMMC="$6" SNAND="$7"
  local RECOVERY="${8:-}"

  mkdir -p "$DIR"
  cp "${FILOGIC}/${ITB_SRC}"   "${DIR}/${ITB_DST}"
  cp "${FILOGIC}/${NVME}"      "${DIR}/${NVME}"
  cp "${FILOGIC}/${SDCARD}"    "${DIR}/${SDCARD}"
  cp "${FILOGIC}/${EMMC}"      "${DIR}/${EMMC}"
  cp "${FILOGIC}/${SNAND}"     "${DIR}/${SNAND}"
  if [ -n "$RECOVERY" ] && [ -f "${FILOGIC}/${RECOVERY}" ]; then
    cp "${FILOGIC}/${RECOVERY}" "${DIR}/${RECOVERY}"
  else
    RECOVERY=""
  fi
  cp "${FILOGIC}/config.buildinfo" "${DIR}/"
  ( cd "$DIR" && sha256sum "${ITB_DST}" "${NVME}" "${SDCARD}" "${EMMC}" "${SNAND}" ${RECOVERY} > sha256sums )
}

if [ "$VARIANT" != "pro" ] && [ "$VARIANT" != "pro-wired" ]; then
  make_release_dir rel-4gb \
    "openwrt-mediatek-filogic-bananapi_bpi-r4-squashfs-sysupgrade.itb" \
    "bpi-r4.itb" \
    "openwrt-mediatek-filogic-bananapi_bpi-r4-nvme-img.bin" \
    "openwrt-mediatek-filogic-bananapi_bpi-r4-sdcard.img.gz" \
    "openwrt-mediatek-filogic-bananapi_bpi-r4-emmc-img.bin" \
    "openwrt-mediatek-filogic-bananapi_bpi-r4-nand-snand-img.bin" \
    "openwrt-mediatek-filogic-bananapi_bpi-r4-initramfs-recovery.itb"

  make_release_dir rel-4gb-poe \
    "openwrt-mediatek-filogic-bananapi_bpi-r4-poe-squashfs-sysupgrade.itb" \
    "bpi-r4-poe.itb" \
    "openwrt-mediatek-filogic-bananapi_bpi-r4-poe-nvme-img.bin" \
    "openwrt-mediatek-filogic-bananapi_bpi-r4-poe-sdcard.img.gz" \
    "openwrt-mediatek-filogic-bananapi_bpi-r4-poe-emmc-img.bin" \
    "openwrt-mediatek-filogic-bananapi_bpi-r4-nand-snand-img.bin" \
    "openwrt-mediatek-filogic-bananapi_bpi-r4-poe-initramfs-recovery.itb"

  make_release_dir rel-8gb \
    "openwrt-mediatek-filogic-bananapi_bpi-r4-8gb-squashfs-sysupgrade.itb" \
    "bpi-r4.itb" \
    "openwrt-mediatek-filogic-bananapi_bpi-r4-8gb-nvme-img.bin" \
    "openwrt-mediatek-filogic-bananapi_bpi-r4-8gb-sdcard.img.gz" \
    "openwrt-mediatek-filogic-bananapi_bpi-r4-8gb-emmc-img.bin" \
    "openwrt-mediatek-filogic-bananapi_bpi-r4-nand-8gb-snand-img.bin" \
    "openwrt-mediatek-filogic-bananapi_bpi-r4-8gb-initramfs-recovery.itb"

  make_release_dir rel-8gb-poe \
    "openwrt-mediatek-filogic-bananapi_bpi-r4-poe-8gb-squashfs-sysupgrade.itb" \
    "bpi-r4-poe.itb" \
    "openwrt-mediatek-filogic-bananapi_bpi-r4-poe-8gb-nvme-img.bin" \
    "openwrt-mediatek-filogic-bananapi_bpi-r4-poe-8gb-sdcard.img.gz" \
    "openwrt-mediatek-filogic-bananapi_bpi-r4-poe-8gb-emmc-img.bin" \
    "openwrt-mediatek-filogic-bananapi_bpi-r4-nand-8gb-snand-img.bin" \
    "openwrt-mediatek-filogic-bananapi_bpi-r4-poe-8gb-initramfs-recovery.itb"
fi

if [ "$VARIANT" = "pro" ] || [ "$VARIANT" = "pro-wired" ]; then
  make_release_dir rel-pro \
    "openwrt-mediatek-filogic-bananapi_bpi-r4-pro-8x-squashfs-sysupgrade.itb" \
    "bpi-r4-pro-8x.itb" \
    "openwrt-mediatek-filogic-bananapi_bpi-r4-pro-8x-nvme-img.bin" \
    "openwrt-mediatek-filogic-bananapi_bpi-r4-pro-8x-sdcard.img.gz" \
    "openwrt-mediatek-filogic-bananapi_bpi-r4-pro-8x-emmc-img.bin" \
    "openwrt-mediatek-filogic-bananapi_bpi-r4-pro-8x-snand-img.bin"
  cp "${REPO_DIR}/rescue/bpi-r4-pro-rescue-sdcard.img.gz" rel-pro/ 2>/dev/null || true
  cp "${REPO_DIR}/rescue/bpi-r4-pro-snand-img.bin"        rel-pro/ 2>/dev/null || true
fi

# SD rescue image into all R4 release dirs
for DIR in rel-4gb rel-4gb-poe rel-8gb rel-8gb-poe; do
  [ -d "$DIR" ] && cp "${REPO_DIR}/rescue/bpi-r4-rescue-sdcard.img.gz" "$DIR/"
done

# UniFi variants = same firmware as 8gb wired + UniFi scripts
if [ "$VARIANT" = "wired" ]; then
  cp -r rel-4gb     rel-4gb-wired
  cp -r rel-4gb-poe rel-4gb-poe-wired
  cp -r rel-8gb     rel-8gb-wired
  cp -r rel-8gb-poe rel-8gb-poe-wired

  cp -r rel-8gb     rel-8gb-unifi
  cp -r rel-8gb-poe rel-8gb-poe-unifi

  for DIR in rel-8gb-unifi rel-8gb-poe-unifi; do
    cp "${REPO_DIR}/unifi/unifi-setup.sh"             "$DIR/"
    cp "${REPO_DIR}/unifi/rc.local"                   "$DIR/"
    cp "${REPO_DIR}/unifi/rc-network.sh"              "$DIR/"
    cp "${REPO_DIR}/unifi/unifi-network-setup-8gb.sh" "$DIR/unifi-network-setup.sh"
  done
fi

if [ "$VARIANT" = "pro-wired" ]; then
  cp -r rel-pro rel-pro-wired
  cp -r rel-pro rel-pro-unifi
  for DIR in rel-pro-unifi; do
    cp "${REPO_DIR}/unifi/unifi-setup.sh"             "$DIR/"
    cp "${REPO_DIR}/unifi/rc.local"                   "$DIR/"
    cp "${REPO_DIR}/unifi/rc-network.sh"              "$DIR/"
    cp "${REPO_DIR}/unifi/unifi-network-setup-8gb.sh" "$DIR/unifi-network-setup.sh"
  done
fi

echo "Release directories in $OUT:"
ls -d "$OUT"/rel-*
