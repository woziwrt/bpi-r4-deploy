#!/bin/sh
# install-nvme.sh - BPI-R4 NVMe install script
# Run from NAND rescue system

NVME_DEV="/dev/nvme0n1"
GH_USER="woziwrt"
GH_REPO="bpi-r4-deploy"
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m'

printf "\n"
printf "=================================================\n"
printf "  BPI-R4 NVMe Installer\n"
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
    1) GH_TAG="release-4gb-standard";        ITB_NAME="bpi-r4.itb";     IMG_NAME="openwrt-mediatek-filogic-bananapi_bpi-r4-nvme-img.bin" ;;
    2) GH_TAG="release-4gb-wired";           ITB_NAME="bpi-r4.itb";     IMG_NAME="openwrt-mediatek-filogic-bananapi_bpi-r4-nvme-img.bin" ;;
    3) GH_TAG="release-4gb-poe";             ITB_NAME="bpi-r4-poe.itb"; IMG_NAME="openwrt-mediatek-filogic-bananapi_bpi-r4-poe-nvme-img.bin" ;;
    4) GH_TAG="release-4gb-poe-wired";       ITB_NAME="bpi-r4-poe.itb"; IMG_NAME="openwrt-mediatek-filogic-bananapi_bpi-r4-poe-nvme-img.bin" ;;
    5) GH_TAG="release-8gb-standard";        ITB_NAME="bpi-r4.itb";     IMG_NAME="openwrt-mediatek-filogic-bananapi_bpi-r4-8gb-nvme-img.bin" ;;
    6) GH_TAG="release-8gb-wired";           ITB_NAME="bpi-r4.itb";     IMG_NAME="openwrt-mediatek-filogic-bananapi_bpi-r4-8gb-nvme-img.bin" ;;
    7) GH_TAG="release-8gb-poe";             ITB_NAME="bpi-r4-poe.itb"; IMG_NAME="openwrt-mediatek-filogic-bananapi_bpi-r4-poe-8gb-nvme-img.bin" ;;
    8) GH_TAG="release-8gb-poe-wired";       ITB_NAME="bpi-r4-poe.itb"; IMG_NAME="openwrt-mediatek-filogic-bananapi_bpi-r4-poe-8gb-nvme-img.bin" ;;
    9) GH_TAG="release-8gb-wired-unifi";     ITB_NAME="bpi-r4.itb";     IMG_NAME="openwrt-mediatek-filogic-bananapi_bpi-r4-8gb-nvme-img.bin" ;;
   10) GH_TAG="release-8gb-poe-wired-unifi"; ITB_NAME="bpi-r4-poe.itb"; IMG_NAME="openwrt-mediatek-filogic-bananapi_bpi-r4-poe-8gb-nvme-img.bin" ;;
    *)
        printf "\n${RED}ERROR: Invalid choice!${NC}\n\n"
        exit 1
        ;;
esac

ITB="/tmp/${ITB_NAME}"
IMG="/tmp/${IMG_NAME}"

printf "\n"
printf "  Selected: %s\n" "$GH_TAG"
printf "\n"

# || 1. Check boot media |||||||||||||||||||||||||||||||||||||||||||||||||||||

printf "[ 1/7 ] Checking boot media...\n"

if ! grep -q "ubi" /proc/cmdline; then
    printf "\n${RED}ERROR: Must be run from NAND rescue system!${NC}\n"
    printf "       Current boot is not from NAND/UBI.\n\n"
    exit 1
fi

printf "        OK -- running from NAND rescue\n\n"

# || 2. NVMe device check ||||||||||||||||||||||||||||||||||||||||||||||||||||

printf "[ 2/7 ] Checking NVMe device...\n"

if [ ! -b "$NVME_DEV" ]; then
    printf "\n${RED}ERROR: NVMe disk not found (%s does not exist).${NC}\n" "$NVME_DEV"
    printf "       Check physical connection and reboot.\n\n"
    exit 1
fi

printf "        OK -- found %s\n\n" "$NVME_DEV"

# || 3. SMART health check ||||||||||||||||||||||||||||||||||||||||||||||||||||

printf "[ 3/7 ] Checking disk health (SMART)...\n\n"

SMART_OUT=$(smartctl -a "$NVME_DEV" 2>/dev/null)

if [ -z "$SMART_OUT" ]; then
    printf "${YELLOW}WARNING: Could not read SMART data -- smartctl failed.${NC}\n"
    printf "         Skipping disk health check.\n\n"
    SMART_SKIP=1
fi

if [ -z "$SMART_SKIP" ]; then
    FAIL=0
    WARN=0

    MODEL=$(echo "$SMART_OUT"    | grep "Model Number"       | sed 's/.*: *//')
    SERIAL=$(echo "$SMART_OUT"   | grep "Serial Number"      | sed 's/.*: *//')
    CAPACITY=$(echo "$SMART_OUT" | grep "Total NVM Capacity" | sed 's/.*: *//')
    printf "        Disk    : %s\n" "$MODEL"
    printf "        Serial  : %s\n" "$SERIAL"
    printf "        Capacity: %s\n\n" "$CAPACITY"

    HEALTH=$(echo "$SMART_OUT" | grep "SMART overall-health" | grep -o "PASSED\|FAILED")
    if [ "$HEALTH" = "FAILED" ]; then
        printf "${RED}  [FAIL] SMART overall-health: FAILED${NC}\n"; FAIL=1
    else
        printf "${GREEN}  [ OK ] SMART overall-health: PASSED${NC}\n"
    fi

    CRIT=$(echo "$SMART_OUT" | grep "Critical Warning" | awk '{print $NF}')
    if [ "$CRIT" != "0x00" ] && [ -n "$CRIT" ]; then
        printf "${RED}  [FAIL] Critical Warning: %s${NC}\n" "$CRIT"; FAIL=1
    else
        printf "${GREEN}  [ OK ] Critical Warning: %s${NC}\n" "$CRIT"
    fi

    SPARE=$(echo "$SMART_OUT" | grep "Available Spare:" | grep -v Threshold | awk '{print $NF}' | tr -d '%')
    if [ -n "$SPARE" ] && [ "$SPARE" -lt 10 ]; then
        printf "${RED}  [FAIL] Available Spare: %s%%${NC}\n" "$SPARE"; FAIL=1
    else
        printf "${GREEN}  [ OK ] Available Spare: %s%%${NC}\n" "$SPARE"
    fi

    USED=$(echo "$SMART_OUT" | grep "Percentage Used" | awk '{print $NF}' | tr -d '%')
    if [ -n "$USED" ] && [ "$USED" -ge 100 ]; then
        printf "${RED}  [FAIL] Percentage Used: %s%%${NC}\n" "$USED"; FAIL=1
    else
        printf "${GREEN}  [ OK ] Percentage Used: %s%%${NC}\n" "$USED"
    fi

    MEDIA_ERR=$(echo "$SMART_OUT" | grep "Media and Data Integrity Errors" | awk '{print $NF}')
    if [ -n "$MEDIA_ERR" ] && [ "$MEDIA_ERR" -gt 0 ]; then
        printf "${YELLOW}  [WARN] Media and Data Integrity Errors: %s${NC}\n" "$MEDIA_ERR"; WARN=1
    else
        printf "${GREEN}  [ OK ] Media and Data Integrity Errors: %s${NC}\n" "$MEDIA_ERR"
    fi

    TEMP=$(echo "$SMART_OUT" | grep "^Temperature:" | awk '{print $2}')
    if [ -n "$TEMP" ] && [ "$TEMP" -ge 70 ]; then
        printf "${YELLOW}  [WARN] Disk temperature: %s C${NC}\n" "$TEMP"; WARN=1
    else
        printf "${GREEN}  [ OK ] Disk temperature: %s C${NC}\n" "$TEMP"
    fi

    printf "\n"

    if [ "$FAIL" -eq 1 ]; then
        printf "${RED}=================================================\n"
        printf "  Disk is not suitable for installation.\n"
        printf "=================================================${NC}\n\n"
        exit 1
    fi

    if [ "$WARN" -eq 1 ]; then
        printf "${YELLOW}  Disk has warnings. Continue anyway? [y/N] ${NC}"
        read ANSWER
        case "$ANSWER" in
            y|Y) printf "\n" ;;
            *)   printf "  Installation cancelled.\n\n"; exit 1 ;;
        esac
    else
        printf "${GREEN}  Disk is healthy. Proceeding.${NC}\n\n"
    fi
fi

# || 4. File source ||||||||||||||||||||||||||||||||||||||||||||||||||||||||||

printf "[ 4/7 ] File source...\n\n"
printf "  [1] Download from GitHub (default)\n"
printf "  [2] Use local files from /tmp (development/testing)\n\n"
printf "  Select [1/2]: "
read USE_LOCAL

case "$USE_LOCAL" in
    2)
        printf "\n        INFO: Using local files from /tmp\n"
        printf "        Checking files...\n"
        ITB="/tmp/openwrt-mediatek-filogic-bananapi_bpi-r4-squashfs-sysupgrade.itb"
        IMG="/tmp/openwrt-mediatek-filogic-bananapi_bpi-r4-nvme-img.bin"
        if [ ! -f "$ITB" ]; then
            printf "${RED}ERROR: %s not found!${NC}\n" "$ITB"; exit 1
        fi
        if [ ! -f "$IMG" ]; then
            printf "${RED}ERROR: %s not found!${NC}\n" "$IMG"; exit 1
        fi
        printf "        OK -- both files present\n\n"
        ;;
    *)
        printf "\n  Use default release or your own fork?\n"
        printf "  [1] Default (woziwrt/bpi-r4-deploy)\n"
        printf "  [2] My fork (same repo name, different username)\n\n"
        printf "  Select [1/2]: "
        read USE_FORK

        case "$USE_FORK" in
            2)
                printf "\n        INFO: Fork repo name must remain 'bpi-r4-deploy'\n"
                printf "        Enter your GitHub username: "
                read GH_USER
                ;;
        esac

        BASE_URL="https://github.com/${GH_USER}/${GH_REPO}/releases/download/${GH_TAG}"
        ITB_URL="${BASE_URL}/${ITB_NAME}"
        IMG_URL="${BASE_URL}/${IMG_NAME}"

        printf "        URL: %s\n\n" "$BASE_URL"

        printf "[ 5/7 ] Network check...\n\n"
        printf "        INFO: Internet required (~150 MB download)\n"
        printf "        Is ethernet connected? [yes/no]: "
        read NET_CONFIRM

        if [ "$NET_CONFIRM" != "yes" ]; then
            printf "\n        Connect ethernet and run the script again.\n\n"
            exit 0
        fi

        if ! ping -c 1 -W 3 github.com > /dev/null 2>&1; then
            printf "\n${RED}ERROR: No network connectivity -- check ethernet and try again.${NC}\n\n"
            exit 1
        fi
        printf "        OK -- network available\n\n"

        printf "        Checking release availability...\n"
        HTTP_CODE=$(wget --server-response --spider "$ITB_URL" 2>&1 | grep "HTTP/" | tail -1 | awk '{print $2}')
        if [ "$HTTP_CODE" != "200" ]; then
            printf "\n${RED}ERROR: Release not found on GitHub (tag: %s).\n" "$GH_TAG"
            printf "       The build has not been created yet.\n"
            printf "       Please run the GitHub Actions workflow first:\n"
            printf "       https://github.com/${GH_USER}/${GH_REPO}/actions\n\n${NC}"
            exit 1
        fi
        printf "        OK -- release available\n\n"

        printf "        Downloading %s...\n" "$ITB_NAME"
        wget -O "$ITB" "$ITB_URL"
        if [ $? -ne 0 ] || [ ! -s "$ITB" ]; then
            printf "\n${RED}ERROR: Download of %s failed.${NC}\n\n" "$ITB_NAME"
            rm -f "$ITB"; exit 1
        fi
        printf "        OK -- %s downloaded\n\n" "$ITB_NAME"

        printf "        Downloading %s...\n" "$IMG_NAME"
        wget -O "$IMG" "$IMG_URL"
        if [ $? -ne 0 ] || [ ! -s "$IMG" ]; then
            printf "\n${RED}ERROR: Download of %s failed.${NC}\n\n" "$IMG_NAME"
            rm -f "$ITB" "$IMG"; exit 1
        fi
        printf "        OK -- %s downloaded\n\n" "$IMG_NAME"
        ;;
esac

# || 6. Write image |||||||||||||||||||||||||||||||||||||||||||||||||||||||||||

printf "[ 6/7 ] Writing image...\n\n"
printf "${RED}  WARNING: This will ERASE ALL DATA on %s.${NC}\n\n" "$NVME_DEV"
printf "  Are you sure? Type YES to confirm: "
read CONFIRM

if [ "$CONFIRM" != "YES" ]; then
    printf "\n  Installation cancelled.\n\n"
    rm -f "$ITB" "$IMG"
    exit 1
fi

printf "\n"

MOUNTED=$(mount | grep "^/dev/nvme0" | awk '{print $1}')
if [ -n "$MOUNTED" ]; then
    for DEV in $MOUNTED; do
        umount "$DEV" 2>/dev/null || true
    done
fi

printf "        Writing partition layout (nvme-img.bin)...\n"
dd if="$IMG" of="$NVME_DEV" bs=1M conv=fsync
if [ $? -ne 0 ]; then
    printf "\n${RED}ERROR: dd nvme-img.bin failed.${NC}\n\n"; exit 1
fi
sync
partprobe "$NVME_DEV" 2>/dev/null
sleep 2
printf "        OK\n\n"

printf "        Repartitioning (p1=256MB, p2=512MB, p3=data)...\n"
sgdisk -d 1 -d 2 /dev/nvme0n1
sgdisk -n 1:2048:526335    -t 1:8300 -c 1:boot       /dev/nvme0n1
sgdisk -n 2:526336:1576959 -t 2:FFFF -c 2:production /dev/nvme0n1
partprobe /dev/nvme0n1
sleep 2
printf "        OK\n\n"

printf "        Formatting boot partition (p1 ext4)...\n"
mkfs.ext4 -F /dev/nvme0n1p1
printf "        OK\n\n"

printf "        Writing kernel to p1...\n"
mkdir -p /mnt/nvme
mount /dev/nvme0n1p1 /mnt/nvme
cp "$ITB" /mnt/nvme/bpi-r4.itb
sync
umount /dev/nvme0n1p1
printf "        OK -- kernel written to p1\n\n"

printf "        Writing rootfs to p2 (raw FIT)...\n"
dd if="$ITB" of=/dev/nvme0n1p2 bs=1M conv=fsync
if [ $? -ne 0 ]; then
    printf "\n${RED}ERROR: dd rootfs failed.${NC}\n\n"; exit 1
fi
sync
printf "        OK -- rootfs written to p2\n\n"

printf "        Creating data partition (p3)...\n"
sgdisk -e /dev/nvme0n1
sgdisk -n 3:0:0 -t 3:8300 -c 3:data /dev/nvme0n1
partprobe /dev/nvme0n1
sleep 2
umount /dev/nvme0n1p3 2>/dev/null || true
mkfs.ext4 -F -L data /dev/nvme0n1p3
printf "        OK -- p3 data partition created\n\n"

rm -f "$ITB" "$IMG"

# || 7. Finalize |||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||

printf "[ 7/7 ] Finalizing...\n\n"

printf "        Setting U-Boot env for NVMe boot...\n"
fw_setenv nvme_boot 1
if [ $? -ne 0 ]; then
    printf "${YELLOW}WARNING: fw_setenv failed -- set nvme_boot manually${NC}\n"
else
    printf "        OK -- nvme_boot=1 set\n"
fi
printf "\n"

printf "${GREEN}=================================================\n"
printf "  Installation complete! Rebooting...\n"
printf "=================================================${NC}\n\n"
sleep 2
reboot
