# ScrAInee

**Intelligente Bildschirmaufnahme mit AI-Power für macOS**

ScrAInee ist eine macOS Menu-Bar App, die kontinuierlich Screenshots aufnimmt, Text via OCR extrahiert und AI-gestützte Zusammenfassungen erstellt. Perfekt für Meetings, Recherche und die Dokumentation deiner Arbeit.

> Inspiriert von Rewind.ai

---

## Features

### Screenshot-Aufnahme

| Feature | Status | Beschreibung |
|---------|--------|--------------|
| Automatische Aufnahme | ✅ Fertig | Kontinuierliche Screenshots in einstellbaren Intervallen (1-60 Sek.) |
| Multi-Monitor Support | ✅ Fertig | Parallele Erfassung aller angeschlossenen Displays |
| Duplikat-Erkennung | ✅ Fertig | Perceptual Hash (dHash) verhindert redundante Screenshots |
| HEIC-Kompression | ✅ Fertig | Platzsparende Speicherung mit einstellbarer Qualität |
| Adaptive Intervalle | ✅ Fertig | Dynamische Anpassung basierend auf Aktivität/Idle-Status |
| App-Erkennung | ✅ Fertig | Erfasst aktive App und Fenstertitel pro Screenshot |

### OCR & Texterkennung

| Feature | Status | Beschreibung |
|---------|--------|--------------|
| Automatische OCR | ✅ Fertig | Vision Framework extrahiert Text aus Screenshots |
| Mehrsprachig | ✅ Fertig | Deutsch und Englisch unterstützt |
| Hintergrund-Verarbeitung | ✅ Fertig | OCR läuft asynchron ohne UI-Blockierung |
| Volltextsuche | ✅ Fertig | Durchsuche alle erfassten Texte |

### AI-Features (Claude API)

| Feature | Status | Beschreibung |
|---------|--------|--------------|
| Quick Ask | ✅ Fertig | Stelle Fragen zum aktuellen Bildschirminhalt |
| Zusammenfassungen | ✅ Fertig | AI-generierte Zusammenfassungen für Zeiträume |
| Meeting-Zusammenfassungen | ✅ Fertig | Automatische Summaries nach Meeting-Ende |
| Kontext-Analyse | 🔄 Geplant | Intelligente Analyse von Arbeitsmustern |

### Meeting-Erkennung

| Feature | Status | Beschreibung |
|---------|--------|--------------|
| Auto-Erkennung | ✅ Fertig | Erkennt Teams, Zoom, Webex, Google Meet |
| Erhöhte Frequenz | ✅ Fertig | Kürzere Intervalle während Meetings |
| Meeting-Sessions | ✅ Fertig | Gruppiert Screenshots pro Meeting |
| Meeting-Notizen | 🔄 Geplant | Automatische Notizen-Generierung |

### Notion-Integration

| Feature | Status | Beschreibung |
|---------|--------|--------------|
| Meeting-Sync | ✅ Fertig | Exportiere Meeting-Zusammenfassungen zu Notion |
| Auto-Sync | ✅ Fertig | Automatischer Upload nach Meeting-Ende |
| Database-Integration | ✅ Fertig | Speichert in konfigurierbarer Notion-Database |

### Timeline & Navigation

| Feature | Status | Beschreibung |
|---------|--------|--------------|
| Timeline-Ansicht | ✅ Fertig | Rewind.AI-Style Navigation durch Screenshots |
| Zeit-Slider | ✅ Fertig | Scrubben durch den Tag mit App-Segmenten |
| Thumbnail-Leiste | ✅ Fertig | Schnelle visuelle Übersicht |
| Tastatursteuerung | ✅ Fertig | Pfeiltasten für Navigation |
| Datum-Navigation | ✅ Fertig | Springe zu beliebigem Tag |

### Galerie & Suche

| Feature | Status | Beschreibung |
|---------|--------|--------------|
| Screenshot-Galerie | ✅ Fertig | Grid-Ansicht aller Screenshots |
| Filter nach App | ✅ Fertig | Zeige nur Screenshots bestimmter Apps |
| Filter nach Zeit | ✅ Fertig | Zeitraum-basierte Filterung |
| Volltextsuche | ✅ Fertig | Suche in OCR-Text und Metadaten |

### Speicher & Datenverwaltung

| Feature | Status | Beschreibung |
|---------|--------|--------------|
| SQLite-Datenbank | ✅ Fertig | GRDB für performante Speicherung |
| Retention Policy | ✅ Fertig | Automatische Bereinigung alter Daten |
| Speicher-Statistiken | ✅ Fertig | Übersicht über genutzten Speicherplatz |
| Thumbnail-Cache | ✅ Fertig | LRU-Cache für schnelles Laden |

### Sicherheit & Privatsphäre

| Feature | Status | Beschreibung |
|---------|--------|--------------|
| Lokale Speicherung | ✅ Fertig | Alle Daten bleiben auf deinem Mac |
| Keychain-Integration | ✅ Fertig | API-Keys sicher im Keychain |
| Hardened Runtime | ✅ Fertig | Code-Signierung für macOS |
| Privacy-Permissions | ✅ Fertig | Saubere Permission-Anfragen |

### UI & Bedienung

| Feature | Status | Beschreibung |
|---------|--------|--------------|
| Menu-Bar App | ✅ Fertig | Unaufdringlich in der Systemleiste |
| Globale Hotkeys | ✅ Fertig | Schnellzugriff per Tastaturkürzel |
| Dark/Light Mode | ✅ Fertig | Folgt System-Einstellung |
| SwiftUI-Interface | ✅ Fertig | Native macOS-Optik |

---

## Tastaturkürzel

| Shortcut | Funktion |
|----------|----------|
| `Cmd+Shift+A` | Quick Ask - AI-Frage zum Kontext |
| `Cmd+Shift+R` | Aufnahme starten/stoppen |
| `Cmd+Shift+F` | Suche öffnen |
| `Cmd+Shift+S` | Zusammenfassung erstellen |
| `Cmd+Shift+G` | Galerie öffnen |
| `Cmd+Shift+T` | Timeline öffnen |

### In der Timeline

| Shortcut | Funktion |
|----------|----------|
| `←` | Vorheriger Screenshot |
| `→` | Nächster Screenshot |
| `Shift+←` | 10 Screenshots zurück |
| `Shift+→` | 10 Screenshots vor |

---

## Systemanforderungen

- **macOS 14.0+** (Sonoma oder neuer)
- **Screen Recording Permission** (Pflicht)
- **Accessibility Permission** (Optional, für globale Hotkeys)

---

## Installation

### Aus Source bauen

```bash
# Repository klonen
git clone https://github.com/miscarriage87/ScrAInee.git
cd ScrAInee

# Mit xcodegen das Xcode-Projekt generieren
brew install xcodegen
xcodegen generate

# In Xcode öffnen
open Scrainee.xcodeproj

# Team auswählen unter Signing & Capabilities, dann Cmd+R
```

### Oder direkt mit Swift Package Manager

```bash
swift build -c release
```

---

## Konfiguration

### Claude API (für AI-Features)

1. Hole dir einen API-Key von [Anthropic Console](https://console.anthropic.com/)
2. Öffne ScrAInee → Einstellungen → AI
3. Füge deinen API-Key ein

### Notion-Integration (optional)

1. Erstelle eine [Notion-Integration](https://www.notion.so/my-integrations)
2. Teile eine Database mit der Integration
3. Öffne ScrAInee → Einstellungen → Notion
4. Füge API-Key und Database-ID ein

---

## Architektur

```
ScrAInee/
├── App/                    # Entry Point, AppState
├── Core/
│   ├── AI/                 # Claude API Client
│   ├── Database/           # GRDB Models & Manager
│   ├── Integration/        # Notion Client
│   ├── Meeting/            # Meeting Detection
│   ├── OCR/                # Vision Framework
│   ├── ScreenCapture/      # ScreenCaptureKit
│   ├── Cache/              # Thumbnail Cache
│   └── Storage/            # File Management
├── Services/               # Hotkeys, Permissions, Keychain
├── UI/
│   ├── MenuBar/            # Menu Bar Dropdown
│   ├── Timeline/           # Timeline View
│   ├── Gallery/            # Screenshot Gallery
│   ├── Search/             # Search View
│   ├── QuickAsk/           # AI Quick Ask
│   └── Settings/           # Einstellungen
└── Tests/                  # Unit & E2E Tests
```

---

## Tech Stack

| Komponente | Technologie |
|------------|-------------|
| UI | SwiftUI |
| Sprache | Swift 5.9+ |
| Datenbank | GRDB.swift (SQLite) |
| Screenshot | ScreenCaptureKit |
| OCR | Vision Framework |
| AI | Claude API (Anthropic) |
| Secrets | KeychainAccess |
| Build | Swift Package Manager + xcodegen |

---

## Speicherort

```
~/Library/Application Support/Scrainee/
├── scrainee.sqlite         # Datenbank
├── screenshots/            # HEIC Screenshots
│   └── 2025/01/15/         # Nach Datum sortiert
└── logs/                   # Log-Dateien
```

### Speicherverbrauch

- ~50-100 KB pro Screenshot (HEIC @ 60% Qualität)
- ~1-2 GB pro Tag bei 3-Sekunden-Intervall
- Automatische Bereinigung nach 30 Tagen (konfigurierbar)

---

## Geplante Features

- [ ] **Export-Funktionen** - PDF, Video-Timelapse
- [ ] **Tagging-System** - Manuelle Tags für Screenshots
- [ ] **Projekt-Gruppierung** - Screenshots nach Projekten organisieren
- [ ] **Smarte Suche** - AI-gestützte semantische Suche
- [ ] **Widgets** - macOS Widgets für Statistiken
- [ ] **Shortcuts-Integration** - Apple Shortcuts Aktionen
- [ ] **Cloud-Sync** - Optional verschlüsselter Cloud-Backup
- [ ] **Browser-Extension** - Erfasse zusätzlich aktive URLs

---

## Bekannte Einschränkungen

- Nur der aktive Space wird erfasst (macOS-Limitierung)
- Safari Private-Mode wird nicht erfasst (systemseitig)
- DRM-geschützte Inhalte erscheinen schwarz

---

## Lizenz

MIT License - siehe [LICENSE](LICENSE)

---

## Mitwirken

Pull Requests willkommen! Bitte erst ein Issue erstellen für größere Änderungen.

---

*Entwickelt mit Claude Code*
