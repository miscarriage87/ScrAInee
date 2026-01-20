# SCRAINEE - Projekt-Dokumentation

## Quick Reference

| Aspekt | Wert |
|--------|------|
| **Plattform** | macOS 13.0+ (Ventura) |
| **Sprache** | Swift 5.9+ |
| **UI Framework** | SwiftUI |
| **Architektur** | MVVM mit @MainActor ObservableObject |
| **Concurrency** | Swift Concurrency (async/await, actors) |
| **Build System** | Swift Package Manager |
| **Min. Test Coverage** | 80% für Core/ |

## Übersicht

SCRAINEE ist eine macOS Menu-Bar Anwendung für automatische Bildschirmaufnahme mit OCR-Texterkennung, AI-gestützten Zusammenfassungen und Meeting-Erkennung. Die App erfasst kontinuierlich Screenshots, extrahiert Text via OCR und ermöglicht die Suche durch vergangene Bildschirminhalte.

## Technologie-Stack

- **Sprache:** Swift 5.9+
- **UI Framework:** SwiftUI
- **Plattform:** macOS 13.0+ (Ventura)
- **Build System:** Swift Package Manager

### Abhängigkeiten

| Paket | Version | Zweck |
|-------|---------|-------|
| GRDB.swift | 6.24.0+ | SQLite Datenbank-Abstraktion |
| KeychainAccess | 4.2.2+ | Sichere Credential-Speicherung |

### System-Frameworks

- **ScreenCaptureKit** - Bildschirmaufnahme (macOS 13+)
- **Vision** - OCR-Texterkennung
- **AppKit** - System-Integration
- **Accessibility** - Fenstertitel-Erkennung
- **Carbon.HIToolbox** - Globale Hotkeys

## Build-Anweisungen

```bash
# Repository klonen
cd /Users/cpohl/Documents/00\ PRIVATE/00\ Coding/CLAUDE\ CODE/SCRAINEE

# Abhängigkeiten laden und bauen
swift build

# Release-Build
swift build -c release

# Mit Xcode öffnen
open Package.swift
```

## Test-Kommandos

```bash
# Alle Tests ausführen
swift test

# Mit Code Coverage
swift test --enable-code-coverage

# Spezifische Tests
swift test --filter ScreenCaptureManagerTests
swift test --filter DisplayManagerTests
swift test --filter HashTrackerTests

# Coverage Report generieren
xcrun llvm-cov report .build/debug/ScraineePackageTests.xctest/Contents/MacOS/ScraineePackageTests \
    -instr-profile .build/debug/codecov/default.profdata
```

## Projektstruktur

```
Scrainee/
├── App/
│   ├── ScraineeApp.swift           # Entry Point, Window-Definitionen
│   └── AppState.swift              # Zentraler State Manager (ObservableObject)
│
├── Core/
│   ├── AI/
│   │   ├── ClaudeAPIClient.swift   # Anthropic Claude API Integration
│   │   └── SummaryGenerator.swift  # AI-Zusammenfassungen
│   │
│   ├── Database/
│   │   ├── DatabaseManager.swift   # GRDB Actor für thread-safe DB-Zugriff
│   │   └── Models/
│   │       ├── Screenshot.swift    # Screenshot-Metadaten
│   │       ├── OCRResult.swift     # OCR-Ergebnisse
│   │       ├── Meeting.swift       # Meeting-Sessions
│   │       ├── SearchResult.swift  # Suchergebnisse
│   │       ├── Summary.swift       # Generierte Zusammenfassungen
│   │       └── ActivitySegment.swift # App-Aktivitäts-Segmente (Timeline)
│   │
│   ├── Integration/
│   │   └── NotionClient.swift      # Notion API für Meeting-Notes Sync
│   │
│   ├── Meeting/
│   │   └── MeetingDetector.swift   # Auto-Erkennung: Teams, Zoom, Webex, Meet
│   │
│   ├── OCR/
│   │   └── OCRManager.swift        # Vision Framework OCR (DE/EN)
│   │
│   ├── ScreenCapture/
│   │   ├── ScreenCaptureManager.swift    # Haupt-Capture-Logik
│   │   ├── DisplayManager.swift          # Multi-Monitor Management
│   │   ├── AdaptiveCaptureManager.swift  # Dynamische Intervall-Anpassung
│   │   └── ScreenshotDiffer.swift        # Duplikat-Erkennung (dHash)
│   │
│   ├── Cache/
│   │   └── ThumbnailCache.swift          # LRU-Cache für Thumbnails (Actor)
│   │
│   └── Storage/
│       ├── StorageManager.swift    # Dateisystem-Management
│       ├── ImageCompressor.swift   # HEIC-Kompression
│       └── RetentionPolicy.swift   # Automatische Bereinigung
│
├── Services/
│   ├── HotkeyManager.swift         # Globale Tastenkürzel
│   ├── PermissionManager.swift     # System-Berechtigungen
│   ├── KeychainService.swift       # Sichere Speicherung
│   ├── ErrorManager.swift          # Fehlerbehandlung
│   └── FileLogger.swift            # Logging
│
├── UI/
│   ├── MenuBar/
│   │   └── MenuBarView.swift       # Menu-Bar Dropdown
│   ├── Settings/
│   │   └── SettingsView.swift      # Einstellungen
│   ├── Search/
│   │   ├── SearchView.swift        # Volltextsuche
│   │   └── SearchViewModel.swift   # Such-Logik
│   ├── Gallery/
│   │   ├── ScreenshotGalleryView.swift
│   │   └── GalleryViewModel.swift
│   ├── Timeline/
│   │   ├── TimelineView.swift          # Timeline-Hauptansicht (Rewind-Style)
│   │   ├── TimelineViewModel.swift     # Timeline State & Logik
│   │   ├── TimelineSliderView.swift    # Zeit-Slider mit App-Segmenten
│   │   └── TimelineThumbnailStrip.swift # Thumbnail-Leiste
│   ├── QuickAsk/
│   │   └── QuickAskView.swift      # AI Quick-Ask Panel
│   └── Summary/
│       └── SummaryRequestView.swift
│
└── Tests/
    └── ScraineeTests/
        ├── Mocks/                  # Test-Doubles
        ├── Unit/                   # Unit Tests
        ├── Integration/            # Integration Tests
        └── Fixtures/               # Test-Daten
```

## Architektur-Prinzipien

### State Management
- **AppState** ist ein `@MainActor ObservableObject` Singleton
- Alle UI-Komponenten observieren AppState via `@EnvironmentObject`
- Änderungen werden über `@Published` Properties propagiert

### Concurrency
- **DatabaseManager** ist ein `actor` für thread-safe DB-Zugriffe
- **HashTracker** ist ein `actor` für thread-safe Hash-Tracking pro Display
- ScreenCaptureKit-Operationen nutzen `async/await`
- Parallele Multi-Monitor-Erfassung via `TaskGroup`

### Dependency Injection
Protokolle für testbare Komponenten:
- `DisplayProviding` - Display-Enumeration
- `ScreenCaptureProviding` - Screenshot-Erfassung
- `DatabaseProviding` - Datenbank-Operationen

### Error Handling
- `ErrorManager` für zentralisierte Fehlerbehandlung
- Kritische Fehler zeigen Alerts
- Nicht-kritische Fehler werden geloggt

## Tastenkürzel

| Shortcut | Funktion |
|----------|----------|
| Cmd+Shift+A | Quick Ask - AI-Frage zum aktuellen Kontext |
| Cmd+Shift+R | Capture an/aus |
| Cmd+Shift+F | Suche öffnen |
| Cmd+Shift+S | Zusammenfassung generieren |
| Cmd+Shift+G | Galerie öffnen |
| Cmd+Shift+T | Timeline öffnen |

### Timeline-Tastenkürzel (im Timeline-Fenster)
| Shortcut | Funktion |
|----------|----------|
| ← | Vorheriger Screenshot |
| → | Nächster Screenshot |
| Shift+← | 10 Screenshots zurück |
| Shift+→ | 10 Screenshots vor |

## Berechtigungen

Die App benötigt:
1. **Screen Recording** (Pflicht) - Für ScreenCaptureKit
2. **Accessibility** (Optional) - Für Fenstertitel und Hotkeys

## Datenspeicherung

```
~/Library/Application Support/Scrainee/
├── scrainee.sqlite           # SQLite Datenbank
├── screenshots/              # HEIC Screenshots
│   └── YYYY/MM/DD/          # Nach Datum organisiert
└── logs/                     # Log-Dateien
```

## Coding-Standards

### Namenskonventionen
- **Klassen/Structs:** PascalCase (`ScreenCaptureManager`)
- **Methoden/Properties:** camelCase (`captureScreen()`)
- **Protokolle:** Suffix `-Providing` oder `-Delegate` (`DisplayProviding`)
- **Enums:** PascalCase, Cases in camelCase
- **Konstanten:** camelCase oder SCREAMING_SNAKE_CASE für globale

### Swift Best Practices
- `@MainActor` für UI-bezogenen Code
- `actor` für thread-safe shared state
- `async/await` statt Completion-Handler
- Optionals mit `guard let` auspacken
- Verwende `Task { @MainActor in }` für UI-Updates aus Background-Tasks
- Bevorzuge `TaskGroup` für parallele Operationen
- Nutze `withCheckedContinuation` für Legacy-APIs

### SwiftUI Best Practices
- Kleine, fokussierte Views (max ~100 Zeilen)
- `@EnvironmentObject` für globalen State (AppState)
- `@StateObject` für View-eigene ViewModels
- `@State` nur für lokalen, transienten UI-State
- Extrahiere wiederverwendbare Views in eigene Dateien
- Verwende `ViewModifier` für wiederholte Styling-Logik

### Kommentare
- MARK-Kommentare für Abschnitte: `// MARK: - Capture Control`
- Nur nicht-offensichtliche Logik kommentieren
- Deutsche Kommentare für Benutzer-sichtbare Strings
- TODO/FIXME mit Ticket-Referenz wenn vorhanden

### Testing
- Unit Tests für alle Core-Komponenten
- Mocks für externe Abhängigkeiten (via Protokolle)
- Mindestens 80% Coverage für Core/
- Verwende `@MainActor` in Tests die UI-Code testen
- Teste async Code mit `await` in async test functions
- Strukturiere Tests nach Arrange-Act-Assert Pattern

### Code Review Checklist
- [ ] Folgt Swift Naming Conventions
- [ ] Keine Force-Unwraps außer bei bekannten sicheren Fällen
- [ ] Proper Error Handling (keine silent failures)
- [ ] Memory Management korrekt (weak self in closures)
- [ ] Thread-Safety gewährleistet
- [ ] Tests vorhanden und passend

## Bekannte Einschränkungen

1. **Spaces:** Nur aktiver Space wird erfasst
2. **Private Fenster:** Safari Private-Mode wird nicht erfasst (systemseitig)
3. **DRM-Inhalte:** Geschützte Inhalte erscheinen schwarz

## API-Integration

### Claude API
- Endpoint: `https://api.anthropic.com/v1/messages`
- Model: `claude-sonnet-4-5-20250514`
- API-Key in Keychain gespeichert

### Notion API
- Endpoint: `https://api.notion.com/v1`
- Version: `2022-06-28`
- API-Key und Database-ID in Keychain

## Changelog

### Version 1.2 (Aktuell)
- **Timeline-Ansicht** (Rewind.AI-Style)
  - Chronologische Screenshot-Navigation
  - Zeit-Slider mit App-Aktivitäts-Segmenten
  - Thumbnail-Leiste für schnelle Übersicht
  - Datum-Navigation und -Auswahl
  - Tastatursteuerung (Pfeiltasten)
- ThumbnailCache Actor für performantes Laden
- ActivitySegment-Modell für App-Tracking

### Version 1.1
- Multi-Monitor Unterstützung (parallele Erfassung)
- Vollständige Test-Suite
- Thread-safe Hash-Tracking
- Bug Fixes (filterByApp, etc.)

---

## Abhängigkeits-Management

### Dokumentation

Dieses Projekt nutzt ein Abhängigkeits-Dokumentationssystem:

- **DEPENDENCY-DOCS.md** - Konzept und Header-Format
- **UI-ARCHITECTURE.md** - UI-Komponenten und Datenflüsse

### Bei Code-Änderungen IMMER prüfen

1. **VOR der Änderung:**
   - Lies den Dependency Header der zu ändernden Datei (falls vorhanden)
   - Identifiziere alle DEPENDENTS (wer nutzt diese Datei)
   - Prüfe die CHANGE IMPACT Sektion

2. **Kritische Dateien mit vielen Abhängigkeiten:**
   | Datei | Dependents | Kritische Aspekte |
   |-------|------------|-------------------|
   | `AppState.swift` | 9+ Views, HotkeyManager | @Published Props, initializeApp() Reihenfolge |
   | `DatabaseManager.swift` | 8+ ViewModels | initialize() vor Queries, Migrations |
   | `MeetingDetector.swift` | 4+ Listener | 5 Notifications, State-Sync mit AppState |
   | `ScreenCaptureManager.swift` | AppState | Delegate-Callbacks, Multi-Monitor |
   | `ScraineeApp.swift` | - | 10+ Window-Observer, openWindowAction |
   | `HotkeyManager.swift` | ScraineeApp | 7 Notifications für Fenster |

3. **Bei Änderungen an Notifications:**
   - ALLE Listener identifizieren (grep nach Notification.Name)
   - ScraineeApp.swift Observer aktualisieren
   - Relevante ViewModels aktualisieren

4. **Bei neuen Views/Features:**
   - Window in ScraineeApp.swift registrieren
   - Falls Hotkey: HotkeyManager + ScraineeApp Observer
   - UI-ARCHITECTURE.md aktualisieren

### Kritische Abhängigkeits-Matrix (Kurzform)

```
WENN DU ÄNDERST...          → DANN PRÜFE AUCH...
───────────────────────────────────────────────────────────
AppState.@Published         → Alle Views mit @EnvironmentObject
AppState.initializeApp()    → DB init vor Queries, Whisper BLOCKING
MeetingDetector.post()      → 4+ Listener (AppState, SCM, Coordinator, VM)
DatabaseManager Schema      → Migrations-Reihenfolge
ScreenCaptureManager.delegate → AppState Extension
HotkeyManager.post()        → ScraineeApp window observers
ScraineeApp.Window()        → HotkeyManager, openWindowAction
```

---

## Claude Code Workflow

### Plan Mode
Für komplexe Features starte im Plan Mode (`Shift+Tab` oder `--permission-mode plan`):
1. Analysiere bestehenden Code
2. Erstelle Implementierungsplan
3. Wechsle zu Normal Mode für Umsetzung

### Extended Thinking
Nutze Extended Thinking für komplexe Entscheidungen:
- `think` - Einfache Planung (~4K tokens)
- `think hard` - Mittlere Komplexität (~10K tokens)
- `ultrathink` - Architektur-Entscheidungen (~32K tokens)

### Verfügbare Commands
- `/build` - Projekt bauen
- `/test` - Tests ausführen
- `/test-coverage` - Tests mit Coverage
- `/feature` - Neues Feature planen
