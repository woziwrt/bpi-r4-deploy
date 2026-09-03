# shellcheck shell=bash
# ============================================================================
# common-easymesh.sh  —  JEDINÝ ZDROJ PRAVDY pro EasyMesh R6 WiFi/mesh vrstvu.
#
# Sourcuje se z builder-universal.sh i builder-x8.sh. Cokoli, co MUSÍ být
# na všech uzlech identické (WiFi patche, iopsys feed, easymesh config, mld
# skripty), žije JEN tady — takže x8 a universal se v tom NEMOHOU rozejít.
#
# Board/identity delta (device target, DTS, mgmt port, AL-MAC) NEPATŘÍ sem —
# ta zůstává v příslušném builder-<board>.sh.
#
# Pravidlo hranice (viz lekce 2026-07-24, split-brain / builder drift):
#   - SEM: všechno WiFi/mesh (patche, feed, easymesh defconfig, genconfig, mld)
#   - board builder: JEN {device defconfig, board patche, identita, role}
#
# Očekávané proměnné od volajícího builderu (nastavit PŘED source):
#   REPO_DIR         = absolutní cesta k repu (kvůli src-link feedu)
#   EASYMESH_SHARED  = absolutní cesta k adresáři se sdíleným iopsys-feed/
#                      a my_files-easymesh/ (WiFi patche). Jeden pro všechny.
#   AUTOBUILD_TARGET = filogic-mac80211-mt798x_rfb-wifi7_nic  (stejný na obou)
# ============================================================================

# --- 1) WiFi patche do MTK feedu (PŘED autobuild prepare) -------------------
# Voláno z build root (kde je mtk-openwrt-feeds/). Identické na všech uzlech.
easymesh_apply_wifi_patches() {
	local P="${EASYMESH_SHARED}/my_files-easymesh"
	local MAC80211="mtk-openwrt-feeds/autobuild/unified/filogic/mac80211/25.12/files"

	# BTWT: mac80211 he-btwt-supported + hostapd wpa_s btwt join.
	# (x8 je NEMĚL — driver/hostapd divergence, root řady dnešních fantomů.)
	\cp -r "$P/999-fix-01-mac80211-btwt-ap-mode.patch" \
		"$MAC80211/package/kernel/mac80211/patches/subsys/0139-fix-mac80211-btwt-ap-mode-he-btwt-supported.patch"
	\cp -r "$P/0264-wpa_s-add-btwt-join-command.patch" \
		"$MAC80211/package/network/services/hostapd/patches/0264-wpa_s-add-btwt-join-command.patch"

	# AP MLD: ap_get_sta() MLD fallback must also find a station that has been
	# answered but not yet acked (WLAN_STA_ASSOC_REQ_OK). Without it an MLD
	# station whose first 4-address frame lands in that window gets a deauth it
	# discards under PMF, the AP never enables WDS for it, and mac80211 reports
	# the unexpected 4-address frame only once - so the node stays associated,
	# reports every link up, and moves nothing. Measured twice on 2026-07-29.
	\cp -r "$P/0266-mld-find-sta-pending-assoc.patch" \
		"$MAC80211/package/network/services/hostapd/patches/0266-mld-find-sta-pending-assoc.patch"

	# AP MLD: the link AID must be marked with the same offset it was allocated
	# with, or two stations get the same AID - and since the 4-address peer
	# interface name is derived from it, the second one is pointed at an interface
	# the first already owns and its bind fails with -EBUSY. Measured 2026-07-29.
	\cp -r "$P/0267-mld-link-aid-offset.patch" \
		"$MAC80211/package/network/services/hostapd/patches/0267-mld-link-aid-offset.patch"

	# AP MLD: ap_free_sta() releases the AID and tears down the 4-address peer
	# interface for every sta_info it frees, including the per-link copies that
	# share the station's AID. So the AID goes back into the general pool while
	# its owner still holds it, and the next station is handed the same one.
	# Companion to 0267: that one fixed how the AID is marked, this one fixes
	# when it is released. Measured 2026-07-30.
	\cp -r "$P/0268-mld-link-free-keeps-aid.patch" \
		"$MAC80211/package/network/services/hostapd/patches/0268-mld-link-free-keeps-aid.patch"

	# Three bugs in MTK's Neg-TTLM ctrl_iface parser, found while getting the
	# TID-to-Link chain to fire on hardware 2026-08-31.
	#
	#  - os_strncmp(token, "link_map_size=", 15): the literal is 14 chars, so
	#    the comparison includes its NUL and never matches a token that has a
	#    value after the '='. link_map_size was silently ignored and
	#    atoi(token + 15) read past the end of the string.
	#  - tid > IEEE80211_TTLM_NUM_TIDS allows tid == 8, one past the end of
	#    dlink[8]/ulink[8]; that write lands in ulink[0].
	#  - os_memset() fills bytes, but dlink/ulink are u16[]. valid_links 0x3
	#    became 0x0303 for every TID the caller did not name explicitly.
	#
	# Not fixed here: def_link_map=1 sets dir = -1 and then trips the
	# direction check. Changing that needs the semantics decided first, and we
	# only ever send def_link_map=0.
	\cp -r "$P/0269-ttlm-ctrl-iface-parser-fixes.patch" \
		"$MAC80211/package/network/services/hostapd/patches/0269-ttlm-ctrl-iface-parser-fixes.patch"

	# per-band WiFi LED (MT7996 single-wiphy MLO) + shared tpt trigger.
	\cp -r "$P/999-wifi-01-mt7996-per-band-leds.patch" \
		"$MAC80211/package/kernel/mt76/patches/9999-w-mt7996-per-band-leds.patch"
	\cp -r "$P/999-wifi-02-mt76-share-tpt-led-trigger.patch" \
		"$MAC80211/package/kernel/mt76/patches/9999-w-mt76-share-tpt-led-trigger.patch"

	# tx_power-from-default-fw ZÁMĚRNĚ vynechán i v universalu (jen defektní
	# BE14 eeprom) — necháváme stejně vynechaný, ať zůstane shodné.
}

# --- 2) mld-*-check watchdogy + mesh helpers do image files/ ----------------
# Voláno z openwrt/ (kde je files/). Identické na všech uzlech.
easymesh_install_mld_scripts() {
	local E="${EASYMESH_SHARED}/my_files-easymesh/etc-files"
	mkdir -p files/usr/sbin files/etc/init.d files/etc/rc.d files/www/cgi-bin

	local s
	# boot-census:S99 zapisuje kazdy boot do /etc/mapc/boot-census.log (prezije
	# sysupgrade diky 97-mapc-db-keep). Spolehlivost je deliverable, ale mereni
	# z 25. 7. byl vzorek JEDEN studeny powercycle. Timhle se serie hromadi sama
	# z kazdeho bootu, ktery kdokoli kdy udela, misto abychom po Petrovi chteli
	# deset powercyclu. Verdikt si uzel odvozuje ze SVE role a SVEHO poctu radii.
	# node-heartbeat:S99 pise jednu radku za minutu + NOVE radky z dmesg do
	# /etc/mapc/heartbeat.log. boot-census odpovida na 'naskocilo to a vydrzelo
	# ctvrt hodiny'; tohle odpovida na 'co delalo minutu predtim, nez umrelo'.
	# 2026-07-25 zmizel bpi-x8 z meshe I z drateneho mgmt portu dve hodiny po
	# poslednim census vzorku a nezustalo po nem NIC - zadny crashlog a dmesg po
	# powercyclu uz popisuje jen novy boot.
	# mld-bsta-relink:S99 dela pro backhaul bSTA to, co mld-link-check pro
	# fronthaul AP-MLD. 5GHz backhaul link sedi na kanalu 36 @ 160 MHz, tedy
	# v bloku zasahujicim do DFS -> AP musi odbehnout 60 s CAC a agent se
	# mezitim pripoji jen na 6 GHz a jednolinkovy zustane (MLO linky se po
	# asociaci nepridavaji). Namereno 28.7.: CAC start v 30.2 s, agent
	# asociuje v 36.9 s. Neni to vada - AP dodrzuje predpisy; hlidac jen
	# pocka a reasociuje. 5GHz fronthaul ceka na tentyz CAC, takze zpozdeni
	# nic nezhorsuje.
	# wnm-enable:S19 bezi PRED netifd (S20), takze `option bss_transition 1`
	# je v /etc/config/wireless drive, nez se z nej konfiguruje hostapd.
	# Bez te volby hostapd KAZDOU BTM odpoved zahodi (`Ignore BSS Transition
	# Management Response ... since BSS Transition Management is disabled`,
	# namereno 4.8. na 4g) - proto btm_success zustaval 0, i kdyz steering
	# prokazatelne funguje. Poradi je zamerne: pozdejsi zapis by vyzadoval
	# `wifi reload`, coz je na MT7996 pri formovani meshe to nejhorsi, co
	# muzeme udelat.
	# wifi-evmap:S94 bezi po ustaleni wireless konfigurace a PRED wifimngr
	# (S95). Bez /etc/wifi.json wifimngr selze uz na otevreni souboru a
	# nezaregistruje ZADNY zdroj udalosti - kazdy producent v libwifi je pak
	# mrtvy kod a klienta se agent dozvi az pollingem, po minutach. Balicek
	# ten soubor nedodava a nic jineho ho nevyrabi.
	# Generuje JEDNU polozku NA LINKU: wifimngr hlida jen socks[0], coz je
	# rodicovsky socket, a na ten hostapd nic neposila (asociace chodi na
	# ap-mld-1_linkN, zmereno 4.8.). Pri jedne polozce na cely MLD se tedy
	# nedrenuje nic. HW overeno na x8: tri wifi.sta na tri nohy MLO.
	# evsrc-check:S99 overuje, ze se wifimngr na hostapd opravdu PRIPOJIL.
	# Startuje na S95 a cte evmap driv, nez existuji linkove ctrl sokety -
	# samotne 5 GHz ceka 60 s na DFS CAC. libwifi takovy zdroj registruje
	# DORMANT s fd_monitor=0, takze wifimngr pro nej neprida uloop fd, nic ho
	# nepolluje a uz nikdy se nepripoji. Zmereno na x8 po studenem startu:
	# wifimngr v 42 s, sokety v 86-93 s -> 1 socket misto 13 a vsichni
	# producenti udalosti jsou mrtvy kod, TISE (evmap se otevrel v poradku).
	# mesh-gwd:S98 - the roaming internet gateway (2026-08-05). The node
	# holding a working uplink carries the clients' gateway address; the
	# others route out through it. Harmless on a node that never sees a
	# cable - it simply routes out like everyone else.
	for s in log-collect:S05 evsrc-check:S99 wifi-evmap:S94 wnm-enable:S19 mld-link-check:S98 mld-config-check:S96 mld-report-check:S99 boot-census:S99 node-heartbeat:S99 mld-bsta-relink:S99 mesh-gwd:S98; do
		local name="${s%%:*}" rc="${s##*:}"
		# usr-sbin part is optional - log-collect is init.d-only
		if [ -e "$E/usr-sbin/$name" ]; then
			\cp "$E/usr-sbin/$name" "files/usr/sbin/$name"; chmod +x "files/usr/sbin/$name"
		fi
		\cp "$E/init.d/$name"   "files/etc/init.d/$name"; chmod +x "files/etc/init.d/$name"
		ln -sf "../init.d/$name" "files/etc/rc.d/${rc}${name}"
	done


	# bssid-pin: JEN nástroj do /usr/sbin, ŽÁDNÝ init.d skript.
	#
	# Vynechání rc.d symlinku službu NEVYPNE: OpenWrt při stavbě rootfs povolí
	# každý /etc/init.d/* s START=, takže se S95 vyrobí znovu. Naměřeno
	# 2026-07-25 — staged files/etc/rc.d mělo jen S96/S98/S99, ale rootfs
	# nového x8 image měl S95bssid-pin, a služba běžela na všech třech uzlech.
	#
	# Běžet nemá: pinuje jen rozhraní, která právě existují, a pin nikdy
	# neodstraní. Nepinnuté BSS si přitom adresu přepočítávají čítačem v
	# iface.uc, takže po každé změně sady rozhraní může sednout na zamrzlý pin.
	# Na x8 se to stalo doslova: default_sta_radio1 (wlan1_0, dnes vypnutá) je
	# připnutá na 06:0c:43:26:81:10, na které běží 5GHz AP wlan1. Závěr z
	# BSSID driftu byl odpinovat, nepinovat — tohle dělalo pravý opak.
	#
	# Nástroj zůstává spustitelný ručně, když někdo pinovat chce.
	\cp "$E/usr-sbin/bssid-pin" files/usr/sbin/bssid-pin; chmod +x files/usr/sbin/bssid-pin

	# mesh-role: sets which node serves DHCP/DNS and routes out. A tool
	# only - the choice is the user's and it is static. Getting it wrong
	# is the 2026-07-25 failure (two DHCP servers, clients with an
	# address and no internet), so it is idempotent and refuses to
	# strand the network.
	\cp "$E/usr-sbin/mesh-role" files/usr/sbin/mesh-role; chmod +x files/usr/sbin/mesh-role

	# mlo-backhaul-setup: postavi REALNY MLO backhaul (druhe AP-MLD + MLD STA)
	# misto dnesniho jednolinkoveho 6GHz spoje. JEN nastroj, ZADNY init.d — pousti
	# se vedome na jednom uzlu, protoze nespravna konfigurace backhaulu shodi mesh.
	#
	# Proc to vubec chceme (naměřeno 2026-07-25): backhaul dnes NENI MLD — tri
	# oddelene per-radiove BSS MAP--BH, kazda s vlastnim klicem, driver hlasi
	# `valid links = 0x0`. MLD STA se proti nim navazat nemuze. A druhy duvod je
	# tezsi: iPhone 16 je MLSR (max_simul_links=1, emlsr_support=0) a na Neg-TTLM
	# neodpovi, takze MLMR protistranu nam da JEDINE nas vlastni router jako MLD
	# STA. Tenhle backhaul je proto i jedina cesta, jak Neg-TTLM predvest.
	\cp "$E/usr-sbin/mlo-backhaul-setup" files/usr/sbin/mlo-backhaul-setup; chmod +x files/usr/sbin/mlo-backhaul-setup

	# mesh-env: vypise nastaveni, ktera zijou MIMO /etc/config (U-Boot env:
	# netmode, owrt_country, disable_mlo) a co z nich reálne platí. Ty hodnoty
	# ridi chovani genconfigu i regulacni domain, v zadnem uci dumpu nejsou a
	# jsou per-kus — 2026-07-25 nas kazda z nich stala hledani na spatnem miste.
	\cp "$E/usr-sbin/mesh-env" files/usr/sbin/mesh-env; chmod +x files/usr/sbin/mesh-env

	\cp "$E/www-cgi/mesh-status" files/www/cgi-bin/mesh-status; chmod +x files/www/cgi-bin/mesh-status
	\cp "$E/mesh-node-names"     files/etc/mesh-node-names

	# Odstrani fantomove bsta sekce, ktere keep-config veze pres generace.
	# Vznikaji tak, ze config_find_bsta_wireless() nekontroluje disabled, takze
	# z disabled wireless sekce vznikne mapagent bsta sekce BEZ priority ->
	# "sh: out of range". Chybejici priority je proto spolehlivy marker.
	# Patch 999 brani vzniku novych, tohle uklidi ty uz zapsane.
	# POZOR: NEMAZAT cely wireless config -- zkouseno 28.7. na HW a polozilo to
	# celou mesh (wifi config vyrobi genericky default bez bSTA a bez backhaul
	# BSS, agent se pak nema jak onboardovat a genconfig mesh vrstvu nepostavi).
	# Opt-in MLO backhaul: genconfig generuje backhaulovou MLD jen pod
	# mapagent.agent.mld_backhaul=1 ("Opt-in: without mld_backhaul=1 nothing"),
	# a ten priznak nikdo do obrazu nedaval - zil jen v behove konfiguraci,
	# tedy presne v tom, co flash zacina znovu. Prvni beh genconfigu po kazdem
	# flashi proto sel legacy vetvi a hlidac to o tri minuty pozdeji opravoval
	# restartem map-agenta. Merene 30.7.: 3 flashe = 3x repairs=1, jeden reboot
	# = repairs=0. Musi bezet PRED 991-multiap-genconfig, ktery ten priznak cte.
	\cp "$E/uci-defaults/93-easymesh-mld-backhaul" files/etc/uci-defaults/; chmod +x files/etc/uci-defaults/93-easymesh-mld-backhaul

	\cp "$E/uci-defaults/94-easymesh-drop-phantom-bsta" files/etc/uci-defaults/; chmod +x files/etc/uci-defaults/94-easymesh-drop-phantom-bsta

	# mapc.db keep pres sysupgrade (deterministic recovery vrstva)
	# Sberac logu zapnout pri bootu - init skript se dosud spoustel jen rucne
	# a /etc/rc.d flash neprezije, takze roura /tmp/mapagent.log zustavala bez ctenare.
	\cp "$E/uci-defaults/92-log-collect-enable" files/etc/uci-defaults/; chmod +x files/etc/uci-defaults/92-log-collect-enable

	# 90-mesh-gateway-vip: hands clients the virtual gateway address,
	# pins public resolvers (the ISP's are known only to whichever node
	# holds the cable), and silences the IPv6 announcements every node
	# was making into the shared bridge. Writes only what is missing -
	# uci-defaults run again after a keep-config sysupgrade.
	\cp "$E/uci-defaults/90-mesh-gateway-vip" files/etc/uci-defaults/; chmod +x files/etc/uci-defaults/90-mesh-gateway-vip

	# 91-mlo-steerd-off: mlo-steerd zustava v obrazu, ale nespousti se sam.
	# Je to druhy, nezavisly steering mozek vedle EasyMesh controlleru a 4.8.
	# bylo zmereno, jak klienta uplne odstavi: set_attlm disabled_links, kde
	# rozhoduje min_rssi() pres VSECHNY stanice a A-TTLM plati celemu AP-MLD.
	# Jeden klient v druhem pokoji tak vypne pasmo i tem u anteny (maska 4 na
	# 4g, 6 na 8g) - klient zustane asociovany a data neteci.
	# Vynechat rc.d symlink NESTACI: OpenWrt povoli kazdy init.d s START=
	# pri stavbe rootfs, takze se musi zakazat az na zarizeni.
	\cp "$E/uci-defaults/91-mlo-steerd-off" files/etc/uci-defaults/; chmod +x files/etc/uci-defaults/91-mlo-steerd-off
	\cp "$E/uci-defaults/97-mapc-db-keep" files/etc/uci-defaults/; chmod +x files/etc/uci-defaults/97-mapc-db-keep

	# Fail-safe: uzel nerozdava DHCP, dokud to node-config.sh vyslovne nedovoli.
	# Druhy DHCP server v mesh L2 domene tise vezme klientum internet.
	\cp "$E/uci-defaults/98-mesh-dhcp-safe" files/etc/uci-defaults/; chmod +x files/etc/uci-defaults/98-mesh-dhcp-safe

	# Per-radiove fronthauly pryc: AP-MLD JE fronthaul (rozhodnuto 2026-07-17).
	# Nutne jako uci-default, NE v genconfigu - tam to na provisionovanem uzlu
	# nikdy nedobehne (viz komentar ve skriptu, prokazano instrumentaci).
	\cp "$E/uci-defaults/99-drop-legacy-fronthaul" files/etc/uci-defaults/; chmod +x files/etc/uci-defaults/99-drop-legacy-fronthaul
}

# --- 5) branka pred buildem --------------------------------------------------
# Sdilene stromy jsou spravne: jeden zdroj pravdy je to, co 9. 8. chybelo, kdyz
# se dva buildery rozesly o devet dni a nikdo si toho nevsiml. Sdileni ale ma
# dve ostri, a obe je videt az kdyz build bezi:
#
#   - `easymesh_setup_iopsys_feed` dela `git reset --hard` + `git clean -fd`.
#     Rozdelana neulozena prace v iopsys-feed tim ZMIZI, bez varovani.
#
#   - z tehoz stromu se stavi ZAPECENA easymesh (produkce, =y) i APK easymesh
#     (lab, =m). Uprava mysleina pro obraz tim meni i balicky, ktere pak nekdo
#     nainstaluje na bezici uzel. Dokud je strom cisty a oznackovany, da se
#     aspon rict, CO se v obou pripadech postavilo.
#
# Proto se pred kazdym buildem overi, ze je z ceho stavet znovu. Prebiti:
# EASYMESH_ALLOW_DIRTY=1 (pro pokusy; takovy build je NEreprodukovatelny).
easymesh_require_clean_trees() {
	local dirty=0 t rev desc
	for t in "${EASYMESH_SHARED}/easymesh-r6-feed" "${EASYMESH_SHARED}/iopsys-feed" "${EASYMESH_SHARED}"; do
		[ -d "$t/.git" ] || continue
		rev=$(git -C "$t" rev-parse --short HEAD 2>/dev/null)
		desc=$(git -C "$t" describe --tags --exact-match HEAD 2>/dev/null || echo "bez znacky")
		if [ -n "$(git -C "$t" status --porcelain 2>/dev/null)" ]; then
			echo "!!! neulozene zmeny: $t  ($rev)" >&2
			git -C "$t" status --porcelain | sed 's/^/        /' >&2
			dirty=1
		else
			echo ">>> strom cisty: $(basename "$t")  $rev  [$desc]"
		fi
	done
	if [ "$dirty" = 1 ] && [ "${EASYMESH_ALLOW_DIRTY:-0}" != "1" ]; then
		echo "" >&2
		echo "STOP: build by tyhle zmeny zahodil (git reset --hard ve feedu)" >&2
		echo "      a vysledek by neslo znovu vyrobit." >&2
		echo "      Bud je zacommituj, nebo spust s EASYMESH_ALLOW_DIRTY=1." >&2
		exit 1
	fi
}

# --- 6) archiv vystupu -------------------------------------------------------
# Oba buildery zacinaji `rm -rf openwrt` a sdileji tyz adresar, takze kazdy
# build smaze uplne vsechno po tom predchozim - vcetne obrazu druhe varianty.
# Dva samostatne stromy by to vyresily, ale nevejdou se na disk (~53 GB kazdy).
# Odlozit si vystup je levnejsi a resi to, na cem zalezi.
#
# Krome binarek se zapisuje i RECEPT. Bez nej jsou obrazy neopakovatelne:
# feeds.conf.default pinuje upstream feedy jen VETVI (`;openwrt-25.12`), takze
# `feeds update` za mesic stahne neco jineho. Hashe se daji zjistit jen behem
# buildu - potom uz je strom smazany.
easymesh_archive_build() {
	local variant="${1:?variant}" root="${2:-$(pwd)}" stamp dst
	[ -d "$root/bin/targets" ] || root="$root/openwrt"
	[ -d "$root/bin/targets" ] || { echo "archiv: nenasel jsem bin/targets pod $root" >&2; return 0; }
	stamp=$(date +%Y-%m-%d-%H%M)
	dst="${HOME}/archiv/${stamp}-${variant}"
	mkdir -p "$dst/images" "$dst/packages"

	find "$root/bin/targets" \( -name '*.itb' -o -name '*.img.gz' \) -exec cp -n {} "$dst/images/" \; 2>/dev/null

	# PRIDANO 23. 8.: eMMC a NAND obrazy jsou `.bin`, takze je find vyse minul
	# a v archivu nikdy nebyly - 23. 8. se musely dolovat ze stromu rucne, a to
	# jde jen do dalsiho buildu, ktery bin/targets prepise.
	# Zabalene, protoze nezabalene maji ~188 MB. `nvme-img.bin` se VYNECHAVA
	# schvalne - ma 592 MB a instaluje se jinou cestou.
	for _b in "$root"/bin/targets/*/*/*emmc-img.bin "$root"/bin/targets/*/*/*snand-img.bin; do
		[ -f "$_b" ] || continue
		_g="$dst/images/$(basename "$_b").gz"
		[ -f "$_g" ] || gzip -c "$_b" > "$_g"
	done
	find "$root/bin/packages" -name '*.apk' \( -path '*easymeshr6*' -o -path '*iopsys*' \) \
		-exec cp -n {} "$dst/packages/" \; 2>/dev/null

	{
		echo "varianta : $variant"
		echo "postaveno: $stamp"
		echo ""
		echo "RECEPT - bez techto revizi to nejde vyrobit znovu"
		local t
		for t in easymesh-r6-feed iopsys-feed; do
			[ -d "${EASYMESH_SHARED}/$t/.git" ] && printf "  %-18s %s  [%s]\n" "$t" \
				"$(git -C "${EASYMESH_SHARED}/$t" rev-parse HEAD)" \
				"$(git -C "${EASYMESH_SHARED}/$t" describe --tags --exact-match HEAD 2>/dev/null || echo 'bez znacky')"
		done
		[ -d "$root/.git" ] && printf "  %-18s %s\n" "openwrt" "$(git -C "$root" rev-parse HEAD)"
		for t in packages luci routing telephony video; do
			[ -d "$root/feeds/$t/.git" ] && printf "  %-18s %s\n" "feeds/$t" "$(git -C "$root/feeds/$t" rev-parse HEAD)"
		done
		echo ""
		echo "OBSAH"
		ls -1 "$dst/images" 2>/dev/null | sed 's|^|  images/|'
		ls -1 "$dst/packages" 2>/dev/null | sed 's|^|  packages/|'
	} > "$dst/MANIFEST.txt"

	echo ">>> archiv: $dst  ($(du -sh "$dst" 2>/dev/null | cut -f1))"
}

# --- 3) iopsys feed = JEDEN sdílený zdroj (proti 991-typu driftu) -----------
# Voláno z openwrt/. Feed žije v EASYMESH_SHARED/iopsys-feed — jeden pro
# universal i x8, takže se NEMŮŽOU rozejít (dnes ráno 991 chyběl v x8 kopii).
# iopsys feed = map-agent, map-controller, libwifi, ieee1905 + vsechny nase
# EasyMesh patche (936, 970-994, genconfig). Zije jako samostatny git repo v
# ${EASYMESH_SHARED}/iopsys-feed a je v .gitignore, protoze ma vlastni historii.
#
# ZALOHA: do 2026-07-25 nebyly nase commity na ZADNEM remote - `origin` je
# upstream dev.iopsys.eu, kam nepushujeme, takze jadro projektu existovalo jen
# na disku VM1. Od 25. 7. je zrcadleno:
#
#   remote woziwrt = https://github.com/woziwrt/iopsys-feed.git  (private)
#   branch devel, pin 2026-08-17 -> f6ef57f45 (map-agent: a join in progress must
#   pass the genconfig gate)
#   predchozi pin f90c7d135: (map-agent: the genconfig hotplug
#   must not rewrite wireless on a box with no mesh role - a factory-fresh
#   router otherwise loses OpenWrt-2g/5g/6g and puts MAP--BH on the air)
#   predchozi pin f82f7370c: credentials come from whoever owns them -
#   mapcontroller on a controller, mapagent ap sections on an agent
#
# Pri obnove na cistem stroji klonovat odtud, ne z upstreamu - upstream nase
# patche nema. Po zmene ve feedu: commit + `git push woziwrt devel` + posunout
# pin nize, jinak `git reset --hard` v teto funkci tu zmenu pri buildu zahodi.
easymesh_setup_iopsys_feed() {
	# Feed musi stat PRESNE na pinu. Kdyz pin lokalne neni, dotahnout ho;
	# kdyz ani to nejde, build ZASTAVIT.
	#
	# 2026-08-17: zachranna vetev tu byla rozbita nadvakrat. Znela
	# `git reset --hard f23efffc4HEAD` (slepenina pinu a slova HEAD, vznikla
	# pri posouvani pinu) a koncila na `|| true`. Kdyby se pin nenasel,
	# postavilo by se to nad cimkoli, co je zrovna vytazene - tedy presne ten
	# tichy drift, proti kteremu pin je. Vracet se k HEAD nema smysl: HEAD
	# muze byt cokoli, kdezto pin je to jedine, co je overene na zeleze.
	#
	# Pin jde prebit zvenci, aby slo znovu postavit starsi PROKAZANY stav:
	#   IOPSYS_PIN=f82f7370c ./builder-...   (+ v easymesh-r6-feed vytahnout
	#   odpovidajici tag, ten se odsud nepretahuje)
	# Bez toho by `git reset --hard` nize kazdy takovy pokus prepsal zpatky
	# na aktualni pin a build by tise vyrobil dnesek misto vcerejska.
	local pin=${IOPSYS_PIN:-025478811}
	( cd "${EASYMESH_SHARED}/iopsys-feed" \
	  && { git rev-parse --verify -q "${pin}^{commit}" >/dev/null 2>&1 || git fetch --all --tags; } \
	  && git reset --hard "${pin}" && git clean -fd ) || {
		echo "FATAL: iopsys-feed nelze postavit na pin ${pin}" >&2
		echo "       (strom: ${EASYMESH_SHARED}/iopsys-feed)" >&2
		exit 1
	}
	grep -q "src-link iopsys" feeds.conf.default || \
		echo "src-link iopsys ${EASYMESH_SHARED}/iopsys-feed" >> feeds.conf.default
	./scripts/feeds update iopsys
	./scripts/feeds install libeasy libwifiutils libwifi libieee1905 ieee1905 \
		ieee1905-map-plugin wifimngr map-controller map-agent
}

# --- 4) easymesh defconfig blok (identický na všech uzlech) -----------------
# Voláno z openwrt/ PO `cp <board-defconfig> .config`. Přidá easymesh symboly
# a vypne TR181/bbfdm. Board defconfig řeší JEN device/HW volby.
# luci-app-wifimgr. Musi byt na VSECH uzlech, ne jen na klasicich: krome UI nese
# /etc/init.d/wifimgr-defaults (START=99), ktery na prvnim bootu nastavi
# country=CZ a factory SSID heslo/sifrovani. Bez nej zustane regulacni domain na
# hardcoded fallbacku US z /lib/wifi/mac80211.uc:155 (board.json nema
# wlan.defaults a owrt_country neni v U-Boot env) - presne to se stalo x8
# 2026-07-25: klasici CZ, x8 US, tedy FCC pravidla v CR.
#
# Proto je balik TADY a ne v per-builder delte: cokoli, co ovlivnuje WiFi, patri
# do sdilene vrstvy. Volat PRED `feeds install -a`, jinak se package nezaregistruje.
easymesh_install_wifimgr() {
	\cp -r "${EASYMESH_SHARED}/my_files-easymesh/luci-app-wifimgr" feeds/luci/applications/luci-app-wifimgr
}

easymesh_apply_defconfig() {
	cat >> .config <<'EASYMESH_EOF'
CONFIG_PACKAGE_libeasy=y
CONFIG_PACKAGE_libwifi=y
CONFIG_PACKAGE_libwifiutils=y
CONFIG_PACKAGE_libieee1905=y
CONFIG_PACKAGE_ieee1905=y
CONFIG_PACKAGE_ieee1905-map-plugin=y
CONFIG_PACKAGE_wifimngr=y
CONFIG_PACKAGE_map-agent=y
CONFIG_PACKAGE_kmod-ebtables=y
CONFIG_PACKAGE_map-controller=y
CONFIG_PACKAGE_wpad-openssl=y
CONFIG_PACKAGE_hostapd-common=y
CONFIG_PACKAGE_hostapd-utils=y
CONFIG_PACKAGE_wpa-cli=y
CONFIG_AGENT_EASYMESH_VERSION=6
CONFIG_CONTROLLER_EASYMESH_VERSION=6
CONFIG_MULTIAP_EASYMESH_VERSION=6
CONFIG_IEEE1905_ETH_MEDIA_EXTENSION=y
CONFIG_IEEE1905_EXTENSION_ALLOWED=y
CONFIG_IEEE1905_PLATFORM_HAS_WIFI=y
CONFIG_IEEE1905_WIFI_EASYMESH=y
CONFIG_LIBWIFI_SKIP_PROBES=y
CONFIG_LIBWIFI_USE_CTRL_IFACE=y
CONFIG_WIFIMNGR_CACHE_SCANRESULTS=y
CONFIG_WIFIMNGR_VENDOR_EXTENSIONS=y
CONFIG_WIFIMNGR_VENDOR_PREFIX="X_IOWRT_EU_"
CONFIG_PACKAGE_libsqlite3=y
CONFIG_PACKAGE_sqlite3-cli=y
CONFIG_PACKAGE_strace=y
CONFIG_PACKAGE_gdb=y
CONFIG_PACKAGE_gdbserver=y
CONFIG_PACKAGE_python3-light=y
# CONFIG_PACKAGE_dm-service is not set
# CONFIG_PACKAGE_libbbfdm-api is not set
# CONFIG_PACKAGE_libbbfdm-ubus is not set
# CONFIG_PACKAGE_bbf_configmngr is not set
CONFIG_BUSYBOX_CUSTOM=y
CONFIG_BUSYBOX_CONFIG_TIMEOUT=y
CONFIG_PACKAGE_luci-app-wifimgr=y
EASYMESH_EOF
	make defconfig
	# TR181 pluginy + libdpp vypnout (defconfig je zapíná defaultně)
	sed -i "s/^CONFIG_IEEE1905_BUILD_TR181_PLUGIN=y/# CONFIG_IEEE1905_BUILD_TR181_PLUGIN is not set/" .config
	sed -i "s/^CONFIG_WIFIMNGR_BUILD_TR181_PLUGIN=y/# CONFIG_WIFIMNGR_BUILD_TR181_PLUGIN is not set/" .config
	sed -i "s/^CONFIG_AGENT_USE_LIBDPP=y/# CONFIG_AGENT_USE_LIBDPP is not set/" .config
	sed -i "s/^CONFIG_CONTROLLER_USE_LIBDPP=y/# CONFIG_CONTROLLER_USE_LIBDPP is not set/" .config
	# dm-service + libbbfdm-* vypnout AŽ TEĎ (po vypnutí TR181 pluginů výše).
	sed -i "s/^CONFIG_PACKAGE_dm-service=y/# CONFIG_PACKAGE_dm-service is not set/" .config
	sed -i "s/^CONFIG_PACKAGE_libbbfdm-api=y/# CONFIG_PACKAGE_libbbfdm-api is not set/" .config
	sed -i "s/^CONFIG_PACKAGE_libbbfdm-ubus=y/# CONFIG_PACKAGE_libbbfdm-ubus is not set/" .config
	make defconfig
}
