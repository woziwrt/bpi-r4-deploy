#!/bin/sh
# builder-fast.sh - rychla smycka pro praci, ktera se nedotyka jadra.
#
# EasyMesh je cely v uzivatelskem prostoru: 7 balicku shellu, rpcd a LuCI plus
# 156 patchu do map-agent, map-controller, libwifi a ieee1905, coz jsou demoni.
# Do jadra nesaha ani jednou. Presto stal do 5. 9. 2026 kazdy jednoradkovy zasah
# cely build od nuly, protoze builder maze strom. Ctyri hodiny za jeden radek
# znamenaji, ze nikdo nedela male kroky a vsichni davkuji.
#
# Zmereno 5. 9. na hotovem SDK:
#   rozbalit SDK 1,4 s | feeds 2,7 s | defconfig 2,0 s
#   prelozit balicek 5,5 s | slozit obraz 17,6 s   => pul minuty misto 45 minut
#
# NA CO TO NENI: zmena jadra, DTS, u-bootu, posun pinu. Na to plny build - SDK
# plati jen pro zaklad, ze ktereho vzniklo, a pojistka nize to hlida.
#
# Pouziti:
#   ./builder-fast.sh <profil> [archiv]
#   PACKAGES="..." ./builder-fast.sh <profil>      # vlastni seznam misto produkcniho
set -e

PROFILE="${1:?pouziti: builder-fast.sh <profil> [archiv]   napr. bananapi_bpi-r4}"
ARCH="${2:-$(ls -dt "$HOME"/archiv/*/ 2>/dev/null | while read d; do [ -d "$d/sdk" ] && { echo "$d"; break; }; done)}"
[ -n "$ARCH" ] && [ -d "$ARCH/sdk" ] || { echo "FATAL: nenasel jsem archiv s sdk/. Spust nejdriv plny build." >&2; exit 1; }
ARCH="${ARCH%/}"
SHARED="${EASYMESH_SHARED:-$HOME/easymesh-shared}"
# Pracovni adresar je NA VARIANTU, stejne jako v img-build.sh. Do 2026-09-06 byl
# jeden spolecny, takze v nem zustalo SDK a IB te varianty, ktera se stavela
# naposled - a druha do nej pak cpala svuj seznam balicku. Projevi se to jako
# "no such package" u kmod-crypto-eip-*, tedy jako chybejici balicky, a neni to
# ono: je to ImageBuilder z jineho buildu.
WORK="${WORK:-$HOME/fast-work/$PROFILE}"

# Archiv se vybira jako NEJNOVEJSI se slozkou sdk/, bez ohledu na to, pro kterou
# variantu je - takze `./builder-fast.sh bananapi_bpi-r4` bez druheho argumentu
# sahne po x8 SDK, kdyz je novejsi. Obe varianty maji tentyz target, takze by z
# toho vylezl obraz, ktery NABEHNE a bude vypadat spravne, jen bude slozeny
# napul z jednoho buildu a napul z druheho. Kdyz jmeno archivu variantu nese,
# radeji se zastavime.
case "$PROFILE" in
	*pro-8x*) case "$ARCH" in *x8*) ;; *)
		echo "FATAL: profil '$PROFILE' je x8, ale archiv vypada na universal:" >&2
		echo "       $ARCH" >&2
		echo "       Predej spravny archiv druhym argumentem." >&2; exit 1 ;; esac ;;
	*) case "$ARCH" in *x8*)
		echo "FATAL: profil '$PROFILE' neni x8, ale archiv ano:" >&2
		echo "       $ARCH" >&2
		echo "       Predej spravny archiv druhym argumentem." >&2; exit 1 ;; esac ;;
esac

echo ">>> archiv : $ARCH"

# --- pojistka: plati to SDK jeste pro dnesni zaklad? -------------------------
# SDK a ImageBuilder jsou vazane na pin, ze ktereho vznikly. Kdyz se od te doby
# posunul OpenWrt nebo MTK pin, prelozilo by se to proti jinemu zakladu, nez do
# ktereho to pak nasadime - a poznalo by se to az na zeleze. Radeji odmitnout.
recipe() { sed -n "s/^  $1  *\([0-9a-f]\{7,\}\).*/\1/p" "$ARCH/MANIFEST.txt" | head -1; }
for b in "$HOME"/universal-new/builder-production-universal.sh "$HOME"/x8-new/builder-x8-production.sh; do
	[ -f "$b" ] || continue
	_ow=$(sed -n 's/^OPENWRT_COMMIT=${OPENWRT_COMMIT:-\([0-9a-f]*\)}.*/\1/p' "$b" | head -1)
	_mt=$(sed -n 's/^MTK_COMMIT=${MTK_COMMIT:-\([0-9a-f]*\)}.*/\1/p' "$b" | head -1)
	break
done
_row=$(recipe openwrt); _rmt=$(recipe mtk-openwrt-feeds)
for pair in "openwrt:$_row:$_ow" "mtk-openwrt-feeds:$_rmt:$_mt"; do
	n=${pair%%:*}; rest=${pair#*:}; a=${rest%%:*}; b2=${rest#*:}
	[ -n "$a" ] && [ -n "$b2" ] || continue
	case "$b2" in "$a"*) ;; *)
		echo "STOP: $n se posunul od doby, kdy vzniklo tohle SDK." >&2
		echo "      SDK: $a" >&2
		echo "      pin: $b2" >&2
		echo "      Spust plny build; rychla smycka na zmenu zakladu neni." >&2
		exit 1 ;;
	esac
done
echo ">>> pojistka: piny sedi se SDK"

# --- SDK: prelozit nase balicky ---------------------------------------------
mkdir -p "$WORK"
SDKD=$(ls -d "$WORK"/openwrt-sdk-* 2>/dev/null | head -1)
if [ -z "$SDKD" ]; then
	echo ">>> rozbaluji SDK"
	tar -I zstd -xf "$ARCH"/sdk/openwrt-sdk-*.tar.zst -C "$WORK"
	SDKD=$(ls -d "$WORK"/openwrt-sdk-* | head -1)
	# Instaluje se jen nasich SEDM balicku, luci-app-easymesh schvalne ne.
	#
	# Ten dela `include $(TOPDIR)/feeds/luci/luci.mk`, takze by si pritahl cely
	# feed luci a s nim luci-base, lucihttp, lua/host, luasrcdiet/host a iwinfo -
	# nic z toho v SDK neni a 5. 9. to shodilo i preklad ostatnich balicku, ktere
	# se do te doby stavely za peti vterin.
	#
	# Nevadi to: co se nezmenilo, se neprekklada a bere se hotove z ImageBuilderu.
	# Kdyz se meni WebUI, je to prace na plny build - tam je stejne potreba videt,
	# jak se chova cely obraz.
	( cd "$SDKD" \
	  && echo "src-link easymeshr6 $SHARED/easymesh-r6-feed" > feeds.conf \
	  && rm -rf dl && ln -sfn "$HOME/dl-shared" dl \
	  && ./scripts/feeds update easymeshr6 >/dev/null \
	  && ./scripts/feeds install easymesh easymesh-api easymesh-core easymesh-config \
	       easymesh-mesh easymesh-wifi easymesh-trace >/dev/null \
	  && make defconfig >/dev/null )
fi
echo ">>> SDK: $SDKD"
( cd "$SDKD" && for p in ${FAST_PACKAGES:-easymesh easymesh-api easymesh-core \
	easymesh-config easymesh-mesh easymesh-wifi easymesh-trace}; do
		[ -d "package/feeds/easymeshr6/$p" ] || continue
		make "package/feeds/easymeshr6/$p/compile" >/tmp/fast-$p.log 2>&1 \
			|| { echo "FATAL: $p se neprelozil, viz /tmp/fast-$p.log" >&2
			     grep -vE 'warning: ignoring type redefinition|defaults for choice values|has a dependency on' /tmp/fast-$p.log | tail -12 >&2
			     exit 1; }
		echo "    prelozeno: $p"
	done )

# --- ImageBuilder: slozit obraz ---------------------------------------------
IBD=$(ls -d "$WORK"/openwrt-imagebuilder-* 2>/dev/null | head -1)
if [ -z "$IBD" ]; then
	echo ">>> rozbaluji ImageBuilder"
	tar -I zstd -xf "$ARCH"/sdk/openwrt-imagebuilder-*.tar.zst -C "$WORK"
	IBD=$(ls -d "$WORK"/openwrt-imagebuilder-* | head -1)
fi
# Pojistka: ImageBuilder musi byt soberstacny (CONFIG_IB_STANDALONE=y).
#
# Bez ni ma v `repositories` adresy na downloads.openwrt.org - vcetne feedu
# easymeshr6, iopsys a mtk_openwrt_feed, ktere tam neexistuji - a v packages/
# jen tri soubory. `make image` pak dojede az k seznamu chybejicich balicku
# (strongswan-*, switch, wifimngr, ...) a spadne po pulantre minute. Radeji to
# rict hned a jmenem. Zmereno 5. 9. 2026 na prvnim IB, ktery jsme kdy postavili.
_n=$(ls "$IBD"/packages/*.apk 2>/dev/null | wc -l)
if [ "$_n" -lt 100 ] && [ -d "$ARCH/sdk/packages-apk" ]; then
	# Tataz zaplata, jakou uz ma img-build.sh. Universal IB z 2026-09-05 14:42
	# vznikl pred CONFIG_IB_STANDALONE=y a nese tri balicky; x8 IB z 16:45 uz
	# je soberstacny. Bez teto vetve se rychla smycka na universalu nedala
	# pouzit vubec - a projevovalo se to jako "no such package" u
	# kmod-crypto-eip-*, tedy jako chybejici balicky.
	echo ">>> IB mel jen $_n balicku, doplnuji z archivu"
	cp -f "$ARCH"/sdk/packages-apk/*.apk "$IBD/packages/"
	_n=$(ls "$IBD"/packages/*.apk | wc -l)
	# Doplnit balicky NESTACI: nesoberstacny IB ma v `repositories` adresy na
	# downloads.openwrt.org a apk si tam sahne pro novejsi verzi. Soberstacny
	# ma ten soubor prazdny.
	if [ -s "$IBD/repositories" ]; then
		cp -f "$IBD/repositories" "$IBD/repositories.puvodni"
		: > "$IBD/repositories"
		echo ">>> odriznuty vzdalene repozitare"
	fi
fi
if [ "$_n" -lt 100 ]; then
	echo "STOP: tenhle ImageBuilder neni soberstacny - ma v sobe jen $_n balicku." >&2
	echo "      Vznikl pred zapnutim CONFIG_IB_STANDALONE=y v builderu," >&2
	echo "      a v archivu neni ani sdk/packages-apk/, odkud ho doplnit." >&2
	echo "      Potrebuje jeden plny build; ten uz IB postavi spravne." >&2
	exit 1
fi

# cerstve prelozene balicky maji prednost pred temi v IB
# Sobestacny IB ma soubor `repositories` PRAZDNY. Kdyz uplne CHYBI, apk skonci
# na "failed to read repositories" a hned za tim vysype seznam balicku, ktere
# "neexistuji" - takze to vypada na chybejici balicky a je to prazdny soubor.
# Zmereno 2026-09-06, stalo to ctvrt hodiny hledani ve spatnem miste.
[ -e "$IBD/repositories" ] || { : > "$IBD/repositories"; echo ">>> chybel prazdny repositories, doplnen"; }

cp -f "$SDKD"/bin/packages/*/easymeshr6/*.apk "$IBD/packages/" 2>/dev/null || true
cp -f "$SDKD"/bin/packages/*/*/*.apk "$IBD/packages/" 2>/dev/null || true

# Bez seznamu vznikne obraz o zlomku velikosti a NIC to nerekne - 5. 9. 16 MB
# proti produkcnim 125 MB. Proto se bere ten, ktery build zapsal.
PKGS="${PACKAGES:-$(cat "$ARCH/sdk/PACKAGES.txt" 2>/dev/null)}"
[ -n "$PKGS" ] || { echo "FATAL: chybi $ARCH/sdk/PACKAGES.txt a PACKAGES neni nastaveno." >&2; exit 1; }

# `files/` overlay. ImageBuilder pece do obrazu jen balicky - tohle jsou soubory,
# ktere v zadnem balicku nejsou: uci-defaults s hostnamem a LED fixem,
# /etc/easymesh-model, preinit 19-expand-fit-rootfs, instalacni skripty.
#
# Bez `FILES=` obraz NABEHNE a bude vypadat spravne, jen nebude mit hostname,
# model ani rozsireny rootfs. Nic to nerekne. Proto se tu radeji zastavime.
FILESDIR="$ARCH/files"
if [ ! -d "$FILESDIR" ]; then
	echo "STOP: $FILESDIR neexistuje - tenhle archiv vznikl pred 5. 9. vecer," >&2
	echo "      kdy se files/ overlay jeste nearchivoval." >&2
	echo "      Obraz by nabehl, ale bez hostname, /etc/easymesh-model a" >&2
	echo "      rozsireni rootfs - a nepoznalo by se to. Bud dopln overlay do" >&2
	echo "      archivu, nebo spust s FAST_ALLOW_NO_FILES=1 (obraz NENI produkcni)." >&2
	[ "${FAST_ALLOW_NO_FILES:-0}" = "1" ] || exit 1
	FILESDIR=""
fi

echo ">>> skladam obraz, profil $PROFILE, $(echo $PKGS | wc -w) balicku${FILESDIR:+, overlay $(find "$FILESDIR" -type f | wc -l) souboru}"
( cd "$IBD" && make image PROFILE="$PROFILE" PACKAGES="$PKGS" ${FILESDIR:+FILES="$FILESDIR"} >/tmp/fast-ib.log 2>&1 ) \
	|| { echo "FATAL: make image selhal, viz /tmp/fast-ib.log" >&2; tail -20 /tmp/fast-ib.log >&2; exit 1; }

echo
echo ">>> HOTOVO:"
ls -l "$IBD"/bin/targets/*/*/*.itb "$IBD"/bin/targets/*/*/*.img.gz 2>/dev/null \
	| awk '{printf "    %6.1f MB  %s\n", $5/1048576, $9}'

# img-overit.sh se diva VYHRADNE do ~/OBRAZY/<varianta>/, kam tenhle skript nic
# neklade. Kdo pusti builder-fast.sh a hned po nem img-overit.sh, dostane
# ZELENOU na uplne jiny obraz - ten, ktery tam nechal posledni img-*.sh nebo
# daemon-fast.sh, treba i o hodinu starsi.
#
# Stalo se to 6. 9. 2026: img-overit hlasil 7 rozdilnych souboru a mezi nimi
# CHYBEL names.sh, ktery se v tom buildu zmenil - protoze kontroloval obraz o
# hodinu starsi. Nic v tom vypisu na to neupozornilo.
#
# Rozdil je vecny, ne nedopatreni: tenhle skript sklada obraz z ARCHIVNICH
# balicku plus nasich sedmi, takze v nem NEJSOU zmeny demonu (mapagent,
# mapcontroller) z daemon-fast.sh. Kopirovat ho do ~/OBRAZY by je proto tise
# zahodilo. Kdyz jsou potreba obe veci naraz, patri nase .apk do
# ~/img-work/<varianta>/*/packages/ a spusti se img-<varianta>.sh.
_v=x8; case "$PROFILE" in *pro-8x*) _v=x8 ;; *) _v=universal ;; esac
echo
echo ">>> POZOR: img-overit.sh kontroluje ~/OBRAZY/$_v/ a tenhle obraz tam NENI."
echo "    Bez toho ti overi cizi obraz a nic nerekne."
