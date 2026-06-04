#!/bin/sh

#
# (c) 2025-2026 Cezary Jackiewicz <cezary@eko.one.pl>
#

DEVICE=$1
if [ -z "$DEVICE" ]; then
	echo '{"error":"Device not found"}'
	exit 0
fi

FORCE_PLMN=$2
[ "x$FORCE_PLMN" = "x1" ] || FORCE_PLMN=""

. /usr/share/libubox/jshn.sh

mmcli -m "$DEVICE" --signal-setup=3 >/dev/null 2>&1

json_load "$(mmcli -m "$DEVICE" -J --get-cell-info 2>/dev/null | jsonfilter -q -e '@.modem.*')" 2>/dev/null
if json_is_a "cell-info" array; then
	json_select "cell-info"
	idx=1
	while json_is_a ${idx} string; do
		json_get_var line $idx
		if echo "$line" | grep -q "serving: yes"; then
			IFS=','
			for F in $line; do
				KEY=""
				VAL=""
				eval $(echo "$F" | awk -F: '{gsub(" ", "");printf "KEY=%s, VAL=%s\n", $1, $2}')
				case "$KEY" in
					"celltype")
						MODE=$VAL
						_MODE=$(echo "$VAL" | tr 'a-z' 'A-Z')
						case "$_MODE" in
							"LTE")
								MODE_NUM=7
								;;
							"UMTS")
								MODE_NUM=2
								;;
						esac
						;;
					"operatorid")
						COPS_NUM=$VAL
						_plmn_mcc=${COPS_NUM:0:3}
						_plmn_mnc=${COPS_NUM:3:3}
						_plmn_mnc=$(printf "%02d" $_plmn_mnc)
						;;
					"tac")
						_TAC=$VAL
						_TAC_DEC=$(printf "%d" "0x$_TAC")
						;;
					"ci")
						_CELLID=$VAL
						_CELLID_DEC=$(printf "%d" "0x$_CELLID")
						;;
					"physicalci")
						_pci=$(printf "%d" "0x$VAL")
						;;
					"earfcn")
						_earfcn=$VAL
						;;
					"rsrp")
						_rsrp=$VAL
						;;
					"rsrq")
						_rsrq=$VAL
						;;
				esac
			done
			break
		fi
		idx=$((idx + 1))
	done
fi

_SIGNAL=0

SIGNAL_JSON=$(mmcli -m "$DEVICE" -J --signal-get 2>/dev/null)
if [ -z "$MODE" ]; then
	for TECH in lte umts; do
		trsrp=$(jsonfilter -s "$SIGNAL_JSON" -e "@.modem.signal.$TECH.rsrp" 2>/dev/null)
		trssi=$(jsonfilter -s "$SIGNAL_JSON" -e "@.modem.signal.$TECH.rssi" 2>/dev/null)
		if { [ "$trsrp" != "--" ] && [ -n "$trsrp" ]; } || { [ "$trssi" != "--" ] && [ -n "$trssi" ]; } then
			case "$TECH" in
				"lte")
					_MODE="LTE"
					MODE=$TECH
					MODE_NUM=7
					;;
				"umts")
					_MODE="UMTS"
					MODE=$TECH
					MODE_NUM=2
					;;
			esac
			break
		fi
	done
fi

T=$(jsonfilter -s "$SIGNAL_JSON" -q -e '@.modem.signal.'$MODE)
if [ -n "$T" ]; then
	_rsrp=""
	_rseq=""
	_rssi=""
	_snr=""
	_rscp=""
	_ecio=""
	eval $(jsonfilter -s "$T" -q -e "_rsrp=@.rsrp" -e "_rsrq=@.rsrq" -e "_rssi=@.rssi" -e "_snr=@.snr" -e "_rscp=@.rscp" -e "_ecio=@.ecio")
	if [ -n "$_rssi" ] && [ "$_rssi" != "--" ]; then
		_rssi=$(echo "$_rssi" | awk '{printf "%d\n", $1}')
		[ "$_rssi" -ge -51 ] && _rssi=-51
		_SIGNAL=$(((_rssi+113)*100/62))
	fi
fi

T=$(mmcli -m "$DEVICE" -J 2>/dev/null)
if [ -n "$FORCE_PLMN" ]; then
	_plmn_description=$(awk -F[\;] '/^'$COPS_NUM';/ {print $3}' /usr/share/modemdata/libs/mccmnc.dat)
	[ -z "$_plmn_description" ] && _plmn_description="$COPS_NUM"
else
	_plmn_description=$(jsonfilter -s "$T" -q -e "@.modem['3gpp']['operator-name']")
fi
REG=$(jsonfilter -s "$T" -q -e "@.modem['3gpp']['registration-state']")
case "$REG" in
	"home")
		_registration=1
		;;
	*)
		_registration=0
		;;
esac

echo "{"
echo "\"signal\":\"$_SIGNAL\","
echo "\"operator_name\":\"$_plmn_description\","
echo "\"operator_mcc\":\"$_plmn_mcc\","
echo "\"operator_mnc\":\"$_plmn_mnc\","
[ -n "$COPS_NUM" ] && COUNTRY=$(awk -F[\;] '/^'$COPS_NUM';/ {print $2}' /usr/share/modemdata/libs/mccmnc.dat)
echo "\"country\":\"$COUNTRY\","
echo "\"mode\":\"$_MODE\","
echo "\"registration\":\"$_registration\","
echo "\"lac_dec\":\"\",\"lac_hex\":\"\",\"cid_dec\":\"${_CELLID_DEC}\",\"cid_hex\":\"${_CELLID}\",\"addon\":["
ADDON=""
[ -n "$_rssi" ] && [ "$_rssi" != "--" ] && ADDON="${ADDON}{\"idx\":35,\"key\":\"RSSI\",\"value\":\"$(printf "%.1f" $_rssi) dBm\"},"
if [ "$MODE_NUM" = "7" ]; then
	[ -n "$_rsrp" ] && [ "$_rsrp" != "--" ] && ADDON="${ADDON}{\"idx\":36,\"key\":\"RSRP\",\"value\":\"$(printf "%.1f" $_rsrp) dBm\"},"
	[ -n "$_rsrq" ] && [ "$_rsrq" != "--" ] && ADDON="${ADDON}{\"idx\":37,\"key\":\"RSRQ\",\"value\":\"$(printf "%.1f" $_rsrq) dB\"},"
	[ -n "$_snr" ] && [ "$_snr" != "--" ] && ADDON="${ADDON}{\"idx\":38,\"key\":\"SNR\",\"value\":\"$(printf "%.1f" $_snr) dB\"},"
	[ -n "$_TAC" ] && ADDON="${ADDON}{\"idx\":23,\"key\":\"TAC\",\"value\":\"${_TAC_DEC} (${_TAC})\"},"
fi
if [ "$MODE_NUM" = "2" ]; then
	[ -n "$_ecio" ] && ADDON="${ADDON}{\"idx\":36,\"key\":\"ECIO\",\"value\":\"$_ecio dB\"},"
fi
[ -n "$_pci" ] && ADDON="${ADDON}{\"idx\":33,\"key\":\"PCI\",\"value\":\"$_pci\"},"
[ -n "$_earfcn" ] && ADDON="${ADDON}{\"idx\":34,\"key\":\"EARFCN\",\"value\":\"$_earfcn\"},"
[ -n "$ADDON" ] && echo "${ADDON%,*}"
echo "]}"

exit 0
