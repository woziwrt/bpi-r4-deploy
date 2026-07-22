#!/bin/sh
# mlo-steerd v0.6 - MLO Link Steering Daemon + Neg-TTLM + R-TWT
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
# Measurement validity (v0.6): a reading only counts if the link is ALIVE —
# per-link `inactive time` <= LINK_INACTIVE_MAX_MS and RSSI above RSSI_FLOOR.
# An idle link reports a sentinel RSSI (~-105 dBm observed on this FW);
# v0.5 turned that into "SNR=-9dB → HARD DISABLE" and, since a link it had
# just re-enabled is idle by definition, re-disabled 6G every expiry block
# forever. MLO clients joining through the flapping link hit SAE timeouts
# (deauth reason=39) — Android shows "wrong password". Idle is not a
# measurement: no data → no steering. A disable additionally needs the bad
# condition confirmed on BAD_CONFIRM consecutive valid readings.
#
# A-TTLM lifecycle (v0.5): hostapd refuses a new set_attlm while one is
# active ("Busy: A-TTLM is on-going") and offers no early cancel, so a
# disable is issued ONCE per ATTLM_DURATION block. When the block expires
# the links come back on their own and the next loop re-measures on the
# re-enabled link — with v0.6 validity gating the probe stays neutral until
# a client actually uses the link again. v0.4 instead re-issued the mask
# every 10 s (rejected → Busy flood) and required valid SNR on a link it
# had itself emptied of clients (re-enable never fired).
#
# R-TWT groups (WiFi 7 R2, recommendation=4):
#   Group 1 (Voice): TID 6+7, ~524ms interval — guaranteed time slot for VoIP
#   Group 2 (Video): TID 4+5, ~262ms interval — guaranteed time slot for video
#   Combined with Neg-TTLM: Voice → time slot + 5G-only link
#                            Video → time slot + 5G+6G links

MLO_IF="ap-mld-1"
INTERVAL=10
ATTLM_DURATION=300000  # ms per disable block; expiry doubles as re-enable probe
ATTLM_DUR_S=$(( ATTLM_DURATION / 1000 ))

# Hard gates (dB)
SNR_HARD_LOW_6=2       # force disable 6G below this
SNR_HARD_HIGH_6=20     # force enable 6G above this (+ retries check)
SNR_HARD_LOW_5=0
SNR_HARD_HIGH_5=15

# Soft zone score thresholds (0-10000 scale)
SCORE_DISABLE=4000
SCORE_ENABLE=6000

# Retries confirmation for hard enable (% of the last interval, not lifetime)
RETRIES_CONFIRM=15
RETRIES_MIN_PKTS=20    # need at least this many tx in the interval to trust %

# Measurement validity (v0.6)
RSSI_FLOOR=-92             # at/below this the reading is sentinel/noise, not signal
LINK_INACTIVE_MAX_MS=30000 # link idle longer than this has no fresh measurement
BAD_CONFIRM=3              # consecutive valid-and-bad readings required to disable

# Cooldown between ATTLM actions (seconds)
COOLDOWN_S=30

# R-TWT group configuration (WiFi 7 R2)
RTWT_ENABLED=1
RTWT_VOICE_ID=1     # Voice TIDs 6+7, mantissa=255, exponent=4096 → ~524ms interval
RTWT_VIDEO_ID=2     # Video TIDs 4+5, mantissa=128, exponent=2048 → ~262ms interval
RTWT_CHECK_INTERVAL=6  # re-verify groups every N main loop iterations
RTWT_MAX_FAILS=3       # consecutive create failures before giving up for good

LOG_FILE=/tmp/steerd.log
LOG_MAX=200

# Events: file + syslog. Periodic status: file only (keeps logread readable).
log() {
    echo "$(date '+%H:%M:%S') [steerd] $*" >> "$LOG_FILE"
    logger -t mlo-steerd "$*"
    log_trim
}
status_log() {
    echo "$(date '+%H:%M:%S') [steerd] $*" >> "$LOG_FILE"
    log_trim
}
log_trim() {
    local lines; lines=$(wc -l < "$LOG_FILE")
    [ "$lines" -gt "$LOG_MAX" ] && tail -n "$LOG_MAX" "$LOG_FILE" > "${LOG_FILE}.tmp" && mv "${LOG_FILE}.tmp" "$LOG_FILE"
}

# Refresh FREQ_L0/1/2 from the live MLD links (channels move: DFS, reconfig).
# v0.4 hardcoded them, silently breaking SNR/busy lookups after any change.
update_link_freqs() {
    local out lid f
    out=$(iw dev "$MLO_IF" info 2>/dev/null)
    for lid in 0 1 2; do
        f=$(echo "$out" | awk -v lid="$lid" '
            /- link ID/ { cur = ($4 == lid) }
            cur && /channel / {
                s=$0; sub(/.*channel [0-9]+ \(/,"",s); sub(/ MHz.*/,"",s)
                print s+0; exit
            }')
        [ -n "$f" ] && [ "$f" -gt 0 ] && eval "FREQ_L$lid=$f"
    done
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

# Lifetime tx totals across all clients: "packets retries"
tx_totals() {
    iw dev "$MLO_IF" station dump 2>/dev/null | awk '
        /tx packets:/ { total += $NF }
        /tx retries:/ { retries += $NF }
        END { printf "%d %d", total+0, retries+0 }'
}

# Get minimum RSSI for a link_id across stations actively using that link.
# Returns "none" when no station has a live, sane reading on it: per-link
# `inactive time` must be recent and RSSI above the sentinel floor —
# an idle link's signal value is a leftover, not a measurement (v0.6).
min_rssi() {
    local lid="$1"
    iw dev "$MLO_IF" station dump 2>/dev/null | awk \
        -v lid="$lid" -v floor="$RSSI_FLOOR" -v max_ia="$LINK_INACTIVE_MAX_MS" '
        /Link/ { in_link = (index($0, "Link " lid ":") > 0); ia = -1 }
        in_link && /inactive time:/ { ia = $(NF-1)+0 }
        in_link && /signal:/ && /\[/ {
            v=$0; sub(/.*signal:[[:space:]]*/,"",v); sub(/[[:space:]].*/, "",v)
            val=v+0
            if (val != 0 && val > floor && ia >= 0 && ia <= max_ia && \
                (min==0 || val < min)) min=val
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

# Print one log line per connected client (file only)
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
' >> "$LOG_FILE"
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

# Check if R-TWT group id exists in current AP state.
# get_btwt prints entries as "id=N min_wake_dur=..." (v0.4 grepped for
# "btwt_id=" which never matches → groups were re-added forever).
btwt_exists() {
    hostapd_cli -i "$MLO_IF" get_btwt 2>/dev/null | grep -qE "(^| )id=$1 "
}

# Create R-TWT groups if missing. Gives up for the session after
# RTWT_MAX_FAILS consecutive failed creates (driver/FW without btwt support
# otherwise gets hammered with a failing add_btwt every minute).
RTWT_FAILS=0
btwt_ensure() {
    [ "$RTWT_ENABLED" -eq 0 ] && return
    local missing=0
    if ! btwt_exists "$RTWT_VOICE_ID"; then
        hostapd_cli -i "$MLO_IF" add_btwt "$RTWT_VOICE_ID" 255 4096 7 \
            recommendation=4 dl_tid_bitmap=0xC0 ul_tid_bitmap=0xC0 >/dev/null 2>&1
        missing=1
    fi
    if ! btwt_exists "$RTWT_VIDEO_ID"; then
        hostapd_cli -i "$MLO_IF" add_btwt "$RTWT_VIDEO_ID" 128 2048 7 \
            recommendation=4 dl_tid_bitmap=0x30 ul_tid_bitmap=0x30 >/dev/null 2>&1
        missing=1
    fi
    [ "$missing" -eq 0 ] && { RTWT_FAILS=0; return; }
    # Give FW a moment to register the groups in beacon, then verify
    sleep 1
    if btwt_exists "$RTWT_VOICE_ID" && btwt_exists "$RTWT_VIDEO_ID"; then
        log "R-TWT: groups ready (Voice id=$RTWT_VOICE_ID ~524ms, Video id=$RTWT_VIDEO_ID ~262ms)"
        RTWT_FAILS=0
    else
        RTWT_FAILS=$(( RTWT_FAILS + 1 ))
        if [ "$RTWT_FAILS" -ge "$RTWT_MAX_FAILS" ]; then
            RTWT_ENABLED=0
            log "R-TWT: create failed ${RTWT_FAILS}x — driver refuses, disabling for this session"
        fi
    fi
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

log "Started v0.6: if=$MLO_IF interval=${INTERVAL}s algo=weighted(SNR60+RET30+BUSY10) validity=(rssi>${RSSI_FLOOR},inact<${LINK_INACTIVE_MAX_MS}ms,confirm=${BAD_CONFIRM}) cooldown=${COOLDOWN_S}s attlm_block=${ATTLM_DUR_S}s rtwt=${RTWT_ENABLED}"
log "Override: set via 'uci set mlo-steerd.global.mode=auto|all_on|5g_only && uci commit mlo-steerd'"

WANT_DISABLE_6=0
WANT_DISABLE_5=0
NEG_TTLM_MACS=""
LAST_ACTION=0
RTWT_LOOP_CTR=0
LAST_MASK_SENT=0       # mask of the currently advertised A-TTLM (0 = none)
ATTLM_SET_AT=0         # epoch when it was issued
RET=0
BAD6_STREAK=0          # consecutive valid-and-bad readings (v0.6 confirmation)
BAD5_STREAK=0
# Seed the counters so the first interval isn't computed against zero
# (that would make iteration one see the lifetime ratio again)
set -- $(tx_totals)
PREV_TX=$1; PREV_RETR=$2

FREQ_L0=""; FREQ_L1=""; FREQ_L2=""
update_link_freqs

# Create R-TWT groups on startup
btwt_ensure

while true; do

    CLIENTS=$(iw dev "$MLO_IF" station dump 2>/dev/null | grep -c '^Station')

    if [ "$CLIENTS" -eq 0 ]; then
        for _mac in $NEG_TTLM_MACS; do neg_ttlm_teardown "$_mac"; done
        NEG_TTLM_MACS=""
        status_log "No clients — idle"
        sleep "$INTERVAL"
        continue
    fi

    # Collect inputs (frequencies first — they move on DFS events/reconfig)
    update_link_freqs
    N0=$(noise_at $FREQ_L0); N1=$(noise_at $FREQ_L1); N2=$(noise_at $FREQ_L2)
    R0=$(min_rssi 0);        R1=$(min_rssi 1);        R2=$(min_rssi 2)
    BUSY2=$(busy_at $FREQ_L2); BUSY1=$(busy_at $FREQ_L1)
    [ -z "$BUSY2" ] && BUSY2=0
    [ -z "$BUSY1" ] && BUSY1=0

    # Per-interval retries % from lifetime counter deltas. v0.4 used the
    # lifetime ratio, which never decays and wedged the enable gate.
    set -- $(tx_totals)
    TX_NOW=$1; RETR_NOW=$2
    DT=$(( TX_NOW - PREV_TX )); DR=$(( RETR_NOW - PREV_RETR ))
    if [ "$DT" -ge "$RETRIES_MIN_PKTS" ] && [ "$DR" -ge 0 ]; then
        RET=$(( DR * 100 / DT ))
    else
        RET=0   # too few samples (or counter reset on reconnect) — don't gate on noise
    fi
    PREV_TX=$TX_NOW; PREV_RETR=$RETR_NOW

    # Compute SNR per-link
    SNR0_S="n/a"; SNR1_S="n/a"; SNR2_S="n/a"
    SNR1_VALID=0; SNR2_VALID=0

    if [ "$R0" != "none" ] && [ -n "$N0" ]; then SNR0=$((R0-N0)); SNR0_S=$SNR0; fi
    if [ "$R1" != "none" ] && [ -n "$N1" ]; then SNR1=$((R1-N1)); SNR1_S=$SNR1; SNR1_VALID=1; fi
    if [ "$R2" != "none" ] && [ -n "$N2" ]; then SNR2=$((R2-N2)); SNR2_S=$SNR2; SNR2_VALID=1; fi

    NOW=$(date +%s)
    COOLDOWN_OK=$(( NOW - LAST_ACTION >= COOLDOWN_S ))

    # A-TTLM expiry: links are back on air; re-measure instead of latching.
    # The fresh (genuinely observed) SNR decides whether to disable again.
    if [ "$LAST_MASK_SENT" -gt 0 ] && [ $(( NOW - ATTLM_SET_AT )) -ge "$ATTLM_DUR_S" ]; then
        log "A-TTLM block (mask=$LAST_MASK_SENT) expired — links re-enabled, probing"
        LAST_MASK_SENT=0
        WANT_DISABLE_6=0
        WANT_DISABLE_5=0
    fi

    # --- Override mode (UCI mlo-steerd.global.mode) ---
    MODE=$(uci -q get mlo-steerd.global.mode 2>/dev/null)
    [ -z "$MODE" ] && MODE="auto"

    if [ "$MODE" = "all_on" ]; then
        WANT_DISABLE_6=0; WANT_DISABLE_5=0
    elif [ "$MODE" = "5g_only" ]; then
        WANT_DISABLE_6=1; WANT_DISABLE_5=0
    fi

    # --- 6G steering (skipped in override mode) ---
    # Invalid reading (idle link / sentinel RSSI) breaks a confirmation streak:
    # only consecutive genuinely-observed bad readings may disable a link.
    [ "$SNR2_VALID" -eq 0 ] && BAD6_STREAK=0
    [ "$SNR1_VALID" -eq 0 ] && BAD5_STREAK=0
    if [ "$MODE" = "auto" ] && [ "$SNR2_VALID" -eq 1 ] && [ "$COOLDOWN_OK" -eq 1 ]; then
        if [ "$WANT_DISABLE_6" -eq 0 ]; then
            # Check for disable (needs BAD_CONFIRM consecutive bad readings)
            BAD6=0
            if [ "$SNR2" -lt "$SNR_HARD_LOW_6" ]; then
                BAD6=1; REASON6="SNR=${SNR2}dB < hard_low=${SNR_HARD_LOW_6}dB"
            else
                SCORE=$(link_score "$SNR2" "$RET" "$BUSY2" "$SNR_HARD_LOW_6" "$SNR_HARD_HIGH_6")
                if [ "$SCORE" -lt "$SCORE_DISABLE" ]; then
                    BAD6=1; REASON6="score=$SCORE < $SCORE_DISABLE (SNR=${SNR2}dB ret=${RET}% busy=${BUSY2}%)"
                fi
            fi
            if [ "$BAD6" -eq 1 ]; then
                BAD6_STREAK=$(( BAD6_STREAK + 1 ))
                if [ "$BAD6_STREAK" -ge "$BAD_CONFIRM" ]; then
                    WANT_DISABLE_6=1; LAST_ACTION=$NOW; BAD6_STREAK=0
                    log "6G: $REASON6 confirmed ${BAD_CONFIRM}x → DISABLE"
                fi
            else
                BAD6_STREAK=0
            fi
        else
            # Check for enable (only reachable while no A-TTLM is advertised,
            # e.g. WANT set during this block before cooldown allowed sending)
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
            BAD5=0
            if [ "$SNR1" -lt "$SNR_HARD_LOW_5" ]; then
                BAD5=1; REASON5="SNR=${SNR1}dB < hard_low=${SNR_HARD_LOW_5}dB"
            else
                SCORE=$(link_score "$SNR1" "$RET" "$BUSY1" "$SNR_HARD_LOW_5" "$SNR_HARD_HIGH_5")
                if [ "$SCORE" -lt "$SCORE_DISABLE" ]; then
                    BAD5=1; REASON5="score=$SCORE < $SCORE_DISABLE (SNR=${SNR1}dB ret=${RET}% busy=${BUSY1}%)"
                fi
            fi
            if [ "$BAD5" -eq 1 ]; then
                BAD5_STREAK=$(( BAD5_STREAK + 1 ))
                if [ "$BAD5_STREAK" -ge "$BAD_CONFIRM" ]; then
                    WANT_DISABLE_5=1; LAST_ACTION=$NOW; BAD5_STREAK=0
                    log "5G: $REASON5 confirmed ${BAD_CONFIRM}x → DISABLE"
                fi
            else
                BAD5_STREAK=0
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
        if [ "$LAST_MASK_SENT" -eq 0 ]; then
            # No A-TTLM on air — advertise this block once
            if attlm_set "$MASK"; then
                LAST_MASK_SENT=$MASK
                ATTLM_SET_AT=$NOW
                log "A-TTLM: advertised mask=$MASK for ${ATTLM_DUR_S}s"
            fi
        elif [ "$MASK" -ne "$LAST_MASK_SENT" ]; then
            # hostapd can't update an active A-TTLM — apply on next expiry
            status_log "A-TTLM: mask change $LAST_MASK_SENT→$MASK deferred until current block expires"
        fi
        STATUS="ATTLM mask=$LAST_MASK_SENT want=$MASK | ret=${RET}% busy6G=${BUSY2}% busy5G=${BUSY1}%"
    else
        # All links up. Neg-TTLM only for NEW MLMR clients (v0.4 re-negotiated
        # with every client every 10 s over the air).
        ACTIVE_MASK=7
        KEPT_MACS=""
        for _mac in $NEG_TTLM_MACS; do
            case " $MLMR_MACS " in
                *" $_mac "*) KEPT_MACS="${KEPT_MACS} ${_mac}" ;;
                *) neg_ttlm_teardown "$_mac" ;;   # client left
            esac
        done
        NEG_TTLM_MACS="$KEPT_MACS"
        for _mac in $MLMR_MACS; do
            case " $NEG_TTLM_MACS " in
                *" $_mac "*) ;;   # already configured
                *) if neg_ttlm_set "$_mac" "$ACTIVE_MASK"; then
                       NEG_TTLM_MACS="${NEG_TTLM_MACS} ${_mac}"
                       log "Neg-TTLM: configured $_mac"
                   fi ;;
            esac
        done
        STATUS="all links up | ret=${RET}% busy6G=${BUSY2}% busy5G=${BUSY1}%"
    fi

    # --- R-TWT group maintenance (every RTWT_CHECK_INTERVAL iterations) ---
    RTWT_LOOP_CTR=$(( RTWT_LOOP_CTR + 1 ))
    if [ $(( RTWT_LOOP_CTR % RTWT_CHECK_INTERVAL )) -eq 0 ]; then
        btwt_ensure
    fi
    RTWT_ST=$(btwt_status)

    # --- Per-client log (file only) ---
    log_clients "$MASK" "$SNR0_S" "$SNR1_S" "$SNR2_S" "$NEG_TTLM_MACS" "$MLMR_MACS"
    status_log "$STATUS | R-TWT:$RTWT_ST"

    sleep "$INTERVAL"
done
