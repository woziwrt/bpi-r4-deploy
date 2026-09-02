#!/bin/sh
# Does Negotiated TTLM actually MOVE traffic, or is it only accepted?
#
# "get_neg_ttlm prints a mapping" proves the negotiation completed. It does not
# prove the data path followed - the driver could accept the mapping and keep
# scheduling exactly as before. The only honest test is to pin every TID to one
# link, push a known amount of traffic, read the per-link byte counters, then pin
# to the other link and show the counters swap.
#
# Two traps this script exists to avoid, both hit on 2026-07-25:
#   - the peer is on the AP/VLAN child (ap-mld-2.sta1), NOT on the parent AP.
#     A dump of the parent returns nothing at all.
#   - on this interface iw prints NO "Link N:" headers; per-link blocks are only
#     indented one level deeper. (On the STA side it does print them. Both formats
#     are real, so parse by indentation here and count blocks in order.)
#
# $1 = STA mac, $2 = peer IP to push traffic to.

IF=ap-mld-2
VLAN_IF=ap-mld-2.sta1
S="${1:?usage: ttlm-steer.sh <sta-mac> <peer-ip>}"
PEER="${2:?}"

# "tx0 rx0 tx1 rx1" - per-link byte counters, in link order
bytes() {
	iw dev "$VLAN_IF" station dump 2>/dev/null | awk -v s="$S" '
		/^Station/ { m = ($2 == s); n = -1 }
		# a deeper-indented "rx bytes" starts a new per-link block
		m && /^\t\trx bytes:/ { n++; rx[n] = $3 }
		m && /^\t\ttx bytes:/ { tx[n] = $3 }
		END { printf "%d %d %d %d", tx[0] + 0, rx[0] + 0, tx[1] + 0, rx[1] + 0 }'
}

set_map() {
	hostapd_cli -i "$IF" negotiated_ttlm request "$S" \
		dir=2 def_link_map=0 link_map_size=0 num_tids=8 \
		0 "$1" 1 "$1" 2 "$1" 3 "$1" 4 "$1" 5 "$1" 6 "$1" 7 "$1" >/dev/null 2>&1
	sleep 3
}

run() {
	label="$1"; mask="$2"          # saved BEFORE any set --, which clobbers $1
	set_map "$mask"
	before=$(bytes)
	ping -c 200 -s 1200 -W 1 "$PEER" >/dev/null 2>&1
	after=$(bytes)

	set -- $before; b0t=$1 b0r=$2 b1t=$3 b1r=$4
	set -- $after;  a0t=$1 a0r=$2 a1t=$3 a1r=$4
	d0=$(( (a0t - b0t) + (a0r - b0r) ))
	d1=$(( (a1t - b1t) + (a1r - b1r) ))
	tot=$((d0 + d1))
	[ "$tot" -gt 0 ] || tot=1
	printf '  %-24s link0 %+9d B (%3d%%)   link1 %+9d B (%3d%%)\n' \
		"$label" "$d0" "$((d0 * 100 / tot))" "$d1" "$((d1 * 100 / tot))"
}

echo "=== per-link citace pred zacatkem ==="
echo "  $(bytes)   (tx0 rx0 tx1 rx1)"
echo
echo "=== provoz podle TTLM mapovani ==="
run "vse na link0 (mask 1)" 1
run "vse na link1 (mask 2)" 2
run "obe linky (mask 3)"    3
echo
echo "=== vysledne mapovani ==="
hostapd_cli -i "$IF" get_neg_ttlm "$S" 2>&1 | head -4 | sed 's/^/    /'
echo
printf '=== spojeni zije: ping %s -> %s ===\n' "$PEER" \
	"$(ping -c3 -W2 "$PEER" >/dev/null 2>&1 && echo OK || echo FAIL)"
