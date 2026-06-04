#!/bin/sh

#
# (c) 2023-2026 Cezary Jackiewicz <cezary@eko.one.pl>
#

DEVICE=$1
if [ -z "$DEVICE" ] || [ ! -e "$DEVICE" ]; then
	echo '{"error":"Device not found"}'
	exit 0
fi
if [ -n "$(pidof uqmi)" ]; then
	echo '{"error":"Device is busy"}'
	exit 0
fi

FORCE_PLMN=$2
[ "x$FORCE_PLMN" = "x1" ] || FORCE_PLMN=""

MBIM=$3
[ "x$MBIM" = "x1" ] && MBIM="-m" || MBIM=""

json_number_first() {
	echo "$1" | sed -n 's/.*"'"$2"'"[[:space:]]*:[[:space:]]*\(-\{0,1\}[0-9][0-9.]*\).*/\1/p' | head -n 1
}

type=""
rssi=""
rsrq=""
rsrp=""
snr=""
ecio=""
fgtype=""
fgrsrq=""
fgrsrp=""
fgsnr=""
T=$(uqmi -t 3000 -s -d $DEVICE $MBIM --get-signal-info 2>/dev/null)
if [ -n "$(jsonfilter -s "$T" -q -e '@.type')" ]; then
	eval $(jsonfilter -s "$T" -q -e 'type=@.type' -e 'rssi=@.rssi' -e 'rsrq=@.rsrq' -e 'rsrp=@.rsrp' -e 'snr=@.snr' -e 'ecio=@.ecio')
else
	eval $(jsonfilter -s "$T" -q \
		-e 'type=@[0].type' -e 'rssi=@[0].rssi' -e 'rsrq=@[0].rsrq' -e 'rsrp=@[0].rsrp' -e 'snr=@[0].snr' \
		-e 'fgtype=@[1].type' -e 'fgrsrq=@[1].rsrq' -e 'fgrsrp=@[1].rsrp' -e 'fgsnr=@[1].snr')
fi

registration=""
plmn_mcc=""
plmn_mnc=""
plmn_description=""
roaming=""
eval $(uqmi -t 3000 -s -d $DEVICE $MBIM --get-serving-system | jsonfilter -q -e 'registration=@.registration' -e 'plmn_mcc=@.plmn_mcc' -e 'plmn_mnc=@.plmn_mnc' -e 'plmn_description=@.plmn_description' -e 'roaming=@.roaming')
[ -n "$plmn_mnc" ] && plmn_mnc=$(printf %02d $plmn_mnc)

MODE=$(echo $type | tr 'a-z' 'A-Z')
case "$MODE" in
	"LTE") MODE_NUM=7;;
	"WCDMA") MODE_NUM=2;;
	*) MODE_NUM=0;;
esac
if [ "$MODE_NUM" = "7" ] && [ "x$fgtype" = "x5gnr" ]; then
	MODE="5G NSA"
fi

COPS_NUM="${plmn_mcc}${plmn_mnc}"
if [ -n "$COPS_NUM" ]; then
	COUNTRY=$(awk -F[\;] '/^'$COPS_NUM';/ {print $2}' /usr/share/modemdata/libs/mccmnc.dat)
	if [ -z "$COUNTRY" ]; then
		T=$(printf %03d $plmn_mnc)
		COUNTRY=$(awk -F[\;] '/^'${plmn_mcc}${T}';/ {print $2}' /usr/share/modemdata/libs/mccmnc.dat)
		if [ -n "$COUNTRY" ]; then
			plmn_mnc="$T"
			COPS_NUM="${plmn_mcc}${plmn_mnc}"
		fi
	fi

	if [ -n "$FORCE_PLMN" ]; then
		plmn_description=$(awk -F[\;] '/^'$COPS_NUM';/ {print $3}' /usr/share/modemdata/libs/mccmnc.dat)
		[ -z "$plmn_description" ] && plmn_description="$COPS_NUM"
	fi
fi

SIGNAL=0
if [ -n "$rssi" ]; then
	rssi=$(echo "$rssi" | awk '{printf "%d\n", $1}')
	[ $rssi -ge -51 ] && rssi=-51
	SIGNAL=$(((rssi+113)*100/62))
fi

case "$registration" in
	"not_registered")
		registration="0"
		;;
	"registered")
		registration="1"
		[ "x$roaming" = "x1" ] && registration="5"
		;;
	"searching")
		registration="2"
		;;
	"registering_denied")
		registration="3"
		;;
	*)
		registration=""
		;;
esac

PB=""
PF=""
PBW=""
PPCI=""
PEARFCN=""
S1B=""
S1F=""
S1BW=""
S1STATE=""
S1PCI=""
S1EARFCN=""
S2B=""
S2F=""
S2BW=""
S2STATE=""
S2PCI=""
S2EARFCN=""
S3B=""
S3F=""
S3BW=""
S3STATE=""
S3PCI=""
S3EARFCN=""
S4B=""
S4F=""
S4BW=""
S4STATE=""
S4PCI=""
S4EARFCN=""
if [ "$MODE_NUM" = "7" ]; then
	T=$(uqmi -t 3000 -s -d $DEVICE $MBIM --get-lte-cphy-ca-info 2>/dev/null)
	eval $(jsonfilter -s "$T" -q -e 'PB=@.primary.band' -e 'PF=@.primary.frequency' -e 'PBW=@.primary.bandwidth' -e 'PPCI=@.primary.cell_id' -e 'PEARFCN=@.primary.channel')
	IDX=1
	for i in 1 2 3 4 5 6 7 8 9 10; do
		T1=$(jsonfilter -s "$T" -q -e "@.secondary_${i}.band")
		if [ -n "$T1" ]; then
			eval $(jsonfilter -s "$T" -q -e "S${IDX}B=@.secondary_${i}.band" -e "S${IDX}F=@.secondary_${i}.frequency" -e "S${IDX}BW=@.secondary_${i}.bandwidth" -e "S${IDX}STATE=@.secondary_${i}.state" -e "S${IDX}PCI=@.secondary_${i}.cell_id" -e "S${IDX}EARFCN=@.secondary_${i}.channel")
			[ $IDX = "4" ] && break
			IDX=$((IDX + 1))
		fi
	done
	[ -n "$PB" ] && MODE="${MODE} B${PB} (${PF} MHz)"
	[ -n "$S1B" ] && [ "x$S1STATE" = "xactivated" ] && MODE="${MODE} / B${S1B} (${S1F} MHz)"
	[ -n "$S2B" ] && [ "x$S2STATE" = "xactivated" ] && MODE="${MODE} / B${S2B} (${S2F} MHz)"
	[ -n "$S3B" ] && [ "x$S3STATE" = "xactivated" ] && MODE="${MODE} / B${S3B} (${S3F} MHz)"
	[ -n "$S4B" ] && [ "x$S4STATE" = "xactivated" ] && MODE="${MODE} / B${S4B} (${S4F} MHz)"
	if [ -n "$fgtype" ]; then
		MODE="${MODE} / ?"
	else
		echo "$MODE" | grep -q " / B" && MODE=${MODE/LTE/LTE-A}
	fi
	if [ -z "$PB" ] || [ -z "$PPCI" ] || [ -z "$PEARFCN" ]; then
		T=$(uqmi -t 3000 -s -d $DEVICE $MBIM --get-cell-location-info 2>/dev/null)
		[ -z "$PB" ] && PB=$(json_number_first "$T" "band")
		[ -z "$PF" ] && PF=$(json_number_first "$T" "frequency")
		[ -z "$PPCI" ] && PPCI=$(json_number_first "$T" "serving_cell_id")
		[ -z "$PPCI" ] && PPCI=$(json_number_first "$T" "physical_cell_id")
		[ -z "$PEARFCN" ] && PEARFCN=$(json_number_first "$T" "channel")
		if [ -n "$PB" ] && ! echo "$MODE" | grep -q " B${PB}"; then
			MODE="${MODE} B${PB}"
			[ -n "$PF" ] && MODE="${MODE} (${PF} MHz)"
		fi
	fi
fi

echo "{"
echo "\"signal\":\"$SIGNAL\","
echo "\"operator_name\":\"$plmn_description\","
echo "\"operator_mcc\":\"$plmn_mcc\","
echo "\"operator_mnc\":\"$plmn_mnc\","
echo "\"country\":\"$COUNTRY\","
echo "\"mode\":\"$MODE\","
echo "\"registration\":\"$registration\","
TAC=""
CELLID=""
if [ "$MODE_NUM" = "7" ]; then
	SCELLID=""
	ENODEBID=""
	eval $(uqmi -t 3000 -s -d $DEVICE $MBIM --get-system-info 2>/dev/null | jsonfilter -q -e 'TAC=@.lte.tracking_area_code' -e 'SCELLID=@.lte.cell_id' -e 'ENODEBID=@.lte.enodeb_id')
	if [ -n "$SCELLID" ] && [ -n "$ENODEBID" ]; then
		CELLID=$(printf "%X%X" $ENODEBID $SCELLID )
		CELLID_DEC=$(printf "%d" "0x$CELLID")
	fi
	[ -n "$TAC" ] && TAC_HEX=$(printf "%X" $TAC)
fi
echo "\"lac_dec\":\"\",\"lac_hex\":\"\",\"cid_dec\":\"$CELLID_DEC\",\"cid_hex\":\"$CELLID\",\"addon\":["
ADDON=""
[ -n "$rssi" ] && ADDON="${ADDON}{\"idx\":35,\"key\":\"RSSI\",\"value\":\"$rssi dBm\"},"
if [ "$MODE_NUM" = "7" ]; then
	[ -n "$TAC" ] && ADDON="${ADDON}{\"idx\":23,\"key\":\"TAC\",\"value\":\"$TAC (${TAC_HEX})\"},"
	[ -n "$PB" ] && ADDON="${ADDON}{\"idx\":30,\"key\":\"Primary band\",\"value\":\"B${PB}${PF:+ (${PF} MHz)}${PBW:+ @${PBW} MHz}\"},"
	[ -n "$rsrp" ] && ADDON="${ADDON}{\"idx\":36,\"key\":\"RSRP\",\"value\":\"$rsrp dBm\"},"
	[ -n "$rsrq" ] && ADDON="${ADDON}{\"idx\":37,\"key\":\"RSRQ\",\"value\":\"$rsrq dB\"},"
	[ -n "$snr" ] && ADDON="${ADDON}{\"idx\":38,\"key\":\"SNR\",\"value\":\"$(printf "%.1f" $snr) dB\"},"
	[ -n "$PPCI" ] && ADDON="${ADDON}{\"idx\":33,\"key\":\"PCI\",\"value\":\"$PPCI\"},"
	[ -n "$PEARFCN" ] && ADDON="${ADDON}{\"idx\":34,\"key\":\"EARFCN\",\"value\":\"$PEARFCN\"},"
	IDX=50
	SCC=1
	if [ -n "$S1B" ] && [ "x$S1STATE" = "xactivated" ]; then
		ADDON="${ADDON}{\"idx\":${IDX} ,\"key\":\"(S${SCC}) band\",\"value\":\"B${S1B} (${S1F} MHz) @${S1BW} MHz\"},"
		[ -n "$S1PCI" ] && ADDON="${ADDON}{\"idx\":$((IDX + 3)),\"key\":\"(S${SCC}) PCI\",\"value\":\"$S1PCI\"},"
		[ -n "$S1EARFCN" ] && ADDON="${ADDON}{\"idx\":$((IDX + 4)),\"key\":\"(S${SCC}) EARFCN\",\"value\":\"$S1EARFCN\"},"
		IDX=$((IDX + 10))
		SCC=$((SCC + 1))
	fi
	if [ -n "$S2B" ] && [ "x$S2STATE" = "xactivated" ]; then
		ADDON="${ADDON}{\"idx\":${IDX},\"key\":\"(S${SCC}) band\",\"value\":\"B${S2B} (${S2F} MHz) @${S2BW} MHz\"},"
		[ -n "$S2PCI" ] && ADDON="${ADDON}{\"idx\":$((IDX + 3)),\"key\":\"(S${SCC}) PCI\",\"value\":\"$S2PCI\"},"
		[ -n "$S2EARFCN" ] && ADDON="${ADDON}{\"idx\":$((IDX + 4)),\"key\":\"(S${SCC}) EARFCN\",\"value\":\"$S2EARFCN\"},"
		IDX=$((IDX + 10))
		SCC=$((SCC + 1))
	fi
	if [ -n "$S3B" ] && [ "x$S3STATE" = "xactivated" ]; then
		ADDON="${ADDON}{\"idx\":${IDX},\"key\":\"(S${SCC}) band\",\"value\":\"B${S3B} (${S3F} MHz) @${S3BW} MHz\"},"
		[ -n "$S3PCI" ] && ADDON="${ADDON}{\"idx\":$((IDX + 3)),\"key\":\"(S${SCC}) PCI\",\"value\":\"$S3PCI\"},"
		[ -n "$S3EARFCN" ] && ADDON="${ADDON}{\"idx\":$((IDX + 4)),\"key\":\"(S${SCC}) EARFCN\",\"value\":\"$S3EARFCN\"},"
		IDX=$((IDX + 10))
		SCC=$((SCC + 1))
	fi
	if [ -n "$S4B" ] && [ "x$S4STATE" = "xactivated" ]; then
		ADDON="${ADDON}{\"idx\":${IDX},\"key\":\"(S${SCC}) band\",\"value\":\"B${S4B} (${S4F} MHz) @${S4BW} MHz\"},"
		[ -n "$S4PCI" ] && ADDON="${ADDON}{\"idx\":$((IDX + 3)),\"key\":\"(S${SCC}) PCI\",\"value\":\"$S4PCI\"},"
		[ -n "$S4EARFCN" ] && ADDON="${ADDON}{\"idx\":$((IDX + 4)),\"key\":\"(S${SCC}) EARFCN\",\"value\":\"$S4EARFCN\"},"
		IDX=$((IDX + 10))
		SCC=$((SCC + 1))
	fi
	if [ -n "$fgtype" ]; then
		ADDON="${ADDON}{\"idx\":${IDX},\"key\":\"(S${SCC}) band\",\"value\":\"5G\"},"
		[ -n "$fgrsrp" ] && ADDON="${ADDON}{\"idx\":$((IDX + 6)),\"key\":\"(S${SCC}) RSRP\",\"value\":\"$fgrsrp dBm\"},"
		[ -n "$fgrsrq" ] && ADDON="${ADDON}{\"idx\":$((IDX + 7)),\"key\":\"(S${SCC}) RSRQ\",\"value\":\"$fgrsrq dB\"},"
		[ -n "$fgsnr" ] && ADDON="${ADDON}{\"idx\":$((IDX + 8)),\"key\":\"(S${SCC}) SNR\",\"value\":\"$(printf "%.1f" $fgsnr) dB\"},"
	fi
fi
if [ "$MODE_NUM" = "2" ]; then
	[ -n "$ecio" ] && ADDON="${ADDON}{\"idx\":36,\"key\":\"ECIO\",\"value\":\"$ecio dB\"},"
fi
[ -n "$ADDON" ] && echo "${ADDON%,*}"
echo "]}"

exit 0
