# Argus Pager

Counter-Surveillance & IMSI-Catcher Detection für den WiFi Pineapple Pager.

Umbrella-Repo das **Chasing Your Tail NG** (WiFi/BT Surveillance Detection) und **Raypager** (IMSI-Catcher Detection via Mudi V2) unter einem einheitlichen Payload zusammenführt.

**Version:** v1.2 (payload.sh) / CYT v4.8 / Raypager v1.1

---

## Neue Features (v1.2 / v4.8)

### Camera Activity Detection
Erkennt ob verdächtige Kameras **aktiv aufzeichnen** — nicht nur ob sie existieren.
Nach dem Hotel-Scan (Modus 4/6) analysiert `camera_activity.py` die Data-Frame-Bandbreite
der erkannten Kamera-BSSIDs. Spikes > 200 KB/s deuten auf Video-Stream/Upload hin.

### Shodan / CVEDB Integration
- **InternetDB** (kostenlos): IP-Lookup für verdächtige Geräte mit öffentlichen IPs (Ports, Tags, CVEs)
- **CVEDB** (kostenlos): Automatischer CVE-Lookup für erkannte Kamera-Hersteller (Hikvision, Dahua, etc.)
- **Shodan Full API** (optional, $49): Erweiterte Host-Info (Org, ASN, Banner)

### Fingerbank Device Identification
MAC-Adresse + DHCP-Fingerprint → Gerätekategorie via Fingerbank API (kostenlos).
Erkennt ob ein Gerät eine IP-Kamera, NVR, IoT-Device etc. ist — unabhängig vom OUI.

### IP-Extraktion aus PCAPs
Extrahiert MAC→IP-Zuordnungen und DHCP Option 55 Fingerprints direkt aus Data-Frames
im PCAP. Ermöglicht InternetDB-Enrichment und Fingerbank-Lookup ohne zusätzliche Captures.

### Weitere Verbesserungen (v1.2)
- Config-Loading optimiert (ein Python-Call statt vier)
- `jget()` Input-Injection Fix (stdin statt String-Interpolation)
- Doppelter GPS-Aufruf in Modus 5/6 behoben
- Dead Code entfernt (`do_cell_scan`, `do_opencellid`)
- SQLite Context Manager + MAC-Case-Fix
- fd-Leak Fix in GPS-Reader
- Shared `utils.py` für Raypager (Threat-Level-Konstanten, Haversine)

---

## Scan-Modi

| Modus | Name | Sensoren | Hardware |
|-------|------|----------|----------|
| 0 | WiFi only | Probe-Request-Analyse | Pager |
| 1 | WiFi + GPS | Probe-Analyse + GPS-Track | Pager |
| 2 | WiFi + BT | Probe + Bluetooth (Standard) | Pager |
| 3 | WiFi + BT + GPS | Alle Pager-Sensoren | Pager |
| 4 | Hotel Scan | Spy-Kamera-Erkennung (WiFi+BT) | Pager |
| **5** | **Argus Full** | WiFi+BT Surveillance + Cell-Threat + GPS | Pager + Mudi |
| **6** | **Hotel Scan 2** | Spy-Kameras + IMSI-Catcher | Pager + Mudi |

Modi 5 und 6 benötigen den Mudi V2 (GL-E750V2) mit laufendem raypager.

---

## How to Use

> ⚠️ Der Payload **muss** über das **Pager-Dashboard** gestartet werden:
> `Payloads → User → Reconnaissance → argus-pager`
> Nicht über `bash payload.sh` in SSH – Pager-APIs funktionieren nur im Dashboard-Kontext.

### Schnellstart

1. Pager via USB-C mit Laptop verbinden
2. Pager-GUI öffnen: `http://172.16.52.1:1471`
3. Payload **argus-pager** → **Start**
4. Im Startmenü: `1 = Standard` (WiFi + BT, 2 Runden) oder `2 = Manuell` für Modusauswahl

### Manueller Scan

Nach Wahl `2 = Manuell`:

1. **Modus wählen** (0–6, siehe Scan-Modi-Tabelle oben)
2. **Runden** eingeben — wie oft der Scan wiederholt wird
3. **Dauer** (Sekunden) — Länge einer Scan-Runde
4. Scan läuft automatisch — LED blinkt blau während Capture
5. Nach dem Scan: Ergebnis-Report wird angezeigt

### Nach dem Scan

- **Watch-List**: Verdächtige Geräte können direkt zur Überwachungsliste hinzugefügt werden
- **OpenCelliD Upload**: Wenn Queue nicht leer → Dialog zum Hochladen der gesammelten Messungen (Modi 5+6)
- **IMEI Rotation** (OPSEC): `2 = IMEI Change` wählen → Mudi rotiert IMEI und bootet neu

---

### Schritt 1 — Ignore-Listen einrichten

Eigene Geräte **vor dem ersten Scan** eintragen, um Fehlalarme zu vermeiden.
Die Dateien liegen in `/root/loot/argus/ignore_lists/` auf dem Pager (gitignored).

**`mac_list.json`** — eigene WiFi- und Bluetooth-Geräte:
```json
{
  "ignore_macs": ["AA:BB:CC:DD:EE:FF", "11:22:33:44:55:66"],
  "comments": {
    "AA:BB:CC:DD:EE:FF": "Eigenes Garmin GPS",
    "11:22:33:44:55:66": "Eigener JBL Lautsprecher"
  }
}
```

**`ssid_list.json`** — eigene Heimnetzwerke (unterdrückt Probe-SSID-Fehlalarme):
```json
{
  "ignore_ssids": ["MeinHeimnetz", "Buero-WLAN"],
  "comments": {
    "MeinHeimnetz": "Heimnetz – ignorieren"
  }
}
```

> **Tipp:** Führe zuerst einen Scan im Modus 0 zuhause durch. Alle verdächtigen Geräte gehören wahrscheinlich dir selbst. MAC in `mac_list.json` eintragen, dann erneut scannen.

---

### Schritt 2 — Bekannte Zonen konfigurieren (optional)

GPS-Koordinaten werden **ausschließlich in `config.json` auf dem Pager** gespeichert — nie im Repository.

```json
"watch_list": {
  "default_zone_radius_m": 100,
  "known_zones": [
    { "name": "Zuhause", "lat": 0.000000, "lon": 0.000000, "radius_m": 150 },
    { "name": "Büro",    "lat": 0.000000, "lon": 0.000000, "radius_m": 100 }
  ]
}
```

Die `config.example.json` im Repository enthält nur Platzhalter-Koordinaten (`0.000000`).

---

### Schritt 3 — Verdächtige Geräte zur Watch-List hinzufügen

Nach jedem Scan können verdächtige Geräte direkt am Pager-Display zur **Watch-List** hinzugefügt werden:

| Typ | Anwendungsfall | Alarm wenn… |
|-----|----------------|-------------|
| **Dynamic** | Unbekanntes Gerät, mehrfach gesehen | Gerät taucht an einem neuen Ort auf (> 500 m entfernt) |
| **Static** | Bekanntes Gerät (z.B. Nachbar-Router) | Gerät taucht außerhalb seiner GPS-Zone auf |

- **Dynamic** ist die richtige Wahl bei Tracking-Verdacht — das Gerät folgt dir über verschiedene Orte.
- **Static** eignet sich für Geräte, die nur an einem festen Ort sein sollten (Zuhause, Hotel, Büro).

---

### Schritt 4 — Scan-Einstellungen wählen

Der **Persistence-Score** (`Erscheinungen ÷ Runden gesamt`) ist die zentrale Kennzahl.
Ein Score ≥ 0,6 markiert ein Gerät als verdächtig.

| Anwendungsfall | Runden | Dauer/Runde | Gesamtzeit | Hinweis |
|----------------|--------|-------------|------------|---------|
| Schnellcheck | 2 | 120 s | ~ 4 Min. | Geringe Aussagekraft |
| Standard | 3 | 300 s | ~ 15 Min. | Gute Balance |
| **Empfohlen (mobil)** | **5** | **120 s** | **~ 10 Min.** | Beste geografische Diversität |
| Hohe Sicherheit | 5 | 300 s | ~ 25 Min. | Für geplante Stopps |

**Grundprinzip:** Geografische Diversität schlägt reine Scan-Dauer.
Ein Gerät, das an fünf verschiedenen Orten auftaucht, ist wesentlich verdächtiger als eines, das lange an einem einzigen Ort zu sehen ist.

---

### Beispiel: 45-Minuten-Fahrt

**Empfohlen:** Modus 5 (Argus Full) · 5 Runden · 120 s/Runde

```
Start  →  [Runde 1: 2 Min.]  →  3–5 km fahren
       →  [Runde 2: 2 Min.]  →  3–5 km fahren
       →  [Runde 3: 2 Min.]  →  3–5 km fahren
       →  [Runde 4: 2 Min.]  →  3–5 km fahren
       →  [Runde 5: 2 Min.]  →  Analyse + Report

Scan-Zeit: ~12 Min.  |  Fahrzeit zwischen den Runden: ~33 Min.
```

**So liest du den Report:**

| Persistence | Erscheinungen | Bewertung |
|-------------|---------------|-----------|
| 1,00 | 5 / 5 | 🔴 Starker Hinweis — Gerät folgt dir |
| 0,80 | 4 / 5 | 🔴 Sehr verdächtig |
| 0,60 | 3 / 5 | 🟡 An der Schwelle — weiter beobachten |
| 0,40 | 2 / 5 | 🟢 Wahrscheinlich Zufall |
| 0,20 | 1 / 5 | 🟢 Nicht verdächtig |

**Praktische Tipps:**

- Runde starten, losfahren — die nächste Runde beginnt automatisch, kein Anhalten nötig
- Gerät mit Score 0,6 beim ersten Lauf: Route wiederholen. Ein echter Verfolger erreicht dann 1,0
- Mit WiGLE aktiviert: Probe-SSIDs im Report können das Heimnetzwerk des Verfolgers verraten
- Modus 5 liefert zusätzlich Cell-Threat-Level — ein GHOST oder MISMATCH auf dem gleichen Abschnitt erhöht den Verdacht erheblich

---

### LED-Status

| LED | Bedeutung |
|-----|-----------|
| Cyan blink | Startup / Initialisierung |
| Blau blink | Scan läuft |
| Gelb/Amber | Analyse läuft |
| Grün | Kein Befund |
| Rot blink | Verdacht / Alert |

---

## Maßnahmen bei Tracker-Fund (SmartTag / AirTag / Tile)

Wenn der Report einen **🔴 TRACKER** meldet (Samsung SmartTag, Apple AirTag, Tile etc.):

### 1. Identifikation bestätigen

Der Report zeigt MAC-Adresse, Hersteller und Company ID:
```
🔴 AA:BB:CC:DD:EE:FF — Samsung Electronics Co.,Ltd
   🔍 TRACKER Company ID 117: Samsung (SmartTag)
```

### 2. Tracker physisch orten (RSSI-Peilung)

Über SSH auf den Pager (während Payload läuft oder danach):

```bash
# Letzten BT-Scan laden und RSSI des Trackers prüfen
python3 -c "
import json, glob
mac = 'AA:BB:CC:DD:EE:FF'   # Tracker-MAC aus Report
for f in sorted(glob.glob('/root/loot/argus/bt_*.json'))[-4:]:
    d = json.load(open(f))
    info = d.get('bt_devices', {}).get(mac)
    if info:
        ts = f.split('bt_')[1].split('_r')[0]
        rnd = f.split('_r')[1].replace('.json','')
        print(f\"{ts} R{rnd}  RSSI={info.get('rssi','?')} dBm\")
"
```

**RSSI-Richtwerte:**

| RSSI | Entfernung (ca.) | Bedeutung |
|------|-----------------|-----------|
| > −60 dBm | < 2 m | Sehr nah — im selben Raum / Auto |
| −60 bis −75 dBm | 2–10 m | Nah — gleiche Etage |
| −75 bis −85 dBm | 10–30 m | Mittlere Distanz |
| < −85 dBm | > 30 m | Weit entfernt / gedämpft |

**Vorgehen:** Auf den Pager achten während du dich im Raum / ums Fahrzeug bewegst.
Je stärker das RSSI (näher an 0), desto näher bist du am Tracker.

> Alternativ: Für **Samsung SmartTag** die offizielle **SmartThings**-App nutzen (erfordert Samsung-Account). Für **Apple AirTag** die **Find My**-App auf iPhone (erkennt fremde AirTags automatisch und zeigt Richtung an). **Tile** und andere Tracker haben keine offizielle Such-App für Fremderkennung.

### 3. Nach dem Fund

- Tracker **nicht sofort entfernen** — zuerst Fotos machen und Fundort dokumentieren
- Tracker aus dem Sichtfeld des Verfolgers entfernen, bevor du ihn abschaltest/versteckst
- MAC zur **Watch-List** hinzufügen (Typ: Static) — so schlägt Argus sofort an wenn der Tracker wieder auftaucht
- Bei Straftat: lokale Behörden kontaktieren (Tracking ohne Wissen ist in den meisten Ländern strafbar)

### 4. Tracker-MACs ignorieren (nach Überprüfung)

Wenn der Tracker als eigenes Gerät bestätigt wurde (z.B. vergessener Koffer-Tracker):
```json
// /root/loot/argus/ignore_lists/mac_list.json
{
  "ignore_macs": ["AA:BB:CC:DD:EE:FF"],
  "comments": { "AA:BB:CC:DD:EE:FF": "Eigener Samsung SmartTag — Reisekoffer" }
}
```

---

## Architektur

```
Argus Pager (Payload auf WiFi Pineapple Pager)
├── payload.sh           Haupt-Payload (DuckyScript UI, alle Modi)
├── config.example.json  Konfig-Vorlage (API-Keys, GPS-Zonen)
├── cyt/                 → submodule: chasing-your-tail-pager
│   └── python/
│       ├── analyze_pcap.py       Probe-Request Persistence-Analyse + InternetDB
│       ├── hotel_scan.py         Hotel-Scan: Kamera-Erkennung + CVEDB + Fingerbank
│       ├── camera_activity.py    Data-Frame Bandbreiten-Analyse (aktive Kameras)
│       ├── pcap_engine.py        PCAP-Parser (Probes, Beacons, Data/IPs, DHCP)
│       ├── shodan_lookup.py      InternetDB + CVEDB + Shodan + Fingerbank APIs
│       ├── bt_scanner.py         BLE/Classic BT Scanner (BlueZ)
│       ├── bt_fingerprint.py     BT Device Fingerprinting (Tracker, Kameras)
│       ├── oui_lookup.py         IEEE OUI → Hersteller
│       ├── wigle_lookup.py       WiGLE SSID/BSSID Abgleich
│       ├── zone_check.py         GPS/IP-basierte Standorterkennung
│       ├── surveillance_analyzer.py  Korrelationsanalyse
│       ├── suspects_db.py        Persistente Verdächtigen-DB
│       └── watch_list.py         Überwachungsliste (static/dynamic)
└── raypager/            → submodule: raypager
    └── python/          (laufen auf Mudi V2)
        ├── cell_info.py    AT+QENG → LTE Cell-Info
        ├── gps.py          NMEA Reader (/dev/ttyACM0)
        ├── opencellid.py   IMSI-Catcher Check + Upload
        ├── blue_merle.py   IMEI Rotation
        ├── utils.py        Shared Constants + Haversine
        └── wigle_cell.py   WiGLE Cell-Tower Lookup
```

```
Pager  →  wlan1mon  →  WiFi PCAP  →  CYT Analyse
                                        ├── Probe Persistence (analyze_pcap.py)
                                        ├── Beacon/Kamera Scan (hotel_scan.py)
                                        ├── Activity Detection (camera_activity.py)
                                        └── IP Enrichment (shodan_lookup.py)
Pager  →  BlueZ    →  BT-Scan    →  BT Fingerprint
Pager  →  SSH      →  Mudi V2:
                        ├── gps.py          (/dev/ttyACM0, u-blox M8130)
                        ├── cell_info.py    (EM050-G Modem via AT)
                        └── opencellid.py   (IMSI-Catcher-Check)
```

---

## Voraussetzungen

### WiFi Pineapple Pager

| Paket | Zweck | Installation |
|-------|-------|-------------|
| `python3` | Analyse-Scripts | `opkg install -d mmc python3` |
| `tcpdump` | 5/6 GHz PCAP via wlan1mon | meist vorinstalliert |
| `bluez-utils` | BT-Scanning | `opkg install -d mmc bluez-utils` |

### Mudi V2 (GL-E750V2) — nur für Modi 5+6

| Komponente | Details |
|------------|---------|
| Hardware | GL-E750V2 mit EM050-G LTE-Modem |
| GPS | u-blox M8130 USB-Dongle → `/dev/ttyACM0` @ 4800 baud |
| Python | `opkg install python3 python3-pyserial` |
| Blue Merle | Installiert unter `/mnt/disk/upper/lib/blue-merle` (overlay FS) |
| raypager Scripts | Deployed nach `/root/raypager/python/` |
| SSH-Key | Pager-Key in Mudi `/etc/dropbear/authorized_keys` eingetragen |
| API-Keys | OpenCelliD-Key + WiGLE-Keys in `config.json` auf Mudi |

**API-Keys** (einzutragen in `config.json` auf dem Pager):

| Key | Dienst | Zweck | Kosten |
|-----|--------|-------|--------|
| `wigle_api_name` + `wigle_api_token` | [WiGLE.net](https://wigle.net) | WiFi-Netz-Abgleich (bekannte SSIDs/BSSIDs) | Kostenlos |
| `opencellid_key` | [OpenCelliD](https://opencellid.org) | Cell-Tower-Verifikation (Modi 5+6, auf Mudi) | Kostenlos |
| `fingerbank_api_key` | [Fingerbank](https://fingerbank.org) | MAC → Gerätekategorie (IP Camera, NVR, IoT) | Kostenlos |
| `shodan_api_key` | [Shodan](https://shodan.io) | Erweiterte IP-Host-Info (Org, ASN, Banner) | $49 einmalig (optional) |

**Ohne API-Keys funktionieren:**
- InternetDB (IP → Ports/CVEs) — kostenlos, kein Key nötig
- CVEDB (Hersteller → CVEs) — kostenlos, kein Key nötig
- OUI-Lookup, BT-Fingerprinting, Kamera-OUI-Erkennung — offline/hardcoded

---

### Lookup-Datenbanken

| Datenbank | Quelle | Verhalten |
|-----------|--------|-----------|
| MAC-Hersteller (OUI) | IEEE (`standards-oui.ieee.org`) | Beim ersten Scan heruntergeladen, danach lokal gecacht, wöchentliches Auto-Update |
| WiFi Kamera-SSIDs / Kamera-OUIs | Hardcoded in `hotel_scan.py` | Kein Online-Zugriff nötig |
| BT Fingerprints / Tracker | Hardcoded in `bt_fingerprint.py` | AirTag, SmartTag, Tile, Chipolo — offline |
| InternetDB (IP → Ports/CVEs) | Shodan (`internetdb.shodan.io`) | Online, kostenlos, kein Key |
| CVEDB (Vendor → CVEs) | Shodan (`cvedb.shodan.io`) | Online, kostenlos, kein Key |
| Fingerbank (MAC → Gerät) | `api.fingerbank.org` | Online, Key nötig (kostenlos) |
| Eigene Ignore-Listen | `ignore_lists/*.json` auf Pager | Gitignored — nur `*.example.json` im Repo |

Der erste Scan benötigt eine Internetverbindung für den OUI-Cache-Download.
Kamera-OUI-, BT- und Tracker-Analyse funktionieren vollständig offline.
InternetDB/CVEDB/Fingerbank-Enrichment erfordert Internet, ist aber optional.

---

### Daten-Beiträge (Upload)

| Dienst | Upload | Verhalten |
|--------|--------|-----------|
| **OpenCelliD** | ✅ Automatisch | Messungen werden während Modi 5+6 in Queue (`/root/loot/raypager/upload_queue/`) gespeichert. Am Payload-Ende: Upload-Dialog erscheint wenn Queue nicht leer. |
| **WiGLE** | ❌ Nur Lookup | WiGLE wird zum Abgleich bekannter Netze verwendet. Upload (Wardriving-Beiträge) ist nicht implementiert — dafür WiGLE Android App nutzen. |

---

**Blue Merle Symlink** (einmalig, dann persistent via rc.local):

```bash
# Symlink setzen
ln -sf /mnt/disk/upper/lib/blue-merle /lib/blue-merle

# Persistent machen (in /etc/rc.local vor exit 0 eintragen):
ln -sf /mnt/disk/upper/lib/blue-merle /lib/blue-merle 2>/dev/null
```

**SSH vom Pager zum Mudi** (Pager wählt Mudi via wlan0cli / 192.168.8.1):

```bash
# Key generieren (auf Pager)
ssh-keygen -t rsa -f /root/.ssh/mudi_key -N ""

# Public Key auf Mudi eintragen
cat /root/.ssh/mudi_key.pub | ssh root@192.168.8.1 \
  'cat >> /etc/dropbear/authorized_keys'
```

---

## Deploy auf den Pager

```bash
# Repo klonen (mit Submodules)
cd /root/payloads/user/reconnaissance/
git clone --recurse-submodules https://github.com/tschakram/argus-pager

# OPSEC-Hook aktivieren
cd argus-pager
git config core.hooksPath hooks

# Config anlegen (NIEMALS committen!)
cp config.example.json config.json
vi config.json   # echte GPS-Zonen, API-Keys, Mudi-Config eintragen

# CRLF-Fix (nach scp von Windows)
sed -i 's/\r//' payload.sh hooks/pre-commit

# Submodule initialisieren (falls nicht via --recurse-submodules)
git submodule update --init --recursive
```

---

## Submodule aktualisieren

```bash
# Auf dem Pager oder lokal:
git submodule update --remote cyt
git submodule update --remote raypager
git add cyt raypager
git commit -m "update submodules"
```

---

## Hardware-Setup (Modus 5+6)

```
Laptop  ──USB-C──►  Pager (172.16.52.1)
                        │
                    WiFi (wlan0cli)
                        │
                        ▼
                    Mudi V2 (192.168.8.1)
                        │
                     ┌──┴──────────────────┐
                     │  GPS: /dev/ttyACM0  │  ← u-blox M8130 USB-Dongle
                     │  LTE: EM050-G Modem │
                     └─────────────────────┘
```

SSH-Configs:
- `~/.ssh/config` → `Host pager` → `172.16.52.1`, Key `~/.ssh/pager_key`
- `~/.ssh/config` → `Host mudi`  → `192.168.8.1`, Key `~/.ssh/mudi_key`

---

## Loot-Struktur auf dem Pager

```
/root/loot/argus/
├── pcap/             WiFi PCAP-Dateien (gitignored)
├── reports/          Analyse-Reports (gitignored)
├── ignore_lists/     mac_list.json, ssid_list.json (gitignored)
├── bt_*.json         BT-Scan-Ergebnisse (gitignored)
└── gps_track.csv     GPS-Track (gitignored)
```

---

## OPSEC

- `config.json` ist gitignored — enthält echte GPS-Koordinaten, API-Keys
- `hooks/pre-commit` blockiert versehentliches Committen von Geodaten, MACs, API-Keys
- `ignore_lists/*.json` sind gitignored — nur `*.example.json` im Repo
- Alle Geodaten (GPS, Zonen) bleiben ausschließlich auf dem Pager

### 802.11w — Management Frame Protection (Pager ↔ Mudi)

Der WiFi-Link zwischen Pager (`wlan0cli`) und Mudi V2 ist standardmäßig anfällig für **Deauthentication-Flood-Angriffe** (aireplay-ng, MDK3 etc.), die die Verbindung unterbrechen können.

**802.11w (PMF)** schützt davor: Deauth/Disassoc-Frames werden kryptografisch signiert — unsignierte Flood-Frames werden vom Client ignoriert.

Aktivierung (einmalig, auf beiden Geräten):

```bash
# Pager
uci set wireless.wlan0cli.ieee80211w='2'
uci commit wireless
wifi reload

# Mudi V2
uci set wireless.default_radio1.ieee80211w='2'
uci commit wireless
wifi reload
```

Verifizierung (auf dem Pager):
```bash
grep ieee80211w /var/run/wpa_supplicant-wlan0cli.conf
# → ieee80211w=2
```

> `ieee80211w=2` = **Required** — Verbindung wird nur noch mit MFP aufgebaut. Flood-Angriffe auf diese Verbindung sind damit wirkungslos.

### Deauth-Flood Monitoring

Der Pineapple-Firmware-Daemon erkennt Deauth/Disassoc-Floods automatisch und triggert den Alert-Payload unter:

```
/root/payloads/alert/deauth_flood_detected/example/payload.sh
```

Der Stock-Payload zeigt nur eine Display-Meldung. Für persistentes Logging sollte er wie folgt erweitert werden:

```bash
#!/bin/bash
ALERT "$_ALERT_DENIAL_MESSAGE"

LOGFILE="/root/loot/deauth_log.json"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
ENTRY=$(printf '{"time":"%s","message":"%s","source":"%s","destination":"%s","ap_bssid":"%s","client":"%s"}' \
    "$TIMESTAMP" \
    "$_ALERT_DENIAL_MESSAGE" \
    "$_ALERT_DENIAL_SOURCE_MAC_ADDRESS" \
    "$_ALERT_DENIAL_DESTINATION_MAC_ADDRESS" \
    "$_ALERT_DENIAL_AP_MAC_ADDRESS" \
    "$_ALERT_DENIAL_CLIENT_MAC_ADDRESS")
echo "$ENTRY" >> "$LOGFILE"
```

Jeder erkannte Angriff wird damit mit Timestamp, Source-MAC, AP-BSSID und Client-MAC in `/root/loot/deauth_log.json` gespeichert (eine JSON-Zeile pro Event).

> **Verfügbare Variablen:** `$_ALERT_DENIAL_SOURCE_MAC_ADDRESS`, `$_ALERT_DENIAL_DESTINATION_MAC_ADDRESS`, `$_ALERT_DENIAL_AP_MAC_ADDRESS`, `$_ALERT_DENIAL_CLIENT_MAC_ADDRESS`, `$_ALERT_DENIAL_MESSAGE`

### ⚠️ IMEI-Wechsel — Rechtslage beachten

Die IMEI-Rotation (Blue Merle) ist ein OPSEC-Feature zum Schutz vor IMSI-Catchern und Bewegungsprofilen. **Die Rechtslage zum Ändern der IMEI variiert stark je nach Land:**

| Land | Rechtslage |
|------|-----------|
| Deutschland | Nicht explizit verboten, aber Nutzung einer gefälschten IMEI in einem Mobilfunknetz kann unter §§ 263, 269 StGB fallen |
| Österreich | Ähnlich DE — keine explizite Regelung, aber mögliche Relevanz im Telekommunikationsrecht |
| Schweiz | Kein explizites Verbot, aber mögliche Konflikte mit Fernmelderecht |
| UK | Illegal seit 2002 (Mobile Telephones Re-programming Act) |
| USA | Illegal unter FCC-Richtlinien (47 USC § 333) |
| Litauen | Keine explizite Regelung bekannt |

> **Empfehlung:** Vor Nutzung der IMEI-Rotation die **Rechtslage im jeweiligen Einsatzland** prüfen. Die Verantwortung liegt beim Anwender. Dieses Tool dient der defensiven Sicherheitsforschung — der Einsatz in illegaler Weise ist nicht beabsichtigt.

### WiGLE Cell-Tower-Daten — Bekannte Ungenauigkeit

Bei einem Cross-Check von 51 Zellen gegen die WiGLE-Datenbank wurde festgestellt, dass **alle Lookups für einen bestimmten MCC identische, nachweislich falsche GPS-Koordinaten** zurücklieferten — mit einem Positionsfehler von über **1.400 km**. Die gemeldeten Positionen lagen in einem völlig anderen Land als die tatsächlichen Zellstandorte.

**Ursache:** WiGLE basiert auf Crowdsourced-Daten (Wardriving-Uploads). Werden Zellen mit falschen GPS-Koordinaten hochgeladen, werden alle Einträge für diesen Netzbereich kontaminiert. Eine Qualitätskontrolle findet nicht statt.

**Konsequenz:**
- WiGLE Cell-Lookup ist für die Cell-Tower-Verifikation **derzeit deaktiviert** (`wigle.enabled: false`)
- OpenCelliD bleibt die primäre Quelle für IMSI-Catcher-Erkennung
- WiGLE wird weiterhin für **WiFi SSID/BSSID-Abgleich** genutzt (dort sind die Daten zuverlässiger)
- Das `wigle_cell.py`-Modul gibt bei deaktiviertem WiGLE `CLEAN` zurück (kein Einfluss auf CELL_THREAT)

---

## Submodule-Repos

- [chasing-your-tail-pager](https://github.com/tschakram/chasing-your-tail-pager) — WiFi/BT Surveillance Detection
- [raypager](https://github.com/tschakram/raypager) — IMSI-Catcher Detection

---

## Lizenz

Basiert auf [ArgeliusLabs/Chasing-Your-Tail-NG](https://github.com/ArgeliusLabs/Chasing-Your-Tail-NG) (MIT).
Erweiterungen: MIT.
