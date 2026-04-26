DTS_DIR := $(DTS_DIR)/mediatek
DEVICE_VARS += SUPPORTED_TELTONIKA_DEVICES
DEVICE_VARS += SUPPORTED_TELTONIKA_HW_MODS

define Image/Prepare
	# For UBI we want only one extra block
	rm -f $(KDIR)/ubi_mark
	echo -ne '\xde\xad\xc0\xde' > $(KDIR)/ubi_mark
	$(if $(CONFIG_MTK_FW_ENC),$(call Image/fw-enc-key-derive))
	$(if $(CONFIG_MTK_ANTI_ROLLBACK),$(call Image/gen-fw-ar-ver))
endef

define Build/fit-with-netgear-top-level-rootfs-node
	$(call Build/fit-its,$(1))
	$(TOPDIR)/scripts/gen_netgear_rootfs_node.sh $(KERNEL_BUILD_DIR)/root.squashfs$(if $(TARGET_PER_DEVICE_ROOTFS),+pkg=$(ROOTFS_ID/$(DEVICE_NAME))) > $@.rootfs
	awk '/configurations/ { system("cat $@.rootfs") } 1' $@.its > $@.its.tmp
	@mv -f $@.its.tmp $@.its
	@rm -f $@.rootfs
	$(call Build/fit-image,$(1))
endef

define Build/mt7981-bl2
	cat $(STAGING_DIR_IMAGE)/mt7981-$1-bl2.img >> $@
endef

define Build/mt7981-bl31-uboot
	cat $(STAGING_DIR_IMAGE)/mt7981_$1-u-boot.fip >> $@
endef

define Build/mt7986-bl2
	cat $(STAGING_DIR_IMAGE)/mt7986-$1-bl2.img >> $@
endef

define Build/mt7986-bl31-uboot
	cat $(STAGING_DIR_IMAGE)/mt7986_$1-u-boot.fip >> $@
endef

define Build/mt7987-bl2
	cat $(STAGING_DIR_IMAGE)/mt7987-$1-bl2.img >> $@
endef

define Build/mt7987-bl31-uboot
	cat $(STAGING_DIR_IMAGE)/mt7987_$1-u-boot.fip >> $@
endef

define Build/mt7988-bl2
	cat $(STAGING_DIR_IMAGE)/mt7988-$1-bl2.img >> $@
endef

define Build/mt7988-bl31-uboot
	cat $(STAGING_DIR_IMAGE)/mt7988_$1-u-boot.fip >> $@
endef

define Build/simplefit
	cp $@ $@.tmp 2>/dev/null || true
	ptgen -g -o $@.tmp -a 1 -l 1024 \
	-t 0x2e -N FIT		-p $(CONFIG_TARGET_ROOTFS_PARTSIZE)M@17k
	cat $@.tmp >> $@
	rm $@.tmp
endef

define Build/mt798x-gpt
	cp $@ $@.tmp 2>/dev/null || true
	ptgen -g -o $@.tmp -a 1 -l 1024 \
		$(if $(findstring sdmmc,$1), \
			-H \
			-t 0x83	-N bl2		-r	-p 4079k@17k \
		) \
			-t 0x83	-N ubootenv	-r	-p 512k@4M \
			-t 0x83	-N factory	-r	-p 2M@4608k \
			-t 0xef	-N fip		-r	-p 4M@6656k \
				-N recovery	-r	-p 32M@12M \
		$(if $(findstring sdmmc,$1), \
				-N install	-r	-p 20M@44M \
			-t 0x2e -N production		-p $(CONFIG_TARGET_ROOTFS_PARTSIZE)M@64M \
		) \
		$(if $(findstring emmc,$1), \
			-t 0x2e -N production		-p $(CONFIG_TARGET_ROOTFS_PARTSIZE)M@64M \
		)
	cat $@.tmp >> $@
	rm $@.tmp
endef

define Build/mt798x-gpt-nvme
	cp $@ $@.tmp 2>/dev/null || true
	ptgen -g -o $@.tmp -a 1 -l 1024 \
			-t 0x83 -N boot		-r	-p 63M@1M \
			-t 0x2e -N production		-p $(CONFIG_TARGET_ROOTFS_PARTSIZE)M@64M
	cat $@.tmp >> $@
	rm $@.tmp
endef

define Device/bananapi_bpi-r4-common-4gb
  DEVICE_VENDOR := Bananapi
  DEVICE_DTS_DIR := $(DTS_DIR)/
  DEVICE_DTS_LOADADDR := 0x45f00000
  DEVICE_DTS_OVERLAY:= \
mt7988a-bananapi-bpi-r4-emmc \
mt7988a-bananapi-bpi-r4-rtc \
mt7988a-bananapi-bpi-r4-sd \
mt7988a-bananapi-bpi-r4-spim-nand \
mt7988a-bananapi-bpi-r4-spim-nand-nmbm \
mt7988a-bananapi-bpi-r4-nvme
  DEVICE_DTC_FLAGS := --pad 4096
  DEVICE_PACKAGES := kmod-hwmon-pwmfan kmod-i2c-mux-pca954x kmod-eeprom-at24 \
    kmod-rtc-pcf8563 kmod-sfp kmod-phy-aquantia kmod-usb3 e2fsprogs f2fsck mkf2fs mt7988-wo-firmware
  DEVICE_COMPAT_VERSION := 1.1
  DEVICE_COMPAT_MESSAGE := The non-switch ports were renamed to match the board/case labels
  KERNEL_LOADADDR := 0x46000000

  ARTIFACTS := \
      emmc-img.bin \
      nvme-img.bin \
      sdcard.img.gz \
      snand-img.bin
  ARTIFACT/emmc-img.bin := mt798x-gpt emmc | \
  pad-to 17k | mt7988-bl2 emmc-comb | \
  pad-to 6656k | mt7988-bl31-uboot $$(DEVICE_NAME)-emmc | \
  pad-to 64M | append-image squashfs-sysupgrade.itb
  ARTIFACT/nvme-img.bin := mt798x-gpt-nvme | \
  pad-to 512M | append-image squashfs-sysupgrade.itb
  ARTIFACT/snand-img.bin := mt7988-bl2 spim-nand-ubi-comb | \
  pad-to 2048k | \
  ubinize-image fit squashfs-sysupgrade.itb
  ARTIFACT/sdcard.img.gz := mt798x-gpt sdmmc |\
  pad-to 17k | mt7988-bl2 sdmmc-comb |\
  pad-to 6656k | mt7988-bl31-uboot $$(DEVICE_NAME)-sdmmc |\
  pad-to 44M | mt7988-bl2 spim-nand-ubi-comb |\
  pad-to 45M | mt7988-bl31-uboot $$(DEVICE_NAME)-snand |\
  pad-to 51M | mt7988-bl2 emmc-comb |\
  pad-to 52M | mt7988-bl31-uboot $$(DEVICE_NAME)-emmc |\
  pad-to 56M | mt798x-gpt emmc |\
$(if $(CONFIG_TARGET_ROOTFS_SQUASHFS),\
  pad-to 64M | append-image squashfs-sysupgrade.itb | check-size |\
) \
  gzip

  KERNEL := kernel-bin | gzip
  IMAGES := sysupgrade.itb
  IMAGE/sysupgrade.itb := append-kernel | fit gzip $$(KDIR)/image-$$(firstword $$(DEVICE_DTS)).dtb external-with-rootfs | pad-rootfs | append-metadata
ifeq ($(DUMP),)
  IMAGE_SIZE := $$(shell expr 64 + $$(CONFIG_TARGET_ROOTFS_PARTSIZE))m
endif

  BLOCKSIZE := 128k
  PAGESIZE := 2048
  UBOOTENV_IN_UBI := 1
  UBINIZE_PARTS := fip=:$(STAGING_DIR_IMAGE)/mt7988_bananapi_bpi-r4-snand-u-boot.fip

endef

define Device/bananapi_bpi-r4-common-8gb
  DEVICE_VENDOR := Bananapi
  DEVICE_DTS_DIR := $(DTS_DIR)/
  DEVICE_DTS_LOADADDR := 0x45f00000
  DEVICE_DTS_OVERLAY:= \
mt7988a-bananapi-bpi-r4-emmc \
mt7988a-bananapi-bpi-r4-rtc \
mt7988a-bananapi-bpi-r4-sd \
mt7988a-bananapi-bpi-r4-spim-nand \
mt7988a-bananapi-bpi-r4-spim-nand-nmbm \
mt7988a-bananapi-bpi-r4-nvme
  DEVICE_DTC_FLAGS := --pad 4096
  DEVICE_PACKAGES := kmod-hwmon-pwmfan kmod-i2c-mux-pca954x kmod-eeprom-at24 \
    kmod-rtc-pcf8563 kmod-sfp kmod-phy-aquantia kmod-usb3 e2fsprogs f2fsck mkf2fs mt7988-wo-firmware
  DEVICE_COMPAT_VERSION := 1.1
  DEVICE_COMPAT_MESSAGE := The non-switch ports were renamed to match the board/case labels
  KERNEL_LOADADDR := 0x46000000
  BPI_R4_FIP_NAME := bananapi_bpi-r4

  ARTIFACTS := \
      emmc-img.bin \
      nvme-img.bin \
      sdcard.img.gz \
      snand-img.bin
  ARTIFACT/emmc-img.bin := mt798x-gpt emmc | \
  pad-to 17k | mt7988-bl2 emmc-comb-4bg | \
  pad-to 6656k | mt7988-bl31-uboot $$(BPI_R4_FIP_NAME)-emmc | \
  pad-to 64M | append-image squashfs-sysupgrade.itb
  ARTIFACT/nvme-img.bin := mt798x-gpt-nvme | \
  pad-to 512M | append-image squashfs-sysupgrade.itb
  ARTIFACT/snand-img.bin := mt7988-bl2 spim-nand-ubi-comb-4bg | \
  pad-to 2048k | \
  ubinize-image fit squashfs-sysupgrade.itb
  ARTIFACT/sdcard.img.gz := mt798x-gpt sdmmc |\
  pad-to 17k | mt7988-bl2 sdmmc-comb-4bg |\
  pad-to 6656k | mt7988-bl31-uboot $$(BPI_R4_FIP_NAME)-sdmmc |\
  pad-to 44M | mt7988-bl2 spim-nand-ubi-comb-4bg |\
  pad-to 45M | mt7988-bl31-uboot $$(BPI_R4_FIP_NAME)-snand |\
  pad-to 51M | mt7988-bl2 emmc-comb-4bg |\
  pad-to 52M | mt7988-bl31-uboot $$(BPI_R4_FIP_NAME)-emmc |\
  pad-to 56M | mt798x-gpt emmc |\
$(if $(CONFIG_TARGET_ROOTFS_SQUASHFS),\
  pad-to 64M | append-image squashfs-sysupgrade.itb | check-size |\
) \
  gzip

  KERNEL := kernel-bin | gzip
  IMAGES := sysupgrade.itb
  IMAGE/sysupgrade.itb := append-kernel | fit gzip $$(KDIR)/image-$$(firstword $$(DEVICE_DTS)).dtb external-with-rootfs | pad-rootfs | append-metadata
ifeq ($(DUMP),)
  IMAGE_SIZE := $$(shell expr 64 + $$(CONFIG_TARGET_ROOTFS_PARTSIZE))m
endif

  BLOCKSIZE := 128k
  PAGESIZE := 2048
  UBOOTENV_IN_UBI := 1
  UBINIZE_PARTS := fip=:$(STAGING_DIR_IMAGE)/mt7988_bananapi_bpi-r4-snand-u-boot.fip

endef

define Device/bananapi_bpi-r4
  DEVICE_MODEL := BPi-R4
  DEVICE_DTS := mt7988a-bananapi-bpi-r4
  DEVICE_DTS_CONFIG := config-mt7988a-bananapi-bpi-r4
  $(call Device/bananapi_bpi-r4-common-4gb)
endef
TARGET_DEVICES += bananapi_bpi-r4

define Device/bananapi_bpi-r4-poe
  DEVICE_MODEL := BPi-R4 2.5GE
  DEVICE_DTS := mt7988a-bananapi-bpi-r4-2g5
  DEVICE_DTS_CONFIG := config-mt7988a-bananapi-bpi-r4-poe
  $(call Device/bananapi_bpi-r4-common-4gb)
  DEVICE_PACKAGES += mt798x-2p5g-phy-firmware-internal kmod-mt798x-2p5g-phy
  SUPPORTED_DEVICES += bananapi,bpi-r4-2g5
  UBINIZE_PARTS := fip=:$(STAGING_DIR_IMAGE)/mt7988_bananapi_bpi-r4-poe-snand-u-boot.fip
endef
TARGET_DEVICES += bananapi_bpi-r4-poe

define Device/bananapi_bpi-r4-8gb
  DEVICE_MODEL := BPi-R4 8GB
  DEVICE_DTS := mt7988a-bananapi-bpi-r4
  DEVICE_DTS_CONFIG := config-mt7988a-bananapi-bpi-r4
  $(call Device/bananapi_bpi-r4-common-8gb)
endef
TARGET_DEVICES += bananapi_bpi-r4-8gb

define Device/bananapi_bpi-r4-poe-8gb
  DEVICE_MODEL := BPi-R4 2.5GE 8GB
  DEVICE_DTS := mt7988a-bananapi-bpi-r4-2g5
  DEVICE_DTS_CONFIG := config-mt7988a-bananapi-bpi-r4-poe
  $(call Device/bananapi_bpi-r4-common-8gb)
  DEVICE_PACKAGES += mt798x-2p5g-phy-firmware-internal kmod-mt798x-2p5g-phy
  SUPPORTED_DEVICES += bananapi,bpi-r4-2g5
  BPI_R4_FIP_NAME := bananapi_bpi-r4-poe
  UBINIZE_PARTS := fip=:$(STAGING_DIR_IMAGE)/mt7988_bananapi_bpi-r4-poe-snand-u-boot.fip
endef
TARGET_DEVICES += bananapi_bpi-r4-poe-8gb
