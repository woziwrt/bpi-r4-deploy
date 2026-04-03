#!/bin/sh
# install-nvme.sh — BPI-R4 NVMe install script
# Run from nand-rescue system
# Required files in /tmp:
#   - openwrt-mediatek-filogic-bananapi_bpi-r4-squashfs-sysupgrade.itb
#   - openwrt-mediatek-filogic-bananapi_bpi-r4-nvme-img.bin (first install only)

NVME_DEV="/dev/nvme0n1"
ITB="/tmp/openwrt-mediatek-filogic-bananapi_bpi-r4-squashfs-sysupgrade.itb"
IMG="/tmp/openwrt-mediatek-filogic-bananapi_bpi-r4-nvme-img.bin"
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m'

printf "\n"
printf "=================================================\n"
printf "  BPI-R4 NVMe Installer\n"
printf "=================================================\n"
printf "\n"

# || 1. Check sysupgrade.itb ||||||||||||||||||||||||||||||||||||||||||||||||||

printf "[ 1/6 ] Checking sysupgrade image...\n"

if [ ! -f "$ITB" ]; then
    printf "\n"
    printf "${RED}ERROR: Image not found: %s${NC}\n" "$ITB"
    printf "       Copy sysupgrade.itb to /tmp/ and try again.\n"
    printf "\n"
    exit 1
fi

printf "        OK -- found %s\n" "$ITB"
printf "        Size: %s bytes\n" "$(wc -c < "$ITB")"
printf "\n"

# || 2. NVMe device check |||||||||||||||||||||||||||||||||||||||||||||||||||||

printf "[ 2/6 ] Checking NVMe device...\n"

if [ ! -b "$NVME_DEV" ]; then
    printf "\n"
    printf "${RED}ERROR: NVMe disk not found (%s does not exist).${NC}\n" "$NVME_DEV"
    printf "       Check physical connection and reboot.\n"
    printf "\n"
    exit 1
fi

printf "        OK -- found %s\n" "$NVME_DEV"
printf "\n"

# || 3. SMART health check ||||||||||||||||||||||||||||||||||||||||||||||||||||

printf "[ 3/6 ] Checking disk health (SMART)...\n"
printf "\n"

SMART_OUT=$(smartctl -a "$NVME_DEV" 2>/dev/null)

if [ -z "$SMART_OUT" ]; then
    printf "${YELLOW}WARNING: Could not read SMART data -- smartctl failed.${NC}\n"
    printf "         Skipping disk health check.\n"
    printf "\n"
    SMART_SKIP=1
fi

if [ -z "$SMART_SKIP" ]; then

    FAIL=0
    WARN=0

    MODEL=$(echo "$SMART_OUT" | grep "Model Number"       | sed 's/.*: *//')
    SERIAL=$(echo "$SMART_OUT" | grep "Serial Number"     | sed 's/.*: *//')
    CAPACITY=$(echo "$SMART_OUT" | grep "Total NVM Capacity" | sed 's/.*: *//')
    printf "        Disk    : %s\n" "$MODEL"
    printf "        Serial  : %s\n" "$SERIAL"
    printf "        Capacity: %s\n" "$CAPACITY"
    printf "\n"

    HEALTH=$(echo "$SMART_OUT" | grep "SMART overall-health" | grep -o "PASSED\|FAILED")
    if [ "$HEALTH" = "FAILED" ]; then
        printf "${RED}  [FAIL] SMART overall-health: FAILED${NC}\n"
        FAIL=1
    else
        printf "${GREEN}  [ OK ] SMART overall-health: PASSED${NC}\n"
    fi

    CRIT=$(echo "$SMART_OUT" | grep "Critical Warning" | awk '{print $NF}')
    if [ "$CRIT" != "0x00" ] && [ -n "$CRIT" ]; then
        printf "${RED}  [FAIL] Critical Warning: %s${NC}\n" "$CRIT"
        FAIL=1
    else
        printf "${GREEN}  [ OK ] Critical Warning: %s${NC}\n" "$CRIT"
    fi

    SPARE=$(echo "$SMART_OUT" | grep "Available Spare:" | grep -v Threshold | awk '{print $NF}' | tr -d '%')
    if [ -n "$SPARE" ] && [ "$SPARE" -lt 10 ]; then
        printf "${RED}  [FAIL] Available Spare: %s%%${NC}\n" "$SPARE"
        FAIL=1
    else
        printf "${GREEN}  [ OK ] Available Spare: %s%%${NC}\n" "$SPARE"
    fi

    USED=$(echo "$SMART_OUT" | grep "Percentage Used" | awk '{print $NF}' | tr -d '%')
    if [ -n "$USED" ] && [ "$USED" -ge 100 ]; then
        printf "${RED}  [FAIL] Percentage Used: %s%%${NC}\n" "$USED"
        FAIL=1
    else
        printf "${GREEN}  [ OK ] Percentage Used: %s%%${NC}\n" "$USED"
    fi

    MEDIA_ERR=$(echo "$SMART_OUT" | grep "Media and Data Integrity Errors" | awk '{print $NF}')
    if [ -n "$MEDIA_ERR" ] && [ "$MEDIA_ERR" -gt 0 ]; then
        printf "${YELLOW}  [WARN] Media and Data Integrity Errors: %s${NC}\n" "$MEDIA_ERR"
        WARN=1
    else
        printf "${GREEN}  [ OK ] Media and Data Integrity Errors: %s${NC}\n" "$MEDIA_ERR"
    fi

    TEMP=$(echo "$SMART_OUT" | grep "^Temperature:" | awk '{print $2}')
    if [ -n "$TEMP" ] && [ "$TEMP" -ge 70 ]; then
        printf "${YELLOW}  [WARN] Disk temperature: %s C${NC}\n" "$TEMP"
        WARN=1
    else
        printf "${GREEN}  [ OK ] Disk temperature: %s C${NC}\n" "$TEMP"
    fi

    printf "\n"

    if [ "$FAIL" -eq 1 ]; then
        printf "${RED}=================================================${NC}\n"
        printf "${RED}  Disk is not suitable for installation.${NC}\n"
        printf "${RED}=================================================${NC}\n"
        printf "\n"
        exit 1
    fi

    if [ "$WARN" -eq 1 ]; then
        printf "${YELLOW}  Disk has warnings. Continue anyway? [y/N] ${NC}"
        read ANSWER
        case "$ANSWER" in
            y|Y) printf "\n" ;;
            *)
                printf "  Installation cancelled.\n\n"
                exit 1
                ;;
        esac
    else
        printf "${GREEN}  Disk is healthy. Proceeding.${NC}\n"
        printf "\n"
    fi

fi

# || 4. Detect install type |||||||||||||||||||||||||||||||||||||||||||||||||||

printf "[ 4/6 ] Detecting install type...\n"

if [ -b "/dev/nvme0n1p1" ] && [ -b "/dev/nvme0n1p2" ]; then
    mkdir -p /mnt/nvme_check
    if mount -t ext4 /dev/nvme0n1p1 /mnt/nvme_check 2>/dev/null; then
        umount /mnt/nvme_check
        INSTALL_TYPE="update"
        printf "        Existing NVMe layout detected -- UPDATE mode\n"
    else
        INSTALL_TYPE="first"
        printf "        Partitions exist but p1 is not ext4 -- FIRST INSTALL mode\n"
    fi
else
    INSTALL_TYPE="first"
    printf "        No valid layout detected -- FIRST INSTALL mode\n"
fi

if [ "$INSTALL_TYPE" = "first" ] && [ ! -f "$IMG" ]; then
    printf "\n"
    printf "${RED}ERROR: First install requires nvme-img.bin${NC}\n"
    printf "       Copy nvme-img.bin to /tmp/ and try again.\n"
    printf "\n"
    exit 1
fi

printf "\n"

# || 5. Unmount existing partitions ||||||||||||||||||||||||||||||||||||||||||

printf "[ 5/6 ] Unmounting NVMe partitions...\n"

MOUNTED=$(mount | grep "^/dev/nvme0" | awk '{print $1}')
if [ -n "$MOUNTED" ]; then
    for DEV in $MOUNTED; do
        printf "        Unmounting %s...\n" "$DEV"
        umount "$DEV" 2>/dev/null
        if mount | grep -q "^$DEV "; then
            printf "${RED}ERROR: Could not unmount %s.${NC}\n" "$DEV"
            exit 1
        fi
    done
    printf "        OK -- all partitions unmounted\n"
else
    printf "        OK -- no partitions mounted\n"
fi
printf "\n"

# || 6. Write image |||||||||||||||||||||||||||||||||||||||||||||||||||||||||||

printf "[ 6/6 ] Writing image...\n"
printf "\n"
printf "${RED}  WARNING: This will ERASE ALL DATA on %s.${NC}\n" "$NVME_DEV"
printf "\n"
printf "  Are you sure? Type YES to confirm: "
read CONFIRM

if [ "$CONFIRM" != "YES" ]; then
    printf "\n  Installation cancelled.\n\n"
    exit 1
fi

printf "\n"

if [ "$INSTALL_TYPE" = "first" ]; then
    printf "        Writing partition layout (nvme-img.bin)...\n"
    dd if="$IMG" of="$NVME_DEV" bs=1M conv=fsync
    if [ $? -ne 0 ]; then
        printf "\n${RED}ERROR: dd nvme-img.bin failed.${NC}\n\n"
        exit 1
    fi
    sync
    partprobe "$NVME_DEV" 2>/dev/null
    sleep 2
    printf "        OK\n\n"
    printf "        Formatting boot partition (p1 ext4)...\n"
    mkfs.ext4 -F /dev/nvme0n1p1
    printf "\n"
fi

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
    printf "\n${RED}ERROR: dd rootfs failed.${NC}\n\n"
    exit 1
fi
sync
printf "        OK -- rootfs written to p2\n\n"

# || Set nvme_boot env ||||||||||||||||||||||||||||||||||||||||||||||||||||||||

printf "        Setting U-Boot env for NVMe boot...\n"
fw_setenv nvme_boot 1
if [ $? -ne 0 ]; then
    printf "${YELLOW}WARNING: fw_setenv failed -- set nvme_boot manually${NC}\n"
else
    printf "        OK -- nvme_boot=1 set\n"
fi
printf "\n"

printf "${GREEN}=================================================${NC}\n"
printf "${GREEN}  Installation complete!${NC}\n"
printf "${GREEN}=================================================${NC}\n"
printf "\n"

if [ "$INSTALL_TYPE" = "first" ]; then
    printf "  Rebooting into NVMe system...\n\n"
    sleep 2
    reboot
else
    printf "  Rebooting...\n\n"
    sleep 2
    reboot
fi

# NOTE: Future — auto download from GitHub release:
# wget -O /tmp/nvme-img.bin   "https://github.com/.../nvme-img.bin"
# wget -O /tmp/sysupgrade.itb "https://github.com/.../sysupgrade.itb"