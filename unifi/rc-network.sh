#!/bin/sh
# rc-network.sh - BPI-R4 UniFi Network Application autostart
# Run after reboot to restore Network Application

NVME_DATA="/mnt/nvme0n1p3"
NETWORK_DIR="$NVME_DATA/unifi-network"
LAN_BRIDGE="br-lan"

ENP0S3_MAC="00:50:43:ba:d0:02"
ENP0S3_IP="192.168.1.2/24"

# =========================================================
# Check flag - skip if setup not done yet
# =========================================================

if [ ! -f "$NVME_DATA/.unifi-network-setup-done" ]; then
    echo "rc-network.sh: setup not done, skipping"
    exit 0
fi

# =========================================================
# Network interface enp0s3
# =========================================================

modprobe dummy 2>/dev/null || true

if ! ip link show enp0s3 > /dev/null 2>&1; then
    ip link add enp0s3 link $LAN_BRIDGE type macvlan mode bridge
    ip link set enp0s3 address $ENP0S3_MAC
    ip addr add $ENP0S3_IP dev enp0s3
    ip link set enp0s3 up
    echo "rc-network.sh: enp0s3 created"
else
    echo "rc-network.sh: enp0s3 already exists"
fi

# =========================================================
# Start Network Application FIRST
# CRITICAL: Docker must create bridge networks before nft rules are added
# =========================================================

cd $NETWORK_DIR && docker-compose up -d
echo "rc-network.sh: docker-compose up done"

# Wait for Docker to create bridge networks
sleep 10

# =========================================================
# NFT firewall rules for Docker bridge networks
# CRITICAL: Must run AFTER docker-compose up so bridge exists
# =========================================================

if ! nft list ruleset | grep -q 'iifname "br-\*" jump forward_docker'; then

    REJECT_HANDLE=$(nft -a list ruleset | awk '/chain forward.*handle 2/,/^[[:space:]]*}/' | grep "jump handle_reject" | sed 's/.*handle //')

    if [ -n "$REJECT_HANDLE" ]; then
        nft insert rule inet fw4 forward handle $REJECT_HANDLE iifname "br-*" oifname "br-wan" accept
        nft insert rule inet fw4 forward handle $REJECT_HANDLE iifname "br-*" jump forward_docker
        echo "rc-network.sh: nft forward rules added (handle $REJECT_HANDLE)"
    else
        echo "rc-network.sh: WARNING - could not find handle_reject handle!"
    fi

    nft add rule inet fw4 accept_to_docker oifname "br-*" accept
    nft add rule inet fw4 srcnat oifname "br-wan" ip saddr 172.16.0.0/12 masquerade
    echo "rc-network.sh: nft accept + masquerade rules added"

else
    echo "rc-network.sh: nft rules already present, skipping"
fi

exit 0
