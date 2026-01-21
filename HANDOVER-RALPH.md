# SCRAINEE - Handover-Dokument für Ralph

**Erstellt:** 2026-01-20
**Zweck:** Umfassende Dokumentation für Code-Review, Fixes, Verbesserungen und Erweiterungen

---

## Inhaltsverzeichnis

1. [Executive Summary](#1-executive-summary)
2. [Architektur-Übersicht](#2-architektur-übersicht)
3. [Kritische Komponenten](#3-kritische-komponenten)
4. [Code-Qualitätsprobleme](#4-code-qualitätsprobleme)
5. [Test-Coverage-Lücken](#5-test-coverage-lücken)
6. [TODO/FIXME Backlog](#6-todofixme-backlog)
7. [UI-Verbesserungspotenziale](#7-ui-verbesserungspotenziale)
8. [Performance-Optimierungen](#8-performance-optimierungen)
9. [Sicherheitsaspekte](#9-sicherheitsaspekte)
10. [Priorisierte Aufgabenliste](#10-priorisierte-aufgabenliste)
11. [Build & Test Kommandos](#11-build--test-kommandos)
12. [Wichtige Dateipfade](#12-wichtige-dateipfade)

---

## 1. Executive Summary

### Was ist SCRAINEE?

Eine macOS Menu-Bar-Anwendung (macOS 13+) für:
- **Automatische Bildschirmaufnahme** mit OCR-Texterkennung
- **Meeting-Erkennung** (Teams, Zoom, Webex, Google Meet) mit Audio-Transkription
- **AI-Zusammenfassungen** via Claude API
- **Notion-Integration** für Meeting-Notes Export

### Technologie-Stack

| Aspekt | Technologie |
|--------|-------------|
| Sprache | Swift 5.9+ |
| UI | SwiftUI (MVVM) |
| Concurrency | Swift Concurrency (async/await, actors) |
| Datenbank | SQLite via GRDB.swift 6.24+ |
| Transkription | WhisperKit (on-device) |
| AI | Claude API (Anthropic) |
| Audio | Core Audio ProcessTap (macOS 14.2+) / ScreenCaptureKit (Fallback) |

### Aktueller Zustand

**Funktioniert:**
- ✅ Screenshot-Capture mit OCR
- ✅ Meeting-Erkennung mit User-Bestätigung
- ✅ Audio-Aufnahme (ProcessTap auf macOS 14.2+)
- ✅ Echtzeit-Transkription (Whisper)
- ✅ AI-Zusammenfassungen (Claude)
- ✅ Timeline-Ansicht (Rewind-Style)
- ✅ Notion-Export

**Bekannte Einschränkungen:**
- ⚠️ ScreenCaptureKit Audio-Fallback (macOS 13-14.1) liefert teilweise stummes Audio
- ⚠️ Multi-Monitor: Sequentielle statt parallele Erfassung (Swift 6 Sendable-Einschränkung)
- ⚠️ Keine Accessibility-Unterstützung (VoiceOver, etc.)
- ⚠️ Keine Internationalisierung (nur Deutsch)

---

## 2. Architektur-Übersicht

### Schichten-Architektur

```
┌─────────────────────────────────────────────────────────────────┐
│                     APP LAYER                                    │
│  ScraineeApp (@main) │ AppState (Singleton Koordinator)         │
│  ├─ CaptureState     │ MeetingState                             │
│  ├─ SettingsState    │ UIState                                  │
└─────────────────────────────────────────────────────────────────┘
                              │
┌─────────────────────────────────────────────────────────────────┐
│                     UI LAYER (SwiftUI)                           │
│  MenuBarView │ SettingsView │ SearchView │ TimelineView         │
│  QuickAskView │ GalleryView │ MeetingMinutesView                │
│  + ViewModels (@MainActor ObservableObject)                     │
└─────────────────────────────────────────────────────────────────┘
                              │
┌─────────────────────────────────────────────────────────────────┐
│                   SERVICES LAYER                                 │
│  HotkeyManager │ PermissionManager │ KeychainService            │
│  ErrorManager │ FileLogger │ StartupCheckManager                │
└─────────────────────────────────────────────────────────────────┘
                              │
┌─────────────────────────────────────────────────────────────────┐
│                     CORE LAYER                                   │
│  ScreenCapture │ Database │ Meeting │ AI │ Audio │ OCR          │
│  Storage │ Integration │ Cache                                  │
└─────────────────────────────────────────────────────────────────┘
                              │
┌─────────────────────────────────────────────────────────────────┐
│                     DATA LAYER                                   │
│  DatabaseManager (Actor + GRDB) │ StorageManager (FileSystem)   │
│  SQLite │ HEIC Files │ Audio WAV │ Logs                         │
└─────────────────────────────────────────────────────────────────┘
```

### State-Management

```swift
AppState (Singleton, @MainActor)
├── captureState: CaptureState      // Screenshot-Capture State
│   ├── isCapturing, screenshotCount, totalScreenshots
│   └── toggleCapture(), startCapture(), stopCapture()
├── meetingState: MeetingState      // Meeting-bezogener State
│   ├── isMeetingActive, currentMeeting, isGeneratingSummary
│   └── handleMeetingStarted/Ended()
├── settingsState: SettingsState    // @AppStorage persistente Settings
└── uiState: UIState                // Transiente UI-State
```

**Hinweis:** Es existiert noch ein Backward-Compatibility-Layer in `AppState.swift` (Zeilen 88-379), der nach vollständiger Migration entfernt werden sollte.

### Notification-basierte Kommunikation

| Notification | Sender | Listener |
|--------------|--------|----------|
| `.windowRequested` | HotkeyManager | ScraineeApp |
| `.meetingStarted` | MeetingDetector | AppState, Coordinator, ScreenCaptureManager |
| `.meetingEnded` | MeetingDetector | AppState, Coordinator |
| `.meetingDetectedAwaitingConfirmation` | MeetingDetector | MeetingIndicatorView |
| `.transcriptionCompleted` | Coordinator | ScraineeApp |

**Wichtig:** 5 Legacy-Notifications sind als `@deprecated` markiert und sollten entfernt werden.

---

## 3. Kritische Komponenten

### Abhängigkeits-Matrix

```
WENN DU ÄNDERST...              → DANN PRÜFE AUCH...
────────────────────────────────────────────────────────────────
AppState.@Published             → 9+ Views mit @EnvironmentObject
AppState.initializeApp()        → DB → Whisper → Capture Reihenfolge (KRITISCH!)
MeetingDetector.post()          → 4+ Listener (AppState, Coordinator, etc.)
DatabaseManager Schema          → Migrations-Reihenfolge in migrate()
ScreenCaptureManager.delegate   → AppState Extension
HotkeyManager.post()            → ScraineeApp window observers
ScraineeApp.Window()            → HotkeyManager, openWindowAction
```

### Kritische Dateien

| Datei | Dependents | Kritische Aspekte |
|-------|------------|-------------------|
| `AppState.swift` | 11+ | @Published Props, initializeApp() Reihenfolge |
| `DatabaseManager.swift` | 8+ | initialize() vor Queries, Migrations |
| `MeetingDetector.swift` | 6 Notifications | State-Sync mit AppState |
| `StorageManager.swift` | 17+ | Alle Dateisystem-Zugriffe |
| `ScreenCaptureManager.swift` | 3 | Delegate-Callbacks, Multi-Monitor |

### App-Initialisierungs-Reihenfolge (KRITISCH!)

```swift
// Diese Reihenfolge NIEMALS ändern!
func initializeApp() async {
    // 1. Datenbank MUSS zuerst
    try await DatabaseManager.shared.initialize()

    // 2. Whisper BLOCKING load (wichtig für Meeting-System)
    try await WhisperTranscriptionService.shared.loadModel()

    // 3. Capture kann starten
    if settingsState.autoStartCapture {
        await captureState.startCapture()
    }
}
```

---

## 4. Code-Qualitätsprobleme

### 🔴 KRITISCH - Sofort beheben

#### 4.1 Force-Unwraps (Crash-Risiko)

| Datei | Zeile | Problem | Fix |
|-------|-------|---------|-----|
| `DateUtils.swift` | 104 | `Calendar.current.date(...)!` | Optional Binding |
| `ExportManager.swift` | 206 | `meeting.notionPageUrl!` | Guard-Statement |
| `ClaudeAPIClient.swift` | 141 | `messagesJSON as! [[String: AnyCodable]]` | `as?` mit Error |
| `ScreenCaptureManager.swift` | 535 | `windowElement as! AXUIElement` | `guard let as?` |

#### 4.2 Silent Error Swallowing (60+ Vorkommen)

**Kritischste Bereiche:**

```swift
// KeychainService.swift (40-94) - ALLE Keychain-Ops nutzen try?
try? keychain.get(key.rawValue)  // Fehler gehen verloren!

// FileLogger.swift (92-252) - Logging-Fehler verschluckt
try? FileManager.default.createDirectory(...)

// DatabaseManager.swift (538) - Verwaiste Dateien möglich
try? FileManager.default.removeItem(at: screenshot.fileURL)
```

**Empfehlung:** Ersetzen durch `do-catch` mit `ErrorManager.handle()` oder `FileLogger`

### 🟡 WICHTIG - Zeitnah beheben

#### 4.3 Print-Statements (60+ Vorkommen)

Alle `print()` sollten durch `FileLogger.shared.log()` ersetzt werden:

- `ProcessTapAudioCapture.swift`: 15+ Debug-Prints
- `AudioCaptureManager.swift`: 10+ Debug-Prints
- `StartupCheckManager.swift`: Health-Check-Logs
- `WhisperTranscriptionService.swift`: Status-Prints

#### 4.4 DispatchQueue.main statt Task @MainActor

```swift
// 5 Vorkommen - sollten ersetzt werden:
// ScraineeApp.swift:122, 400, 523
// SettingsView.swift:537, 581

// VON:
DispatchQueue.main.async { ... }

// ZU:
Task { @MainActor in ... }
```

### 🟢 POSITIV

- ✅ Alle ObservableObject-Klassen korrekt mit `@MainActor` markiert
- ✅ Exzellente `[weak self]` Verwendung (40+ korrekte Fälle)
- ✅ Keine leeren catch-Blöcke
- ✅ Actors für Thread-Safety (DatabaseManager, HashTracker, OCRSemaphore)

---

## 5. Test-Coverage-Lücken

### Aktuelle Test-Situation

| Layer | Komponenten | Getestet | Coverage |
|-------|------------|----------|----------|
| Core/AI | 3 | 0 | **0%** 🔴 |
| Core/Audio | 2 | 0 | **0%** 🔴 |
| Core/Meeting | 2 | 0 | **0%** 🔴 |
| Services | 8 | 0 | **0%** 🔴 |
| UI/ViewModels | 10+ | 0 | **0%** 🔴 |
| Core/Database | 1 + 9 Models | 1 (E2E) | ~80% ✅ |
| Core/ScreenCapture | 4 | 1 | 25% ⚠️ |
| Core/Storage | 3 | 2 (E2E) | ~60% ⚠️ |

**Geschätzte Gesamt-Coverage:** ~25-30%

### Kritische Komponenten ohne Tests

1. **WhisperTranscriptionService** - Model-Loading, Health-Checks, Race-Conditions
2. **MeetingDetector** - 5 Notifications, State-Machine, App-Erkennung
3. **ScreenCaptureManager** - ScreenCaptureKit-Integration, Delegate-Callbacks
4. **HotkeyManager** - 7 Notifications, globale Hotkeys
5. **PermissionManager** - Berechtigungs-Prüfung, Silent Failures möglich
6. **KeychainService** - Credentials könnten verloren gehen

### Fehlende Test-Szenarien

- ❌ Error-Cases (Disk-Full, DB-Corruption, API-Timeouts)
- ❌ ViewModel-Tests für State-Management
- ❌ Mock-Validierung mit `spec` (aktuell akzeptieren Mocks beliebige Argumente)

---

## 6. TODO/FIXME Backlog

### Offene TODOs

| Datei | Zeile | Beschreibung | Priorität |
|-------|-------|--------------|-----------|
| `SettingsValidator.swift` | 185 | `meetingInterval: nil` - Settings Export unvollständig | Mittel |

### Backward-Compatibility zu entfernen

| Datei | Zeilen | Beschreibung |
|-------|--------|--------------|
| `AppState.swift` | 88-379 | 6 Sections mit Wrapper-Properties/Methods |
| `HotkeyManager.swift` | 240-249 | 5 Legacy Window-Notifications (@deprecated) |
| `ScraineeApp.swift` | 540+ | Legacy Window-Opening-Methoden |

### Deaktivierte Features

| Feature | Datei | Zeile | Grund |
|---------|-------|-------|-------|
| Auto-Meeting-End-Erkennung | `MeetingDetector.swift` | 57, 327-329 | Zu unzuverlässig (Fokus-Wechsel) |

### Ungenutzte Features (fertig implementiert)

| Feature | Datei | Status |
|---------|-------|--------|
| Export Manager (PDF, CSV, JSON) | `ExportManager.swift` | Bereit, keine UI-Integration |

---

## 7. UI-Verbesserungspotenziale

### 🔴 KRITISCH - Accessibility

**Aktuelle Situation:** Keine Accessibility-Unterstützung

- ❌ Keine `.accessibilityLabel()` oder `.accessibilityHint()`
- ❌ VoiceOver-Support fehlt komplett
- ❌ Keyboard-Navigation nur in Timeline vorhanden
- ⚠️ Nur 15 `.help()` Tooltips insgesamt

**Empfohlener Fix:**
```swift
Button(action: { ... }) {
    Image(systemName: "...")
}
.accessibilityLabel("Aufnahme pausieren")
.accessibilityHint("Schaltet die Screenshot-Aufnahme um")
```

### 🟡 WICHTIG - Internationalisierung

**Aktuelle Situation:** 625 hardcodierte deutsche Strings

- ❌ Keine `Localizable.strings` Datei
- ❌ Keine `LocalizedStringKey` Verwendung

### 🟡 WICHTIG - Inkonsistenzen

| Problem | Beispiele |
|---------|-----------|
| Embedded ViewModels | `QuickAskViewModel`, `SummaryRequestViewModel` in View-Dateien |
| Duplizierte Components | `MenuButton`, `ActionButton`, `QuickOptionButton` |
| Inkonsistente Empty-States | Unterschiedliche Layouts |
| Magic Numbers | Hardcodierte Größen ohne zentrale Konstanten |

### Empfohlene Struktur

```
UI/
├── Components/           # FEHLT - Shared Components
│   ├── Buttons/
│   ├── Cards/
│   └── EmptyStates/
├── Constants/            # FEHLT
│   ├── LayoutConstants.swift
│   └── ColorTheme.swift
└── [bestehende Ordner]
```

---

## 8. Performance-Optimierungen

### ✅ Bereits implementiert

| Optimierung | Beschreibung | Impact |
|-------------|--------------|--------|
| Database Indexes | 4 neue Indexes (app_time, display_time, etc.) | 10-50x schnellere Queries |
| ThumbnailCache (Actor) | LRU-Cache für Timeline | Schnelles Scrolling |
| OCR Semaphore | Max 4 parallele Tasks | Memory-Spikes verhindert |
| WhisperKit Auto-Unload | Nach 5 Min Inaktivität | ~3GB RAM gespart |
| StorageManager Caching | 60s Size-Cache | UI-Freezes eliminiert |

### ⚠️ Noch ausstehend

| Optimierung | Beschreibung | Aufwand |
|-------------|--------------|---------|
| Multi-Monitor Parallel | Aktuell sequentiell (Swift 6 Sendable) | Hoch |
| Timeline Memory | `ForEach(Array(enumerated()))` Overhead | Mittel |
| Combine Throttling | Live-Updates bei schnellen Transkripten | Niedrig |

---

## 9. Sicherheitsaspekte

### Keychain-Nutzung

```swift
// Gespeicherte Secrets:
- Claude API Key (service: "claude-api")
- Notion API Key (service: "notion-api")
- Notion Database ID (service: "notion-database")
```

**Problem:** `KeychainService` verwendet durchgehend `try?` - Fehler werden verschluckt.

### Berechtigungen

| Berechtigung | Typ | Geprüft durch |
|--------------|-----|---------------|
| Screen Recording | Pflicht | PermissionManager |
| Accessibility | Optional | PermissionManager |

### Datenspeicherung

```
~/Library/Application Support/Scrainee/
├── scrainee.sqlite          # Verschlüsselt durch macOS FileVault
├── screenshots/             # HEIC-Kompression (60% Quality)
├── audio/                   # WAV-Dateien (16kHz Mono)
└── logs/                    # 7 Tage Retention
```

### Entitlements

```xml
<!-- Scrainee.entitlements -->
<key>com.apple.security.app-sandbox</key>
<true/>
<key>com.apple.security.cs.disable-library-validation</key>
<true/>  <!-- Für WhisperKit während lokaler Entwicklung -->
```

---

## 10. Priorisierte Aufgabenliste

### Phase 1: Kritische Fixes (Sofort)

- [ ] **Force-Unwraps entfernen** (4 Stellen) - Crash-Risiko
- [ ] **KeychainService Error-Handling** - Credentials-Verlust-Risiko
- [ ] **FileLogger try? Fixes** - Logging-Ausfälle unbemerkt

### Phase 2: Tests (Hoch prioritär)

- [ ] **WhisperTranscriptionService Tests** - Race-Conditions dokumentiert
- [ ] **MeetingDetector Tests** - 5 Notifications, State-Machine
- [ ] **ScreenCaptureManager Tests** - Kern-Funktionalität
- [ ] **Services Tests** (HotkeyManager, PermissionManager, KeychainService)

### Phase 3: Code-Cleanup (Mittel prioritär)

- [ ] **Backward-Compatibility entfernen** (AppState, HotkeyManager)
- [ ] **60+ print() → FileLogger** ersetzen
- [ ] **try? → do-catch** Umstellung (60+ Stellen)
- [ ] **DispatchQueue.main → Task @MainActor**

### Phase 4: UI-Verbesserungen (Mittel prioritär)

- [ ] **Accessibility Labels** für alle Buttons
- [ ] **Shared Components Library** aufbauen
- [ ] **LayoutConstants.swift** einführen
- [ ] **Embedded ViewModels** auslagern

### Phase 5: Erweiterungen (Niedrig prioritär)

- [ ] **Internationalisierung** vorbereiten (Localizable.strings)
- [ ] **Export Manager** UI-Integration
- [ ] **Preview-Infrastruktur** (Mock-Data, States)
- [ ] **Multi-Monitor Parallel** (nach Swift 6 Stabilisierung)

---

## 11. Build & Test Kommandos

```bash
# Projekt-Verzeichnis
cd /Users/cpohl/Documents/00\ PRIVATE/00\ Coding/CLAUDE\ CODE/SCRAINEE

# Build
swift build

# Release Build
swift build -c release

# Alle Tests
swift test

# Tests mit Coverage
swift test --enable-code-coverage

# Spezifische Tests
swift test --filter ScreenCaptureManagerTests
swift test --filter DatabaseE2ETests

# Xcode-Projekt regenerieren
xcodegen generate

# Xcode öffnen
open Scrainee.xcodeproj
```

---

## 12. Wichtige Dateipfade

### Dokumentation

| Datei | Inhalt |
|-------|--------|
| `/CLAUDE.md` | Projekt-Übersicht, Coding-Standards, Build-Anweisungen |
| `/STATUS.md` | Aktueller Status, letzte Änderungen, nächste Schritte |
| `/UI-ARCHITECTURE.md` | UI-Komponenten, Datenflüsse |
| `/DEPENDENCY-DOCS.md` | Dependency Header Format |

### Kritische Code-Dateien

| Datei | Verantwortung |
|-------|---------------|
| `App/ScraineeApp.swift` | Entry Point, Window-Definitionen |
| `App/AppState.swift` | Zentraler State Manager |
| `App/State/*.swift` | Sub-State-Objekte |
| `Core/Database/DatabaseManager.swift` | Thread-safe DB-Zugriff |
| `Core/Meeting/MeetingDetector.swift` | Meeting-Erkennung |
| `Core/Audio/ProcessTapAudioCapture.swift` | Audio-Capture (macOS 14.2+) |
| `Core/Audio/WhisperTranscriptionService.swift` | On-Device Transkription |
| `Core/AI/ClaudeAPIClient.swift` | AI-Integration |

### Test-Dateien

| Datei | Coverage |
|-------|----------|
| `Tests/ScraineeTests/E2E/FullPipelineE2ETests.swift` | Komplette Pipeline |
| `Tests/ScraineeTests/E2E/DatabaseE2ETests.swift` | DB + FTS5 + OCR |
| `Tests/ScraineeTests/Unit/DisplayManagerTests.swift` | Multi-Monitor |
| `Tests/ScraineeTests/Helpers/TestDatabaseManager.swift` | Test-Infrastruktur |

### Datenspeicherung (Runtime)

```
~/Library/Application Support/Scrainee/
├── scrainee.sqlite
├── screenshots/YYYY/MM/DD/
├── audio/meeting_*.wav
└── logs/
```

---

## Anhang: Dependency Headers

Alle 60 Swift-Dateien enthalten standardisierte Dependency Headers im Format:

```swift
// ═══════════════════════════════════════════════════════════════
// MARK: - 📋 DEPENDENCY DOCUMENTATION
// ═══════════════════════════════════════════════════════════════
// FILE: [Name]
// PURPOSE: [Beschreibung]
// LAYER: [App|Core|Service|UI]
//
// ┌───────────────────────────────────────────────────────────────┐
// │ DEPENDENCIES (was diese Datei NUTZT)                         │
// │ IMPORTS: ...                                                  │
// │ LISTENS TO: ...                                               │
// └───────────────────────────────────────────────────────────────┘
//
// ┌───────────────────────────────────────────────────────────────┐
// │ DEPENDENTS (wer diese Datei NUTZT)                           │
// │ USED BY: ...                                                  │
// │ POSTS: ...                                                    │
// └───────────────────────────────────────────────────────────────┘
//
// LAST UPDATED: YYYY-MM-DD
```

Diese Headers erleichtern das Verständnis der Abhängigkeiten bei Code-Änderungen erheblich.

---

**Ende des Handover-Dokuments**
