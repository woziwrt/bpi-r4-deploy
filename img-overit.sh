#!/bin/sh
# Overi, ze obraz slozeny z ImageBuilderu odpovida tomu z plneho buildu.
#
# PROC to nejde poznat jednodusseji: md5 celych obrazu se lisi VZDY - v hlavicce
# FIT je casove razitko a squashfs ma vlastni metadata. Dva spravne obrazy tedy
# vypadaji jako ruzne. Stejne tak velikost a pocet souboru sedi i tehdy, kdyz je
# uvnitr JINA VERZE balicku - 5. 9. 2026 se takhle do obrazu dostal mt76-test
# stazeny z internetu a nepoznalo se to.
#
# Proto se rozbaluji oba rootfs a porovnava se KAZDY soubor.
# Ocekavany a nezavadny rozdil je jediny: /etc/apk/world (seznam vyzadanych
# balicku, ne obsah systemu). Cokoli navic je nalez.
set -e
VARIANT="${1:?pouziti: img-overit.sh universal|x8}"
case "$VARIANT" in
	universal) GLOB='*-production';    PROFILE=bananapi_bpi-r4 ;;
	x8)        GLOB='*-production-x8'; PROFILE=bananapi_bpi-r4-pro-8x ;;
	*) echo "neznama varianta: $VARIANT" >&2; exit 1 ;;
esac

ARCH=""
for d in $(ls -dt "$HOME"/archiv/$GLOB/ 2>/dev/null); do
	[ "$VARIANT" = universal ] && case "$d" in *-production-x8/) continue ;; esac
	[ -d "$d/images" ] || continue
	ARCH="${d%/}"; break
done
[ -n "$ARCH" ] || { echo "STOP: nenasel jsem archiv varianty $VARIANT." >&2; exit 1; }

PLNY="$ARCH/images/openwrt-mediatek-filogic-$PROFILE-squashfs-sysupgrade.itb"
ZIB="$HOME/OBRAZY/$VARIANT/openwrt-mediatek-filogic-$PROFILE-squashfs-sysupgrade.itb"
[ -f "$PLNY" ] || { echo "STOP: chybi obraz z plneho buildu: $PLNY" >&2; exit 1; }
[ -f "$ZIB" ]  || { echo "STOP: chybi obraz z IB: $ZIB   (spust nejdriv img-$VARIANT.sh)" >&2; exit 1; }

echo ">>> varianta: $VARIANT"
echo "    plny build: $PLNY"
echo "    z IB      : $ZIB"
echo

a=$(wc -c < "$PLNY"); b=$(wc -c < "$ZIB")
printf "  velikost : %s vs %s  (rozdil %s B)\n" "$a" "$b" "$((b-a))"

W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
o1=$(grep -abo hsqs "$PLNY" | head -1 | cut -d: -f1)
o2=$(grep -abo hsqs "$ZIB"  | head -1 | cut -d: -f1)
printf "  squashfs : offset %s vs %s\n" "$o1" "$o2"
# POZOR: unsquashfs vraci 2 i kdyz vsechno rozbalilo spravne - pod beznym
# uzivatelem nedokaze nastavit vlastnika souboru. Na navratovy kod se tedy
# spolehnout nejde, kontroluje se pocet rozbalenych souboru.
unsquashfs -o "$o1" -d "$W/plny" "$PLNY" >"$W/u1.log" 2>&1 || true
unsquashfs -o "$o2" -d "$W/zib"  "$ZIB"  >"$W/u2.log" 2>&1 || true
n1=$(find "$W/plny" -type f | wc -l); n2=$(find "$W/zib" -type f | wc -l)
printf "  souboru  : %s vs %s\n\n" "$n1" "$n2"
[ "$n1" -gt 100 ] && [ "$n2" -gt 100 ] || {
	echo "STOP: rozbaleni selhalo (plny=$n1, zIB=$n2 souboru)." >&2
	tail -5 "$W/u1.log" "$W/u2.log" >&2
	exit 1
}

( cd "$W/plny" && find . -type f -exec md5sum {} + | sort -k2 ) > "$W/h1"
( cd "$W/zib"  && find . -type f -exec md5sum {} + | sort -k2 ) > "$W/h2"
diff "$W/h1" "$W/h2" | grep '^<' | awk '{print $3}' > "$W/lisi" || true

lisi=$(grep -c . "$W/lisi" 2>/dev/null || echo 0)
nalez=$(grep -v '^\./etc/apk/world$' "$W/lisi" | grep -c . || true)

if [ "$nalez" -eq 0 ]; then
	echo "  ✅ OBSAHOVE SHODNE  (lisi se $lisi: jen /etc/apk/world, coz je v poradku)"
	exit 0
fi
echo "  ❌ NALEZ - lisi se $nalez souboru nad ramec /etc/apk/world:"
grep -v '^\./etc/apk/world$' "$W/lisi" | sed 's/^/      /'
echo
echo "  Nejcastejsi pricina: ImageBuilder si sahl na downloads.openwrt.org."
echo "  Zkontroluj, ze je prazdny:  ~/img-work/$VARIANT/openwrt-imagebuilder-*/repositories"
exit 1
