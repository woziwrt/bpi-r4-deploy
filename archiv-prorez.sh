#!/bin/sh
# Prorezani archivu: RECEPT se necha navzdy, VYSLEDEK jen u poslednich generaci.
#
# Jeden archiv ma ~2 GB, z toho je recept (MANIFEST.txt, files/, packages/,
# sdk/PACKAGES.txt) asi 1,4 MB. Zbytek jsou obrazy a SDK, ktere jdou z receptu
# postavit znovu - a hlavne je nikdo starsi nez par dni nepotrebuje, protoze
# navrat se dela o jednu, nanejvys dve generace zpatky.
#
#   ./archiv-prorez.sh            nasucho, jen ukaze co by smazal
#   ./archiv-prorez.sh smazat     opravdu smaze
#
# NECHAVA se vzdy: MANIFEST.txt, FILES.txt, files/, packages/,
#                  sdk/PACKAGES.txt, sdk/*.manifest, sdk/MD5SUMS.txt,
#                  sdk/packages-apk/
# MAZE se: sdk/*.tar.zst (SDK a ImageBuilder) a images/
DELAT="${1:-}"
KEEP=2            # kolik nejnovejsich generaci KAZDE varianty zustane cele

celkem=0
for varianta in production production-x8; do
	n=0
	for d in $(ls -dt "$HOME"/archiv/*-"$varianta"/ 2>/dev/null); do
		# glob 'production' chytne i 'production-x8', vyfiltruj
		[ "$varianta" = production ] && case "$d" in *-production-x8/) continue ;; esac
		n=$((n + 1))
		d="${d%/}"
		if [ "$n" -le "$KEEP" ]; then
			printf "  NECHAT CELE  %s\n" "$(basename "$d")"
			continue
		fi
		vel=$(du -sk "$d/images" "$d"/sdk/*.tar.zst 2>/dev/null | awk '{s+=$1} END {print s+0}')
		[ "${vel:-0}" -eq 0 ] && continue
		celkem=$((celkem + vel))
		printf "  prorezat     %-34s uvolni %5d MB\n" "$(basename "$d")" "$((vel / 1024))"
		if [ "$DELAT" = smazat ]; then
			rm -rf "$d/images" || echo "    !!! nepodarilo se smazat $d/images" >&2
			rm -f "$d"/sdk/*.tar.zst || echo "    !!! nepodarilo se smazat tarbally v $d/sdk" >&2
			echo "prorezano $(date '+%F %T') - obrazy a SDK smazany, recept zustava" > "$d/PROREZANO.txt"
		fi
	done
done

echo
if [ "$DELAT" = smazat ]; then
	echo "  SMAZANO, uvolneno $((celkem / 1024 / 1024)) GB"
else
	echo "  nasucho: uvolnilo by se $((celkem / 1024 / 1024)) GB   (spust s argumentem 'smazat')"
fi
