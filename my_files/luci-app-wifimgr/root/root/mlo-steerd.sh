#!/bin/sh
# mlo-steerd v0.4 - MLO Link Steering Daemon + Neg-TTLM + R-TWT
#
# Steering algorithm (per-link):
#   Hard disable : SNR < SNR_HARD_LOW (ignore other params)
#   Hard enable  : SNR > SNR_HARD_HIGH AND retries < RETRIES_CONFIRM
#   Soft zone    : weighted score = SNR*60% + retries*30% + busy*10%
#                  score < SCORE_DISABLE → disable
#                  score > SCORE_ENABLE  → enable
#                  score in between      → no change (hysteresis)
#   Cooldown     : min COOLDOWN_S seconds between ATTLM actions
#
# R-TWT groups (WiFi 7 R2, recommendation=4):
#   Group 1 (Voice): TID 6+7, ~524ms interval — guaranteed time slot for VoIP
#   Group 2 (Video): TID 4+5, ~262ms interval — guaranteed time slot for video
#   Combined with Neg-TTLM: Voice → time slot + 5G-only link
#                            Video → time slot + 5G+6G links

MLO_IF="ap-mld-1"
INTERVAL=10
ATTLM_DURATION=25000   # ms, must be > INTERVAL*1000 with margin

# Hard gates (dB)
SNR_HARD_LOW_6=2       # force disable 6G below this
SNR_HARD_HIGH_6=20     # force enable 6G above this (+ retries check)
SNR_HARD_LOW_5=0
SNR_HARD_HIGH_5=15

# Soft zone score thresholds (0-10000 scale)
SCORE_DISABLE=4000
SCORE_ENABLE=6000

# Retries confirmation for hard enable
RETRIES_CONFIRM=15     # % max retries to confirm enable
RETRIES_MIN_PKTS=300   # min tx packets per interval for a fresh retries %; below it the last value is kept
RETRIES_STATE=/tmp/steerd-retries.state

# Cooldown between ATTLM actions (seconds)
COOLDOWN_S=30

# R-TWT group configuration (WiFi 7 R2)
RTWT_ENABLED=1
RTWT_VOICE_ID=1     # Voice TIDs 6+7, mantissa=255, exponent=4096 → ~524ms interval
RTWT_VIDEO_ID=2     # Video TIDs 4+5, mantissa=128, exponent=2048 → ~262ms interval
RTWT_CHECK_INTERVAL=6  # re-verify groups every N main loop iterations

# Link → frequency mapping (fallbacks; refreshed from the running AP every loop)
FREQ_L0=2462
FREQ_L1=5180
FREQ_L2=6135

LOG_FILE=/tmp/steerd.log
LOG_MAX=200
log() {
    local msg="$(date '+%H:%M:%S') [steerd] $*"
    echo "$msg" >> "$LOG_FILE"
    logger -t mlo-steerd "$*"
    local lines; lines=$(wc -l < "$LOG_FILE")
    [ "$lines" -gt "$LOG_MAX" ] && tail -n "$LOG_MAX" "$LOG_FILE" > "${LOG_FILE}.tmp" && mv "${LOG_FILE}.tmp" "$LOG_FILE"
}

# Refresh FREQ_L0..2 from the actual link channels (channel/ACS/DFS changes)
update_link_freqs() {
    local lid freq
    while read -r lid freq; do
        case "$lid" in
            0) FREQ_L0=$freq ;;
            1) FREQ_L1=$freq ;;
            2) FREQ_L2=$freq ;;
        esac
    done <<EOF
$(iw dev "$MLO_IF" info 2>/dev/null | awk '
    /link ID/ { lid=$4 }
    /channel/ && lid != "" { f=$3; gsub(/[^0-9]/, "", f); print lid, f; lid="" }
')
EOF
}

# Get noise floor (dBm) for a frequency
noise_at() {
    local freq="$1"
    iw dev "$MLO_IF" survey dump 2>/dev/null | awk -v f="$freq" '
        index($0, f " MHz [in use]") { found=1; next }
        found && /noise:/ { gsub(/[^-0-9]/, "", $2); print $2+0; found=0; exit }
    '
}

# Get channel busy % for a frequency (cumulative since last reset — good enough)
busy_at() {
    local freq="$1"
    iw dev "$MLO_IF" survey dump 2>/dev/null | awk -v f="$freq" '
        index($0, f " MHz [in use]") { found=1; next }
        found && /channel active time:/ { active=$(NF-1)+0; next }
        found && /channel busy time:/   { busy=$(NF-1)+0
            if (active > 0) printf "%d", (busy * 100) / active
            else print "0"
            found=0; exit
        }
        found && /frequency:/ && !index($0, f) { found=0 }
    '
}

# Get aggregate tx retries % across all connected clients over the last interval.
# Counters in station dump are cumulative since association, so the previous
# per-station values are kept in RETRIES_STATE and only the delta is used.
# Only the per-station totals are read (one leading tab); the per-link lines
# under "Link N:" repeat the same traffic and would count it twice.
# Must be called once per loop: each call advances the baseline.
retries_pct() {
    iw dev "$MLO_IF" station dump 2>/dev/null | awk \
        -v state="$RETRIES_STATE" -v minp="$RETRIES_MIN_PKTS" '
        BEGIN {
            last = -1
            while ((getline l < state) > 0) {
                split(l, a, " ")
                if (a[1] == "_last") last = a[2]
                else { pp[a[1]] = a[2]; pr[a[1]] = a[3] }
            }
            close(state)
        }
        /^Station / { mac = $2 }
        /^\ttx packets:/ { p[mac] = $NF; total += $NF }
        /^\ttx retries:/ { r[mac] = $NF; retries += $NF }
        END {
            # New stations and re-associations (counters went down) have
            # no baseline yet and are left out of this interval
            for (m in p)
                if ((m in pp) && p[m] >= pp[m] && r[m] >= pr[m]) {
                    dp += p[m] - pp[m]; dr += r[m] - pr[m]
                }
            if (dp >= minp)    pct = int(dr * 100 / dp)
            else if (last >= 0) pct = last
            else               pct = (total > 0) ? int(retries * 100 / total) : 0
            printf "" > state
            for (m in p) print m, p[m], r[m] > state
            print "_last", pct > state
            print pct
        }
    '
}

# Get minimum RSSI for a link_id (returns "none" if link idle)
min_rssi() {
    local lid="$1"
    iw dev "$MLO_IF" station dump 2>/dev/null | awk -v lid="$lid" '
        /Link/ { in_link = (index($0, "Link " lid ":") > 0) }
        in_link && /signal:/ && /\[/ {
            v=$0; sub(/.*signal:[[:space:]]*/,"",v); sub(/[[:space:]].*/, "",v)
            val=v+0
            if (val != 0 && (min==0 || val < min)) min=val
            in_link=0
        }
        END { print (min+0 != 0) ? min : "none" }
    '
}

# Weighted link score (0-10000). Inputs: snr, retries%, busy%
# SNR normalized over soft zone [hard_low..hard_high]
link_score() {
    local snr="$1" ret="$2" busy="$3"
    local low="$4" high="$5"   # hard gate values for this link
    local range=$(( high - low ))
    local snr_norm=$(( (snr - low) * 100 / range ))
    [ $snr_norm -lt 0 ]   && snr_norm=0
    [ $snr_norm -gt 100 ] && snr_norm=100
    local ret_score=$(( 100 - ret ))
    [ $ret_score -lt 0 ] && ret_score=0
    local busy_score=$(( 100 - busy ))
    [ $busy_score -lt 0 ] && busy_score=0
    echo $(( snr_norm * 60 + ret_score * 30 + busy_score * 10 ))
}

# Remaining A-TTLM duration in ms, 0 if no A-TTLM is active.
# hostapd refuses SET_ATTLM while one is active ("Busy: A-TTLM is on-going"),
# so a new mapping can only be issued after the previous one expires.
attlm_remaining_ms() {
    hostapd_cli -i "$MLO_IF" get_attlm 2>/dev/null | awk '
        /Remaining Expected Duration:/ { print $4 + 0; found=1 }
        END { if (!found) print 0 }
    '
}

# issue SET_ATTLM for given disabled_links bitmask
attlm_set() {
    local mask="$1"
    hostapd_cli -i "$MLO_IF" set_attlm \
        disabled_links=$mask switch_time=200 \
        duration=$ATTLM_DURATION link_mapping_size=0 >/dev/null 2>&1
}

# Return space-separated list of MLMR client MACs (max_simul_links > 1)
get_mlmr_macs() {
    hostapd_cli -i "$MLO_IF" all_sta 2>/dev/null | awk '
        /^[0-9a-f][0-9a-f]:[0-9a-f][0-9a-f]:/ { mac=$1 }
        /max_simul_links=/ {
            split($1,a,"="); if (a[2]+0 > 1) print mac
        }
    '
}

# Print one log line per connected client
log_clients() {
    local mask="$1"
    local snr0="$2" snr1="$3" snr2="$4"
    local ttlm_macs="$5"
    local dis0=$(( mask & 1 ))
    local dis1=$(( (mask >> 1) & 1 ))
    local dis2=$(( (mask >> 2) & 1 ))

    iw dev "$MLO_IF" station dump 2>/dev/null | awk \
        -v dis0="$dis0" -v dis1="$dis1" -v dis2="$dis2" \
        -v snr0="$snr0" -v snr1="$snr1" -v snr2="$snr2" \
        -v mlmr_macs="$6" -v ttlm_macs="$ttlm_macs" \
        -v prefix="$(date '+%H:%M:%S') [steerd]" '
    BEGIN {
        n=split(ttlm_macs,t," "); for(i=1;i<=n;i++) has_ttlm[t[i]]=1
        n=split(mlmr_macs,m," "); for(i=1;i<=n;i++) is_mlmr[m[i]]=1
        band[0]="2G"; band[1]="5G"; band[2]="6G"
        snr[0]=snr0; snr[1]=snr1; snr[2]=snr2
        dis[0]=dis0;  dis[1]=dis1;  dis[2]=dis2
    }
    /^Station / {
        if (mac != "") print_client()
        mac=$2; cur_link=-1
    }
    /Link [0-9]+:/ { tmp=$0; sub(/.*Link /,"",tmp); sub(/:.*/, "",tmp); cur_link=tmp+0 }
    cur_link>=0 && /signal:/ && /\[/ {
        sig=$0; sub(/.*signal:[[:space:]]*/,"",sig); sub(/[[:space:]].*/, "",sig)
        if (sig+0 != 0) active_link=cur_link
    }
    END { if (mac != "") print_client() }
    function print_client(    type,l,info,ttlm,short) {
        type = (mac in is_mlmr) ? "MLMR" : "EMLSR"
        short = substr(mac,1,8)
        info = ""
        for (l=0; l<=2; l++) {
            if (snr[l] == "n/a") {
                info = info " " band[l] ":idle"
            } else if (dis[l]) {
                info = info " " band[l] ":dis(snr=" snr[l] ")"
            } else {
                info = info " " band[l] ":snr=" snr[l]
            }
        }
        ttlm = (mac in has_ttlm) ? "  TTLM:active" : ""
        printf "%s  %-9s %-5s %s%s\n", prefix, short, type, info, ttlm
    }
'
}

# Apply Neg-TTLM for MLMR client
neg_ttlm_set() {
    local mac="$1" active="$2"
    local L1=$(( (active >> 1) & 1 ))
    local L2=$(( (active >> 2) & 1 ))
    local voice video be bg

    [ "$L1" -eq 1 ] && voice=2 || voice="$active"
    video=0
    [ "$L1" -eq 1 ] && video=$(( video | 2 ))
    [ "$L2" -eq 1 ] && video=$(( video | 4 ))
    [ "$video" -eq 0 ] && video="$active"
    be="$active"; [ "$be" -eq 0 ] && be=7
    bg=$(( active & 3 )); [ "$bg" -eq 0 ] && bg="$active"

    hostapd_cli -i "$MLO_IF" negotiated_ttlm request "$mac" \
        dir=2 def_link_map=0 link_map_size=1 num_tids=8 \
        0 "$be" 1 "$bg" 2 "$bg" 3 "$be" \
        4 "$video" 5 "$video" 6 "$voice" 7 "$voice" >/dev/null 2>&1
}

neg_ttlm_teardown() {
    hostapd_cli -i "$MLO_IF" negotiated_ttlm teardown "$1" >/dev/null 2>&1
}

# Check if R-TWT group id exists in current AP state
btwt_exists() {
    hostapd_cli -i "$MLO_IF" get_btwt 2>/dev/null | grep -q "^id=$1 "
}

# Create R-TWT groups if missing. First add_btwt call may timeout (known FW delay)
# but succeeds; a second call with same id returns FAIL (slot occupied) — that is OK.
btwt_ensure() {
    [ "$RTWT_ENABLED" -eq 0 ] && return
    local changed=0
    if ! btwt_exists "$RTWT_VOICE_ID"; then
        hostapd_cli -i "$MLO_IF" add_btwt "$RTWT_VOICE_ID" 255 4096 7 \
            recommendation=4 dl_tid_bitmap=0xC0 ul_tid_bitmap=0xC0 >/dev/null 2>&1
        log "R-TWT: created Voice group id=$RTWT_VOICE_ID (TID 6+7, ~524ms)"
        changed=1
    fi
    if ! btwt_exists "$RTWT_VIDEO_ID"; then
        hostapd_cli -i "$MLO_IF" add_btwt "$RTWT_VIDEO_ID" 128 2048 7 \
            recommendation=4 dl_tid_bitmap=0x30 ul_tid_bitmap=0x30 >/dev/null 2>&1
        log "R-TWT: created Video group id=$RTWT_VIDEO_ID (TID 4+5, ~262ms)"
        changed=1
    fi
    [ "$changed" -eq 0 ] && return
    # Give FW a moment to register the groups in beacon
    sleep 1
}

# Return R-TWT status string for log ("V+D" / "V" / "D" / "none")
btwt_status() {
    [ "$RTWT_ENABLED" -eq 0 ] && echo "off" && return
    local v=0 d=0
    btwt_exists "$RTWT_VOICE_ID" && v=1
    btwt_exists "$RTWT_VIDEO_ID" && d=1
    if [ "$v" -eq 1 ] && [ "$d" -eq 1 ]; then echo "V+D"
    elif [ "$v" -eq 1 ]; then echo "V"
    elif [ "$d" -eq 1 ]; then echo "D"
    else echo "none"
    fi
}

# --- main ---

log "Started v0.4: if=$MLO_IF interval=${INTERVAL}s algo=weighted(SNR60+RET30+BUSY10) cooldown=${COOLDOWN_S}s rtwt=${RTWT_ENABLED}"
log "Override: set via 'uci set mlo-steerd.global.mode=auto|all_on|5g_only && uci commit mlo-steerd'"

WANT_DISABLE_6=0
WANT_DISABLE_5=0
NEG_TTLM_MACS=""
LAST_ACTION=0
RTWT_LOOP_CTR=0
rm -f "$RETRIES_STATE"

# Create R-TWT groups on startup
btwt_ensure

while true; do

    CLIENTS=$(iw dev "$MLO_IF" station dump 2>/dev/null | grep -c '^Station')

    if [ "$CLIENTS" -eq 0 ]; then
        for _mac in $NEG_TTLM_MACS; do neg_ttlm_teardown "$_mac"; done
        NEG_TTLM_MACS=""
        log "No clients — idle"
        sleep "$INTERVAL"
        continue
    fi

    # Collect inputs
    update_link_freqs
    N0=$(noise_at $FREQ_L0); N1=$(noise_at $FREQ_L1); N2=$(noise_at $FREQ_L2)
    R0=$(min_rssi 0);        R1=$(min_rssi 1);        R2=$(min_rssi 2)
    RET=$(retries_pct)
    BUSY2=$(busy_at $FREQ_L2); BUSY1=$(busy_at $FREQ_L1)
    [ -z "$BUSY2" ] && BUSY2=0
    [ -z "$BUSY1" ] && BUSY1=0

    # Compute SNR per-link
    SNR0_S="n/a"; SNR1_S="n/a"; SNR2_S="n/a"
    SNR1_VALID=0; SNR2_VALID=0

    if [ "$R0" != "none" ] && [ -n "$N0" ]; then SNR0=$((R0-N0)); SNR0_S=$SNR0; fi
    if [ "$R1" != "none" ] && [ -n "$N1" ]; then SNR1=$((R1-N1)); SNR1_S=$SNR1; SNR1_VALID=1; fi
    if [ "$R2" != "none" ] && [ -n "$N2" ]; then SNR2=$((R2-N2)); SNR2_S=$SNR2; SNR2_VALID=1; fi

    NOW=$(date +%s)
    COOLDOWN_OK=$(( NOW - LAST_ACTION >= COOLDOWN_S ))

    # --- Override mode (UCI mlo-steerd.global.mode) ---
    MODE=$(uci -q get mlo-steerd.global.mode 2>/dev/null)
    [ -z "$MODE" ] && MODE="auto"

    if [ "$MODE" = "all_on" ]; then
        WANT_DISABLE_6=0; WANT_DISABLE_5=0
    elif [ "$MODE" = "5g_only" ]; then
        WANT_DISABLE_6=1; WANT_DISABLE_5=0
    fi

    # --- 6G steering (skipped in override mode) ---
    if [ "$MODE" = "auto" ] && [ "$SNR2_VALID" -eq 1 ] && [ "$COOLDOWN_OK" -eq 1 ]; then
        if [ "$WANT_DISABLE_6" -eq 0 ]; then
            # Check for disable
            if [ "$SNR2" -lt "$SNR_HARD_LOW_6" ]; then
                WANT_DISABLE_6=1; LAST_ACTION=$NOW
                log "6G: SNR=${SNR2}dB < hard_low=${SNR_HARD_LOW_6}dB → HARD DISABLE"
            else
                SCORE=$(link_score "$SNR2" "$RET" "$BUSY2" "$SNR_HARD_LOW_6" "$SNR_HARD_HIGH_6")
                if [ "$SCORE" -lt "$SCORE_DISABLE" ]; then
                    WANT_DISABLE_6=1; LAST_ACTION=$NOW
                    log "6G: SNR=${SNR2}dB ret=${RET}% busy=${BUSY2}% score=$SCORE < $SCORE_DISABLE → DISABLE"
                fi
            fi
        else
            # Check for enable
            if [ "$SNR2" -gt "$SNR_HARD_HIGH_6" ] && [ "$RET" -lt "$RETRIES_CONFIRM" ]; then
                WANT_DISABLE_6=0; LAST_ACTION=$NOW
                log "6G: SNR=${SNR2}dB > hard_high=${SNR_HARD_HIGH_6}dB ret=${RET}% → HARD ENABLE"
            else
                SCORE=$(link_score "$SNR2" "$RET" "$BUSY2" "$SNR_HARD_LOW_6" "$SNR_HARD_HIGH_6")
                if [ "$SCORE" -gt "$SCORE_ENABLE" ]; then
                    WANT_DISABLE_6=0; LAST_ACTION=$NOW
                    log "6G: SNR=${SNR2}dB ret=${RET}% busy=${BUSY2}% score=$SCORE > $SCORE_ENABLE → ENABLE"
                fi
            fi
        fi
    fi

    # --- 5G steering (only if 6G already disabled, skipped in override mode) ---
    if [ "$MODE" = "auto" ] && [ "$SNR1_VALID" -eq 1 ] && [ "$COOLDOWN_OK" -eq 1 ]; then
        if [ "$WANT_DISABLE_5" -eq 0 ] && [ "$WANT_DISABLE_6" -eq 1 ]; then
            if [ "$SNR1" -lt "$SNR_HARD_LOW_5" ]; then
                WANT_DISABLE_5=1; LAST_ACTION=$NOW
                log "5G: SNR=${SNR1}dB < hard_low=${SNR_HARD_LOW_5}dB → HARD DISABLE"
            else
                SCORE=$(link_score "$SNR1" "$RET" "$BUSY1" "$SNR_HARD_LOW_5" "$SNR_HARD_HIGH_5")
                if [ "$SCORE" -lt "$SCORE_DISABLE" ]; then
                    WANT_DISABLE_5=1; LAST_ACTION=$NOW
                    log "5G: SNR=${SNR1}dB ret=${RET}% busy=${BUSY1}% score=$SCORE < $SCORE_DISABLE → DISABLE"
                fi
            fi
        elif [ "$WANT_DISABLE_5" -eq 1 ]; then
            if [ "$SNR1" -gt "$SNR_HARD_HIGH_5" ] && [ "$RET" -lt "$RETRIES_CONFIRM" ]; then
                WANT_DISABLE_5=0; LAST_ACTION=$NOW
                log "5G: SNR=${SNR1}dB > hard_high=${SNR_HARD_HIGH_5}dB → HARD ENABLE"
            else
                SCORE=$(link_score "$SNR1" "$RET" "$BUSY1" "$SNR_HARD_LOW_5" "$SNR_HARD_HIGH_5")
                if [ "$SCORE" -gt "$SCORE_ENABLE" ]; then
                    WANT_DISABLE_5=0; LAST_ACTION=$NOW
                    log "5G: SNR=${SNR1}dB ret=${RET}% busy=${BUSY1}% score=$SCORE > $SCORE_ENABLE → ENABLE"
                fi
            fi
        fi
    fi

    # --- Compute ATTLM mask and apply ---
    MASK=0
    [ "$WANT_DISABLE_5" -eq 1 ] && MASK=$(( MASK | 2 ))
    [ "$WANT_DISABLE_6" -eq 1 ] && MASK=$(( MASK | 4 ))

    MLMR_MACS=$(get_mlmr_macs)

    if [ "$MASK" -gt 0 ]; then
        for _mac in $NEG_TTLM_MACS; do neg_ttlm_teardown "$_mac"; done
        NEG_TTLM_MACS=""
        # Re-arm right at expiry instead of every loop: avoids the refused
        # "Busy" calls and the gap where disabled links briefly come back.
        REMAIN=$(attlm_remaining_ms)
        if [ "$REMAIN" -gt 0 ] && [ "$REMAIN" -lt $(( INTERVAL * 1000 )) ]; then
            sleep $(( REMAIN / 1000 + 1 ))
            REMAIN=$(attlm_remaining_ms)
        fi
        [ "$REMAIN" -eq 0 ] && attlm_set "$MASK"
        STATUS="ATTLM mask=$MASK | ret=${RET}% busy6G=${BUSY2}% busy5G=${BUSY1}%"
    else
        ACTIVE_MASK=7
        NEW_NEG_MACS=""
        for _mac in $MLMR_MACS; do
            # Mapping is static while all links are up: send it once per client
            case " $NEG_TTLM_MACS " in
                *" $_mac "*) NEW_NEG_MACS="${NEW_NEG_MACS} ${_mac}"; continue ;;
            esac
            neg_ttlm_set "$_mac" "$ACTIVE_MASK" && NEW_NEG_MACS="${NEW_NEG_MACS} ${_mac}"
        done
        NEG_TTLM_MACS="$NEW_NEG_MACS"
        STATUS="all links up | ret=${RET}% busy6G=${BUSY2}% busy5G=${BUSY1}%"
    fi

    # --- R-TWT group maintenance (every RTWT_CHECK_INTERVAL iterations) ---
    RTWT_LOOP_CTR=$(( RTWT_LOOP_CTR + 1 ))
    if [ $(( RTWT_LOOP_CTR % RTWT_CHECK_INTERVAL )) -eq 0 ]; then
        btwt_ensure
    fi
    RTWT_ST=$(btwt_status)

    # --- Per-client log ---
    log_clients "$MASK" "$SNR0_S" "$SNR1_S" "$SNR2_S" "$NEG_TTLM_MACS" "$MLMR_MACS"
    log "$STATUS | R-TWT:$RTWT_ST"

    sleep "$INTERVAL"
done
