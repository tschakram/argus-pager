# Argus Pager

Counter-Surveillance & IMSI-Catcher Detection für den WiFi Pineapple Pager.

Umbrella-Repo das **Chasing Your Tail NG** (WiFi/BT Surveillance Detection) und **Raypager** (IMSI-Catcher Detection via Mudi V2) unter einem einheitlichen Payload zusammenführt.

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

## Architektur

```
Argus Pager (Payload auf WiFi Pineapple Pager)
├── cyt/          → submodule: github.com/tschakram/chasing-your-tail-pager
│   └── python/   (analyze_pcap, bt_scanner, hotel_scan, zone_check, ...)
└── raypager/     → submodule: github.com/tschakram/raypager
    └── python/   (cell_info, gps, opencellid, blue_merle — laufen auf Mudi)

Pager  →  wlan1mon  →  WiFi PCAP  →  CYT Analyse
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

| Key | Dienst | Zweck |
|-----|--------|-------|
| `wigle_api_name` + `wigle_api_token` | [WiGLE.net](https://wigle.net) | WiFi-Netz-Abgleich (bekannte SSIDs/BSSIDs) |
| `opencellid_key` | [OpenCelliD](https://opencellid.org) | Cell-Tower-Verifikation (Modi 5+6, auf Mudi) |

WiGLE und OpenCelliD erfordern eine kostenlose Registrierung.

---

### Lookup-Datenbanken

| Datenbank | Quelle | Verhalten |
|-----------|--------|-----------|
| MAC-Hersteller (OUI) | IEEE (`standards-oui.ieee.org`) | Beim ersten Scan heruntergeladen, danach lokal gecacht (`/root/loot/*/oui_cache.json`), wöchentliches Auto-Update |
| WiFi Kamera-SSIDs / Kamera-OUIs | Hardcoded in `cyt/python/hotel_scan.py` | Kein Online-Zugriff nötig |
| BT Service UUIDs, Kamera/Mikrofon-Fingerprints | Hardcoded in `cyt/python/bt_fingerprint.py` | Kein Online-Zugriff nötig |
| BT Tracker (AirTag, SmartTag, Tile, Chipolo) | Hardcoded in `cyt/python/bt_fingerprint.py` | Erkennung via Company ID, Service UUID, Appearance, Gerätename |
| Eigene Ignore-Listen (MACs, SSIDs) | `ignore_lists/*.json` auf dem Pager | Gitignored — nur `*.example.json` im Repo |

Der erste Scan benötigt eine Internetverbindung für den OUI-Cache-Download. Danach funktioniert die Kamera-, BT- und Tracker-Analyse vollständig offline.

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

---

## Submodule-Repos

- [chasing-your-tail-pager](https://github.com/tschakram/chasing-your-tail-pager) — WiFi/BT Surveillance Detection
- [raypager](https://github.com/tschakram/raypager) — IMSI-Catcher Detection

---

## Lizenz

Basiert auf [ArgeliusLabs/Chasing-Your-Tail-NG](https://github.com/ArgeliusLabs/Chasing-Your-Tail-NG) (MIT).
Erweiterungen: MIT.
