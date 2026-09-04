#!/bin/sh
# rc-network.sh - BPI-R4 UniFi Network Application autostart
# Run after reboot to restore Network Application

NVME_DATA="/mnt/nvme0n1p3"
NETWORK_DIR="$NVME_DATA/unifi-network"
LAN_BRIDGE="br-lan"

ENP0S3_MAC="00:50:43:ba:d0:02"
ENP0S3_IP="192.168.1.2/24"

if [ ! -f "$NVME_DATA/.unifi-network-setup-done" ]; then
    echo "rc-network.sh: setup not done, skipping"
    exit 0
fi

# Network interface enp0s3
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

# Start Network Application
# Docker bridge forwarding rules are handled by /etc/config/firewall
# (config include docker_wan -> /etc/docker-wan-forward.nft, chain-prepend)
cd $NETWORK_DIR && docker-compose up -d

# Docker daemon auto-restarts containers on boot without respecting depends_on ordering.
# Wait for mongo to be healthy, then restart unifi-network to ensure cloud connection.
timeout 90 sh -c 'until docker exec unifi-db mongo --eval "db.adminCommand(\"ping\")" > /dev/null 2>&1; do sleep 3; done' \
    && docker restart unifi-network \
    || echo "rc-network.sh: mongo wait timed out, unifi-network may lack remote access"
echo "rc-network.sh: done"

exit 0
