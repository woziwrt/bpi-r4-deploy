#!/bin/sh
# install-emmc.sh - Install OpenWrt to eMMC
# Must be run from NAND rescue system only!

EMMC_DEV="/dev/mmcblk0"
EMMC_BOOT="/dev/mmcblk0boot0"
GH_USER="woziwrt"
GH_REPO="bpi-r4-deploy"
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

printf "\n"
printf "=================================================\n"
printf "  BPI-R4 eMMC Installer\n"
printf "=================================================\n"
printf "\n"

# || 0. Variant selection |||||||||||||||||||||||||||||||||||||||||||||||||||||

printf "Select your board variant:\n"
printf "\n"
printf "  1) 4GB standard (WiFi)\n"
printf "  2) 4GB wired (no WiFi)\n"
printf "  3) 4GB PoE (WiFi)\n"
printf "  4) 4GB PoE wired (no WiFi)\n"
printf "  5) 8GB standard (WiFi)\n"
printf "  6) 8GB wired (no WiFi)\n"
printf "  7) 8GB PoE (WiFi)\n"
printf "  8) 8GB PoE wired (no WiFi)\n"
printf "  9) 8GB wired UniFi\n"
printf " 10) 8GB PoE wired UniFi\n"
printf "\n"
printf "Enter choice [1-10]: "
read VARIANT

case "$VARIANT" in
    1) GH_TAG="release-4gb-standard";        EMMC_NAME="openwrt-mediatek-filogic-bananapi_bpi-r4-emmc-img.bin" ;;
    2) GH_TAG="release-4gb-wired";           EMMC_NAME="openwrt-mediatek-filogic-bananapi_bpi-r4-emmc-img.bin" ;;
    3) GH_TAG="release-4gb-poe";             EMMC_NAME="openwrt-mediatek-filogic-bananapi_bpi-r4-poe-emmc-img.bin" ;;
    4) GH_TAG="release-4gb-poe-wired";       EMMC_NAME="openwrt-mediatek-filogic-bananapi_bpi-r4-poe-emmc-img.bin" ;;
    5) GH_TAG="release-8gb-standard";        EMMC_NAME="openwrt-mediatek-filogic-bananapi_bpi-r4-8gb-emmc-img.bin" ;;
    6) GH_TAG="release-8gb-wired";           EMMC_NAME="openwrt-mediatek-filogic-bananapi_bpi-r4-8gb-emmc-img.bin" ;;
    7) GH_TAG="release-8gb-poe";             EMMC_NAME="openwrt-mediatek-filogic-bananapi_bpi-r4-poe-8gb-emmc-img.bin" ;;
    8) GH_TAG="release-8gb-poe-wired";       EMMC_NAME="openwrt-mediatek-filogic-bananapi_bpi-r4-poe-8gb-emmc-img.bin" ;;
    9) GH_TAG="release-8gb-wired-unifi";     EMMC_NAME="openwrt-mediatek-filogic-bananapi_bpi-r4-8gb-emmc-img.bin" ;;
   10) GH_TAG="release-8gb-poe-wired-unifi"; EMMC_NAME="openwrt-mediatek-filogic-bananapi_bpi-r4-poe-8gb-emmc-img.bin" ;;
    *)
        printf "\n${RED}ERROR: Invalid choice!${NC}\n\n"
        exit 1
        ;;
esac

EMMC_IMG="/tmp/${EMMC_NAME}"

printf "\n"
printf "  Selected: %s\n" "$GH_TAG"
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

# || 3. File source ||||||||||||||||||||||||||||||||||||||||||||||||||||||||||

printf "[ 3/7 ] File source...\n"
printf "\n"
printf "  [1] Download from GitHub (default)\n"
printf "  [2] Use local files from /tmp (development/testing)\n"
printf "\n"
printf "  Select [1/2]: "
read USE_LOCAL

case "$USE_LOCAL" in
    2)
        printf "\n"
        printf "        INFO: Using local files from /tmp\n"
        printf "        Checking files...\n"
        EMMC_IMG="/tmp/openwrt-mediatek-filogic-bananapi_bpi-r4-emmc-img.bin"
        if [ ! -f "$EMMC_IMG" ]; then
            printf "${RED}ERROR: %s not found!${NC}\n" "$EMMC_IMG"
            exit 1
        fi
        printf "        OK -- file present\n\n"
        ;;
    *)
        printf "\n"
        printf "  Use default release or your own fork?\n"
        printf "  [1] Default (woziwrt/bpi-r4-deploy)\n"
        printf "  [2] My fork (same repo name, different username)\n"
        printf "\n"
        printf "  Select [1/2]: "
        read USE_FORK

        case "$USE_FORK" in
            2)
                printf "\n"
                printf "        INFO: Fork repo name must remain 'bpi-r4-deploy'\n"
                printf "        Enter your GitHub username: "
                read GH_USER
                ;;
            *)
                ;;
        esac

        EMMC_IMG_URL="https://github.com/${GH_USER}/${GH_REPO}/releases/download/${GH_TAG}/${EMMC_NAME}"
        printf "        URL: %s\n\n" "$EMMC_IMG_URL"

        # || 4. Network check ||||||||||||||||||||||||||||||||||||||||||||||||

        printf "[ 4/7 ] Network check...\n"
        printf "\n"
        printf "        INFO: Internet required (~154 MB download)\n"
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

        printf "        OK -- network available\n\n"

        printf "        Checking release availability...\n"
        HTTP_CODE=$(wget --server-response --spider "$EMMC_IMG_URL" 2>&1 | grep "HTTP/" | tail -1 | awk '{print $2}')
        if [ "$HTTP_CODE" != "200" ]; then
            printf "\n${RED}ERROR: Release not found on GitHub (tag: %s).\n" "$GH_TAG"
            printf "       The build has not been created yet.\n"
            printf "       Please run the GitHub Actions workflow first:\n"
            printf "       https://github.com/${GH_USER}/${GH_REPO}/actions\n\n${NC}"
            exit 1
        fi
        printf "        OK -- release available\n\n"

        # || 5. Download emmc-img.bin ||||||||||||||||||||||||||||||||||||||||

        printf "[ 5/7 ] Downloading %s...\n\n" "$EMMC_NAME"

        wget -O "$EMMC_IMG" "$EMMC_IMG_URL"

        if [ $? -ne 0 ] || [ ! -s "$EMMC_IMG" ]; then
            printf "\n${RED}ERROR: Download failed.${NC}\n"
            printf "       Check network or URL and try again.\n\n"
            rm -f "$EMMC_IMG"
            exit 1
        fi

        printf "\n        OK -- downloaded\n\n"
        ;;
esac

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
