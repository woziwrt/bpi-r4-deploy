#!/bin/sh
# Negotiated TTLM experiment against a live MLO client.
#
# Instruments the AP side rather than inferring from state: hostapd goes to DEBUG,
# a marker goes into the log, the request is sent, and only the log between the
# markers is read. "get_neg_ttlm still inactive" alone cannot distinguish "frame
# never sent" from "client refused" - the log can.
#
# Run with the client MAC as $1 and the link bitmap as $2 (bit0=link0 2.4G,
# bit1=link1 5G, bit2=link2 6G). Default 4 = pin everything to 6 GHz.

IF="${3:-ap-mld-1}"
S="${1:?usage: ttlm-test.sh <sta-mac> [link-bitmap] [iface]}"
MAP="${2:-4}"

echo "== klient =="
hostapd_cli -i "$IF" all_sta 2>/dev/null | awk -v s="$S" '
	$1 == s { p = 1; print "  " $1; next }
	/^[0-9a-f][0-9a-f]:/ { p = 0 }
	p && /max_simul_links|emlsr_support|emlmr_support|^flags/ { print "  " $0 }'

echo "== per-link tx PRED =="
iw dev "$IF" station dump 2>/dev/null | awk -v s="$S" '
	/^Station/ { m = $2 }
	m == s && /^\tLink [0-9]+:/ { l = $2; sub(":", "", l) }
	m == s && /^\t\ttx bytes:/ { printf "  link%s tx=%s\n", l, $3 }
	m == s && /^\t\tsignal:/ { printf "  link%s signal=%s\n", l, $2 }'

echo "== zapinam DEBUG =="
hostapd_cli -i "$IF" log_level DEBUG 2>&1 | sed 's/^/  /'

logger -t TTLMMARK "BEGIN-TTLM-TEST"
sleep 1

echo "== request: vsech 8 TID na masku $MAP =="
hostapd_cli -i "$IF" negotiated_ttlm request "$S" \
	dir=2 def_link_map=0 link_map_size=0 num_tids=8 \
	0 "$MAP" 1 "$MAP" 2 "$MAP" 3 "$MAP" \
	4 "$MAP" 5 "$MAP" 6 "$MAP" 7 "$MAP" 2>&1 | sed 's/^/  odpoved: /'

sleep 5
logger -t TTLMMARK "END-TTLM-TEST"

echo "== log mezi znackami (jen radky o TTLM / action / mgmt) =="
logread | awk '/BEGIN-TTLM-TEST/, /END-TTLM-TEST/' \
	| grep -viE 'TTLMMARK' \
	| grep -iE 'ttlm|action|tid|mld|link|prot' \
	| tail -30 | sed 's/^/  /'

echo "== vsechny radky mezi znackami (pocet) =="
logread | awk '/BEGIN-TTLM-TEST/, /END-TTLM-TEST/' | grep -vc TTLMMARK | sed 's/^/  /'

echo "== stav PO =="
echo "  get_neg_ttlm: $(hostapd_cli -i "$IF" get_neg_ttlm "$S" 2>&1)"
echo "  get_attlm:    $(hostapd_cli -i "$IF" get_attlm 2>&1)"

echo "== per-link tx PO =="
iw dev "$IF" station dump 2>/dev/null | awk -v s="$S" '
	/^Station/ { m = $2 }
	m == s && /^\tLink [0-9]+:/ { l = $2; sub(":", "", l) }
	m == s && /^\t\ttx bytes:/ { printf "  link%s tx=%s\n", l, $3 }'

hostapd_cli -i "$IF" log_level INFO >/dev/null 2>&1
echo "== log_level vracen na INFO =="
