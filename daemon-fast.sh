#!/bin/sh
# daemon-fast.sh - rychla smycka pro DEMONY (map-controller, map-agent,
# ieee1905, libwifi, libeasy), tedy pro nasich 157 patchu do iopsysu.
#
# PROC ZVLAST OD builder-fast.sh: ten stavi nase shellove balicky pres SDK za
# pul minuty. Pokus rozsirit ho o demony (2026-09-06) selhal - SDK je pri kazdem
# behu prelozi ZNOVU od nuly (`clean-build`), takze by kazdy beh stal 40+ minut
# misto dvou. Plny strom to umi prirustkove, protoze v nem uz stoji.
#
# Zmereno 2026-09-06 na map-controlleru:
#   preklad v plnem strome 90 s | vlozeni do IB 1 s | obraz 20 s  => ~2 minuty
#
# Plny strom se pouziva JEN jako prekladac. Obraz se sklada v samostatnem
# ImageBuilderu v ~/img-work/<varianta>/, mimo plne stromy - tak, jak ma.
# Builder na zacatku kazdeho plneho buildu strom stejne maze (`rm -rf openwrt`),
# takze se v nem nic neztraci.
#
# NA CO TO NENI: jadro, DTS, u-boot, posun pinu. Na to plny build.
#
# Pouziti:
#   ./daemon-fast.sh <varianta> <balicek> [dalsi...]
#   ./daemon-fast.sh x8 map-controller
#   ./daemon-fast.sh universal map-agent libwifi
set -e

VARIANT="${1:?pouziti: daemon-fast.sh <varianta: universal|x8> <balicek> [...]}"
shift
[ $# -gt 0 ] || { echo "FATAL: zadny balicek. Napr.: daemon-fast.sh x8 map-controller" >&2; exit 1; }

case "$VARIANT" in
	universal) TREE="$HOME/universal-new/openwrt" ;;
	x8)        TREE="$HOME/x8-new/openwrt" ;;
	*) echo "FATAL: varianta musi byt 'universal' nebo 'x8', ne '$VARIANT'." >&2; exit 1 ;;
esac

[ -d "$TREE" ] || { echo "FATAL: strom $TREE neexistuje. Spust nejdriv plny build." >&2; exit 1; }
[ -d "$TREE/feeds/iopsys" ] || { echo "FATAL: $TREE/feeds/iopsys chybi - strom nema nalinkovany iopsys feed." >&2; exit 1; }

IBD=$(ls -d "$HOME/img-work/$VARIANT"/openwrt-imagebuilder-* 2>/dev/null | head -1)
[ -n "$IBD" ] || { echo "FATAL: pro '$VARIANT' neni rozbaleny ImageBuilder v ~/img-work/$VARIANT/." >&2
                   echo "       Spust nejdriv ./img-$VARIANT.sh, ten si ho rozbali." >&2; exit 1; }

echo ">>> varianta : $VARIANT"
echo ">>> strom    : $TREE"
echo ">>> IB       : $IBD"

STAMP=$(mktemp); trap 'rm -f "$STAMP"' EXIT

for P in "$@"; do
	[ -d "$TREE/feeds/iopsys/$P" ] || {
		echo "FATAL: balicek '$P' v iopsys feedu neni." >&2
		echo "       Je tam: $(ls "$TREE/feeds/iopsys" | tr '\n' ' ')" >&2; exit 1; }

	echo ">>> prekladam $P"
	( cd "$TREE" && make "package/feeds/iopsys/$P/compile" -j8 ) >"/tmp/daemon-fast-$P.log" 2>&1 || {
		echo "FATAL: $P se neprelozil, viz /tmp/daemon-fast-$P.log" >&2
		grep -vE 'warning|recursive dependency' "/tmp/daemon-fast-$P.log" | tail -12 >&2
		exit 1; }

	# Pojistka na tichou nulu: `make` skonci uspechem i tehdy, kdyz uz je vse
	# hotove - ale kdyz balicek NIKDY nevznikl, take neceka nic. Hledame soubor,
	# ne navratovou hodnotu.
	APK=$(ls -t "$TREE"/bin/packages/*/iopsys/"$P"-*.apk 2>/dev/null | head -1)
	[ -n "$APK" ] || { echo "FATAL: $P se tvari prelozene, ale zadny .apk nevznikl." >&2; exit 1; }

	cp -f "$APK" "$IBD/packages/"
	echo "    $(basename "$APK")  ->  IB"
	echo "$P $(basename "$APK")" >> "$STAMP"
done

echo ">>> skladam obraz"
"$(dirname "$0")/img-$VARIANT.sh"

echo
echo ">>> v obraze jsou tyto cerstve balicky:"
sed 's/^/    /' "$STAMP"
echo
echo ">>> POVINNE dalsi krok:  ./img-overit.sh $VARIANT"
echo "    Ocekavany nalez: lisi se prave ty binarky, ktere jsi menil,"
echo "    plus ./lib/apk/db/installed a ./lib/apk/db/scripts.tar.gz."
