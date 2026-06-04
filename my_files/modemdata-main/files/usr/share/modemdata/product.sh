#!/bin/sh

#
# (c) 2024-2025 Cezary Jackiewicz <cezary@eko.one.pl>
#

DEVICE=$1
if [ -n "$DEVICE" ] && [ -e "$DEVICE" ]; then
	RES="/usr/share/modemdata"
	. $RES/libs/getdevicevendorproduct
	VIDPID=$(getdevicevendorproduct $DEVICE)
	if [ -e "$RES/vendorproduct/$VIDPID" ]; then
		. "$RES/vendorproduct/$VIDPID"
	else
		. "$RES/vendorproduct/generic"
	fi
fi

cat <<EOF
{
"vendor":"${VENDOR}",
"product":"${PRODUCT}",
"revision":"${REVISION}",
"imei":"${IMEI}",
"iccid":"${ICCID}",
"imsi":"${IMSI}"
}
EOF

exit 0
