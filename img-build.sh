#!/bin/sh
# Slozi obraz z ImageBuilderu. Nic neprekklada - viz `builder-fast.sh`, ktery
# umi i prelozit nase balicky pres SDK. Tenhle skript je na to, kdyz chces
# jenom obraz z toho, co uz je hotove.
#
# Vysledky VZDY v  ~/OBRAZY/<varianta>/  - sdcard.img.gz a sysupgrade.itb.
#
# Pousti se pres img-universal.sh nebo img-x8.sh, ne primo.
set -e

VARIANT="${1:?pouziti: img-build.sh universal|x8 [priprav]}"
JEN_PRIPRAV="${2:-}"
case "$VARIANT" in
	universal) GLOB='*-production';    PROFILE=bananapi_bpi-r4 ;;
	x8)        GLOB='*-production-x8'; PROFILE=bananapi_bpi-r4-pro-8x ;;
	*) echo "neznama varianta: $VARIANT (universal | x8)" >&2; exit 1 ;;
esac

# `universal` glob by chytil i `-production-x8`, proto se x8 vyfiltruje.
ARCH=""
for d in $(ls -dt "$HOME"/archiv/$GLOB/ 2>/dev/null); do
	[ "$VARIANT" = universal ] && case "$d" in *-production-x8/) continue ;; esac
	[ -d "$d/sdk" ] || continue
	ARCH="${d%/}"; break
done
[ -n "$ARCH" ] || { echo "STOP: nenasel jsem archiv varianty $VARIANT se slozkou sdk/." >&2; exit 1; }

WORK="$HOME/img-work/$VARIANT"
OUT="$HOME/OBRAZY/$VARIANT"
PKGS_FILE="$ARCH/sdk/PACKAGES.txt"
FILESDIR="$ARCH/files"

echo ">>> varianta : $VARIANT   profil: $PROFILE"
echo ">>> archiv   : $ARCH"

[ -f "$PKGS_FILE" ] || { echo "STOP: chybi $PKGS_FILE" >&2; exit 1; }
[ -d "$FILESDIR" ] || { echo "STOP: chybi $FILESDIR - obraz by nemel hostname, /etc/easymesh-model ani rozsireny rootfs, a nepoznalo by se to." >&2; exit 1; }

# --- ImageBuilder: rozbalit jednou, pak uz jen pouzivat --------------------
mkdir -p "$WORK"
IBD=$(ls -d "$WORK"/openwrt-imagebuilder-* 2>/dev/null | head -1)
if [ -z "$IBD" ]; then
	echo ">>> rozbaluji ImageBuilder"
	tar -I zstd -xf "$ARCH"/sdk/openwrt-imagebuilder-*.tar.zst -C "$WORK"
	IBD=$(ls -d "$WORK"/openwrt-imagebuilder-* | head -1)
fi

# --- balicky uvnitr IB -----------------------------------------------------
# ImageBuilder postaveny pred 5. 9. 2026 (bez CONFIG_IB_STANDALONE=y) nese jen
# base-files, libc a kernel. Doplni se z archivu, pokud tam ty balicky jsou.
n=$(ls "$IBD"/packages/*.apk 2>/dev/null | wc -l)
if [ "$n" -lt 100 ]; then
	if [ -d "$ARCH/sdk/packages-apk" ]; then
		echo ">>> IB mel jen $n balicku, doplnuji z archivu"
		cp -f "$ARCH"/sdk/packages-apk/*.apk "$IBD/packages/"
		n=$(ls "$IBD"/packages/*.apk | wc -l)
		# ⚠️ ZMERENO 5. 9. 2026, a je to past: nesoberstacny IB ma v
		# `repositories` deset adres na downloads.openwrt.org. Doplnit mu
		# balicky NESTACI - apk si tam sahne a vezme NOVEJSI verzi z
		# internetu. Takhle se do obrazu dostalo mt76-test 2026.03.19
		# misto naseho 2026.03.05, tise, a poznalo se to az porovnanim
		# rozbalenych rootfs. Soberstacny IB ma ten soubor PRAZDNY.
		if [ -s "$IBD/repositories" ]; then
			cp -f "$IBD/repositories" "$IBD/repositories.puvodni"
			: > "$IBD/repositories"
			echo ">>> odriznuty vzdalene repozitare (jinak by si apk stahl novejsi balicky)"
		fi
	else
		echo "STOP: ImageBuilder ma v sobe jen $n balicku a v archivu neni sdk/packages-apk/." >&2
		echo "      Vznikl pred zapnutim CONFIG_IB_STANDALONE=y. Potrebuje jeden plny build." >&2
		exit 1
	fi
fi
echo ">>> balicku v IB: $n"

# --- kontrola PRED skladanim ----------------------------------------------
# `make image` s chybejicim balickem dojede az na konec a spadne po pul minute.
# Radeji to rict hned a jmenem.
chybi=""
for p in $(cat "$PKGS_FILE"); do
	set -- "$IBD/packages/$p"-[0-9]*.apk
	[ -f "$1" ] || chybi="$chybi $p"
done
if [ -n "$chybi" ]; then
	echo "STOP: v ImageBuilderu chybi tyhle balicky ze seznamu varianty $VARIANT:" >&2
	for p in $chybi; do echo "        $p" >&2; done
	exit 1
fi

if [ "$JEN_PRIPRAV" = priprav ]; then
	echo ">>> ImageBuilder je pripraveny: $IBD"
	exit 0
fi

# --- slozit ----------------------------------------------------------------
echo ">>> skladam: $(wc -w < "$PKGS_FILE") balicku, overlay $(find "$FILESDIR" -type f | wc -l) souboru"
LOG=/tmp/img-$VARIANT.log
( cd "$IBD" && make image PROFILE="$PROFILE" PACKAGES="$(cat "$PKGS_FILE")" FILES="$FILESDIR" >"$LOG" 2>&1 ) \
	|| { echo "STOP: make image selhal, viz $LOG" >&2; tail -20 "$LOG" >&2; exit 1; }

# --- vysledky na jedno misto ----------------------------------------------
mkdir -p "$OUT"
BIN="$IBD/bin/targets/mediatek/filogic"
for f in "$BIN"/*"$PROFILE"-sdcard.img.gz "$BIN"/*"$PROFILE"-squashfs-sysupgrade.itb; do
	[ -f "$f" ] || continue
	cp -f "$f" "$OUT/"
done
( cd "$OUT" && md5sum *.img.gz *.itb > MD5SUMS.txt 2>/dev/null ) || true

echo
echo ">>> HOTOVO - vysledky v $OUT"
ls -l "$OUT"/*.img.gz "$OUT"/*.itb 2>/dev/null \
	| awk '{printf "    %6.1f MB  %s\n", $5/1048576, $9}'
echo
echo "    md5 v $OUT/MD5SUMS.txt"
