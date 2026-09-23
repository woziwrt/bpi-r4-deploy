#!/bin/sh
# Overi obraz z RYCHLE SMYCKY (builder-fast.sh) proti plnemu buildu.
#
# img-overit.sh tenhle obraz overit NEUMI: porovnava na uplnou shodu, a obraz
# z rychle smycky se lisit MA - jsou v nem nove verze nasich balicku. Az do
# 22. 9. 2026 proto obraz z rychle smycky neoveroval NIC, prestoze se z nej
# flashuji uzly.
#
# Otazka, na kterou tenhle skript odpovida, neni "je to stejne?", ale:
#   "lisi se JENOM to, co jsme zmenili my?"
# Kazdy jiny rozdil znamena, ze si ImageBuilder sahl jinam, nez mel.
set -eu

VARIANT="${1:?pouziti: img-overit-fast.sh universal|8gb|x8}"
# 8gb je tentyz plny build jako universal, jen jiny profil obrazu - corridor
# ma 8 GB RAM a potrebuje vlastni DTS. Chybel tu do 22. 9. 2026 a skript pak
# tise overil universal obraz misto nej.
case "$VARIANT" in
	universal) PROFILE=bananapi_bpi-r4 ;;
	8gb)       PROFILE=bananapi_bpi-r4-8gb ;;
	x8)        PROFILE=bananapi_bpi-r4-pro-8x ;;
	*) echo "STOP: varianta musi byt universal, 8gb nebo x8." >&2; exit 1 ;;
esac

# Archiv plneho buildu - tentyz vyber podle profilu jako v builder-fast.sh.
_je_x8() { case "$1" in *-production-x8|*-production-x8/) return 0 ;; *) return 1 ;; esac; }
ARCH=""
for d in $(ls -dt "$HOME"/archiv/*/ 2>/dev/null); do
	[ -d "$d/images" ] || continue
	case "$VARIANT" in
		x8) _je_x8 "$d" || continue ;;
		*)  _je_x8 "$d" && continue ;;
	esac
	ARCH="${d%/}"; break
done
[ -n "$ARCH" ] || { echo "STOP: nenasel jsem archiv plneho buildu pro $VARIANT." >&2; exit 1; }

PLNY="$ARCH/images/openwrt-mediatek-filogic-$PROFILE-squashfs-sysupgrade.itb"
RYCHLY=$(ls -t "$HOME"/fast-work/"$PROFILE"/openwrt-imagebuilder-*/bin/targets/*/*/*"$PROFILE"-squashfs-sysupgrade.itb 2>/dev/null | head -1)
[ -f "$PLNY" ]   || { echo "STOP: chybi obraz z plneho buildu: $PLNY" >&2; exit 1; }
[ -n "$RYCHLY" ] || { echo "STOP: v ~/fast-work/$PROFILE neni zadny obraz - spust nejdriv builder-fast.sh." >&2; exit 1; }

# Obraz musi byt mladsi nez archiv, jinak overujeme neco davno prekonaneho.
[ "$RYCHLY" -nt "$PLNY" ] || {
	echo "STOP: obraz z rychle smycky je STARSI nez plny build." >&2
	echo "      rychly: $(date -r "$RYCHLY" '+%d.%m. %H:%M')  $RYCHLY" >&2
	echo "      plny  : $(date -r "$PLNY"   '+%d.%m. %H:%M')" >&2
	exit 1
}

# IB nesmi mit kam sahnout ven. Prazdne 'repositories' je jedina pojistka,
# ktera to zarucuje pred slozenim obrazu, ne az po nem.
IBDIR=$(dirname "$(dirname "$(dirname "$(dirname "$RYCHLY")")")")
if [ -f "$IBDIR/repositories" ] && grep -v '^#' "$IBDIR/repositories" | grep -q '[a-z]'; then
	echo "STOP: $IBDIR/repositories neni prazdne - IB mohl stahovat z internetu." >&2
	grep -v '^#' "$IBDIR/repositories" | grep '[a-z]' | sed 's/^/      /' >&2
	exit 1
fi

echo ">>> varianta  : $VARIANT"
echo "    plny build: $PLNY"
echo "    rychly    : $RYCHLY"
echo

# Seznam souboru, ktere NASE balicky vlastni. Bere se z .apk, ktere rychla
# smycka prave prelozila - ne z odhadu podle cesty.
SDK=$(ls -dt "$HOME"/fast-work/"$PROFILE"/openwrt-sdk-* 2>/dev/null | head -1)
[ -n "$SDK" ] || { echo "STOP: nenasel jsem SDK v ~/fast-work/$PROFILE." >&2; exit 1; }

W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT

# .apk je od OpenWrt 24 format APKv3 - binarni, ne tar, 'tar tzf' na nem selze
# TICHE a vrati prazdny seznam. Seznam souboru se proto bere z instalacnich
# stromu '.pkgdir', ktere SDK necha lezet vedle prelozeneho balicku.
: > "$W/nase"
: > "$W/nase-jmena"
pocet_pkg=0
for pd in "$SDK"/build_dir/target-*/*/.pkgdir/*; do
	[ -d "$pd" ] || continue
	case "$(basename "$pd")" in *.installed) continue ;; esac
	( cd "$pd" && find . \( -type f -o -type l \) ) >> "$W/nase" || true
	basename "$pd" >> "$W/nase-jmena"
	pocet_pkg=$((pocet_pkg + 1))
done
sort -u "$W/nase" -o "$W/nase"
pocet_souboru=$(grep -c . "$W/nase" || true)
echo "    nase balicky: $pocet_pkg, $pocet_souboru souboru"
[ "$pocet_souboru" -gt 0 ] || {
	echo "STOP: nenasel jsem ani jeden soubor nasich balicku." >&2
	echo "      Bez toho by skript oznacil za cizi uplne vsechno." >&2
	exit 1
}

o1=$(grep -abo hsqs "$PLNY"   | head -1 | cut -d: -f1)
o2=$(grep -abo hsqs "$RYCHLY" | head -1 | cut -d: -f1)
unsquashfs -o "$o1" -d "$W/plny"   "$PLNY"   >"$W/u1.log" 2>&1 || true
unsquashfs -o "$o2" -d "$W/rychly" "$RYCHLY" >"$W/u2.log" 2>&1 || true
n1=$(find "$W/plny" -type f | wc -l); n2=$(find "$W/rychly" -type f | wc -l)
printf "    souboru     : %s (plny) vs %s (rychly)\n\n" "$n1" "$n2"
[ "$n1" -gt 100 ] && [ "$n2" -gt 100 ] || {
	echo "STOP: rozbaleni selhalo (plny=$n1, rychly=$n2)." >&2
	tail -5 "$W/u1.log" "$W/u2.log" >&2
	exit 1
}

# OCEKAVANE="map-agent wpad-openssl ...": packages built OUTSIDE the SDK on
# purpose - in the full tree and dropped into the IB (daemons, hostapd). They
# may differ in version and in their own files; nothing else may. Their file
# lists come from the NEW image's /lib/apk/packages/<pkg>.list, so a file the
# new build adds is covered too.
#
# Until 2026-09-23 the only allowed difference was our seven SDK packages, and
# the first image with a patched wpad and map-agent stopped at the version
# check without ever comparing a file.
for _p in ${OCEKAVANE:-}; do
	_l="$W/rychly/lib/apk/packages/$_p.list"
	[ -s "$_l" ] || { echo "STOP: OCEKAVANE '$_p' neni v novem obrazu ($_l)." >&2; exit 1; }
	sed 's#^/#./#' "$_l" >> "$W/nase"
	echo "$_p" >> "$W/nase-jmena"
	echo "    ocekavany   : $_p ($(grep -c . "$_l") souboru)"
done
[ -n "${OCEKAVANE:-}" ] && { sort -u "$W/nase" -o "$W/nase"; echo; }

( cd "$W/plny"   && find . -type f -exec md5sum {} + | sort -k2 ) > "$W/h1"
( cd "$W/rychly" && find . -type f -exec md5sum {} + | sort -k2 ) > "$W/h2"
# Rozdil v OBOU smerech - soubor smazany z rychleho obrazu je taky nalez.
diff "$W/h1" "$W/h2" | grep '^[<>]' | awk '{print $3}' | sort -u > "$W/lisi"

# Databaze apk a /etc/apk/world se lisi vzdy, protoze nesou cisla verzi.
# Neignoruji se ale naslepo - rozeberou se na seznam balicku a verzi a plati
# tataz otazka: smi se lisit jen to, co jsme prelozili my. Prave timhle se
# 22. 9. 2026 naslo, ze IB skladal z archivu stareho o jeden plny build.
_vl=0
sort -u "$W/nase-jmena" -o "$W/nase-jmena"
for x in plny rychly; do
	grep -E '^P:|^V:' "$W/$x/lib/apk/db/installed" 2>/dev/null \
		| paste - - | sed 's/^P://; s/	V:/ /' | sort > "$W/$x.verze" || true
done
if [ -s "$W/plny.verze" ] && [ -s "$W/rychly.verze" ]; then
	join -j1 "$W/plny.verze" "$W/rychly.verze" 2>/dev/null > "$W/spojene" || true
	awk '$2 != $3 { print $1 }' "$W/spojene" | sort -u > "$W/verze-lisi"
	comm -23 "$W/verze-lisi" "$W/nase-jmena" > "$W/verze-cizi" || true
	_vl=$(grep -c . "$W/verze-lisi" || true)
	_vc=$(grep -c . "$W/verze-cizi" || true)
	if [ "$_vc" -gt 0 ]; then
		echo "  ❌ NALEZ - $_vc balicku ma jinou verzi, a nejsou nase:" >&2
		awk 'NR==FNR { c[$1]=1; next } c[$1] { printf "      %-30s plny %-16s rychly %s\n", $1, $2, $3 }' \
			"$W/verze-cizi" "$W/spojene" >&2
		echo >&2
		echo "  SDK nebo ImageBuilder pochazi z jineho archivu, nez ze ktereho se stavi." >&2
		echo "  Smaz ~/fast-work/<profil>/ a pust rychlou smycku znovu." >&2
		exit 1
	fi
	echo "    verze balicku: lisi se $_vl, vsechny nase"
fi

grep -v -e '^\./etc/apk/world$' -e '^\./lib/apk/db/installed$' \
       -e '^\./lib/apk/db/scripts\.tar\.gz$' -e '^\./usr/lib/opkg/status$' \
       "$W/lisi" > "$W/lisi2" || true

# /lib/apk/packages/<balicek>.list je seznam souboru daneho balicku. Kdyz nas
# balicek dostane novy soubor, zmeni se i tenhle seznam - a v .pkgdir neni,
# takze by se pocital za cizi. Povoluji se JMENOVITE jen seznamy NASICH
# balicku: kdyz se zmeni seznam ciziho balicku, je to porad nalez.
while read -r _nase_pkg; do
	[ -n "$_nase_pkg" ] || continue
	grep -v -x "\./lib/apk/packages/$_nase_pkg\.list" "$W/lisi2" > "$W/lisi2.tmp" || true
	mv "$W/lisi2.tmp" "$W/lisi2"
done < "$W/nase-jmena"
comm -23 "$W/lisi2" "$W/nase" > "$W/cizi" || true

nase_zm=$(comm -12 "$W/lisi2" "$W/nase" | grep -c . || true)
cizi_zm=$(grep -c . "$W/cizi" || true)

echo "  zmeneno v nasich balicich : $nase_zm"
echo "  zmeneno JINDE             : $cizi_zm"
echo

if [ "$cizi_zm" -eq 0 ]; then
	# Shoda je spravny vysledek, kdyz neni co prelozit: po plnem buildu je
	# feed totozny s archivem a rychla smycka legitimne vyrobi tentyz obraz.
	# Poplach patri JEN na pripad, kdy se lisi VERZE balicku a soubory ne -
	# tedy smycka neco prelozila a do obrazu se to nedostalo.
	if [ "$nase_zm" -eq 0 ]; then
		if [ "$_vl" -gt 0 ]; then
			echo "  ❌ NALEZ: $_vl balicku ma jinou verzi, ale zadny soubor se nelisi." >&2
			echo "     Rychla smycka je prelozila a do obrazu se nedostaly." >&2
			exit 1
		fi
		echo "  ✅ V PORADKU - obraz je totozny s plnym buildem."
		echo "     Feed se od archivu nelisi, takze nebylo co prelozit."
		exit 0
	fi
	echo "  ✅ V PORADKU - lisi se jen to, co jsme prelozili."
	comm -12 "$W/lisi2" "$W/nase" | sed 's/^/      /'
	exit 0
fi

echo "  ❌ NALEZ - $cizi_zm souboru se lisi MIMO nase balicky:"
head -40 "$W/cizi" | sed 's/^/      /'
[ "$cizi_zm" -gt 40 ] && echo "      ... a dalsich $((cizi_zm - 40))"
echo
echo "  Nejcastejsi pricina: ImageBuilder si sahl na downloads.openwrt.org,"
echo "  nebo je SDK z jineho buildu nez archiv (viz vyber archivu podle profilu)."
exit 1
