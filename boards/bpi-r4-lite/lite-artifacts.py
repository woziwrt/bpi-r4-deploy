"""Give the bananapi_bpi-r4-lite device in filogic.mk its image artifacts back.

MTK patches-base 1132 drops the ARTIFACTS of the upstream OpenWrt device, so
the build would make only sysupgrade.itb. This adds the upstream SD card,
eMMC, SPI-NAND and NOR artifacts after the sysupgrade.itb line, without the
initramfs-recovery stage in the SD image (it does not fit the 12M-44M slot).
Does nothing if the device already has ARTIFACTS.

usage: lite-artifacts.py <filogic.mk>
"""
import sys

ARTIFACTS = r"""  ARTIFACTS := \
	       emmc-preloader.bin emmc-bl31-uboot.fip \
	       nor-preloader.bin nor-bl31-uboot.fip \
	       sdcard.img.gz \
	       snand-preloader.bin snand-bl31-uboot.fip
  ARTIFACT/emmc-preloader.bin	:= mt7987-bl2 emmc-comb
  ARTIFACT/emmc-bl31-uboot.fip	:= mt7987-bl31-uboot bananapi_bpi-r4-lite-emmc
  ARTIFACT/nor-preloader.bin	:= mt7987-bl2 nor-comb
  ARTIFACT/nor-bl31-uboot.fip	:= mt7987-bl31-uboot bananapi_bpi-r4-lite-nor
  ARTIFACT/snand-preloader.bin	:= mt7987-bl2 spim-nand2-ubi-comb
  ARTIFACT/snand-bl31-uboot.fip	:= mt7987-bl31-uboot bananapi_bpi-r4-lite-snand
  ARTIFACT/sdcard.img.gz	:= mt798x-gpt sdmmc |\
				   pad-to 17k | mt7987-bl2 sdmmc-comb |\
				   pad-to 6656k | mt7987-bl31-uboot bananapi_bpi-r4-lite-sdmmc |\
				   pad-to 44M | mt7987-bl2 spim-nand2-ubi-comb |\
				   pad-to 45M | mt7987-bl31-uboot bananapi_bpi-r4-lite-snand |\
				   pad-to 49M | mt7987-bl2 nor-comb |\
				   pad-to 50M | mt7987-bl31-uboot bananapi_bpi-r4-lite-nor |\
				   pad-to 51M | mt7987-bl2 emmc-comb |\
				   pad-to 52M | mt7987-bl31-uboot bananapi_bpi-r4-lite-emmc |\
				   pad-to 56M | mt798x-gpt emmc |\
				$(if $(CONFIG_TARGET_ROOTFS_SQUASHFS),\
				   pad-to 64M | append-image squashfs-sysupgrade.itb | check-size |\
				) \
				  gzip
"""

ANCHOR = ("  IMAGE/sysupgrade.itb := append-kernel | fit gzip "
          "$$(KDIR)/image-$$(firstword $$(DEVICE_DTS)).dtb "
          "external-with-rootfs | pad-rootfs | append-metadata\n")

path = sys.argv[1]
mk = open(path).read()
start = mk.index("define Device/bananapi_bpi-r4-lite\n")
end = mk.index("\nendef\n", start)
block = mk[start:end]
if "ARTIFACTS" in block:
    sys.exit(0)
if ANCHOR not in block:
    sys.exit("lite-artifacts.py: sysupgrade.itb line of bananapi_bpi-r4-lite not found in " + path)
block = block.replace(ANCHOR, ANCHOR + ARTIFACTS, 1)
open(path, "w").write(mk[:start] + block + mk[end:])
