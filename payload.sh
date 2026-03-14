#!/bin/bash
# =============================================================================
# Argus Pager v1.0 — Counter-Surveillance & IMSI-Catcher Detection
# WiFi Pineapple Pager DuckyScript payload
#
# Scan-Modi:
#   0 = Nur WiFi           (Probe-Request-Analyse)
#   1 = WiFi + GPS         (Pager GPS_GET)
#   2 = WiFi + BT          (Standard)
#   3 = WiFi + BT + GPS    (Alle Pager-Sensoren)
#   4 = Hotel-Scan         (Spy-Kamera-Erkennung via WiFi+BT)
#   5 = Argus Full         (Pager WiFi+BT + Mudi GPS+Cell) ← NEU
#   6 = Hotel Scan 2       (Mode 4 + Mode 5: Kamera+Cell)  ← NEU
#
# Architektur:
#   Pager  →  wlan1mon (PCAP)        →  CYT Analyse
#   Pager  →  BlueZ   (BT-Scan)     →  BT Fingerprint
#   Pager  →  SSH     →  Mudi V2:
#                          ├── cell_info.py   (EM050-G via AT)
#                          ├── gps.py         (u-blox M8130 /dev/ttyACM0)
#                          └── opencellid.py  (IMSI-Catcher-Check)
#
# Repos (submodules):
#   github.com/tschakram/argus-pager        ← dieses Repo
#   └── cyt/      github.com/tschakram/chasing-your-tail-pager
#   └── raypager/ github.com/tschakram/raypager
#
# Deploy auf Pager:
#   /root/payloads/user/reconnaissance/argus-pager/
#   └── cyt/python/      (CYT submodule)
#   └── raypager/python/ (raypager submodule, Script-Referenz für Mudi-Remote)
# Config:  $PAYLOAD_DIR/config.json   (gitignored)
# Loot:    /root/loot/argus/
# =============================================================================

export PATH="/mmc/usr/bin:/mmc/usr/sbin:/mmc/bin:/mmc/sbin:$PATH"
export LD_LIBRARY_PATH="/mmc/usr/lib:/mmc/lib:${LD_LIBRARY_PATH:-}"

chmod 755 "$0" 2>/dev/null

PAYLOAD_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG="$PAYLOAD_DIR/config.json"
CYT_PY="$PAYLOAD_DIR/cyt/python"

LOOT_DIR="/root/loot/argus"
PCAP_DIR="$LOOT_DIR/pcap"
REPORT_DIR="$LOOT_DIR/reports"

mkdir -p "$PCAP_DIR" "$REPORT_DIR"

# ── LED-Konstanten ────────────────────────────────────────────────────────────
LED_OFF="000000"
LED_WHITE="ffffff"
LED_GREEN="00ff00"
LED_YELLOW="ffff00"
LED_ORANGE="ff8800"
LED_RED="ff0000"
LED_BLUE="0000ff"
LED_CYAN="00ffff"

# ── Mudi SSH-Config (Defaults, überschreibbar via config.json) ────────────────
MUDI_HOST="192.168.8.1"
MUDI_USER="root"
MUDI_KEY="/root/.ssh/mudi_key"
MUDI_PY="/root/raypager/python"

if command -v python3 >/dev/null 2>&1 && [ -f "$CONFIG" ]; then
    _h=$(python3 -c "import json; d=json.load(open('$CONFIG')); print(d.get('mudi_host',''),end='')" 2>/dev/null)
    _u=$(python3 -c "import json; d=json.load(open('$CONFIG')); print(d.get('mudi_user',''),end='')" 2>/dev/null)
    _k=$(python3 -c "import json; d=json.load(open('$CONFIG')); print(d.get('mudi_key',''),end='')" 2>/dev/null)
    _p=$(python3 -c "import json; d=json.load(open('$CONFIG')); print(d.get('mudi_python',''),end='')" 2>/dev/null)
    [ -n "$_h" ] && MUDI_HOST="$_h"
    [ -n "$_u" ] && MUDI_USER="$_u"
    [ -n "$_k" ] && MUDI_KEY="$_k"
    [ -n "$_p" ] && MUDI_PY="$_p"
fi

SSH_OPTS="-i $MUDI_KEY -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes -o HostKeyAlgorithms=+ssh-rsa"

# ── SSH-Helpers ───────────────────────────────────────────────────────────────
mudi()      { ssh $SSH_OPTS "$MUDI_USER@$MUDI_HOST" "$@" 2>/dev/null; }
mudi_py()   { local s="$1"; shift; mudi "cd '$MUDI_PY' && python3 '$s' $*"; }
check_mudi(){ mudi "echo ok" | grep -q "ok"; }

# ── Spinner-Helpers ───────────────────────────────────────────────────────────
spin_start() { START_SPINNER "$1"; }
spin_stop()  { STOP_SPINNER "$1" 2>/dev/null; STOP_SPINNER 2>/dev/null; }

# ── JSON-Field-Helper (läuft auf Pager) ───────────────────────────────────────
jget() {
    echo "$1" | python3 -c \
        "import json,sys; d=json.load(sys.stdin); print(d.get('$2','${3:-?}'),end='')" 2>/dev/null
}

# ── Cell-Threat Feedback ──────────────────────────────────────────────────────
threat_label() {
    case "$1" in
        0) echo "CLEAN"    ;; 1) echo "UNKNOWN"  ;;
        2) echo "MISMATCH" ;; 3) echo "GHOST"    ;; *) echo "?";;
    esac
}

threat_feedback() {
    case "$1" in
        0) LED $LED_GREEN  ;;
        1) LED $LED_YELLOW; VIBRATE 200 ;;
        2) LED $LED_ORANGE; VIBRATE 300; sleep 0.2; VIBRATE 300 ;;
        3) LED $LED_RED;    VIBRATE 500 ;;
    esac
}

# ── GPS via Mudi ──────────────────────────────────────────────────────────────
GPS_LAT=""; GPS_LON=""

get_mudi_gps() {
    local fix
    fix=$(mudi_py "gps.py" "--timeout" "8" 2>/dev/null)
    if [ -n "$fix" ]; then
        GPS_LAT=$(echo "$fix" | cut -d' ' -f1)
        GPS_LON=$(echo "$fix" | cut -d' ' -f2)
        return 0
    fi
    return 1
}

# ── Zone-Picker (manuell via NUMBER_PICKER) ────────────────────────────────────
_zone_picker() {
    local ztmp
    ztmp=$(mktemp /tmp/argus_zp_XXXXXX 2>/dev/null || echo "/tmp/argus_zp_$$")
    python3 "$CYT_PY/watchlist_add.py" \
        --list-zones --config "$CONFIG" 2>/dev/null \
        | grep "^ZONE:" | grep -v "^ZONE:Aktueller GPS" | cut -d: -f2- > "$ztmp"
    printf 'Mobil-Modus\n' >> "$ztmp"

    local label="" zi=1 zname
    while IFS= read -r zname; do
        local short
        short=$(echo "$zname" | cut -d'-' -f1)
        label="${label}${zi}=${short} "
        zi=$((zi+1))
    done < "$ztmp"

    local idx
    idx=$(NUMBER_PICKER "${label% }:" 1)
    local result
    result=$(sed -n "${idx}p" "$ztmp" 2>/dev/null)
    rm -f "$ztmp"
    echo "${result:-Mobil-Modus}"
}

# ── Zone ermitteln: GPS→Haversine | IP-Geo | Manuell ─────────────────────────
# Setzt CURRENT_ZONE
CURRENT_ZONE="Mobil-Modus"

get_zone() {
    local lat="${1:-}" lon="${2:-}"
    local zone_result

    if [ -n "$lat" ] && [ "$lat" != "0" ]; then
        zone_result=$(python3 "$CYT_PY/zone_check.py" \
            --config "$CONFIG" --lat "$lat" --lon "$lon" 2>/dev/null)
        case "$zone_result" in
            ZONE_GPS:*)
                CURRENT_ZONE=$(echo "$zone_result" | cut -d: -f2)
                local dist
                dist=$(echo "$zone_result" | cut -d: -f3)
                LOG green "📍 Zone: $CURRENT_ZONE (GPS, ${dist}m)"
                return
                ;;
        esac
    fi

    zone_result=$(python3 "$CYT_PY/zone_check.py" --config "$CONFIG" 2>/dev/null)
    case "$zone_result" in
        ZONE_IP:*)
            local zname zdist zcity
            zname=$(echo "$zone_result" | cut -d: -f2)
            zdist=$(echo "$zone_result" | cut -d: -f3)
            zcity=$(echo "$zone_result" | cut -d: -f4)
            CONFIRMATION_DIALOG "IP-Geo: $zcity" "Zone: $zname (~${zdist}m) OK?"
            if [ $? -eq 0 ]; then
                CURRENT_ZONE="$zname"
                LOG green "📍 Zone: $CURRENT_ZONE (IP)"
                return
            fi
            ;;
    esac

    CURRENT_ZONE=$(_zone_picker)
    [ "$CURRENT_ZONE" = "Mobil-Modus" ] && LOG "📍 Mobil" || LOG green "📍 $CURRENT_ZONE"
}

# ── WiFi/BT-Scan (Kern-Scan-Schleife, genutzt von Modi 0-6) ──────────────────
# Setzt: PCAP_FILES[], BT_SCAN_FILES[], SCAN_START_TIME
PCAP_FILES=()
BT_SCAN_FILES=()
SCAN_START_TIME=0
TCPDUMP_5G_PID=""
MUDI_ROUND_GPS_PID=""
MUDI_ROUND_CELL_PID=""

_scan_cleanup() {
    PINEAPPLE_HOPPING_STOP 2>/dev/null
    WIFI_PCAP_STOP 2>/dev/null
    [ -n "$TCPDUMP_5G_PID" ]      && kill "$TCPDUMP_5G_PID"      2>/dev/null
    [ -n "$MUDI_ROUND_GPS_PID" ]  && kill "$MUDI_ROUND_GPS_PID"  2>/dev/null
    [ -n "$MUDI_ROUND_CELL_PID" ] && kill "$MUDI_ROUND_CELL_PID" 2>/dev/null
    LED $LED_OFF
}

run_wifi_bt_scan() {
    local rounds="$1"
    local duration="$2"
    local use_bt="${3:-false}"
    local use_pager_gps="${4:-false}"   # true → GPS_GET pro Runde (Pager-intern)
    local use_mudi="${5:-false}"        # true → GPS+Cell pro Runde via Mudi (Modi 5+6)

    PCAP_FILES=()
    BT_SCAN_FILES=()
    SCAN_START_TIME=$(date +%s)
    TCPDUMP_5G_PID=""
    MUDI_ROUND_GPS_PID=""
    MUDI_ROUND_CELL_PID=""

    trap _scan_cleanup EXIT INT TERM

    LED cyan blink
    local spid
    spid=$(spin_start "Starte Channel-Hopping...")
    PINEAPPLE_HOPPING_START
    sleep 2
    spin_stop "$spid"
    LOG green "✓ Channel-Hopping aktiv (2.4/5/6 GHz)"

    for ROUND in $(seq 1 "$rounds"); do
        LOG ""
        LOG blue "━━━━━━━━━━━━━━━━━━━━━━━━━━"
        LOG blue "  Runde $ROUND / $rounds"
        LOG blue "━━━━━━━━━━━━━━━━━━━━━━━━━━"

        local TS
        TS=$(date +%Y%m%d_%H%M%S)
        local PCAP_FILE="$PCAP_DIR/scan_${TS}_r${ROUND}.pcap"
        local PCAP_5G_FILE="$PCAP_DIR/scan_${TS}_r${ROUND}_5g.pcap"

        # GPS pro Runde (Pager-intern, Modi 1+3)
        if [ "$use_pager_gps" = true ]; then
            local graw gla glo gal
            graw=$(GPS_GET)
            gla=$(echo "$graw" | awk '{print $1}')
            glo=$(echo "$graw" | awk '{print $2}')
            gal=$(echo "$graw" | awk '{print $3}')
            if [ -n "$gla" ] && [ "$gla" != "0" ]; then
                LOG "📍 GPS: $gla, $glo"
                echo "$TS,$gla,$glo,$gal" >> "$LOOT_DIR/gps_track.csv"
            fi
        fi

        local PCAP_START_TIME
        PCAP_START_TIME=$(date +%s)

        LED blue blink
        WIFI_PCAP_START

        # 5/6 GHz parallel via wlan1mon
        tcpdump -i wlan1mon -w "$PCAP_5G_FILE" 2>/dev/null &
        TCPDUMP_5G_PID=$!

        # BT-Scan parallel
        local BT_PID="" BT_FILE=""
        if [ "$use_bt" = true ]; then
            BT_FILE="$LOOT_DIR/bt_${TS}_r${ROUND}.json"
            python3 "$CYT_PY/bt_scanner.py" \
                --duration "$duration" --output "$BT_FILE" &
            BT_PID=$!
            LOG "🔍 WiFi + BT Capture läuft..."
        else
            LOG "🔍 WiFi Capture läuft..."
        fi

        # Mudi GPS+Cell parallel (Modi 5+6) — laufen während des Captures
        local MUDI_GPS_TMP="" MUDI_CELL_TMP=""
        if [ "$use_mudi" = true ] && [ "$MUDI_AVAILABLE" = true ]; then
            MUDI_GPS_TMP="/tmp/argus_gps_${ROUND}_$$"
            MUDI_CELL_TMP="/tmp/argus_cell_${ROUND}_$$"
            local gps_to=$(( duration > 18 ? duration - 10 : 8 ))
            mudi_py "gps.py" "--timeout" "$gps_to" > "$MUDI_GPS_TMP" 2>/dev/null &
            MUDI_ROUND_GPS_PID=$!
            mudi_py "cell_info.py" > "$MUDI_CELL_TMP" 2>/dev/null &
            MUDI_ROUND_CELL_PID=$!
            LOG "📡 Mudi GPS+Cell parallel gestartet (${gps_to}s Timeout)"
        fi
        LOG "   Dauer: ${duration}s"

        # Countdown
        local elapsed=0 step=15 remaining
        while [ "$elapsed" -lt "$duration" ]; do
            sleep $step
            elapsed=$((elapsed + step))
            remaining=$((duration - elapsed))
            [ "$remaining" -gt 0 ] && LOG "   ⏱ Noch ${remaining}s..."
        done

        # Stoppen
        WIFI_PCAP_STOP
        if [ -n "$TCPDUMP_5G_PID" ]; then
            kill "$TCPDUMP_5G_PID" 2>/dev/null
            wait "$TCPDUMP_5G_PID" 2>/dev/null
            TCPDUMP_5G_PID=""
        fi
        [ -n "$BT_PID" ] && wait "$BT_PID" 2>/dev/null
        if [ -f "$BT_FILE" ]; then
            BT_SCAN_FILES+=("$BT_FILE")
            local bt_cnt
            bt_cnt=$(python3 -c "import json; d=json.load(open('$BT_FILE')); print(len(d.get('bt_devices',{})))" 2>/dev/null || echo '?')
            LOG green "✓ BT: $bt_cnt Geräte"
        fi

        # Mudi GPS+Cell einsammeln
        if [ -n "$MUDI_ROUND_GPS_PID" ]; then
            wait "$MUDI_ROUND_GPS_PID" 2>/dev/null
            MUDI_ROUND_GPS_PID=""
            local gps_fix
            gps_fix=$(cat "$MUDI_GPS_TMP" 2>/dev/null)
            rm -f "$MUDI_GPS_TMP"
            if [ -n "$gps_fix" ]; then
                GPS_LAT=$(echo "$gps_fix" | cut -d' ' -f1)
                GPS_LON=$(echo "$gps_fix" | cut -d' ' -f2)
                echo "$TS,$GPS_LAT,$GPS_LON," >> "$LOOT_DIR/gps_track.csv"
                LOG green "✓ GPS R${ROUND}: $GPS_LAT, $GPS_LON"
            else
                LOG yellow "⚠ Kein GPS-Fix (R${ROUND})"
            fi
        fi
        if [ -n "$MUDI_ROUND_CELL_PID" ]; then
            wait "$MUDI_ROUND_CELL_PID" 2>/dev/null
            MUDI_ROUND_CELL_PID=""
            local cell_r
            cell_r=$(cat "$MUDI_CELL_TMP" 2>/dev/null)
            rm -f "$MUDI_CELL_TMP"
            [ -n "$cell_r" ] && CELL_JSON="$cell_r"
        fi

        sleep 5     # WIFI_PCAP_STOP flush abwarten

        # Neueste PCAP ermitteln (nach PCAP_START_TIME erstellt)
        local LATEST_PCAP=""
        for f in $(ls -t /root/loot/pcap/*.pcap 2>/dev/null); do
            local ft
            ft=$(date -r "$f" +%s 2>/dev/null)
            if [ "$ft" -ge "$PCAP_START_TIME" ]; then
                LATEST_PCAP="$f"
                break
            fi
        done

        if [ -n "$LATEST_PCAP" ]; then
            cp "$LATEST_PCAP" "$PCAP_FILE"
            PCAP_FILES+=("$PCAP_FILE")
            local probe24 probe56
            probe24=$(tcpdump -r "$PCAP_FILE" 2>/dev/null | wc -l)
            if [ -s "$PCAP_5G_FILE" ]; then
                probe56=$(tcpdump -r "$PCAP_5G_FILE" 2>/dev/null | wc -l)
                LOG green "✓ Runde $ROUND: ${probe24} Frames (2.4GHz) + ${probe56} (5/6GHz)"
            else
                LOG green "✓ Runde $ROUND: $probe24 Frames (2.4GHz)"
            fi
        else
            LOG yellow "⚠ Keine neue PCAP gefunden"
        fi

        [ "$ROUND" -lt "$rounds" ] && { LOG yellow "⏸ Pause 10s..."; sleep 10; }
    done

    PINEAPPLE_HOPPING_STOP
    LOG green "✓ WiFi/BT Scan abgeschlossen"
}

# ── Hilfsfunktionen für PCAP/BT-Listen ────────────────────────────────────────
_pcap_list() {
    local out=""
    for f in "${PCAP_FILES[@]}"; do
        out="${out:+$out,}$f"
        local f5g="${f%.pcap}_5g.pcap"
        [ -f "$f5g" ] && out="${out:+$out,}$f5g"
    done
    echo "$out"
}

_bt_list() {
    local IFS=,
    echo "${BT_SCAN_FILES[*]}"
}

# ═════════════════════════════════════════════════════════════════════════════
# ANALYSE-FUNKTIONEN
# Kein Subshell-Pattern (rpt=$(...)) — Report-Pfad + RC werden als Globals
# gesetzt, damit START_SPINNER im Subshell-Kontext keine stdout-Kontamination
# verursachen kann.
# ═════════════════════════════════════════════════════════════════════════════
LATEST_REPORT=""
ANALYSIS_RC=0

# ── CYT Analyse (Modi 0-3, 5) ─────────────────────────────────────────────────
# Setzt LATEST_REPORT und ANALYSIS_RC (0=clean, 2=verdächtig)
do_cyt_analysis() {
    local pcap_list="$1" bt_list="$2" min_apps="$3"
    LATEST_REPORT=""; ANALYSIS_RC=0
    local spid
    spid=$(spin_start "CYT Analyse...")
    local out
    out=$(python3 "$CYT_PY/analyze_pcap.py" \
        --pcaps "$pcap_list" \
        --config "$CONFIG" \
        --output-dir "$REPORT_DIR" \
        --threshold "$PERSISTENCE_THRESHOLD" \
        --min-appearances "$min_apps" \
        ${bt_list:+--bt-scans "$bt_list"} 2>&1)
    ANALYSIS_RC=$?
    spin_stop "$spid"
    LATEST_REPORT=$(echo "$out" | grep "REPORT_PATH:" | cut -d: -f2-)
    [ -z "$LATEST_REPORT" ] && \
        LATEST_REPORT=$(ls "$REPORT_DIR"/cyt_report_*.md 2>/dev/null | sort | tail -1)
}

# ── Hotel-Scan Analyse (Modi 4, 6) ────────────────────────────────────────────
# Setzt LATEST_REPORT und ANALYSIS_RC (0=clean, 2=Kamera-Verdacht)
do_hotel_analysis() {
    local pcap_list="$1" bt_file="$2"
    LATEST_REPORT=""; ANALYSIS_RC=0
    local spid
    spid=$(spin_start "Hotel-Analyse...")
    local out
    out=$(python3 "$CYT_PY/hotel_scan.py" \
        --pcap "$pcap_list" \
        ${bt_file:+--bt-scan "$bt_file"} \
        --output-dir "$REPORT_DIR" 2>&1)
    ANALYSIS_RC=$?
    spin_stop "$spid"
    LATEST_REPORT=$(echo "$out" | grep "REPORT_PATH:" | cut -d: -f2-)
    [ -z "$LATEST_REPORT" ] && \
        LATEST_REPORT=$(ls "$REPORT_DIR"/hotel_scan_*.md 2>/dev/null | sort | tail -1)
}

# ── Cell+GPS-Block an Report-Datei anhängen (Fix B) ───────────────────────────
append_cell_to_report() {
    local report="$1"
    [ -z "$report" ] || [ ! -f "$report" ] && return
    local rat mcc mnc cid rsrp thr_lbl gps_line ts
    rat=$(jget    "$CELL_JSON" rat     LTE)
    mcc=$(jget    "$CELL_JSON" mcc     -)
    mnc=$(jget    "$CELL_JSON" mnc     -)
    cid=$(jget    "$CELL_JSON" cell_id -)
    rsrp=$(jget   "$CELL_JSON" rsrp   -)
    thr_lbl=$(threat_label "${CELL_THREAT:-0}")
    gps_line="kein GPS"
    [ -n "$GPS_LAT" ] && gps_line="$(printf '%.6f' "$GPS_LAT"), $(printf '%.6f' "$GPS_LON")"
    ts=$(date '+%Y-%m-%d %H:%M:%S')
    cat >> "$report" <<CELLBLOCK

---

## Cell-Scan (Mudi V2) — $ts

| Feld | Wert |
|------|------|
| Threat | **$thr_lbl** |
| RAT | $rat |
| MCC/MNC | $mcc/$mnc |
| Cell-ID | $cid |
| RSRP | ${rsrp} dBm |
| GPS | $gps_line |
| Zone | ${CURRENT_ZONE:-Mobil} |
CELLBLOCK
}

# ── Cell-Scan via Mudi (Modi 5, 6) ────────────────────────────────────────────
# Setzt CELL_JSON, CELL_THREAT
CELL_JSON=""
CELL_THREAT=0
MUDI_AVAILABLE=false

do_cell_scan() {
    local spid
    spid=$(spin_start "Cell-Scan via Mudi...")

    # GPS nur holen wenn noch nicht gesetzt (Fix A: kein Doppel-SSH)
    if [ -z "$GPS_LAT" ]; then
        get_mudi_gps && LOG green "✓ GPS: $GPS_LAT, $GPS_LON" || LOG yellow "⚠ Kein Mudi-GPS"
    else
        LOG green "✓ GPS: $GPS_LAT, $GPS_LON (bereits gesetzt)"
    fi

    CELL_JSON=$(mudi_py "cell_info.py" 2>/dev/null)
    if [ -z "$CELL_JSON" ]; then
        spin_stop "$spid"
        LOG red "✗ Keine Cell-Daten (Mudi nicht erreichbar?)"
        CELL_THREAT=1
        return 1
    fi

    local ocid_out
    if [ -n "$GPS_LAT" ]; then
        ocid_out=$(mudi_py "opencellid.py" "$GPS_LAT" "$GPS_LON" "--queue" 2>/dev/null)
        CELL_THREAT=$?
    else
        ocid_out=$(mudi_py "opencellid.py" 2>/dev/null)
        CELL_THREAT=$?
    fi

    # CYT-Export für raypager-Reports
    mudi_py "cyt_export.py" "scan" "$GPS_LAT" "$GPS_LON" >/dev/null 2>&1

    spin_stop "$spid"
    LOG "📡 Cell-Threat: $(threat_label $CELL_THREAT)"
    return 0
}

# ── OpenCelliD-Check nach per-Runden-Scan (Modi 5+6) ─────────────────────────
# Setzt CELL_THREAT; braucht CELL_JSON gesetzt (durch run_wifi_bt_scan)
do_opencellid() {
    [ -z "$CELL_JSON" ] && return 1
    local spid
    spid=$(spin_start "OpenCelliD Check...")
    if [ -n "$GPS_LAT" ]; then
        mudi_py "opencellid.py" "$GPS_LAT" "$GPS_LON" "--queue" >/dev/null 2>/dev/null
    else
        mudi_py "opencellid.py" >/dev/null 2>/dev/null
    fi
    CELL_THREAT=$?
    mudi_py "cyt_export.py" "scan" "$GPS_LAT" "$GPS_LON" >/dev/null 2>&1
    spin_stop "$spid"
    LOG "📡 Cell-Threat: $(threat_label $CELL_THREAT)"
}

# ── Mudi-Verbindung prüfen und MUDI_AVAILABLE setzen ─────────────────────────
check_mudi_connect() {
    local spid
    spid=$(spin_start "Verbinde Mudi...")
    if check_mudi; then
        spin_stop "$spid"
        LOG green "✓ Mudi verbunden ($MUDI_HOST)"
        MUDI_AVAILABLE=true
    else
        spin_stop "$spid"
        LOG yellow "⚠ Mudi nicht erreichbar — kein GPS/Cell"
        MUDI_AVAILABLE=false
    fi
}

# ═════════════════════════════════════════════════════════════════════════════
# ERGEBNIS-ANZEIGE
# ═════════════════════════════════════════════════════════════════════════════

show_cyt_result() {
    local report="$1" rc="$2" is_hotel="${3:-false}"

    if [ "$is_hotel" = true ]; then
        local wcam bcam susp
        wcam=$(grep "WiFi Kamera-Verdächtige:" "$report" | grep -o '[0-9]*' | head -1)
        bcam=$(grep "BLE Kamera/IoT-Verdächtige:" "$report" | grep -o '[0-9]*' | head -1)
        susp=$(( ${wcam:-0} + ${bcam:-0} ))
        LOG "📷 WiFi Kameras: ${wcam:-0}  📡 BLE: ${bcam:-0}"
        if [ "$rc" -eq 2 ] || [ "${susp:-0}" -gt 0 ]; then
            LED red blink
            LOG red "🚨 KAMERA VERDACHT!"
            LOG red "   Raum gründlich prüfen!"
            grep "KRITISCH\|📷\|🔴" "$report" 2>/dev/null | head -8 | while IFS= read -r line; do
                LOG red "$line"
            done
            VIBRATE 5
        else
            LED $LED_GREEN
            LOG green "✅ Keine Kameras erkannt — Raum unauffällig"
        fi
    else
        local total susp
        total=$(grep "Geräte gesamt" "$report" | grep -o '[0-9]*' | head -1)
        susp=$(grep "Verdächtig" "$report" | grep -o '[0-9]*' | head -1)
        LOG "📊 Geräte: ${total:-0}   🔍 Verdächtig: ${susp:-0}"
        if [ "$rc" -eq 2 ] || [ "${susp:-0}" -gt 0 ]; then
            LED red blink
            LOG red "⚠ WARNUNG: Verdächtige Geräte!"
            grep "🔴\|⚠" "$report" 2>/dev/null | head -8 | while IFS= read -r line; do
                LOG red "$line"
            done
            VIBRATE 3
        else
            LED $LED_GREEN
            LOG green "✅ Keine Auffälligkeiten"
        fi
    fi
    LOG ""
    LOG "Report: $report"
}

show_cell_result_inline() {
    # Kurze Cell-Zeilen für kombinierte Reports
    local thr="$1"
    local rat mcc mnc cid rsrp thr_lbl
    rat=$(jget  "$CELL_JSON" rat  LTE)
    mcc=$(jget  "$CELL_JSON" mcc  -)
    mnc=$(jget  "$CELL_JSON" mnc  -)
    cid=$(jget  "$CELL_JSON" cell_id -)
    rsrp=$(jget "$CELL_JSON" rsrp -)
    thr_lbl=$(threat_label "$thr")
    LOG "📡 Cell: $rat $mcc/$mnc | CID:$cid | RSRP:${rsrp}dBm"
    LOG "   Threat: $thr_lbl"
    [ -n "$GPS_LAT" ] && LOG "📍 GPS: $(printf '%.4f' "$GPS_LAT"), $(printf '%.4f' "$GPS_LON")"
}

# ═════════════════════════════════════════════════════════════════════════════
# SCAN-MODI IMPLEMENTIERUNGEN
# ═════════════════════════════════════════════════════════════════════════════

# ── Modus 0-3: CYT Standard ───────────────────────────────────────────────────
run_mode_cyt() {
    local scan_mode="$1" rounds="$2" duration="$3"
    local use_bt=false use_gps=false

    case "$scan_mode" in
        1) use_gps=true ;;
        2) use_bt=true ;;
        3) use_gps=true; use_bt=true ;;
    esac

    # Pager GPS prüfen
    local pager_gps=false
    if [ "$use_gps" = true ]; then
        local graw gla
        graw=$(GPS_GET)
        gla=$(echo "$graw" | awk '{print $1}')
        if [ -n "$gla" ] && [ "$gla" != "0" ]; then
            pager_gps=true
            LOG green "✓ GPS-Fix: $gla"
        else
            LOG yellow "⚠ Kein GPS-Fix (Pager)"
        fi
    fi

    # Zone bestimmen
    if [ "$pager_gps" = true ]; then
        local graw
        graw=$(GPS_GET)
        get_zone "$(echo "$graw" | awk '{print $1}')" "$(echo "$graw" | awk '{print $2}')"
    else
        get_zone
    fi

    local min_apps=$(( duration / 60 + 2 ))
    [ "$min_apps" -lt 3 ]  && min_apps=3
    [ "$min_apps" -gt 15 ] && min_apps=15
    LOG "Min. Appearances: ${min_apps} | Runden: $rounds | Dauer: ${duration}s"
    LOG "Starte in 5s... ROT = Abbruch"
    sleep 5

    run_wifi_bt_scan "$rounds" "$duration" "$use_bt" "$pager_gps"

    LED amber solid
    LOG ""
    local pcap_list bt_list
    pcap_list=$(_pcap_list)
    bt_list=$(_bt_list)
    do_cyt_analysis "$pcap_list" "$bt_list" "$min_apps"

    LOG blue "━━━━━━━━━━━━━━━━━━━━━━━━━━"
    LOG blue "       ERGEBNIS"
    LOG blue "━━━━━━━━━━━━━━━━━━━━━━━━━━"
    [ -f "$LATEST_REPORT" ] && show_cyt_result "$LATEST_REPORT" "$ANALYSIS_RC" false \
        || LOG yellow "⚠ Kein Report"

    _watch_list_ui "$LATEST_REPORT"
    LOG ""
    LOG "Drücke ROT zum Beenden"
    WAIT_FOR_BUTTON_PRESS "red"
}

# ── Modus 4: Hotel-Scan ───────────────────────────────────────────────────────
run_mode_hotel() {
    local rounds="$1" duration="$2"

    get_zone
    LOG "Starte in 5s... ROT = Abbruch"
    sleep 5

    run_wifi_bt_scan "$rounds" "$duration" true false

    LED amber solid
    LOG ""
    local pcap_list bt_list bt_first
    pcap_list=$(_pcap_list)
    bt_list=$(_bt_list)
    bt_first=$(echo "$bt_list" | cut -d',' -f1)
    do_hotel_analysis "$pcap_list" "$bt_first"

    LOG blue "━━━━━━━━━━━━━━━━━━━━━━━━━━"
    LOG blue "     HOTEL ERGEBNIS"
    LOG blue "━━━━━━━━━━━━━━━━━━━━━━━━━━"
    [ -f "$LATEST_REPORT" ] && show_cyt_result "$LATEST_REPORT" "$ANALYSIS_RC" true \
        || LOG yellow "⚠ Kein Report"

    LOG ""
    LOG "Drücke ROT zum Beenden"
    WAIT_FOR_BUTTON_PRESS "red"
}

# ── Modus 5: Argus Full (Pager WiFi+BT + Mudi GPS+Cell) ──────────────────────
run_mode_argus() {
    local rounds="$1" duration="$2"

    # Mudi-Check
    check_mudi_connect
    [ "$MUDI_AVAILABLE" = false ] && sleep 3

    # GPS für Zone (aus Mudi, falls verfügbar)
    if [ "$MUDI_AVAILABLE" = true ] && get_mudi_gps; then
        get_zone "$GPS_LAT" "$GPS_LON"
    else
        get_zone
    fi

    LOG "Starte in 5s... ROT = Abbruch"
    sleep 5

    CELL_JSON=""; CELL_THREAT=0

    # WiFi+BT+Mudi GPS+Cell parallel pro Runde
    run_wifi_bt_scan "$rounds" "$duration" true false true

    # OpenCelliD-Check mit letztem GPS+Cell-Snapshot
    [ "$MUDI_AVAILABLE" = true ] && [ -n "$CELL_JSON" ] && do_opencellid

    LED amber solid
    LOG ""
    local pcap_list bt_list
    pcap_list=$(_pcap_list)
    bt_list=$(_bt_list)

    local min_apps=$(( duration / 60 + 2 ))
    [ "$min_apps" -lt 3 ]  && min_apps=3
    [ "$min_apps" -gt 15 ] && min_apps=15

    do_cyt_analysis "$pcap_list" "$bt_list" "$min_apps"
    local argus_cyt_report="$LATEST_REPORT"
    local argus_cyt_rc="$ANALYSIS_RC"

    # Cell+GPS in Report schreiben
    [ "$MUDI_AVAILABLE" = true ] && [ -n "$CELL_JSON" ] && \
        append_cell_to_report "$argus_cyt_report"

    # ── Ergebnis ──────────────────────────────────────────────
    LOG blue "━━━━━━━━━━━━━━━━━━━━━━━━━━"
    LOG blue "   WiFi / BT"
    LOG blue "━━━━━━━━━━━━━━━━━━━━━━━━━━"
    [ -f "$argus_cyt_report" ] && show_cyt_result "$argus_cyt_report" "$argus_cyt_rc" false \
        || LOG yellow "⚠ Kein WiFi-Report"

    LOG ""
    LOG blue "━━━━━━━━━━━━━━━━━━━━━━━━━━"
    LOG blue "   Cell / GPS (Mudi)"
    LOG blue "━━━━━━━━━━━━━━━━━━━━━━━━━━"
    if [ "$MUDI_AVAILABLE" = true ] && [ -n "$CELL_JSON" ]; then
        show_cell_result_inline "$CELL_THREAT"
        threat_feedback "$CELL_THREAT"
    else
        LOG yellow "  Mudi nicht verfügbar"
    fi

    # Gesamt-Threat
    local overall=$(( argus_cyt_rc == 2 ? 2 : 0 ))
    [ "${CELL_THREAT:-0}" -gt "$overall" ] && overall="$CELL_THREAT"

    LOG ""
    LOG blue "━━━━━━━━━━━━━━━━━━━━━━━━━━"
    LOG blue "   ARGUS GESAMT"
    LOG blue "━━━━━━━━━━━━━━━━━━━━━━━━━━"

    local wifi_susp cell_lbl gps_line
    wifi_susp=$(grep "Verdächtig" "$argus_cyt_report" 2>/dev/null | grep -o '[0-9]*' | head -1)
    cell_lbl=$(threat_label "${CELL_THREAT:-0}")
    gps_line="kein GPS"
    [ -n "$GPS_LAT" ] && gps_line="$(printf '%.4f' "$GPS_LAT"), $(printf '%.4f' "$GPS_LON")"

    local body
    printf -v body \
        "WiFi Verdächtig: %s Geräte\nBT-Scan:         aktiv\nCell Threat:     %s\nGPS:             %s\nZone:            %s" \
        "${wifi_susp:-0}" "$cell_lbl" "$gps_line" "${CURRENT_ZONE:-Mobil}"
    SHOW_REPORT "Argus Gesamt" "$body"
    WAIT_FOR_BUTTON_PRESS

    [ "$overall" -ge 2 ] && VIBRATE 5

    _watch_list_ui "$argus_cyt_report"

    LOG ""
    LOG "Drücke ROT zum Beenden"
    WAIT_FOR_BUTTON_PRESS "red"
}

# ── Modus 6: Hotel Scan 2 (Spy-Kameras + Cell-Bedrohung) ──────────────────────
run_mode_hotel2() {
    local rounds="$1" duration="$2"

    # Mudi-Check
    check_mudi_connect
    [ "$MUDI_AVAILABLE" = false ] && sleep 2

    # GPS für Zone
    if [ "$MUDI_AVAILABLE" = true ] && get_mudi_gps; then
        get_zone "$GPS_LAT" "$GPS_LON"
    else
        get_zone
    fi

    LOG "Starte in 5s... ROT = Abbruch"
    sleep 5

    CELL_JSON=""; CELL_THREAT=0

    # WiFi+BT+Mudi GPS+Cell parallel pro Runde
    run_wifi_bt_scan "$rounds" "$duration" true false true

    # OpenCelliD-Check mit letztem GPS+Cell-Snapshot
    [ "$MUDI_AVAILABLE" = true ] && [ -n "$CELL_JSON" ] && do_opencellid

    LED amber solid
    LOG ""
    local pcap_list bt_list bt_first
    pcap_list=$(_pcap_list)
    bt_list=$(_bt_list)
    bt_first=$(echo "$bt_list" | cut -d',' -f1)

    do_hotel_analysis "$pcap_list" "$bt_first"
    local hotel2_rpt="$LATEST_REPORT"
    local hotel2_rc="$ANALYSIS_RC"

    # Cell+GPS in Report schreiben (Fix B)
    [ "$MUDI_AVAILABLE" = true ] && [ -n "$CELL_JSON" ] && \
        append_cell_to_report "$hotel2_rpt"

    # ── Ergebnis ──────────────────────────────────────────────
    LOG blue "━━━━━━━━━━━━━━━━━━━━━━━━━━"
    LOG blue "   Hotel Scan (Kameras)"
    LOG blue "━━━━━━━━━━━━━━━━━━━━━━━━━━"
    [ -f "$hotel2_rpt" ] && show_cyt_result "$hotel2_rpt" "$hotel2_rc" true \
        || LOG yellow "⚠ Kein Hotel-Report"

    LOG ""
    LOG blue "━━━━━━━━━━━━━━━━━━━━━━━━━━"
    LOG blue "   Cell / GPS (Mudi)"
    LOG blue "━━━━━━━━━━━━━━━━━━━━━━━━━━"
    if [ "$MUDI_AVAILABLE" = true ] && [ -n "$CELL_JSON" ]; then
        show_cell_result_inline "$CELL_THREAT"
        threat_feedback "$CELL_THREAT"
    else
        LOG yellow "  Mudi nicht verfügbar"
    fi

    # Kombinierter Report
    local wcam bcam cell_lbl gps_line
    wcam=$(grep "WiFi Kamera-Verdächtige:" "$hotel2_rpt" 2>/dev/null | grep -o '[0-9]*' | head -1)
    bcam=$(grep "BLE Kamera/IoT-Verdächtige:" "$hotel2_rpt" 2>/dev/null | grep -o '[0-9]*' | head -1)
    cell_lbl=$(threat_label "${CELL_THREAT:-0}")
    gps_line="kein GPS"
    [ -n "$GPS_LAT" ] && gps_line="$(printf '%.4f' "$GPS_LAT"), $(printf '%.4f' "$GPS_LON")"

    local body
    printf -v body \
        "WiFi Kameras:  %s\nBLE Verdächt:  %s\nCell Threat:   %s\nGPS:           %s\nZone:          %s" \
        "${wcam:-0}" "${bcam:-0}" "$cell_lbl" "$gps_line" "${CURRENT_ZONE:-Mobil}"
    SHOW_REPORT "Hotel Scan 2" "$body"
    WAIT_FOR_BUTTON_PRESS

    # Kombinierter Alert
    local overall=0
    [ "${hotel2_rc:-0}" -eq 2 ] && overall=2
    [ "${CELL_THREAT:-0}" -gt "$overall" ] && overall="$CELL_THREAT"
    [ "$overall" -ge 2 ] && VIBRATE 5

    LOG ""
    LOG "Drücke ROT zum Beenden"
    WAIT_FOR_BUTTON_PRESS "red"
}

# ── Watch-List UI ──────────────────────────────────────────────────────────────
_watch_list_ui() {
    local report="$1"
    [ -z "$report" ] || [ ! -f "$report" ] && return

    local wl_tmp
    wl_tmp=$(mktemp /tmp/argus_wl_XXXXXX 2>/dev/null || echo "/tmp/argus_wl_$$")

    grep "^| 🔴" "$report" | awk -F'|' '{
        mac=$2; gsub(/[^0-9a-fA-F:]/, "", mac)
        vendor=$3; gsub(/^[[:space:]]+|[[:space:]]+$/, "", vendor)
        if (length(mac) == 17) print mac "|" vendor
    }' > "$wl_tmp"

    local mac_count
    mac_count=$(awk 'END{print NR}' "$wl_tmp")

    if [ "$mac_count" -gt 0 ]; then
        LOG ""
        LOG blue "━━━━━━━━━━━━━━━━━━━━━━━━━━"
        LOG blue "   Watch-List Management"
        LOG blue "━━━━━━━━━━━━━━━━━━━━━━━━━━"

        # MACs nummeriert ab 1; Skip = mac_count+1 (letzter Eintrag, als Default)
        local i=1
        while IFS='|' read -r wl_mac wl_vendor; do
            [ -z "$wl_mac" ] && continue
            LOG "  $i. $wl_vendor"
            LOG "     $wl_mac"
            i=$((i+1))
        done < "$wl_tmp"
        local skip_idx=$((mac_count + 1))
        LOG "  $skip_idx. Überspringen"
        sleep 8

        local WL_LABEL="" wi=1
        while IFS='|' read -r wl_mac wl_vendor; do
            [ -z "$wl_mac" ] && continue
            local sfx
            sfx=$(echo "$wl_mac" | cut -c10-)
            WL_LABEL="${WL_LABEL}${wi}=${sfx} "
            wi=$((wi+1))
        done < "$wl_tmp"
        WL_LABEL="${WL_LABEL}${skip_idx}=Skip"

        local pick
        pick=$(NUMBER_PICKER "${WL_LABEL}:" $skip_idx)   # Default = Skip
        [ $? -ne 0 ] && rm -f "$wl_tmp" && return
        [ "$pick" -eq "$skip_idx" ] 2>/dev/null && rm -f "$wl_tmp" && return

        if [ "$pick" -ge 1 ] 2>/dev/null && [ "$pick" -le "$mac_count" ] 2>/dev/null; then
            local sel_line sel_mac sel_vendor
            sel_line=$(sed -n "${pick}p" "$wl_tmp")
            sel_mac=$(echo "$sel_line" | cut -d'|' -f1)
            sel_vendor=$(echo "$sel_line" | cut -d'|' -f2-)

            local wt_pick
            wt_pick=$(NUMBER_PICKER $'Watch-Typ:\n1:Dynamic\n2:Static\n3:Cancel' 1)
            [ $? -ne 0 ] && rm -f "$wl_tmp" && return
            [ "$wt_pick" -eq 3 ] 2>/dev/null && rm -f "$wl_tmp" && return

            local watch_type="dynamic"
            [ "$wt_pick" -eq 2 ] && watch_type="static"

            CONFIRMATION_DIALOG "Watch-List hinzufügen?" "$sel_mac ($watch_type)"
            if [ $? -eq 0 ]; then
                local wl_out wl_status
                wl_out=$(python3 "$CYT_PY/watchlist_add.py" \
                    --mac "$sel_mac" --label "$sel_vendor" \
                    --type "$watch_type" --config "$CONFIG" \
                    --path "$LOOT_DIR/watch_list.json" 2>/dev/null)
                wl_status=$(echo "$wl_out" | grep "^WATCHLIST:" | cut -d: -f2)
                case "$wl_status" in
                    OK)             VIBRATE 3; LOG green "✓ Watch-List: $sel_mac ($watch_type)" ;;
                    ALREADY_EXISTS) LOG yellow "⚠ Bereits in Watch-List" ;;
                    *)              LOG red "✗ Fehler beim Hinzufügen" ;;
                esac
            fi
        fi
    fi

    rm -f "$wl_tmp"
}

# ═════════════════════════════════════════════════════════════════════════════
# MAIN
# ═════════════════════════════════════════════════════════════════════════════
PERSISTENCE_THRESHOLD=0.6

# ── Startup-Banner ────────────────────────────────────────────────────────────
LED cyan blink
LOG "=============================="
LOG "      Argus Pager v1.0"
LOG "=============================="
LOG ""
LOG " Counter-Surveillance"
LOG " + IMSI-Catcher Detection"
LOG ""
sleep 2

# ── Dependency Check ──────────────────────────────────────────────────────────
SPINNER_ID=$(spin_start "Checking...")
if ! command -v python3 >/dev/null 2>&1; then
    spin_stop "$SPINNER_ID"
    LOG red "Python3 fehlt! Installiere..."
    opkg install -d mmc python3 2>/dev/null
fi

# Systemzeit synchronisieren
CURRENT_YEAR=$(date +%Y)
ntpd -q -p pool.ntp.org 2>/dev/null && \
    LOG green "✓ NTP: $(date '+%d.%m.%Y %H:%M')" || \
    LOG green "✓ Systemzeit: $(date '+%d.%m.%Y %H:%M')"

spin_stop "$SPINNER_ID"

# Cleanup alter Scan-Daten
python3 "$CYT_PY/cleanup.py" --config "$CONFIG" 2>/dev/null \
    | grep "^CLEANUP:" | cut -d: -f2- \
    | while IFS= read -r msg; do [ -n "$msg" ] && LOG green "🗑 $msg"; done
sleep 1

# ── Standard-Dauer aus Config ─────────────────────────────────────────────────
CFG_DURATION=$(python3 -c "
import json
try:
    c=json.load(open('$CONFIG'))
    print(c.get('timing',{}).get('check_interval',60))
except: print(60)
" 2>/dev/null)
CFG_DURATION=${CFG_DURATION:-60}

# ── Quick Start vs. Manuell ───────────────────────────────────────────────────
LOG ""
LOG blue "━━━━━━━━━━━━━━━━━━━━━━━━━━"
LOG blue "   Standard-Konfiguration"
LOG blue "━━━━━━━━━━━━━━━━━━━━━━━━━━"
LOG ""
LOG "  Modus:  2 (WiFi + BT)"
LOG "  Runden: 2"
LOG "  Dauer:  ${CFG_DURATION}s"
LOG ""
sleep 2

QSTART=$(NUMBER_PICKER "1=Standard 2=Manuell:" 1)
[ $? -ne 0 ] && QSTART=1

if [ "$QSTART" -eq 1 ]; then
    LOG green "  ✓ Standard: WiFi + BT"
    run_mode_cyt 2 2 "$CFG_DURATION"
else
    LOG ""
    LOG blue "━━━━━━━━━━━━━━━━━━━━━━━━━━"
    LOG blue "     Scan-Modi"
    LOG blue "━━━━━━━━━━━━━━━━━━━━━━━━━━"
    LOG ""
    LOG "0 = Nur WiFi"
    LOG "1 = WiFi + GPS (Pager)"
    LOG "2 = WiFi + BT"
    LOG "3 = WiFi + BT + GPS"
    LOG "4 = Hotel-Scan  (Kamera)"
    LOG "5 = Argus Full  (Pager+Mudi)"
    LOG "6 = Hotel Scan 2 (Kamera+Cell)"
    LOG ""
    sleep 4

    SCAN_MODE=$(NUMBER_PICKER "Modus (0-6):" 2)
    [ $? -ne 0 ] && SCAN_MODE=2

    SCAN_ROUNDS=$(NUMBER_PICKER "Scan-Runden:" 2)
    [ $? -ne 0 ] && SCAN_ROUNDS=2

    SCAN_DURATION=$(NUMBER_PICKER "Dauer (Sek):" "$CFG_DURATION")
    [ $? -ne 0 ] && SCAN_DURATION=$CFG_DURATION

    LOG ""
    LOG "Modus: $SCAN_MODE | Runden: $SCAN_ROUNDS | Dauer: ${SCAN_DURATION}s"
    sleep 1

    case "$SCAN_MODE" in
        0|1|2|3) run_mode_cyt    "$SCAN_MODE" "$SCAN_ROUNDS" "$SCAN_DURATION" ;;
        4)       run_mode_hotel               "$SCAN_ROUNDS" "$SCAN_DURATION" ;;
        5)       run_mode_argus               "$SCAN_ROUNDS" "$SCAN_DURATION" ;;
        6)       run_mode_hotel2              "$SCAN_ROUNDS" "$SCAN_DURATION" ;;
        *)
            LOG red "Unbekannter Modus: $SCAN_MODE"
            LOG "Drücke ROT zum Beenden"
            WAIT_FOR_BUTTON_PRESS "red"
            ;;
    esac
fi

LED $LED_OFF
exit 0
