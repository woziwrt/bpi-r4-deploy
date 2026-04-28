#!/bin/sh
# unifi-network-setup-8gb.sh - BPI-R4 UniFi Network Application setup (8GB variant)
# Run after unifi-setup.sh (Protect) has completed successfully
# Requires: Protect running, NVMe mounted, internet available

NVME_DATA="/mnt/nvme0n1p3"
NETWORK_DIR="$NVME_DATA/unifi-network"
GH_USER="woziwrt"
GH_REPO="bpi-r4-deploy"

ENP0S3_MAC="00:50:43:ba:d0:02"
ENP0S3_IP="192.168.1.2/24"
LAN_BRIDGE="br-lan"

RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m'

printf "\n"
printf "=================================================\n"
printf "  BPI-R4 UniFi Network Application Setup (8GB)\n"
printf "=================================================\n"
printf "\n"

# || 1. Check prerequisites |||||||||||||||||||||||||||||||||||||||||||||||||

printf "[ 1/7 ] Checking prerequisites...\n"

if [ ! -f "$NVME_DATA/.unifi-setup-done" ]; then
    printf "${RED}ERROR: Protect setup not completed!${NC}\n"
    printf "       Run unifi-setup.sh first.\n\n"
    exit 1
fi

if ! docker ps | grep -q "unifi-protect"; then
    printf "${YELLOW}WARNING: unifi-protect container is not running.${NC}\n"
    printf "         Continue anyway? [y/N]: "
    read ANS
    case "$ANS" in
        y|Y) ;;
        *) exit 1 ;;
    esac
fi

printf "        OK\n\n"

# || 2. uhttpd - move LuCI to port 8081 ||||||||||||||||||||||||||||||||||||

printf "[ 2/7 ] Moving LuCI to port 8081 (freeing 8080 for Network Application)...\n"

uci set uhttpd.main.listen_http='0.0.0.0:8081'
uci set uhttpd.main.listen_https='0.0.0.0:8444'
uci commit uhttpd
/etc/init.d/uhttpd restart

printf "        OK -- LuCI moved to port 8081\n\n"

# || 3. Network interface enp0s3 |||||||||||||||||||||||||||||||||||||||||||

printf "[ 3/7 ] Setting up network interface enp0s3 (macvlan)...\n"

modprobe dummy

if ip link show enp0s3 > /dev/null 2>&1; then
    ip link del enp0s3 2>/dev/null || true
fi

ip link add enp0s3 link $LAN_BRIDGE type macvlan mode bridge
ip link set enp0s3 address $ENP0S3_MAC
ip addr add $ENP0S3_IP dev enp0s3
ip link set enp0s3 up

printf "        OK -- enp0s3 up at 192.168.1.2\n\n"

# || 4. NFT firewall rules |||||||||||||||||||||||||||||||||||||||||||||||||

printf "[ 4/7 ] Configuring nftables firewall rules for Docker bridge networks...\n"

REJECT_HANDLE=$(nft -a list ruleset | awk '/chain forward.*handle 2/,/^[[:space:]]*}/' | grep "jump handle_reject" | sed 's/.*handle //')
if [ -z "$REJECT_HANDLE" ]; then
    printf "${YELLOW}WARNING: Could not find handle_reject handle, adding rules at end${NC}\n"
    nft add rule inet fw4 forward iifname "br-*" jump forward_docker
    nft add rule inet fw4 forward iifname "br-*" oifname "br-wan" accept
else
    nft insert rule inet fw4 forward handle $REJECT_HANDLE iifname "br-*" oifname "br-wan" accept
    nft insert rule inet fw4 forward handle $REJECT_HANDLE iifname "br-*" jump forward_docker
fi

nft add rule inet fw4 accept_to_docker oifname "br-*" accept
nft add rule inet fw4 srcnat oifname "br-wan" ip saddr 172.16.0.0/12 masquerade

printf "        OK -- nftables rules added\n\n"

# || 5. Swap file |||||||||||||||||||||||||||||||||||||||||||||||||||||||||||

printf "[ 5/7 ] Creating swap file (2GB on p3)...\n"

if [ ! -f "$NVME_DATA/swapfile" ]; then
    dd if=/dev/zero of=$NVME_DATA/swapfile bs=1M count=2048
    chmod 600 $NVME_DATA/swapfile
    mkswap $NVME_DATA/swapfile
fi

swapon $NVME_DATA/swapfile 2>/dev/null || true

# Add to rc.local for persistence
if ! grep -q "swapfile" /etc/rc.local 2>/dev/null; then
    echo "swapon $NVME_DATA/swapfile" >> /etc/rc.local
fi

printf "        OK -- swap active\n\n"

# || 6. Storage structure + config files |||||||||||||||||||||||||||||||||||

printf "[ 6/7 ] Creating storage structure and configuration...\n"

mkdir -p $NETWORK_DIR/db
mkdir -p $NETWORK_DIR/config/data

# init-mongo.js
cat > $NETWORK_DIR/init-mongo.js << 'EOF'
db.getSiblingDB("admin").createUser({user: "unifi", pwd: "unifipass", roles: [{role: "root", db: "admin"}]});
db.getSiblingDB("unifi").createUser({user: "unifi", pwd: "unifipass", roles: [{role: "dbOwner", db: "unifi"}]});
db.getSiblingDB("unifi_stat").createUser({user: "unifi", pwd: "unifipass", roles: [{role: "dbOwner", db: "unifi_stat"}]});
EOF

# system.properties
cat > $NETWORK_DIR/config/data/system.properties << 'EOF'
db.mongo.uri=mongodb://unifi:unifipass@unifi-db:27017/unifi?authSource=admin
db.mongo.uri.unifi_stat=mongodb://unifi:unifipass@unifi-db:27017/unifi_stat?authSource=admin
EOF

# docker-compose.yml - 8GB optimized
# MEM_LIMIT/MEM_STARTUP: Java heap limits via linuxserver env vars
# mem_limit: container memory hard limit
# --wiredTigerCacheSizeGB: MongoDB cache limit (default is 50% of RAM = 4GB on 8GB system)
cat > $NETWORK_DIR/docker-compose.yml << 'EOF'
services:
  unifi-network:
    image: lscr.io/linuxserver/unifi-network-application:latest
    container_name: unifi-network
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=Europe/Prague
      - MONGO_USER=unifi
      - MONGO_PASS=unifipass
      - MONGO_HOST=unifi-db
      - MONGO_PORT=27017
      - MONGO_DBNAME=unifi
      - MONGO_AUTHSOURCE=admin
      - MEM_LIMIT=2048
      - MEM_STARTUP=512
    volumes:
      - /mnt/nvme0n1p3/unifi-network/config:/config
    ports:
      - 8443:8443
      - 3478:3478/udp
      - 8080:8080
    depends_on:
      unifi-db:
        condition: service_healthy
    restart: unless-stopped
    mem_limit: 2g
  unifi-db:
    image: mongo:4.4.18
    container_name: unifi-db
    command: mongod --bind_ip_all --wiredTigerCacheSizeGB 0.25
    environment:
      - MONGO_INITDB_ROOT_USERNAME=root
      - MONGO_INITDB_ROOT_PASSWORD=rootpass
    volumes:
      - /mnt/nvme0n1p3/unifi-network/db:/data/db
      - /mnt/nvme0n1p3/unifi-network/init-mongo.js:/docker-entrypoint-initdb.d/init-mongo.js:ro
    healthcheck:
      test: ["CMD", "mongo", "--eval", "db.adminCommand('ping')"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 30s
    restart: unless-stopped
    mem_limit: 1g
EOF

printf "        OK\n\n"

# || 7. Start Network Application ||||||||||||||||||||||||||||||||||||||||||

printf "[ 7/7 ] Starting UniFi Network Application...\n\n"

cd $NETWORK_DIR && docker-compose up -d

sleep 10

if docker ps | grep -q "unifi-network"; then
    printf "        OK -- containers running\n\n"
else
    printf "${RED}ERROR: Containers failed to start. Check: docker-compose logs${NC}\n\n"
    exit 1
fi

touch "$NVME_DATA/.unifi-network-setup-done"

printf "${GREEN}=================================================${NC}\n"
printf "${GREEN}  UniFi Network Application Setup complete! (8GB)${NC}\n"
printf "${GREEN}=================================================${NC}\n"
printf "\n"
printf "  UniFi Network Application : https://192.168.1.2:8443\n"
printf "  UniFi Protect             : https://192.168.1.1\n"
printf "  LuCI                      : http://192.168.1.1:8081\n"
printf "\n"
printf "${YELLOW}  IMPORTANT: Disable auto-update after first login!${NC}\n"
printf "  Settings -> Auto Update -> disable all\n"
printf "\n"
printf "${YELLOW}  NOTE: UDP 10001 (device discovery) is shared with Protect.${NC}\n"
printf "  For AP adoption use SSH set-inform or adopt via Protect WebUI.\n"
printf "\n"
