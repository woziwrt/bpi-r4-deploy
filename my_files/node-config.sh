#!/bin/sh
# easymesh-r6 — node role + management/mesh split, run ON a freshly-flashed
# BPI-R4 (default 192.168.1.1). Works for BOTH classic BPI-R4 and Pro-8X.
#
# Splits the box into two isolated worlds (decided 2026-07-11, ADR 0008), to
# avoid BOTH a bridge loop AND a chicken-and-egg management path:
#   - MGMT port → standalone `lan_3` interface = MANAGEMENT (192.168.1.x)
#   - br-lan (WiFi + remaining LAN ports) = MESH / data (10.10.10.x)
# Management is a different bridge/subnet than the WiFi we tune, so:
#   * no shared L2 between ethernet and WiFi backhaul → no broadcast-storm loop
#   * SSH rides MGMT, independent of the mesh → re-tuning WiFi never locks you out
#
# Usage (on the node, over its default 192.168.1.1):
#   sh node-config.sh controller bpi-4g 192.168.1.1
#   sh node-config.sh agent      bpi-8g 192.168.1.3
#   sh node-config.sh agent      bpi-x8 192.168.1.2            # Pro-8X, AL-MAC auto
#   sh node-config.sh agent      bpi-x8 192.168.1.2 aa:bb:cc:dd:ee:ff  # explicit AL-MAC
# The mesh IP is derived automatically: 10.10.10.<last octet of the mgmt IP>.
#
# ONE image, per-node identity applied here → scales to N nodes (incl. multiple
# Pro-8X). Replaces the old baked 999-x8-identity (single fixed identity → could
# not scale to two Pro-8X, and duplicated the agent-role recipe → autostart drift).
#
# IMPORTANT: the switch/Mac cable must go to the node's MGMT port —
# classic = LAN3, Pro-8X = mxl_lan0. See docs/lab-nodes.md and docs/adr/0008-*.md.

set -e
ROLE="$1"
HOSTNAME="$2"
MGMT_IP="$3"
AL_MAC_OVERRIDE="$4"   # optional; only consulted on Pro-8X (empty HW label)

[ -n "$HOSTNAME" ] && [ -n "$MGMT_IP" ] || {
  echo "usage: sh node-config.sh {controller|agent} <hostname> <mgmt-ip> [al-mac]"
  echo "  e.g. sh node-config.sh controller bpi-4g 192.168.1.1"
  echo "       sh node-config.sh agent      bpi-8g 192.168.1.3"
  echo "       sh node-config.sh agent      bpi-x8 192.168.1.2   # Pro-8X"
  exit 1
}
MESH_IP="10.10.10.${MGMT_IP##*.}"   # mesh subnet, same last octet as mgmt

# --- board detection: which port is MANAGEMENT? ---
# Classic BPI-R4 = lan3. Pro-8X uses an MxL862xx DSA switch → mxl_lan0. The board
# bridge itself (all mxl_lan* + eth3, wan=eth1, board.json) is set up separately,
# role-independent, by the 99-pro-8x-network uci-default; here we only carve the
# MGMT port out of br-lan and give it its own subnet.
if [ -e /sys/class/net/mxl_lan0 ]; then
  BOARD='pro-8x'; MGMT_PORT='mxl_lan0'
else
  BOARD='classic'; MGMT_PORT='lan3'
fi

# --- lab-fixed WiFi backhaul (MAP--BH) — deterministic across flashes ---
# The iopsys per-device default backhaul key is RANDOM (controller f8ec31d…,
# agent 67192… — different), which is why the working bSTA config was
# un-reproducible "keep-config mystery" state that a clean `-n` flash destroyed.
# Fix the backhaul BSS creds lab-wide so the controller advertises a known key
# and the agent can pre-seed its bSTA declaratively (no WPS/DPP, no mystery).
LAB_BH_SSID='MAP--BH'
LAB_BH_ENC='sae'
LAB_BH_KEY='f8ec31d777aca27ab62e37c5907223db2d710fef66a7c062cbd71cfaad91e77'

# hostname
uci set system.@system[0].hostname="$HOSTNAME"
uci commit system

# --- stable ieee1905 AL-MAC (Pro-8X only) ---
# Classic derives its AL-MAC from the HW label (get_mac_label) → already stable
# and per-unit unique. Pro-8X has an EMPTY label → 30-set-ieee1905-al-macaddr
# bails and the demon picks a RANDOM AL-MAC at each boot → every `-n`/`-F` flash
# changes the node's 1905 identity and leaves a GHOST in the controller/mapc.db
# (num_nodes grows). Derive a stable one from a real HW MAC instead (per-unit
# unique, survives flashes) — the scalable replacement for the old baked value.
if [ "$BOARD" = pro-8x ]; then
  AL_MAC="$AL_MAC_OVERRIDE"
  if [ -z "$AL_MAC" ]; then
    for _i in eth0 eth1 eth2 mxl_lan0 mxl_lan1; do
      _m=$(cat "/sys/class/net/$_i/address" 2>/dev/null || true)
      case "$_m" in ""|"00:00:00:00:00:00"|"ff:ff:ff:ff:ff:ff") ;; *) AL_MAC="$_m"; break ;; esac
    done
  fi
  [ -n "$AL_MAC" ] || {
    echo "FATAL: Pro-8X has no usable HW MAC for a stable 1905 AL-MAC and none given."
    echo "  Re-run with an explicit AL-MAC as the 4th arg:"
    echo "  sh node-config.sh $ROLE $HOSTNAME $MGMT_IP aa:bb:cc:dd:ee:ff"
    exit 1
  }
  uci set ieee1905.ieee1905.macaddress="$AL_MAC"
  uci commit ieee1905
  echo "Pro-8X: stable 1905 AL-MAC = $AL_MAC"
fi

# --- management / mesh split (ADR 0008) ---
# 1) pull the MGMT port out of the br-lan bridge
uci del_list network.@device[0].ports="$MGMT_PORT" 2>/dev/null || true
# 2) standalone MANAGEMENT interface on the MGMT port.
#    NOTE: always set netmask — without it lan ends up /32 (isolated host,
#    reachable on console but dead from the network). Bit us on 8g 2026-07-11.
uci set network.lan_3=interface
uci set network.lan_3.device="$MGMT_PORT"
uci set network.lan_3.proto='static'
uci set network.lan_3.ipaddr="$MGMT_IP"
uci set network.lan_3.netmask='255.255.255.0'
# 3) br-lan (WiFi + remaining ports) → MESH subnet
uci set network.lan.ipaddr="$MESH_IP"
uci set network.lan.netmask='255.255.255.0'
uci commit network
# 4) firewall: put the management interface into the lan zone ATOMICALLY, in the
#    same commit as the split — before the network/firewall restart. If you add it
#    AFTER, the fresh lan_3 is rejected (ICMP "port unreachable") and you lock
#    yourself out. That is exactly what forced a console rescue on 8g 2026-07-11.
#    @zone[0] is 'lan' on the stock image (verified); adjust if that ever changes.
uci add_list firewall.@zone[0].network='lan_3'
uci commit firewall

case "$ROLE" in
  controller)
    # --- DHCP: controller adresy rozdava (jediny v siti) ---
    # Explicitne, ne spolehnutim na default: agenti si to vypinaji ve sve vetvi a
    # politika ma byt videt na obou stranach, ne jen na jedne.
    # Explicitni 0, ne delete: 98-mesh-dhcp-safe nastavuje bezpecny default
    # jen kdyz hodnota NEEXISTUJE, takze smazani by ji pri pristim keep-config
    # upgradu nechalo znovu prepnout na 1 a controller by prestal rozdavat adresy.
    uci set dhcp.lan.ignore='0'
    uci commit dhcp

    # keep both mapcontroller + mapagent (collocated controller)
    /etc/init.d/mapcontroller enable
    /etc/init.d/mapagent enable
    # deterministic backhaul BSS creds so agents can pre-seed their bSTA (see above)
    for b in 2g 5g; do
        uci set mapcontroller.ap_bh_${b}.ssid="$LAB_BH_SSID"
        uci set mapcontroller.ap_bh_${b}.encryption="$LAB_BH_ENC"
        uci set mapcontroller.ap_bh_${b}.key="$LAB_BH_KEY"
    done
    uci commit mapcontroller
    # --- fronthaul AP-MLD config-model bridge: make wifimngr publish wifi.apmld ---
    # The base image declares the fronthaul AP-MLD natively (config wifi-iface 'ap_mld_1',
    # device='radio0 radio1 radio2', mlo=1) and it runs on RF (hostapd ap-mld-1). BUT
    # wifimngr only creates the `wifi.apmld.<ifname>` ubus object for a `config wifi-mld`
    # section (wifimngr.c:6238 loop over num_wifi_mld; uci_get_wifi_mlds() at uci.c:471
    # counts ONLY section type 'wifi-mld'). Without it num_wifi_mld=0 → no wifi.apmld →
    # iopsys map-agent's num_ap_mld=0 → it never emits the AP-MLD Config TLV (0xE0) →
    # controller apmld/affiliated_ap/ttlm stay empty. Declaring this section bridges the
    # iopsys datamodel onto our native MLD netdev; netifd ignores unknown section types so
    # RF is untouched. ifname MUST be the real MLD netdev; mode 'ap' is mandatory (an
    # unknown mode aborts object creation with EINVAL, wifimngr ubus.c:604).
    uci set wireless.mld0='wifi-mld'
    uci set wireless.mld0.ifname='ap-mld-1'
    uci set wireless.mld0.mode='ap'
    uci commit wireless
    # --- map-agent MLD credential: make the (colocated) agent emit AP-MLD Config TLV (0xE0) ---
    # The agent queries wifi.apmld.<ifname> (→ fills num_ap_mld → emits 0xE0 → controller persists
    # apmld/affiliated_ap/ttlm) ONLY when its OWN config declares a `config mld` credential AND each
    # per-band fronthaul @ap carries option mld_id matching it (map-agent agent.c:4356-4364 gate on
    # cfg->mldlist + f->mld_id). Base config has neither → num_ap_mld=0 → no 0xE0. Declare the
    # fronthaul AP-MLD (ap-mld-1, tri-band) and tag every fronthaul AP with mld_id=1. Keyed by
    # type=fronthaul, NOT index (anonymous @ap indices are fragile across config regen).
    uci -q delete mapagent.apmld0
    uci set mapagent.apmld0=mld
    uci set mapagent.apmld0.id='1'
    uci set mapagent.apmld0.ifname='ap-mld-1'
    uci set mapagent.apmld0.type='fronthaul'
    uci set mapagent.apmld0.ssid='MT76_AP_MLD'
    uci set mapagent.apmld0.encryption='sae-mixed'
    uci add_list mapagent.apmld0.band='2'
    uci add_list mapagent.apmld0.band='5'
    uci add_list mapagent.apmld0.band='6'
    i=0
    while uci -q get "mapagent.@ap[$i]" >/dev/null 2>&1; do
        [ "$(uci -q get "mapagent.@ap[$i].type")" = "fronthaul" ] && uci set "mapagent.@ap[$i].mld_id=1"
        i=$((i+1))
    done
    uci commit mapagent
    echo "controller '$HOSTNAME' ($BOARD): mgmt $MGMT_IP ($MGMT_PORT) / mesh $MESH_IP (br-lan). Rebooting..."
    ;;
  agent)
    # --- DHCP: agent NESMI rozdavat adresy ---
    # Mesh je jedna L2 domena (br-lan premostena pres backhaul), takze druhy DHCP
    # server na nem odpovi klientovi driv nez controller a vnuti mu SAM SEBE jako
    # default gateway. Agent nikam nerouti -> klient ma adresu, asociaci i signal,
    # ale ZADNY internet, a vypada to jako vada radia.
    # HW pozorovano 2026-07-25: iPhone 11 dostal 10.10.10.111 od x8 a byl bez
    # internetu, zbyle dva telefony na tomtez AP-MLD jely, protoze lease mely od 4g.
    # Klasicky "vic DHCP na jedne siti" - resene uz driv, ale nikdy nezapecene,
    # takze to reflash x8 smazal. Proto to patri sem, na jedno misto pro vsechny agenty.
    uci set dhcp.lan.ignore='1'
    uci commit dhcp
    /etc/init.d/dnsmasq restart >/dev/null 2>&1 || true

    # --- default route + DNS na controller ---
    # Agent ma br-lan staticky, takze nedostane default route od nikoho a bez
    # tohohle nema SAM pristup na internet: nesynchronizuje cas, nic si nestahne.
    # Klientu se to netkne (ti maji gateway z DHCP od controlleru), takze je to
    # tise a vypada to jako drobnost - dokud nekdo neresi, proc jeden uzel ma
    # spatny cas nebo mu selze fetch.
    # HW namereno 2026-07-25: bpi-8g mel gateway/dns rucne nastavene a internet
    # jel, bpi-x8 po reflashi nemel ani jedno a byl bez internetu. Pate opakovani
    # tehoz vzorce za jeden den (rucni oprava, nezapecena, smazana reflashem).
    # Controller je v tomto labu vzdy .1 v mesh podsiti - stejna konvence, ze ktere
    # se vyse pocita MESH_IP.
    uci set network.lan.gateway='10.10.10.1'
    uci set network.lan.dns='10.10.10.1'
    uci commit network

    # agent-only: disable the controller daemon, point agent at a remote controller.
    # controller_select is an ANONYMOUS uci section → path is @controller_select[0],
    # not .controller_select (the named form fails "Entry not found"). Bit us 2026-07-11.
    /etc/init.d/mapcontroller disable
    uci set mapcontroller.controller.enabled='0'
    uci set mapagent.@controller_select[0].local='0'
    uci set mapagent.@controller_select[0].mode='auto'
    # autostart=0 is MANDATORY: default is '1' → agent auto-starts its OWN controller
    # → split-brain (two controllers invalidate the whole mesh). HW-confirmed on x8
    # 2026-07-24. This line must live in exactly one place (here) for every agent.
    uci set mapagent.@controller_select[0].autostart='0'
    uci commit mapcontroller

    # --- L0 wireless backhaul STA: REMOVED 2026-08-23 ---
    #
    # What stood here was the July 2026 workaround: `fw_setenv netmode extender`
    # plus a hand-written `mapagent bsta` and a matching wifi-iface, pre-seeded
    # with the lab MAP--BH credentials. It was right then - iopsys map_genconfig
    # emits a bSTA only under the netmode branch, so without it agent.c never
    # set has_bsta and the backhaul never formed (HW-proven 2026-07-15).
    #
    # It is wrong now, for three reasons:
    #
    # 1. The same branch that produced the bSTA also deletes every wireless.*
    #    with mode=ap (map_genconfig:514-516). Measured 2026-08-16: with the
    #    variable set the radios did not come up at all - 10 wifi-iface
    #    sections instead of 4, three of them with an empty SSID, and netifd
    #    tearing down every phy on the reference error that follows.
    # 2. The boards that matter got a better path meanwhile - the MLD backhaul
    #    through our own mesh layer. mlo-backhaul-setup (easymesh-wifi) adds
    #    exactly the declarations map_genconfig would not, and says so:
    #    "Nothing here touches /etc/config/wireless". Running both leaves two
    #    generators over one node and two sets of sections on one ifname.
    # 3. It baked LAB credentials into a production image. Harmless only for
    #    as long as nobody runs this script from an old note.
    #
    # The U-Boot variable itself is not removed by deleting this: it lives in
    # NAND and survives firstboot and every eMMC reinstall. That is what the
    # uci-default 07-x8-clear-netmode is for.
    echo "agent '$HOSTNAME' ($BOARD): mgmt $MGMT_IP ($MGMT_PORT) / mesh $MESH_IP (br-lan). Rebooting..."
    ;;
  *)
    echo "role must be 'controller' or 'agent'"; exit 1 ;;
esac

sync
reboot
