<p align="center">
  <img src="docs/assets/logo.png" alt="ScrAInee Logo" width="128" height="128">
</p>

<h1 align="center">ScrAInee</h1>

<p align="center">
  <strong>Intelligente Bildschirmaufnahme mit AI-Power für macOS</strong>
</p>

<p align="center">
  <a href="#features">Features</a> •
  <a href="#installation">Installation</a> •
  <a href="#konfiguration">Konfiguration</a> •
  <a href="#tastaturkürzel">Shortcuts</a> •
  <a href="#architektur">Architektur</a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Platform-macOS%2014%2B-blue?style=flat-square" alt="Platform">
  <img src="https://img.shields.io/badge/Swift-5.9%2B-orange?style=flat-square" alt="Swift">
  <img src="https://img.shields.io/badge/AI-Claude%20Sonnet%204.5-purple?style=flat-square" alt="AI Model">
  <img src="https://img.shields.io/badge/Tests-95%20passed-green?style=flat-square" alt="Tests">
  <img src="https://img.shields.io/badge/License-MIT-lightgrey?style=flat-square" alt="License">
</p>

---

## Was ist ScrAInee?

ScrAInee ist eine macOS Menu-Bar App, die kontinuierlich Screenshots aufnimmt, Text via OCR extrahiert und AI-gestützte Zusammenfassungen erstellt. Perfekt für:

- **Meetings dokumentieren** - Automatische Zusammenfassungen nach Meeting-Ende
- **Recherche nachverfolgen** - Finde wieder, was du gesehen hast
- **Arbeitszeit analysieren** - Timeline-Ansicht deines Tages
- **Quick Ask** - Stelle Fragen zum aktuellen Bildschirminhalt

> Inspiriert von Rewind.ai - aber lokal, privat und mit Claude AI

---

## Features

### Screenshot-Aufnahme

| Feature | Beschreibung |
|---------|--------------|
| **Automatische Aufnahme** | Kontinuierliche Screenshots in einstellbaren Intervallen (1-60 Sek.) |
| **Multi-Monitor Support** | Parallele Erfassung aller angeschlossenen Displays |
| **Duplikat-Erkennung** | Perceptual Hash (dHash) verhindert redundante Screenshots |
| **HEIC-Kompression** | Platzsparende Speicherung mit einstellbarer Qualität |
| **Adaptive Intervalle** | Dynamische Anpassung basierend auf Aktivität/Idle-Status |
| **App-Erkennung** | Erfasst aktive App und Fenstertitel pro Screenshot |

### OCR & Texterkennung

| Feature | Beschreibung |
|---------|--------------|
| **Automatische OCR** | Vision Framework extrahiert Text aus Screenshots |
| **Mehrsprachig** | Deutsch und Englisch unterstützt |
| **Hintergrund-Verarbeitung** | OCR läuft asynchron ohne UI-Blockierung |
| **Volltextsuche** | Durchsuche alle erfassten Texte mit FTS5 |

### AI-Features (Claude Sonnet 4.5)

| Feature | Beschreibung |
|---------|--------------|
| **Quick Ask** | Stelle Fragen zum aktuellen Kontext - nutzt OCR, Meetings, Summaries |
| **Zusammenfassungen** | AI-generierte Zusammenfassungen für beliebige Zeiträume |
| **Meeting-Zusammenfassungen** | Automatische Summaries nach Meeting-Ende |
| **Action Items** | Extrahiert Aufgaben aus Meeting-Inhalten |

### Meeting-Erkennung

| Feature | Beschreibung |
|---------|--------------|
| **Auto-Erkennung** | Erkennt Teams, Zoom, Webex, Google Meet automatisch |
| **Erhöhte Frequenz** | Kürzere Capture-Intervalle während Meetings |
| **Meeting-Sessions** | Gruppiert Screenshots pro Meeting |
| **Notion-Sync** | Automatischer Export zu Notion nach Meeting-Ende |

### Timeline & Navigation

| Feature | Beschreibung |
|---------|--------------|
| **Timeline-Ansicht** | Rewind.AI-Style Navigation durch Screenshots |
| **Zeit-Slider** | Scrubben durch den Tag mit App-Segmenten |
| **Thumbnail-Leiste** | Schnelle visuelle Übersicht |
| **Tastatursteuerung** | Pfeiltasten für Navigation |

---

## Tastaturkürzel

### Global

| Shortcut | Funktion |
|----------|----------|
| `Cmd+Shift+A` | **Quick Ask** - AI-Frage zum Kontext |
| `Cmd+Shift+R` | Aufnahme starten/stoppen |
| `Cmd+Shift+F` | Suche öffnen |
| `Cmd+Shift+S` | Zusammenfassung erstellen |
| `Cmd+Shift+G` | Galerie öffnen |
| `Cmd+Shift+T` | Timeline öffnen |

### In der Timeline

| Shortcut | Funktion |
|----------|----------|
| `←` / `→` | Vorheriger / Nächster Screenshot |
| `Shift+←` / `Shift+→` | 10 Screenshots zurück / vor |

---

## Installation

### Voraussetzungen

- **macOS 14.0+** (Sonoma oder neuer)
- **Xcode 15+** (für Build)
- **Screen Recording Permission** (Pflicht)
- **Accessibility Permission** (Optional, für globale Hotkeys)

### Aus Source bauen

```bash
# Repository klonen
git clone https://github.com/miscarriage87/ScrAInee.git
cd ScrAInee

# Xcode-Projekt öffnen
open Scrainee.xcodeproj

# Oder mit Swift Package Manager
swift build -c release
```

### Tests ausführen

```bash
swift test
# 95 Tests, 0 Failures
```

---

## Konfiguration

### Claude API (für AI-Features)

1. Hole dir einen API-Key von [Anthropic Console](https://console.anthropic.com/)
2. Öffne ScrAInee → Einstellungen → AI
3. Füge deinen API-Key ein
4. Der Key wird sicher im macOS Keychain gespeichert

> ScrAInee verwendet Claude Sonnet 4.5 (`claude-sonnet-4-5-20250929`) für beste Ergebnisse

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
│   ├── AI/                 # Claude API Client (Sonnet 4.5)
│   ├── Database/           # GRDB Models & Manager (Actor)
│   ├── Integration/        # Notion Client
│   ├── Meeting/            # Meeting Detection
│   ├── OCR/                # Vision Framework
│   ├── ScreenCapture/      # ScreenCaptureKit
│   ├── Cache/              # Thumbnail Cache (LRU)
│   └── Storage/            # File Management
├── Services/               # Hotkeys, Permissions, Keychain
├── UI/
│   ├── MenuBar/            # Menu Bar Dropdown
│   ├── Timeline/           # Timeline View (Rewind-Style)
│   ├── Gallery/            # Screenshot Gallery
│   ├── Search/             # FTS5 Search
│   ├── QuickAsk/           # AI Quick Ask
│   └── Settings/           # Einstellungen
└── Tests/                  # 95 Unit & E2E Tests
```

---

## Tech Stack

| Komponente | Technologie |
|------------|-------------|
| **UI** | SwiftUI |
| **Sprache** | Swift 5.9+ |
| **Concurrency** | Swift Concurrency (async/await, actors) |
| **Datenbank** | GRDB.swift (SQLite + FTS5) |
| **Screenshot** | ScreenCaptureKit |
| **OCR** | Vision Framework |
| **AI** | Claude Sonnet 4.5 (Anthropic API) |
| **Secrets** | KeychainAccess |

---

## Datenspeicherung

```
~/Library/Application Support/Scrainee/
├── scrainee.sqlite         # Datenbank
├── screenshots/            # HEIC Screenshots
│   └── 2026/01/17/         # Nach Datum sortiert
└── logs/                   # Log-Dateien
```

### Speicherverbrauch

- ~50-100 KB pro Screenshot (HEIC @ 60% Qualität)
- ~1-2 GB pro Tag bei 3-Sekunden-Intervall
- Automatische Bereinigung nach 30 Tagen (konfigurierbar)

---

## Privatsphäre & Sicherheit

- **100% Lokal** - Alle Daten bleiben auf deinem Mac
- **Keychain** - API-Keys sicher im System-Keychain
- **Hardened Runtime** - Code-Signierung für macOS
- **Keine Telemetrie** - Keine Daten werden gesendet (außer an Claude API bei AI-Features)

---

## Roadmap

- [ ] **Offline-LLM** - Ollama-Integration für lokale AI-Verarbeitung
- [ ] **Knowledge Base** - Semantische Suche mit Vektor-Embeddings
- [ ] **Projekt-Überwachung** - Automatische Analyse von Projekt-Ordnern
- [ ] **Export** - PDF, Video-Timelapse
- [ ] **Widgets** - macOS Widgets für Statistiken

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

<p align="center">
  <sub>Entwickelt mit ❤️ und Claude Code</sub>
</p>
