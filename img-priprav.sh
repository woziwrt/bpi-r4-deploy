#!/bin/sh
# Pripravi OBA ImageBuildery, aby byly pripravene k pouziti - rozbali je,
# doplni balicky, kdyz jsou prazdne, a odrizne vzdalene repozitare.
# Neskvlada zadny obraz. Pousti se po kazdem plnem buildu.
#
# Pripravene lezi v  ~/img-work/universal/  a  ~/img-work/x8/
D=$(dirname "$0")
chyb=0
for v in universal x8; do
	echo "############ $v ############"
	"$D/img-build.sh" "$v" priprav || { echo "!!! $v se nepodarilo pripravit" >&2; chyb=$((chyb+1)); }
	echo
done
echo "############ stav ############"
for v in universal x8; do
	ibd=$(ls -d "$HOME/img-work/$v"/openwrt-imagebuilder-* 2>/dev/null | head -1)
	if [ -n "$ibd" ]; then
		printf "  %-10s %4d balicku   repozitare ven: %s\n" "$v" \
			"$(ls "$ibd"/packages/*.apk 2>/dev/null | wc -l)" \
			"$([ -s "$ibd/repositories" ] && echo "ANO - POZOR" || echo "ne")"
	else
		printf "  %-10s nepripraveny\n" "$v"
	fi
done
exit $chyb
