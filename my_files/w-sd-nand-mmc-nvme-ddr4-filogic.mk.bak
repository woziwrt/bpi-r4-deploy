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

# Variation of the normal partition table to account
# for factory and mfgdata partition
#
# Keep fip partition at standard offset to keep consistency
# with uboot commands
define Build/mt7988-mozart-gpt
	cp $@ $@.tmp 2>/dev/null || true
	ptgen -g -o $@.tmp -a 1 -l 1024 \
			-t 0x83	-N ubootenv	-r	-p 512k@4M \
			-t 0xef	-N fip		  -r	-p 4M@6656k \
			-t 0x83	-N factory	-r	-p 8M@25M \
			-t 0x2e	-N mfgdata	-r	-p 8M@33M \
			-t 0xef -N recovery	-r	-p 32M@41M \
			-t 0x2e -N production		-p $(CONFIG_TARGET_ROOTFS_PARTSIZE)M@73M
	cat $@.tmp >> $@
	rm $@.tmp
endef

define Build/append-openwrt-one-eeprom
	dd if=$(STAGING_DIR_IMAGE)/mt7981_eeprom_mt7976_dbdc.bin >> $@
endef

define Build/mstc-header
  $(eval version=$(word 1,$(1)))
  $(eval magic=$(word 2,$(1)))
  gzip -c $@ | tail -c8 > $@.crclen
  ( \
    printf "$(magic)"; \
    tail -c+5 $@.crclen; head -c4 $@.crclen; \
    dd if=/dev/zero bs=4 count=2; \
    printf "$(version)" | dd bs=56 count=1 conv=sync 2>/dev/null; \
    dd if=/dev/zero bs=$$((0x20000 - 0x84)) count=1 conv=sync 2>/dev/null | \
      tr "\0" "\377"; \
    cat $@; \
  ) > $@.new
  mv $@.new $@
endef

define Build/zyxel-nwa-fit-filogic
	$(TOPDIR)/scripts/mkits-zyxel-fit-filogic.sh \
		$@.its $@ "80 e1 81 e1 ff ff ff ff ff ff"
	PATH=$(LINUX_DIR)/scripts/dtc:$(PATH) mkimage -f $@.its $@.new
	@mv $@.new $@
endef

define Build/cetron-header
	$(eval magic=$(word 1,$(1)))
	$(eval model=$(word 2,$(1)))
	( \
		dd if=/dev/zero bs=856 count=1 2>/dev/null; \
		printf "$(model)," | dd bs=128 count=1 conv=sync 2>/dev/null; \
		md5sum $@ | cut -f1 -d" " | dd bs=32 count=1 2>/dev/null; \
		printf "$(magic)" | dd bs=4 count=1 conv=sync 2>/dev/null; \
		cat $@; \
	) > $@.tmp
	fw_crc=$$(gzip -c $@.tmp | tail -c 8 | od -An -N4 -tx4 --endian little | tr -d ' \n'); \
	printf "$$(echo $$fw_crc | sed 's/../\\x&/g')" | cat - $@.tmp > $@
	rm $@.tmp
endef

define Device/abt_asr3000
  DEVICE_VENDOR := ABT
  DEVICE_MODEL := ASR3000
  DEVICE_DTS := mt7981b-abt-asr3000
  DEVICE_DTS_DIR := ../dts
  DEVICE_PACKAGES := kmod-mt7915e kmod-mt7981-firmware mt7981-wo-firmware
  UBINIZE_OPTS := -E 5
  BLOCKSIZE := 128k
  PAGESIZE := 2048
  KERNEL_IN_UBI := 1
  UBOOTENV_IN_UBI := 1
  IMAGES := sysupgrade.itb
  KERNEL_INITRAMFS_SUFFIX := -recovery.itb
  KERNEL := kernel-bin | gzip
  KERNEL_INITRAMFS := kernel-bin | lzma | \
	fit lzma $$(KDIR)/image-$$(firstword $$(DEVICE_DTS)).dtb with-initrd | pad-to 64k
  IMAGE/sysupgrade.itb := append-kernel | \
	fit gzip $$(KDIR)/image-$$(firstword $$(DEVICE_DTS)).dtb external-static-with-rootfs | append-metadata
  ARTIFACTS := preloader.bin bl31-uboot.fip
  ARTIFACT/preloader.bin := mt7981-bl2 spim-nand-ddr3
  ARTIFACT/bl31-uboot.fip := mt7981-bl31-uboot abt_asr3000
endef
TARGET_DEVICES += abt_asr3000

define Device/acelink_ew-7886cax
  DEVICE_VENDOR := Acelink
  DEVICE_MODEL := EW-7886CAX
  DEVICE_DTS := mt7986a-acelink-ew-7886cax
  DEVICE_DTS_DIR := ../dts
  DEVICE_PACKAGES := kmod-mt7915e kmod-mt7986-firmware mt7986-wo-firmware
  UBINIZE_OPTS := -E 5
  BLOCKSIZE := 128k
  PAGESIZE := 2048
  IMAGE_SIZE := 65536k
  KERNEL_IN_UBI := 1
  IMAGES += factory.bin
  IMAGE/factory.bin := append-ubi | check-size $$$$(IMAGE_SIZE)
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
endef
TARGET_DEVICES += acelink_ew-7886cax

define Device/acer_predator-w6
  DEVICE_VENDOR := Acer
  DEVICE_MODEL := Predator Connect W6
  DEVICE_DTS := mt7986a-acer-predator-w6
  DEVICE_DTS_DIR := ../dts
  DEVICE_DTS_LOADADDR := 0x47000000
  DEVICE_PACKAGES := kmod-usb3 kmod-mt7915e kmod-mt7916-firmware kmod-mt7986-firmware mt7986-wo-firmware e2fsprogs f2fsck mkf2fs
  IMAGES := sysupgrade.bin
  KERNEL := kernel-bin | lzma | fit lzma $$(KDIR)/image-$$(firstword $$(DEVICE_DTS)).dtb
  KERNEL_INITRAMFS := kernel-bin | lzma | \
	fit lzma $$(KDIR)/image-$$(firstword $$(DEVICE_DTS)).dtb with-initrd | pad-to 64k
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
endef
TARGET_DEVICES += acer_predator-w6

define Device/acer_predator-w6d
  DEVICE_VENDOR := Acer
  DEVICE_MODEL := Predator Connect W6d
  DEVICE_DTS := mt7986a-acer-predator-w6d
  DEVICE_DTS_DIR := ../dts
  DEVICE_DTS_LOADADDR := 0x47000000
  DEVICE_PACKAGES := kmod-usb3 kmod-mt7915e kmod-mt7916-firmware kmod-mt7986-firmware mt7986-wo-firmware e2fsprogs f2fsck mkf2fs
  IMAGES := sysupgrade.bin
  KERNEL := kernel-bin | lzma | fit lzma $$(KDIR)/image-$$(firstword $$(DEVICE_DTS)).dtb
  KERNEL_INITRAMFS := kernel-bin | lzma | \
	fit lzma $$(KDIR)/image-$$(firstword $$(DEVICE_DTS)).dtb with-initrd | pad-to 64k
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
endef
TARGET_DEVICES += acer_predator-w6d

define Device/acer_predator-w6x-stock
  DEVICE_VENDOR := Acer
  DEVICE_MODEL := Predator Connect W6x (Stock Layout)
  DEVICE_DTS := mt7986a-acer-predator-w6x-stock
  SUPPORTED_DEVICES += acer,predator-w6x
  DEVICE_DTS_DIR := ../dts
  DEVICE_DTS_LOADADDR := 0x47000000
  KERNEL_IN_UBI := 1
  UBOOTENV_IN_UBI := 1
  DEVICE_PACKAGES := kmod-usb3 kmod-leds-ws2812b kmod-mt7915e kmod-mt7986-firmware mt7986-wo-firmware
  IMAGES := sysupgrade.bin
  KERNEL := kernel-bin | lzma | fit lzma $$(KDIR)/image-$$(firstword $$(DEVICE_DTS)).dtb
  KERNEL_INITRAMFS := kernel-bin | lzma | \
	fit lzma $$(KDIR)/image-$$(firstword $$(DEVICE_DTS)).dtb with-initrd | pad-to 64k
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
endef
TARGET_DEVICES += acer_predator-w6x-stock

define Device/acer_predator-w6x-ubootmod
  DEVICE_VENDOR := Acer
  DEVICE_MODEL := Predator Connect W6x (OpenWrt U-Boot Layout)
  DEVICE_DTS := mt7986a-acer-predator-w6x-ubootmod
  DEVICE_DTS_DIR := ../dts
  DEVICE_PACKAGES := kmod-usb3 kmod-leds-ws2812b kmod-mt7915e kmod-mt7986-firmware mt7986-wo-firmware
  KERNEL_INITRAMFS_SUFFIX := -recovery.itb
  IMAGES := sysupgrade.itb
  UBINIZE_OPTS := -E 5
  BLOCKSIZE := 128k
  PAGESIZE := 2048
  KERNEL_IN_UBI := 1
  UBOOTENV_IN_UBI := 1
  KERNEL := kernel-bin | gzip
  KERNEL_INITRAMFS := kernel-bin | lzma | \
	fit lzma $$(KDIR)/image-$$(firstword $$(DEVICE_DTS)).dtb with-initrd | pad-to 64k
  IMAGE/sysupgrade.itb := append-kernel | \
	fit gzip $$(KDIR)/image-$$(firstword $$(DEVICE_DTS)).dtb external-static-with-rootfs | append-metadata
  ARTIFACTS := preloader.bin bl31-uboot.fip
  ARTIFACT/preloader.bin := mt7986-bl2 spim-nand-ddr4
  ARTIFACT/bl31-uboot.fip := mt7986-bl31-uboot acer_predator-w6x
endef
TARGET_DEVICES += acer_predator-w6x-ubootmod

define Device/acer_vero-w6m
  DEVICE_VENDOR := Acer
  DEVICE_MODEL := Connect Vero W6m
  DEVICE_DTS := mt7986a-acer-vero-w6m
  DEVICE_DTS_DIR := ../dts
  DEVICE_DTS_LOADADDR := 0x47000000
  DEVICE_PACKAGES := kmod-leds-ktd202x kmod-mt7915e kmod-mt7916-firmware kmod-mt7986-firmware mt7986-wo-firmware e2fsprogs f2fsck mkf2fs
  IMAGES := sysupgrade.bin
  KERNEL := kernel-bin | lzma | fit lzma $$(KDIR)/image-$$(firstword $$(DEVICE_DTS)).dtb
  KERNEL_INITRAMFS := kernel-bin | lzma | \
	fit lzma $$(KDIR)/image-$$(firstword $$(DEVICE_DTS)).dtb with-initrd | pad-to 64k
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
endef
TARGET_DEVICES += acer_vero-w6m

define Device/asiarf_ap7986-003
  DEVICE_VENDOR := AsiaRF
  DEVICE_MODEL := AP7986 003
  DEVICE_DTS := mt7986a-asiarf-ap7986-003
  DEVICE_DTS_DIR := ../dts
  DEVICE_PACKAGES := kmod-usb3 kmod-mt7915e kmod-mt7986-firmware mt7986-wo-firmware
  UBINIZE_OPTS := -E 5
  BLOCKSIZE := 128k
  PAGESIZE := 2048
  IMAGE_SIZE := 65536k
  KERNEL_IN_UBI := 1
  IMAGES += factory.bin
  IMAGE/factory.bin := append-ubi | check-size $$$$(IMAGE_SIZE)
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
  KERNEL := kernel-bin | lzma | fit lzma $$(KDIR)/image-$$(firstword $$(DEVICE_DTS)).dtb
endef
TARGET_DEVICES += asiarf_ap7986-003

define Device/adtran_smartrg
  DEVICE_VENDOR := Adtran
  DEVICE_DTS_DIR := ../dts
  DEVICE_PACKAGES := e2fsprogs f2fsck mkf2fs kmod-hwmon-pwmfan
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
endef

define Device/smartrg_sdg-8612
$(call Device/adtran_smartrg)
  DEVICE_MODEL := SDG-8612
  DEVICE_DTS := mt7986a-smartrg-SDG-8612
  DEVICE_PACKAGES += kmod-mt7915e kmod-mt7986-firmware mt7986-wo-firmware
endef
TARGET_DEVICES += smartrg_sdg-8612

define Device/smartrg_sdg-8614
$(call Device/adtran_smartrg)
  DEVICE_MODEL := SDG-8614
  DEVICE_DTS := mt7986a-smartrg-SDG-8614
  DEVICE_PACKAGES += kmod-mt7915e kmod-mt7986-firmware mt7986-wo-firmware
endef
TARGET_DEVICES += smartrg_sdg-8614

define Device/smartrg_sdg-8622
$(call Device/adtran_smartrg)
  DEVICE_MODEL := SDG-8622
  DEVICE_DTS := mt7986a-smartrg-SDG-8622
  DEVICE_PACKAGES += kmod-mt7915e kmod-mt7915-firmware kmod-mt7986-firmware mt7986-wo-firmware
endef
TARGET_DEVICES += smartrg_sdg-8622

define Device/smartrg_sdg-8632
$(call Device/adtran_smartrg)
  DEVICE_MODEL := SDG-8632
  DEVICE_DTS := mt7986a-smartrg-SDG-8632
  DEVICE_PACKAGES += kmod-mt7915e kmod-mt7915-firmware kmod-mt7986-firmware mt7986-wo-firmware
endef
TARGET_DEVICES += smartrg_sdg-8632

define Device/smartrg_sdg-8733
$(call Device/adtran_smartrg)
  DEVICE_MODEL := SDG-8733
  DEVICE_DTS := mt7988a-smartrg-SDG-8733
  DEVICE_PACKAGES += kmod-mt7996-firmware kmod-phy-aquantia kmod-usb3 mt7988-wo-firmware
endef
TARGET_DEVICES += smartrg_sdg-8733

define Device/smartrg_sdg-8733a
$(call Device/adtran_smartrg)
  DEVICE_MODEL := SDG-8733A
  DEVICE_DTS := mt7988d-smartrg-SDG-8733A
  DEVICE_PACKAGES += mt7988-2p5g-phy-firmware kmod-mt7996-233-firmware kmod-phy-aquantia mt7988-wo-firmware
endef
TARGET_DEVICES += smartrg_sdg-8733a

define Device/smartrg_sdg-8734
$(call Device/adtran_smartrg)
  DEVICE_MODEL := SDG-8734
  DEVICE_DTS := mt7988a-smartrg-SDG-8734
  DEVICE_PACKAGES += kmod-mt7996-firmware kmod-phy-aquantia kmod-sfp kmod-usb3 mt7988-wo-firmware
endef
TARGET_DEVICES += smartrg_sdg-8734

define Device/airpi_ap3000m
  DEVICE_VENDOR := Airpi
  DEVICE_MODEL := AP3000M
  DEVICE_DTS := mt7981b-airpi-ap3000m
  DEVICE_DTS_DIR := ../dts
  DEVICE_PACKAGES := kmod-mt7915e kmod-mt7981-firmware mt7981-wo-firmware \
  	kmod-hwmon-pwmfan kmod-usb3 f2fsck mkf2fs
  KERNEL := kernel-bin | lzma | fit lzma $$(KDIR)/image-$$(firstword $$(DEVICE_DTS)).dtb
  KERNEL_INITRAMFS := kernel-bin | lzma | \
        fit lzma $$(KDIR)/image-$$(firstword $$(DEVICE_DTS)).dtb with-initrd | pad-to 64k
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
endef
TARGET_DEVICES += airpi_ap3000m

define Device/arcadyan_mozart
  DEVICE_VENDOR := Arcadyan
  DEVICE_MODEL := Mozart
  DEVICE_DTS := mt7988a-arcadyan-mozart
  DEVICE_DTS_DIR := ../dts
  DEVICE_DTC_FLAGS := --pad 4096
  DEVICE_DTS_LOADADDR := 0x45f00000
  DEVICE_PACKAGES := kmod-hwmon-pwmfan e2fsprogs f2fsck mkf2fs kmod-mt7996-firmware
  KERNEL_LOADADDR := 0x46000000
  KERNEL := kernel-bin | gzip
  KERNEL_INITRAMFS := kernel-bin | lzma | \
	fit lzma $$(KDIR)/image-$$(firstword $$(DEVICE_DTS)).dtb with-initrd | pad-to 64k
  KERNEL_INITRAMFS_SUFFIX := .itb
  IMAGE_SIZE := $$(shell expr 64 + $$(CONFIG_TARGET_ROOTFS_PARTSIZE))m
  IMAGES := sysupgrade.itb
  IMAGE/sysupgrade.itb := append-kernel | fit gzip $$(KDIR)/image-$$(firstword $$(DEVICE_DTS)).dtb external-with-rootfs | pad-rootfs | append-metadata
  ARTIFACTS := emmc-preloader.bin emmc-bl31-uboot.fip emmc-gpt.bin
  ARTIFACT/emmc-gpt.bin := mt7988-mozart-gpt
  ARTIFACT/emmc-preloader.bin	:= mt7988-bl2 emmc-comb
  ARTIFACT/emmc-bl31-uboot.fip	:= mt7988-bl31-uboot arcadyan_mozart
  SUPPORTED_DEVICES += arcadyan,mozart
endef
TARGET_DEVICES += arcadyan_mozart

define Device/asus_rt-ax52
  DEVICE_VENDOR := ASUS
  DEVICE_MODEL := RT-AX52
  DEVICE_ALT0_VENDOR := ASUS
  DEVICE_ALT0_MODEL := RT-AX52 PRO
  DEVICE_DTS := mt7981b-asus-rt-ax52
  DEVICE_DTS_DIR := ../dts
  DEVICE_PACKAGES := kmod-mt7915e kmod-mt7981-firmware mt7981-wo-firmware
  IMAGES := sysupgrade.bin
  KERNEL := kernel-bin | lzma | \
	fit lzma $$(KDIR)/image-$$(firstword $$(DEVICE_DTS)).dtb
  KERNEL_INITRAMFS := kernel-bin | lzma | \
	fit lzma $$(KDIR)/image-$$(firstword $$(DEVICE_DTS)).dtb with-initrd | pad-to 64k
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
ifeq ($(IB),)
  ARTIFACTS := initramfs.trx
  ARTIFACT/initramfs.trx := append-image-stage initramfs-kernel.bin | \
	uImage none | asus-trx -v 3 -n $$(DEVICE_MODEL)
endif
endef
TARGET_DEVICES += asus_rt-ax52

define Device/asus_rt-ax57m
  DEVICE_VENDOR := ASUS
  DEVICE_MODEL := RT-AX57M
  DEVICE_ALT0_VENDOR := ASUS
  DEVICE_ALT0_MODEL := RT-AX54HP
  DEVICE_ALT0_VARIANT := V2
  DEVICE_ALT1_VENDOR := ASUS
  DEVICE_ALT1_MODEL := RT-AX1800HP
  DEVICE_ALT1_VARIANT := V2
  DEVICE_ALT2_VENDOR := ASUS
  DEVICE_ALT2_MODEL := RT-AX1800S
  DEVICE_ALT2_VARIANT := V2
  DEVICE_ALT3_VENDOR := ASUS
  DEVICE_ALT3_MODEL := RT-AX3000S
  DEVICE_DTS := mt7981b-asus-rt-ax57m
  DEVICE_DTS_DIR := ../dts
  DEVICE_PACKAGES := kmod-mt7915e kmod-mt7981-firmware mt7981-wo-firmware
  IMAGES := sysupgrade.bin
  KERNEL := kernel-bin | lzma | \
	fit lzma $$(KDIR)/image-$$(firstword $$(DEVICE_DTS)).dtb
  KERNEL_INITRAMFS := kernel-bin | lzma | \
	fit lzma $$(KDIR)/image-$$(firstword $$(DEVICE_DTS)).dtb  with-initrd | pad-to 64k
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
ifeq ($(IB),)
  ARTIFACTS := initramfs.trx
  ARTIFACT/initramfs.trx := append-image-stage initramfs-kernel.bin | \
	uImage none | asus-trx -v 3 -n $$(DEVICE_MODEL)
endif
endef
TARGET_DEVICES += asus_rt-ax57m

define Device/asus_rt-ax59u
  DEVICE_VENDOR := ASUS
  DEVICE_MODEL := RT-AX59U
  DEVICE_DTS := mt7986a-asus-rt-ax59u
  DEVICE_DTS_DIR := ../dts
  DEVICE_PACKAGES := kmod-usb3 kmod-mt7915e kmod-mt7986-firmware mt7986-wo-firmware
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
endef
TARGET_DEVICES += asus_rt-ax59u

define Device/asus_tuf-ax4200
  DEVICE_VENDOR := ASUS
  DEVICE_MODEL := TUF-AX4200
  DEVICE_DTS := mt7986a-asus-tuf-ax4200
  DEVICE_DTS_DIR := ../dts
  DEVICE_DTS_LOADADDR := 0x47000000
  DEVICE_PACKAGES := kmod-usb3 kmod-mt7915e kmod-mt7986-firmware mt7986-wo-firmware
  IMAGES := sysupgrade.bin
  KERNEL := kernel-bin | lzma | \
	fit lzma $$(KDIR)/image-$$(firstword $$(DEVICE_DTS)).dtb
  KERNEL_INITRAMFS := kernel-bin | lzma | \
	fit lzma $$(KDIR)/image-$$(firstword $$(DEVICE_DTS)).dtb with-initrd | pad-to 64k
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
ifeq ($(IB),)
ifneq ($(CONFIG_TARGET_ROOTFS_INITRAMFS),)
ifeq ($(CONFIG_TARGET_ROOTFS_INITRAMFS_SEPARATE),)
  # The default boot command of the bootloader does not load the ramdisk from the FIT image
  ARTIFACTS := initramfs.trx
  ARTIFACT/initramfs.trx := append-image-stage initramfs-kernel.bin | \
	uImage none | asus-trx -v 3 -n $$(DEVICE_MODEL)
endif
endif
endif
endef
TARGET_DEVICES += asus_tuf-ax4200

define Device/asus_tuf-ax4200q
  DEVICE_VENDOR := ASUS
  DEVICE_MODEL := TUF-AX4200Q
  DEVICE_DTS := mt7986a-asus-tuf-ax4200q
  DEVICE_DTS_DIR := ../dts
  DEVICE_PACKAGES := kmod-usb3 kmod-mt7915e kmod-mt7986-firmware mt7986-wo-firmware
  IMAGES := sysupgrade.bin
  KERNEL := kernel-bin | lzma | \
	fit lzma $$(KDIR)/image-$$(firstword $$(DEVICE_DTS)).dtb
  KERNEL_INITRAMFS := kernel-bin | lzma | \
	fit lzma $$(KDIR)/image-$$(firstword $$(DEVICE_DTS)).dtb with-initrd | pad-to 64k
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
ifeq ($(IB),)
ifeq ($(CONFIG_TARGET_INITRAMFS_FORCE),y)
  ARTIFACTS := initramfs.trx
  ARTIFACT/initramfs.trx := append-image-stage initramfs-kernel.bin | \
	uImage none | asus-trx -v 3 -n TUF-AX4200
endif
endif
endef
TARGET_DEVICES += asus_tuf-ax4200q

define Device/asus_tuf-ax6000
  DEVICE_VENDOR := ASUS
  DEVICE_MODEL := TUF-AX6000
  DEVICE_DTS := mt7986a-asus-tuf-ax6000
  DEVICE_DTS_DIR := ../dts
  DEVICE_DTS_LOADADDR := 0x47000000
  DEVICE_PACKAGES := kmod-usb3 kmod-mt7915e kmod-mt7986-firmware mt7986-wo-firmware
  IMAGES := sysupgrade.bin
  KERNEL := kernel-bin | lzma | \
	fit lzma $$(KDIR)/image-$$(firstword $$(DEVICE_DTS)).dtb
  KERNEL_INITRAMFS := kernel-bin | lzma | \
	fit lzma $$(KDIR)/image-$$(firstword $$(DEVICE_DTS)).dtb with-initrd | pad-to 64k
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
endef
TARGET_DEVICES += asus_tuf-ax6000

define Device/asus_zenwifi-bt8
  DEVICE_VENDOR := ASUS
  DEVICE_MODEL := ZenWiFi BT8
  DEVICE_DTS := mt7988d-asus-zenwifi-bt8
  DEVICE_DTS_DIR := ../dts
  DEVICE_PACKAGES := kmod-usb3 mt7988-2p5g-phy-firmware kmod-mt7996-firmware mt7988-wo-firmware
  KERNEL := kernel-bin | gzip | \
	fit gzip $$(KDIR)/image-$$(firstword $$(DEVICE_DTS)).dtb
  KERNEL_INITRAMFS := kernel-bin | lzma | \
	fit lzma $$(KDIR)/image-$$(firstword $$(DEVICE_DTS)).dtb with-initrd | pad-to 64k
  KERNEL_LOADADDR := 0x48080000
  IMAGES := sysupgrade.bin
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
ifeq ($(IB),)
ifneq ($(CONFIG_TARGET_ROOTFS_INITRAMFS),)
  ARTIFACTS := factory.bin
  ARTIFACT/factory.bin := append-image initramfs-kernel.bin | uImage lzma
endif
endif
endef
TARGET_DEVICES += asus_zenwifi-bt8

define Device/asus_zenwifi-bt8-ubootmod
  DEVICE_VENDOR := ASUS
  DEVICE_MODEL := ZenWiFi BT8
  DEVICE_VARIANT := U-Boot mod
  DEVICE_DTS := mt7988d-asus-zenwifi-bt8-ubootmod
  DEVICE_DTS_DIR := ../dts
  DEVICE_DTS_LOADADDR := 0x45f00000
  DEVICE_PACKAGES := kmod-usb3 mt7988-2p5g-phy-firmware kmod-mt7996-firmware mt7988-wo-firmware
  ARTIFACTS := preloader.bin bl31-uboot.fip
  ARTIFACT/preloader.bin := mt7988-bl2 spim-nand-ubi-ddr4
  ARTIFACT/bl31-uboot.fip := mt7988-bl31-uboot asus_zenwifi-bt8
  KERNEL := kernel-bin | gzip
  KERNEL_INITRAMFS := kernel-bin | lzma | \
	fit lzma $$(KDIR)/image-$$(firstword $$(DEVICE_DTS)).dtb with-initrd | pad-to 64k
  KERNEL_INITRAMFS_SUFFIX := -recovery.itb
  KERNEL_LOADADDR := 0x46000000
  KERNEL_IN_UBI := 1
  UBOOTENV_IN_UBI := 1
  IMAGES := sysupgrade.itb
  IMAGE/sysupgrade.itb := append-kernel | fit gzip $$(KDIR)/image-$$(firstword $$(DEVICE_DTS)).dtb external-with-rootfs | pad-rootfs | append-metadata
endef
TARGET_DEVICES += asus_zenwifi-bt8-ubootmod


define Device/bananapi_bpi-r3
  DEVICE_VENDOR := Bananapi
  DEVICE_MODEL := BPi-R3
  DEVICE_DTS := mt7986a-bananapi-bpi-r3
  DEVICE_DTS_CONFIG := config-mt7986a-bananapi-bpi-r3
  DEVICE_DTS_OVERLAY:= mt7986a-bananapi-bpi-r3-emmc mt7986a-bananapi-bpi-r3-nand \
		       mt7986a-bananapi-bpi-r3-nor mt7986a-bananapi-bpi-r3-sd \
		       mt7986a-bananapi-bpi-r3-respeaker-2mics
  DEVICE_DTS_DIR := $(DTS_DIR)/
  DEVICE_DTS_LOADADDR := 0x43f00000
  DEVICE_PACKAGES := kmod-hwmon-pwmfan kmod-i2c-gpio kmod-mt7915e kmod-mt7986-firmware kmod-sfp kmod-usb3 \
		     e2fsprogs f2fsck mkf2fs mt7986-wo-firmware
  IMAGES := sysupgrade.itb
  KERNEL_LOADADDR := 0x44000000
  KERNEL_INITRAMFS_SUFFIX := -recovery.itb
  ARTIFACTS := \
	       emmc-preloader.bin emmc-bl31-uboot.fip \
	       nor-preloader.bin nor-bl31-uboot.fip \
	       sdcard.img.gz \
	       snand-preloader.bin snand-bl31-uboot.fip
  ARTIFACT/emmc-preloader.bin	:= mt7986-bl2 emmc-ddr4
  ARTIFACT/emmc-bl31-uboot.fip	:= mt7986-bl31-uboot bananapi_bpi-r3-emmc
  ARTIFACT/nor-preloader.bin	:= mt7986-bl2 nor-ddr4
  ARTIFACT/nor-bl31-uboot.fip	:= mt7986-bl31-uboot bananapi_bpi-r3-nor
  ARTIFACT/snand-preloader.bin	:= mt7986-bl2 spim-nand-ubi-ddr4
  ARTIFACT/snand-bl31-uboot.fip	:= mt7986-bl31-uboot bananapi_bpi-r3-snand
  ARTIFACT/sdcard.img.gz	:= mt798x-gpt sdmmc |\
				   pad-to 17k | mt7986-bl2 sdmmc-ddr4 |\
				   pad-to 6656k | mt7986-bl31-uboot bananapi_bpi-r3-sdmmc |\
				   pad-to 44M | mt7986-bl2 spim-nand-ubi-ddr4 |\
				   pad-to 45M | mt7986-bl31-uboot bananapi_bpi-r3-snand |\
				   pad-to 49M | mt7986-bl2 nor-ddr4 |\
				   pad-to 50M | mt7986-bl31-uboot bananapi_bpi-r3-nor |\
				   pad-to 51M | mt7986-bl2 emmc-ddr4 |\
				   pad-to 52M | mt7986-bl31-uboot bananapi_bpi-r3-emmc |\
				   pad-to 56M | mt798x-gpt emmc |\
				$(if $(CONFIG_TARGET_ROOTFS_SQUASHFS),\
				   pad-to 64M | append-image squashfs-sysupgrade.itb | check-size |\
				) \
				  gzip
ifeq ($(DUMP),)
  IMAGE_SIZE := $$(shell expr 64 + $$(CONFIG_TARGET_ROOTFS_PARTSIZE))m
endif
  KERNEL			:= kernel-bin | gzip
  KERNEL_INITRAMFS := kernel-bin | lzma | \
	fit lzma $$(KDIR)/image-$$(firstword $$(DEVICE_DTS)).dtb with-initrd | pad-to 64k
  IMAGE/sysupgrade.itb := append-kernel | fit gzip $$(KDIR)/image-$$(firstword $$(DEVICE_DTS)).dtb external-static-with-rootfs | pad-rootfs | append-metadata
  DEVICE_DTC_FLAGS := --pad 4096
  DEVICE_COMPAT_VERSION := 1.3
  DEVICE_COMPAT_MESSAGE := First sfp port renamed from eth1 to sfp1
endef
TARGET_DEVICES += bananapi_bpi-r3

define Device/bananapi_bpi-r3-mini
  DEVICE_VENDOR := Bananapi
  DEVICE_MODEL := BPi-R3 Mini
  DEVICE_DTS := mt7986a-bananapi-bpi-r3-mini
  DEVICE_DTS_CONFIG := config-mt7986a-bananapi-bpi-r3-mini
  DEVICE_DTS_DIR := ../dts
  DEVICE_DTS_LOADADDR := 0x43f00000
  DEVICE_PACKAGES := kmod-eeprom-at24 kmod-hwmon-pwmfan kmod-mt7915e kmod-mt7986-firmware \
		     kmod-phy-airoha-en8811h kmod-usb3 e2fsprogs f2fsck mkf2fs mt7986-wo-firmware
  KERNEL_LOADADDR := 0x44000000
  KERNEL := kernel-bin | gzip
  KERNEL_INITRAMFS := kernel-bin | lzma | \
    fit lzma $$(KDIR)/image-$$(firstword $$(DEVICE_DTS)).dtb with-initrd | pad-to 64k
  KERNEL_INITRAMFS_SUFFIX := -recovery.itb
  BLOCKSIZE := 128k
  PAGESIZE := 2048
  KERNEL_IN_UBI := 1
  UBOOTENV_IN_UBI := 1
  IMAGES := snand-factory.bin sysupgrade.itb
ifeq ($(DUMP),)
  IMAGE_SIZE := $$(shell expr 64 + $$(CONFIG_TARGET_ROOTFS_PARTSIZE))m
endif
  IMAGE/sysupgrade.itb := append-kernel | \
    fit gzip $$(KDIR)/image-$$(firstword $$(DEVICE_DTS)).dtb external-static-with-rootfs | \
    pad-rootfs | append-metadata
  ARTIFACTS := \
	emmc-gpt.bin emmc-preloader.bin emmc-bl31-uboot.fip \
	snand-factory.bin snand-preloader.bin snand-bl31-uboot.fip
  ARTIFACT/emmc-gpt.bin := mt798x-gpt emmc
  ARTIFACT/emmc-preloader.bin := mt7986-bl2 emmc-ddr4
  ARTIFACT/emmc-bl31-uboot.fip := mt7986-bl31-uboot bananapi_bpi-r3-mini-emmc
  ARTIFACT/snand-factory.bin := mt7986-bl2 spim-nand-ubi-ddr4 | pad-to 256k | \
				mt7986-bl2 spim-nand-ubi-ddr4 | pad-to 512k | \
				mt7986-bl2 spim-nand-ubi-ddr4 | pad-to 768k | \
				mt7986-bl2 spim-nand-ubi-ddr4 | pad-to 2048k | \
				ubinize-image fit squashfs-sysupgrade.itb
  ARTIFACT/snand-preloader.bin := mt7986-bl2 spim-nand-ubi-ddr4
  ARTIFACT/snand-bl31-uboot.fip := mt7986-bl31-uboot bananapi_bpi-r3-mini-snand
  UBINIZE_PARTS := fip=:$(STAGING_DIR_IMAGE)/mt7986_bananapi_bpi-r3-mini-snand-u-boot.fip
ifneq ($(CONFIG_PACKAGE_airoha-en8811h-firmware),)
  UBINIZE_PARTS += en8811h-fw=:$(STAGING_DIR_IMAGE)/EthMD32.bin
endif
endef
TARGET_DEVICES += bananapi_bpi-r3-mini

define Device/bananapi_bpi-r4-common
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
      emmc-gpt.bin emmc-preloader.bin emmc-bl31-uboot.fip \
      emmc-img.bin \
      nvme-img.bin \
      sdcard.img.gz \
      snand-preloader.bin snand-bl31-uboot.fip \
      snand-img.bin
  ARTIFACT/emmc-gpt.bin := mt798x-gpt emmc
  ARTIFACT/emmc-preloader.bin := mt7988-bl2 emmc-comb-8g
  ARTIFACT/emmc-bl31-uboot.fip := mt7988-bl31-uboot $$(DEVICE_NAME)-emmc
  ARTIFACT/emmc-img.bin := mt798x-gpt emmc | \
  pad-to 17k | mt7988-bl2 emmc-comb-8g | \
  pad-to 6656k | mt7988-bl31-uboot $$(DEVICE_NAME)-emmc | \
  pad-to 64M | append-image squashfs-sysupgrade.itb
  ARTIFACT/nvme-img.bin := mt798x-gpt-nvme | \
  pad-to 512M | append-image squashfs-sysupgrade.itb
  ARTIFACT/snand-preloader.bin := mt7988-bl2 spim-nand-comb-8g
  ARTIFACT/snand-bl31-uboot.fip := mt7988-bl31-uboot $$(DEVICE_NAME)-snand
  ARTIFACT/snand-img.bin := mt7988-bl2 spim-nand-comb-8g | \
  pad-to 2048k | \
  ubinize-image fit squashfs-sysupgrade.itb
  ARTIFACT/sdcard.img.gz := mt798x-gpt sdmmc |\
  pad-to 17k | mt7988-bl2 sdmmc-comb-8g |\
  pad-to 6656k | mt7988-bl31-uboot $$(DEVICE_NAME)-sdmmc |\
  pad-to 44M | mt7988-bl2 spim-nand-comb-8g |\
  pad-to 45M | mt7988-bl31-uboot $$(DEVICE_NAME)-snand |\
  pad-to 51M | mt7988-bl2 emmc-comb-8g |\
  pad-to 52M | mt7988-bl31-uboot $$(DEVICE_NAME)-emmc |\
  pad-to 56M | mt798x-gpt emmc |\
$(if $(CONFIG_TARGET_ROOTFS_SQUASHFS),\
  pad-to 64M | append-image squashfs-sysupgrade.itb | check-size |\
) \
  gzip

  KERNEL := kernel-bin | gzip
  KERNEL_INITRAMFS := kernel-bin | lzma | \
fit lzma $$(KDIR)/image-$$(firstword $$(DEVICE_DTS)).dtb with-initrd | pad-to 64k
  IMAGES := sysupgrade.itb

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
  $(call Device/bananapi_bpi-r4-common)
endef
TARGET_DEVICES += bananapi_bpi-r4

define Device/bananapi_bpi-r4-poe
  DEVICE_MODEL := BPi-R4 2.5GE
  DEVICE_DTS := mt7988a-bananapi-bpi-r4-2g5
  DEVICE_DTS_CONFIG := config-mt7988a-bananapi-bpi-r4-poe
  $(call Device/bananapi_bpi-r4-common)
  DEVICE_PACKAGES += mt798x-2p5g-phy-firmware-internal kmod-mt798x-2p5g-phy
  SUPPORTED_DEVICES += bananapi,bpi-r4-2g5
endef
TARGET_DEVICES += bananapi_bpi-r4-poe

define Device/bananapi_bpi-r4-lite
  DEVICE_VENDOR := Bananapi
  DEVICE_MODEL := BPi-R4 Lite
  DEVICE_DTS := mt7987a-bananapi-bpi-r4-lite
  DEVICE_DTS_OVERLAY:= \
	mt7987a-bananapi-bpi-r4-lite-nand \
	mt7987a-bananapi-bpi-r4-lite-nand-nmbm \
	mt7987a-bananapi-bpi-r4-lite-nor \
	mt7987a-bananapi-bpi-r4-lite-emmc \
	mt7987a-bananapi-bpi-r4-lite-sd \
	mt7987a-bananapi-bpi-r4-lite-1pcie-2L \
	mt7987a-bananapi-bpi-r4-lite-2pcie-1L \
	mt7987-spidev
  DEVICE_DTS_CONFIG := config-mt7987a-bananapi-bpi-r4-lite
  DEVICE_DTC_FLAGS := --pad 4096
  DEVICE_DTS_DIR := $(DTS_DIR)/
  DEVICE_DTS_LOADADDR := 0x4ff00000
  DEVICE_PACKAGES := kmod-eeprom-at24 kmod-gpio-pca953x kmod-i2c-mux-pca954x \
		     kmod-rtc-pcf8563 kmod-sfp kmod-usb3 e2fsprogs mkf2fs \
		     mt798x-2p5g-phy-firmware-internal kmod-mt798x-2p5g-phy \
		     blkid kmod-hwmon-pwmfan
  BLOCKSIZE := 128k
  PAGESIZE := 2048
  KERNEL_IN_UBI := 1
  UBOOTENV_IN_UBI := 1
  KERNEL_LOADADDR := 0x40000000
  KERNEL := kernel-bin | gzip
  KERNEL_INITRAMFS := kernel-bin | lzma | \
	fit lzma $$(KDIR)/image-$$(firstword $$(DEVICE_DTS)).dtb with-initrd | pad-to 64k
  IMAGES := sysupgrade.itb
  KERNEL_INITRAMFS_SUFFIX := -recovery.itb
  KERNEL_IN_UBI := 1
  IMAGES := sysupgrade.itb
  IMAGE/sysupgrade.itb := append-kernel | fit gzip $$(KDIR)/image-$$(firstword $$(DEVICE_DTS)).dtb external-with-rootfs | pad-rootfs | append-metadata
ifeq ($(DUMP),)
  IMAGE_SIZE := $$(shell expr 64 + $$(CONFIG_TARGET_ROOTFS_PARTSIZE))m
endif
endef
TARGET_DEVICES += bananapi_bpi-r4-lite

define Device/bananapi_bpi-r4-pro
  DEVICE_MODEL := BPi-R4-Pro-8X
  DEVICE_DTS := mt7988a-bananapi-bpi-r4-pro
  DEVICE_DTS_CONFIG := config-mt7988a-bananapi-bpi-r4-pro
  $(call Device/bananapi_bpi-r4-common)
  UBINIZE_PARTS := fip=:$(STAGING_DIR_IMAGE)/mt7988_bananapi_bpi-r4-pro-snand-u-boot.fip
endef
TARGET_DEVICES += bananapi_bpi-r4-pro
