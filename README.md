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
