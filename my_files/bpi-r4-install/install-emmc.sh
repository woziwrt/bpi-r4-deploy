#!/bin/sh
# install-emmc.sh — Install OpenWrt to eMMC
# Must be run from NAND rescue system only!

EMMC_IMG="/tmp/emmc-img.bin"
EMMC_DEV="/dev/mmcblk0"
EMMC_BOOT="/dev/mmcblk0boot0"
GH_USER="woziwrt"
GH_REPO="bpi-r4-rescue"
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

printf "\n"
printf "=================================================\n"
printf "  BPI-R4 eMMC Installer\n"
printf "=================================================\n"
printf "\n"

# || 1. Check boot media |||||||||||||||||||||||||||||||||||||||||||||||||||||

printf "[ 1/7 ] Checking boot media...\n"

if ! grep -q "ubi" /proc/cmdline; then
    printf "\n"
    printf "${RED}ERROR: Must be run from NAND rescue system!${NC}\n"
    printf "       Current boot is not from NAND/UBI.\n"
    printf "\n"
    exit 1
fi

printf "        OK -- running from NAND rescue\n"
printf "\n"

# || 2. Check eMMC device ||||||||||||||||||||||||||||||||||||||||||||||||||||

printf "[ 2/7 ] Checking eMMC device...\n"

if [ ! -b "$EMMC_DEV" ]; then
    printf "\n"
    printf "${RED}ERROR: eMMC not found (%s does not exist).${NC}\n" "$EMMC_DEV"
    printf "       Check hardware and reboot.\n"
    printf "\n"
    exit 1
fi

if [ ! -b "$EMMC_BOOT" ]; then
    printf "\n"
    printf "${RED}ERROR: %s not found -- this may be SD card, not eMMC!${NC}\n" "$EMMC_BOOT"
    printf "       Make sure eMMC is installed and detected.\n"
    printf "\n"
    exit 1
fi

printf "        OK -- found %s (eMMC confirmed via %s)\n" "$EMMC_DEV" "$EMMC_BOOT"
printf "\n"

# || 3. Release source |||||||||||||||||||||||||||||||||||||||||||||||||||||||

printf "[ 3/7 ] Release source...\n"
printf "\n"
printf "  Use default release or your own fork?\n"
printf "  [1] Default (woziwrt/bpi-r4-rescue)\n"
printf "  [2] My fork (same repo name, different username)\n"
printf "\n"
printf "  Select [1/2]: "
read USE_FORK

case "$USE_FORK" in
    2)
        printf "\n"
        printf "        INFO: Fork repo name must remain 'bpi-r4-rescue'\n"
        printf "        Enter your GitHub username: "
        read GH_USER
        ;;
    *)
        ;;
esac

EMMC_IMG_URL="https://github.com/${GH_USER}/${GH_REPO}/releases/download/rescue-latest/openwrt-mediatek-filogic-bananapi_bpi-r4-emmc-img.bin"
printf "        URL: %s\n" "$EMMC_IMG_URL"
printf "\n"

# || 4. Network check ||||||||||||||||||||||||||||||||||||||||||||||||||||||||

printf "[ 4/7 ] Network check...\n"
printf "\n"
printf "        INFO: Internet required (~103 MB download)\n"
printf "        Is ethernet connected? [yes/no]: "
read NET_CONFIRM

if [ "$NET_CONFIRM" != "yes" ]; then
    printf "\n        Connect ethernet and run the script again.\n\n"
    exit 0
fi

if ! ping -c 1 -W 3 github.com > /dev/null 2>&1; then
    printf "\n"
    printf "${RED}ERROR: No network connectivity -- check ethernet and try again.${NC}\n"
    printf "\n"
    exit 1
fi

printf "        OK -- network available\n"
printf "\n"

# || 5. Download emmc-img.bin ||||||||||||||||||||||||||||||||||||||||||||||||

printf "[ 5/7 ] Downloading emmc-img.bin (~103 MB)...\n"
printf "\n"

wget -O "$EMMC_IMG" "$EMMC_IMG_URL"

if [ $? -ne 0 ] || [ ! -s "$EMMC_IMG" ]; then
    printf "\n"
    printf "${RED}ERROR: Download failed.${NC}\n"
    printf "       Check network or URL and try again.\n"
    printf "\n"
    rm -f "$EMMC_IMG"
    exit 1
fi

printf "\n        OK -- downloaded\n"
printf "\n"

# || 6. Confirm and write ||||||||||||||||||||||||||||||||||||||||||||||||||||

printf "[ 6/7 ] Writing image...\n"
printf "\n"
printf "${RED}  WARNING: This will ERASE ALL DATA on %s.${NC}\n" "$EMMC_DEV"
printf "\n"
printf "  Are you sure? Type YES to confirm: "
read CONFIRM

if [ "$CONFIRM" != "YES" ]; then
    printf "\n  Installation cancelled.\n\n"
    rm -f "$EMMC_IMG"
    exit 1
fi

printf "\n"
printf "        Writing image to %s...\n" "$EMMC_DEV"
dd if="$EMMC_IMG" of="$EMMC_DEV" bs=1M conv=fsync
if [ $? -ne 0 ]; then
    printf "\n${RED}ERROR: dd failed.${NC}\n\n"
    rm -f "$EMMC_IMG"
    exit 1
fi
sync
printf "        OK -- image written\n\n"

printf "        Writing BL2 to boot partition...\n"
echo 0 > /sys/block/mmcblk0boot0/force_ro
dd if="$EMMC_IMG" of="$EMMC_BOOT" bs=512 skip=34 count=512 conv=fsync
sync
printf "        OK -- BL2 written\n\n"

# || 7. Set boot partition + cleanup |||||||||||||||||||||||||||||||||||||||||

printf "[ 7/7 ] Finalizing...\n"

mmc bootpart enable 1 1 "$EMMC_DEV"
printf "        OK -- eMMC boot partition set\n"

rm -f "$EMMC_IMG"
printf "        OK -- cleanup done\n"
printf "\n"

printf "${GREEN}=================================================${NC}\n"
printf "${GREEN}  Installation complete!${NC}\n"
printf "${GREEN}=================================================${NC}\n"
printf "\n"
printf "  Next steps:\n"
printf "  1. Power off the device\n"
printf "  2. Set DIP switch: SW3-A=1, SW3-B=0 (eMMC boot)\n"
printf "  3. Power on\n"
printf "\n"