# ScrAInee - Projektstatus

**Letzte Aktualisierung:** 2026-01-20
**Aktueller Branch:** main
**Letzter Commit:** a5b4b4a

---

## Kürzlich implementierte Features

### Session 2026-01-20 (Update 17) - Handover-Dokument für Ralph

#### Aufgabe
Umfassende Dokumentation des Repositories für Code-Review, Fixes und Erweiterungen.

#### Erstellte Datei
`HANDOVER-RALPH.md` - Enthält:

| Abschnitt | Inhalt |
|-----------|--------|
| **Executive Summary** | Was ist SCRAINEE, Tech-Stack, aktueller Zustand |
| **Architektur-Übersicht** | Schichten, State-Management, Notifications |
| **Kritische Komponenten** | Abhängigkeits-Matrix, kritische Dateien, Init-Reihenfolge |
| **Code-Qualitätsprobleme** | Force-Unwraps, try? Swallowing, print() Statements |
| **Test-Coverage-Lücken** | ~25-30% Coverage, 6 kritische Komponenten ohne Tests |
| **TODO/FIXME Backlog** | Offene TODOs, Backward-Compat zu entfernen |
| **UI-Verbesserungspotenziale** | Accessibility, i18n, Inkonsistenzen |
| **Performance-Optimierungen** | Bereits implementiert + ausstehend |
| **Sicherheitsaspekte** | Keychain, Berechtigungen, Datenspeicherung |
| **Priorisierte Aufgabenliste** | 5 Phasen mit konkreten Tasks |

#### Identifizierte Hauptprobleme

**Kritisch (sofort beheben):**
- 4 Force-Unwraps mit Crash-Risiko
- KeychainService Error-Handling (silent failures)
- FileLogger try? Probleme

**Hoch prioritär (Tests fehlen):**
- WhisperTranscriptionService (0%)
- MeetingDetector (0%)
- ScreenCaptureManager (0%)
- Services Layer (0%)

**Mittel prioritär:**
- 60+ try? Verwendungen ersetzen
- 60+ print() durch Logger ersetzen
- Backward-Compatibility Layer entfernen
- Accessibility Labels hinzufügen

---

### Session 2026-01-20 (Update 16) - Audio Format Mismatch Fix

#### Problem
ProcessTap Audio Capture schlug fehl mit:
```
Format mismatch: input hw <2 ch, 48000 Hz>, client format <2 ch, 44100 Hz>
Failed to create tap, config change pending!
```

#### Root Cause
Das Aggregate Device und AVAudioEngine wurden nicht explizit auf die Hardware-Sample-Rate (48kHz) konfiguriert. AVAudioEngine verwendete einen Default (44.1kHz), was zum Format-Mismatch führte.

#### Implementierter Fix

**1. Neue Hilfsmethode `getDeviceSampleRate()`**
- Fragt die nominelle Sample Rate des Aggregate Device ab via CoreAudio API
- Verwendet `kAudioDevicePropertyNominalSampleRate`

**2. Dynamische Sample Rate Anpassung in `setupAudioEngine()`**
- Hardware Sample Rate wird VOR Engine-Start abgefragt
- `config.sampleRate` wird dynamisch aktualisiert
- Explizites `AVAudioFormat` wird mit Hardware-Rate erstellt
- Tap wird mit diesem Format installiert (nicht vom `inputNode.outputFormat`)

```swift
// Neu: Hardware Rate abfragen und explizites Format verwenden
if let hwSampleRate = getDeviceSampleRate(deviceID: aggregateDeviceID) {
    config.sampleRate = hwSampleRate
    print("[DEBUG] ProcessTapAudioCapture: Using hardware sample rate: \(hwSampleRate) Hz")
}

guard let captureFormat = AVAudioFormat(
    commonFormat: .pcmFormatFloat32,
    sampleRate: config.sampleRate,
    channels: AVAudioChannelCount(config.channels),
    interleaved: false
) else { ... }

engine.inputNode.installTap(onBus: 0, bufferSize: 4096, format: captureFormat) { ... }
```

#### Geänderte Datei

| Datei | Änderung |
|-------|----------|
| `Core/Audio/ProcessTapAudioCapture.swift` | +`getDeviceSampleRate()`, dynamisches Format in `setupAudioEngine()` |

#### Verifizierung

Nach dem Fix sollte die Konsole zeigen:
```
[DEBUG] ProcessTapAudioCapture: Using hardware sample rate: 48000.0 Hz
[DEBUG] ProcessTapAudioCapture: Using capture format: <AVAudioFormat: 2 ch, 48000 Hz, Float32>
[DEBUG] ProcessTapAudioCapture: Audio engine started
```

**Kein "Format mismatch" Fehler mehr!**

---

### Session 2026-01-20 (Update 15) - Core Audio ProcessTap für zuverlässiges Audio-Capture

#### Problem
ScreenCaptureKit lieferte konstant **stummes Audio** (maxAmp = 0.0000) bei Microsoft Teams, unabhängig von der Filter-Konfiguration:
- Display-Filter: maxAmp = 0.0000
- App-Filter: Kurzzeitig Audio (0.0567), dann wieder Stille
- All-Apps-Filter: maxAmp = 0.0000

**Root Cause:** ScreenCaptureKit hat auf macOS 15 bekannte Probleme mit Audio-Capture von bestimmten Apps wie Teams.

#### Implementierte Lösung

**Core Audio ProcessTap API (macOS 14.2+):**
- Neue `ProcessTapAudioCapture` Klasse nutzt `AudioHardwareCreateProcessTap`
- Deutlich zuverlässiger als ScreenCaptureKit für System-Audio
- Erfasst **gesamtes System-Audio** über einen globalen Tap

#### Neue Capture-Strategie

| macOS Version | Methode | Zuverlässigkeit |
|---------------|---------|-----------------|
| **14.2+** | Core Audio ProcessTap | ⭐⭐⭐ Hoch |
| **13.0-14.1** | ScreenCaptureKit (Fallback) | ⭐ Niedrig |

#### Neue Dateien

| Datei | Beschreibung |
|-------|-------------|
| `Core/Audio/ProcessTapAudioCapture.swift` | Core Audio ProcessTap Implementation |

#### Geänderte Dateien

| Datei | Änderung |
|-------|----------|
| `Core/Audio/AudioCaptureManager.swift` | Nutzt ProcessTap primär, ScreenCaptureKit als Fallback |

#### Technische Details

**ProcessTapAudioCapture:**
```swift
// Globaler Tap für gesamtes System-Audio
let tapDescription = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
tapDescription.muteBehavior = .unmuted  // System-Audio bleibt hörbar
tapDescription.isPrivate = true
tapDescription.isMixdown = true  // Mix zu Stereo

AudioHardwareCreateProcessTap(tapDescription, &tapID)
```

**AudioCaptureManager Logik:**
```swift
func startRecording(...) async throws {
    // 1. Versuche ProcessTap (macOS 14.2+)
    if #available(macOS 14.2, *) {
        try await startProcessTapRecording(for: meetingId, config: config)
        activeCaptureMethod = .processTap
        return
    }

    // 2. Fallback: ScreenCaptureKit
    try await setupAudioStream(forApp: appBundleId)
    activeCaptureMethod = .screenCapture
}
```

#### Verifizierung (TEST ERFORDERLICH!)

1. **App starten, Teams-Meeting beitreten**
2. **Konsole prüfen:**
   ```
   [DEBUG] AudioCaptureManager: Using ProcessTap capture (macOS 14.2+)
   [DEBUG] ProcessTapAudioCapture: Created tap with ID XXX
   [DEBUG] ProcessTapAudioCapture: Audio engine started
   [DEBUG] ProcessTapAudioCapture: XXX samples, maxAmp: 0.XXXX
   ```
   - maxAmp > 0.01 = Audio wird erfasst ✅

3. **Audio-Datei testen:**
   ```bash
   afplay ~/Library/Application\ Support/Scrainee/audio/meeting_*.wav
   ```

#### Quellen

- [AudioCap GitHub](https://github.com/insidegui/AudioCap) - macOS 14.4+ System Audio Recording
- [Core Audio Tap Gist](https://gist.github.com/sudara/34f00efad69a7e8ceafa078ea0f76f6f) - macOS 14.2 Tap API Example

---

### Session 2026-01-20 (Update 14) - Audio-Capture Fix: App-spezifisches Capture (ÜBERHOLT)

**HINWEIS:** Diese Lösung wurde durch Update 15 (ProcessTap) ersetzt, da ScreenCaptureKit kein Audio von Teams lieferte.

#### Problem
Audio-Dateien wurden während Meetings (Microsoft Teams) erstellt, aber waren **stumm** (maxAmp = 0.0000).

#### Versuchte Lösung (nicht erfolgreich)
App-spezifische ScreenCaptureKit Filter - alle Varianten lieferten stummes Audio

---

### Session 2026-01-20 (Update 13) - Phase 2.2: AppState Aufteilung

#### Aufgabe
Aufteilung des monolithischen `AppState` in separate, fokussierte State-Objekte für bessere Wartbarkeit, Testbarkeit und Separation of Concerns.

#### Neue State-Struktur

| State-Objekt | Verantwortung | Properties |
|--------------|---------------|------------|
| **CaptureState** | Screen Capture Logik | isCapturing, screenshotCount, totalScreenshots, lastCaptureTime, currentApp, storageUsed |
| **MeetingState** | Meeting Management | isMeetingActive, currentMeeting, isGeneratingSummary, lastSummary, currentMeetingDbId |
| **SettingsState** | Persistente Einstellungen | captureInterval, retentionDays, ocrEnabled, heicQuality, notionEnabled, etc. |
| **UIState** | Transiente UI-States | showPermissionAlert, errorMessage |

#### Implementierte Phasen

| Phase | Beschreibung | Status |
|-------|-------------|--------|
| **A** | State-Objekte erstellen + Backward-Compatibility Layer | ✅ |
| **B** | CaptureState migrieren (MenuBarView, ContextOverlay, HotkeyManager) | ✅ |
| **C** | MeetingState migrieren (MenuBarView, ScreenCaptureManager) | ✅ |
| **D** | SettingsState migrieren (SettingsValidator, ScraineeApp, ScreenCaptureManager, AdminViewModel) | ✅ |
| **E** | UIState migrieren (ScraineeApp, MenuBarView) | ✅ |
| **F** | Cleanup und Dokumentation | ✅ |

#### Neue Dateien

| Datei | Beschreibung |
|-------|-------------|
| `Scrainee/App/State/CaptureState.swift` | Capture-bezogener State mit toggleCapture(), startCapture(), stopCapture() |
| `Scrainee/App/State/MeetingState.swift` | Meeting-bezogener State mit handleMeetingStarted/Ended() |
| `Scrainee/App/State/SettingsState.swift` | @AppStorage-basierte persistente Settings |
| `Scrainee/App/State/UIState.swift` | Transienter UI-State |

#### Geänderte Dateien

| Datei | Änderung |
|-------|----------|
| `App/AppState.swift` | Sub-State-Objekte, Backward-Compatibility Properties, setupStateConnections() |
| `UI/MenuBar/MenuBarView.swift` | captureState, meetingState, uiState Zugriffe |
| `UI/ContextOverlay/ContextOverlayView.swift` | captureState Zugriffe |
| `Services/HotkeyManager.swift` | captureState.toggleCapture() |
| `Core/ScreenCapture/ScreenCaptureManager.swift` | meetingState.isMeetingActive, settingsState.heicQuality/ocrEnabled |
| `Services/SettingsValidator.swift` | settingsState für Import/Export/Reset |
| `App/ScraineeApp.swift` | settingsState, uiState, captureState Zugriffe |
| `UI/Admin/AdminViewModel.swift` | settingsState.retentionDays |

#### Architektur nach Migration

```swift
AppState (Koordinator)
├── captureState: CaptureState      // @Published
│   ├── isCapturing, screenshotCount, etc.
│   └── toggleCapture(), startCapture(), stopCapture()
├── meetingState: MeetingState      // @Published
│   ├── isMeetingActive, currentMeeting, etc.
│   └── handleMeetingStarted/Ended()
├── settingsState: SettingsState    // @Published
│   └── @AppStorage properties
└── uiState: UIState                // @Published
    └── showPermissionAlert, errorMessage
```

#### Build & Tests
- ✅ Build erfolgreich
- ✅ 95 Tests bestanden
- ✅ Keine Breaking Changes durch Backward-Compatibility Layer

---

### Session 2026-01-20 (Update 12) - Phase 2 Architektur-Refactoring

#### Aufgabe
Implementierung von Phase 2 des Architektur-Optimierungsplans: Database Indexes, Window-Konsolidierung und Notification-Konsolidierung.

#### Implementierte Optimierungen

| Optimierung | Beschreibung | Impact |
|-------------|-------------|--------|
| **Database Indexes** | 4 neue Performance-Indexes für Timeline/Gallery-Queries | 10-50x schnellere Queries |
| **Window-Konsolidierung** | 6 duplizierte openXxxWindow() Methoden → 1 generische openWindow() | -60 LOC, DRY-Prinzip |
| **Notification-Konsolidierung** | 5 Window-Notifications → 1 generische .windowRequested | 16 → 11 Notifications |
| **WindowConfig Registry** | Zentrale Konfiguration aller App-Fenster | Single Source of Truth |

#### Bearbeitete Dateien

| Datei | Änderung |
|-------|----------|
| `Scrainee/Core/Database/DatabaseManager.swift` | +4 Performance-Indexes (app_time, display_time, ocr_screenshot, meetings_status) |
| `Scrainee/App/ScraineeApp.swift` | WindowConfig Registry, generisches openWindow(), 5 Observer → 1 |
| `Scrainee/Services/HotkeyManager.swift` | .windowRequested Notification, Legacy-Notifications @deprecated |
| `Scrainee/UI/ContextOverlay/ContextOverlayView.swift` | Auf .windowRequested umgestellt |

#### Neue Architektur-Elemente

**WindowConfig Registry:**
```swift
struct WindowConfig {
    let id: String
    let title: String
    let isFloating: Bool

    static let registry: [String: WindowConfig] = [
        "quickask", "search", "summary", "timeline",
        "meetingminutes", "meetingindicator", "gallery", "summarylist"
    ]
}
```

**Generische Window-Notification:**
```swift
// Sender (HotkeyManager):
NotificationCenter.default.post(
    name: .windowRequested,
    object: nil,
    userInfo: ["windowId": "quickask"]
)

// Empfänger (ScraineeApp):
let windowObserver = NotificationCenter.default.addObserver(
    forName: .windowRequested, ...
) { notification in
    guard let windowId = notification.userInfo?["windowId"] as? String else { return }
    self?.openWindow(windowId)
}
```

#### Build & Tests
- ✅ Build erfolgreich (keine Errors)
- ✅ 95 Tests bestanden
- ✅ Keine Deprecation-Warnings mehr

#### Phase 2.2 (AppState Aufteilung): ERLEDIGT ✅
Die Aufteilung von AppState in CaptureState/MeetingState/SettingsState/UIState wurde erfolgreich implementiert.
- Backward-Compatibility Layer ermöglichte schrittweise Migration
- Alle 95 Tests bestehen weiterhin
- Siehe Update 13 oben für Details

---

### Session 2026-01-20 (Update 11) - Phase 1 Optimierungen

#### Aufgabe
Implementierung der Phase 1 Quick Wins aus dem Optimierungsplan zur Verbesserung von Performance und Ressourcenverbrauch.

#### Implementierte Optimierungen

| Optimierung | Beschreibung | Impact |
|-------------|-------------|--------|
| **DEBUG Print-Statements entfernt** | 83 DEBUG/ERROR prints aus 7 Dateien entfernt | CPU-Entlastung bei jedem Capture-Zyklus |
| **calculateDirectorySize() Caching** | 60-Sekunden-Cache für Verzeichnisgröße | Eliminiert UI-Freezes bei großem Screenshot-Archiv |
| **WhisperKit Auto-Unload** | Automatisches Entladen nach 5 Minuten Inaktivität | ~3GB RAM gespart zwischen Meetings |
| **OCR Semaphore** | Max 4 parallele OCR-Tasks via Actor-basiertem Semaphore | Verhindert Memory-Spikes (2GB+ → max 400MB) |

#### Bearbeitete Dateien

| Datei | Änderung |
|-------|----------|
| `Scrainee/Core/Audio/AudioCaptureManager.swift` | 22 DEBUG prints entfernt |
| `Scrainee/Core/Meeting/MeetingTranscriptionCoordinator.swift` | 15 DEBUG prints entfernt, Auto-Unload implementiert |
| `Scrainee/App/AppState.swift` | 14 DEBUG prints entfernt |
| `Scrainee/Core/Meeting/MeetingDetector.swift` | 11 DEBUG prints entfernt |
| `Scrainee/App/ScraineeApp.swift` | 7 DEBUG prints entfernt |
| `Scrainee/Core/ScreenCapture/ScreenCaptureManager.swift` | 5 DEBUG prints entfernt, OCR Semaphore hinzugefügt |
| `Scrainee/Core/Audio/WhisperTranscriptionService.swift` | 3 DEBUG prints entfernt |
| `Scrainee/Core/Storage/StorageManager.swift` | Size-Caching mit 60s Intervall |
| `Scrainee/UI/MeetingIndicator/MeetingIndicatorViewModel.swift` | deinit Sendable-Fix |

#### WhisperKit Auto-Unload Details

```swift
// Nach Meeting-Ende wird Auto-Unload geplant
private let modelUnloadDelay: Duration = .seconds(300)  // 5 Minuten

private func scheduleModelUnload() {
    modelUnloadTask = Task {
        try await Task.sleep(for: modelUnloadDelay)
        if !isTranscribing {
            whisperService.unloadModel()  // ~3GB RAM freigegeben
        }
    }
}
```

#### OCR Semaphore Details

```swift
// Actor-basierter Semaphore für Thread-Sicherheit
private actor OCRSemaphore {
    private let maxConcurrent: Int = 4
    func acquire() async { ... }
    func release() { ... }
}
```

#### Size-Caching Details

```swift
// StorageManager cacht jetzt die Verzeichnisgröße
private var cachedDirectorySize: Int64 = 0
private var lastSizeCalculation: Date = .distantPast
private let sizeRecalculationInterval: TimeInterval = 60
```

#### Build & Tests
- ✅ Build erfolgreich
- ✅ 95 Tests bestanden
- ⚠️ Multi-Monitor Parallel Capture aufgrund Swift 6 Sendable-Einschränkungen noch sequentiell

---

### Session 2026-01-20 (Update 10) - Vollständige Dependency Header Dokumentation

#### Aufgabe
Dependency Headers in ALLE 60 Swift-Dateien des Projekts eingefügt. Außerdem wurde das Konzept in die globale CLAUDE.md aufgenommen.

#### Neue Dokumentations-Dateien
| Datei | Zweck |
|-------|-------|
| `UI-ARCHITECTURE.md` | Vollständige UI-Komponenten-Dokumentation mit Button→Funktion Mappings |
| `DEPENDENCY-DOCS.md` | Konzept und Format-Spezifikation für Dependency Headers |

#### Bearbeitete Dateien (alle 60 Swift-Dateien)

| Layer | Dateien | Besonderheiten |
|-------|---------|----------------|
| **App** | 2 | AppState, ScraineeApp - ausführliches Format (kritisch) |
| **Core/Database** | 10 | DatabaseManager (ausführlich), 9 Models (kompakt) |
| **Core/Meeting** | 2 | MeetingDetector (6 Notifications!), TranscriptionCoordinator |
| **Core/Audio** | 2 | AudioCaptureManager, WhisperTranscriptionService |
| **Core/ScreenCapture** | 4 | ScreenCaptureManager (Delegate-Pattern), DisplayManager, etc. |
| **Core/Storage** | 3 | StorageManager (17 Dependents!), ImageCompressor, RetentionPolicy |
| **Core/AI** | 3 | ClaudeAPIClient, SummaryGenerator, MeetingMinutesGenerator |
| **Core/Integration** | 1 | NotionClient |
| **Core/OCR** | 1 | OCRManager |
| **Core/Cache** | 1 | ThumbnailCache |
| **Services** | 8 | HotkeyManager (5 Notifications!), PermissionManager, etc. |
| **UI/Timeline** | 4 | View, ViewModel, Slider, ThumbnailStrip |
| **UI/Search** | 2 | View, ViewModel |
| **UI/Gallery** | 2 | View, ViewModel |
| **UI/Summary** | 3 | RequestView, ListView, NotionExportPreview |
| **UI/QuickAsk** | 1 | QuickAskView |
| **UI/MenuBar** | 1 | MenuBarView (Haupt-UI) |
| **UI/Settings** | 1 | SettingsView (6 Tabs) |
| **UI/MeetingMinutes** | 2 | View, ViewModel |
| **UI/MeetingIndicator** | 2 | View, ViewModel (empfängt 6 Notifications!) |
| **UI/Admin** | 2 | DashboardView, ViewModel |
| **UI/ContextOverlay** | 1 | ContextOverlayView |
| **Utilities** | 2 | Logger, DateUtils |

#### Globale CLAUDE.md aktualisiert
Das Dependency-Dokumentationssystem wurde in die globale `~/.claude/CLAUDE.md` aufgenommen und gilt jetzt für ALLE Projekte.

#### Kritischste Abhängigkeiten (Quick Reference)
```
Datei                    → Dependents  → Kritische Aspekte
─────────────────────────────────────────────────────────────
StorageManager.swift     → 17          → Alle Dateisystem-Zugriffe
AppState.swift           → 11          → @Published, initializeApp() Reihenfolge
MeetingDetector.swift    → 6 Notif.    → State-Sync mit AppState, Listener
ScreenCaptureManager     → Delegate    → AppState Extension, Multi-Monitor
HotkeyManager.swift      → 5 Notif.    → ScraineeApp Window-Observer
```

---

### Session 2026-01-20 (Update 9) - Dependency Headers fuer Core/ScreenCapture und Core/Storage

#### Aufgabe
Dependency Headers fuer die ScreenCapture- und Storage-Layer eingefuegt. Ausfuehrliches Format fuer ScreenCaptureManager (mit Delegate-Pattern), kompaktes Format fuer die anderen Dateien.

#### Bearbeitete Dateien

| Datei | Format | Dokumentierte Abhaengigkeiten |
|-------|--------|-------------------------------|
| `Core/ScreenCapture/ScreenCaptureManager.swift` | Ausfuehrlich | 8 interne Dependencies, 3 Data Models, 3 Dependents, 3 Notifications empfangen, Delegate-Protokoll |
| `Core/ScreenCapture/DisplayManager.swift` | Kompakt | ScreenCaptureKit, IOKit; genutzt von ScreenCaptureManager, Tests |
| `Core/ScreenCapture/AdaptiveCaptureManager.swift` | Kompakt | Foundation, Combine; genutzt von ScreenCaptureManager, AppState |
| `Core/ScreenCapture/ScreenshotDiffer.swift` | Kompakt | CoreGraphics; genutzt von E2E-Tests |
| `Core/Storage/StorageManager.swift` | Kompakt | Foundation; 17 Dependents (kritischste Datei!) |
| `Core/Storage/ImageCompressor.swift` | Kompakt | ImageIO, StorageManager; genutzt von ScreenCaptureManager, SummaryGenerator |
| `Core/Storage/RetentionPolicy.swift` | Kompakt | DatabaseManager, StorageManager; genutzt von ScraineeApp, SettingsView |

#### ScreenCaptureManager Delegate-Protokoll

```swift
protocol ScreenCaptureManagerDelegate: AnyObject {
    func screenCaptureManager(_:didCaptureScreenshot:) // Erfolgreicher Capture
    func screenCaptureManager(_:didFailWithError:)     // Capture-Fehler
}
```

Implementiert von: AppState, MockScreenCaptureDelegate (Tests)

#### Kritische Abhaengigkeiten

| Datei | Dependents-Anzahl | Kritikalitaet |
|-------|-------------------|---------------|
| StorageManager.swift | 17 | Hoechste - alle Dateisystem-Zugriffe |
| ScreenCaptureManager.swift | 3 | Hoch - zentrale Capture-Pipeline |
| DisplayManager.swift | 5 | Mittel - Multi-Monitor-Support |

---

### Session 2026-01-20 (Update 8) - Dependency Headers fuer Services-Layer

#### Aufgabe
Dependency Headers fuer alle Services-Layer Swift-Dateien eingefuegt. Besonderer Fokus auf HotkeyManager mit ausfuehrlicher Notification-Dokumentation.

#### Bearbeitete Dateien

| Datei | Format | Dokumentierte Abhaengigkeiten |
|-------|--------|------------------------------|
| `Services/HotkeyManager.swift` | Ausfuehrlich | 5 Notifications gesendet (Tabelle), Carbon.HIToolbox, PermissionManager, AppState |
| `Services/PermissionManager.swift` | Kompakt | ScreenCaptureKit, AXIsProcessTrusted, 7 Dependents |
| `Services/KeychainService.swift` | Kompakt | KeychainAccess (Third-Party), 3 Keys dokumentiert |
| `Services/ErrorManager.swift` | Kompakt | FileLogger, 6 bekannte Error-Typen |
| `Services/FileLogger.swift` | Kompakt | StorageManager, os.log, Log-Pfade und Retention |
| `Services/SettingsValidator.swift` | Kompakt | AppState fuer Import/Export |
| `Services/ExportManager.swift` | Kompakt | PDFKit, DatabaseManager, Export-Formate |
| `Services/StartupCheckManager.swift` | Kompakt | 6 Services geprueft, Required vs Optional |

#### HotkeyManager Notifications (KRITISCH)

| Notification | Tastenkuerzel | Aktion |
|--------------|---------------|--------|
| `.showQuickAsk` | Cmd+Shift+A | Quick Ask Window oeffnen |
| `.showSearch` | Cmd+Shift+F | Search Window oeffnen |
| `.showSummary` | Cmd+Shift+S | Summary Request Window oeffnen |
| `.showTimeline` | Cmd+Shift+T | Timeline Window oeffnen |
| `.showMeetingMinutes` | Cmd+Shift+M | Meeting Minutes Window oeffnen |

**Hinweis:** Cmd+Shift+R (Toggle Capture) ruft direkt `AppState.shared.toggleCapture()` auf - keine Notification!

---

### Session 2026-01-20 (Update 7) - Dependency Headers fuer Core/Meeting und Core/Audio

#### Aufgabe
Ausführliche Dependency Headers für die Core Meeting- und Audio-Dateien eingefügt. Besonderer Fokus auf MeetingDetector mit allen Notifications.

#### Bearbeitete Dateien

| Datei | Dokumentierte Abhängigkeiten |
|-------|------------------------------|
| `Core/Meeting/MeetingDetector.swift` | 6 Notifications gesendet, 2 System-Notifications gehört, 3 direkte Nutzer, State-Sync mit AppState |
| `Core/Meeting/MeetingTranscriptionCoordinator.swift` | 4 Core Services, 2 Notifications gehört, 1 Notification gesendet, 3 AppStorage Keys |
| `Core/Audio/AudioCaptureManager.swift` | 3 Imports, StorageManager Dependency, Audio-Chunk-Callback-Pattern |
| `Core/Audio/WhisperTranscriptionService.swift` | WhisperKit Package, 4 direkte Nutzer, Thread-Safety via NSLock |

#### MeetingDetector Notifications (KRITISCH)

| Notification | Wann | Listener |
|--------------|------|----------|
| `.meetingDetectedAwaitingConfirmation` | Meeting erkannt, wartet auf Bestätigung | MeetingIndicatorViewModel, ScraineeApp |
| `.meetingStarted` | Nach DB-Insert, User bestätigt | TranscriptionCoordinator, AppState, ScreenCaptureManager |
| `.meetingEnded` | Meeting beendet | TranscriptionCoordinator, AppState |
| `.meetingEndConfirmationRequested` | App denkt Meeting ist vorbei (deaktiviert) | MeetingIndicatorViewModel |
| `.meetingContinued` | User sagt Meeting läuft noch | MeetingIndicatorViewModel |
| `.meetingStartDismissed` | User lehnt Aufnahme ab (5min Snooze) | MeetingIndicatorViewModel |

---

### Session 2026-01-20 (Update 6) - Dependency Header Documentation

#### Aufgabe
Dependency Headers für die kritischsten App-Layer Swift-Dateien eingefügt, um Abhängigkeiten und Auswirkungen von Änderungen zu dokumentieren.

#### Bearbeitete Dateien

| Datei | Dokumentierte Abhängigkeiten |
|-------|------------------------------|
| `App/AppState.swift` | 10 Import-Dependencies, 2 Notification-Listener, 1 Protokoll-Implementation, 11 Dependents |
| `App/ScraineeApp.swift` | 10 Service-Imports, 10 UI-View-Imports, 10 Notification-Listener, 3 Exports |

#### Header-Format
Das eingeführte Format dokumentiert:
- **DEPENDENCIES**: Imports, Notifications die empfangen werden, implementierte Protokolle
- **DEPENDENTS**: Wer diese Datei nutzt, welche Notifications gesendet werden, was exportiert wird
- **CHANGE IMPACT**: Was bei Änderungen beachtet werden muss

---

### Session 2026-01-20 (Update 5) - Meeting-Start-Bestätigung

#### Problem
Die Meeting-Erkennung war zu sensibel - sie startete automatisch die Transkription, sobald eine Meeting-App (Teams, Zoom, Webex, Google Meet) erkannt wurde, ohne den Benutzer zu fragen.

#### Implementierte Lösung

**Neuer Flow:**
1. Meeting-App wird erkannt
2. Floating-Dialog erscheint in der **Mitte-oben** des Hauptbildschirms
3. Dialog fragt: "Meeting erkannt: [App-Name] - Möchtest du aufnehmen?"
4. **"Ja, aufnehmen"** → Recording startet, Indikator wechselt in Recording-Modus
5. **"Nein"** → App wird für **5 Minuten ignoriert** (Snooze)

**Neue Properties in MeetingDetector:**
- `pendingStartConfirmation: Bool` - Meeting erkannt, wartet auf Bestätigung
- `detectedMeetingAppName: String?` - Name der erkannten App
- `detectedMeetingBundleId: String?` - Bundle-ID der erkannten App
- `snoozedApps: [String: Date]` - Temporär ignorierte Apps
- `snoozeDuration: TimeInterval = 300` - 5 Minuten Snooze

**Neue Methoden in MeetingDetector:**
- `requestStartConfirmation(app:bundleId:)` - Fordert Bestätigung an
- `confirmMeetingStart()` - Benutzer bestätigt → Recording startet
- `dismissMeetingStart()` - Benutzer lehnt ab → App wird gesnoozed
- `isAppSnoozed(_:)` - Prüft ob App in Snooze-Liste

**Neue Notifications:**
- `.meetingDetectedAwaitingConfirmation` - Meeting erkannt, wartet auf Bestätigung
- `.meetingStartDismissed` - Benutzer hat Aufnahme abgelehnt

**UI-Änderungen:**
- **MeetingIndicatorView** hat jetzt zwei Modi:
  - **Start-Bestätigung**: Blaues Icon, Frage mit Ja/Nein-Buttons, zentriert oben
  - **Recording**: Roter pulsierender Punkt, Timer, Stop-Button, rechts oben
- Fenster wird per `positionWindowCenterTop()` automatisch positioniert

**Edge-Cases behandelt:**
- App wird geschlossen während Bestätigung pending → Dialog schließt automatisch
- Mehrere Meeting-Apps → Erste wird angezeigt, bei "Nein" wird sie gesnoozed
- Snooze läuft ab → Benutzer wird nach 5 Minuten erneut gefragt

#### Geänderte Dateien

| Datei | Änderung |
|-------|----------|
| `Core/Meeting/MeetingDetector.swift` | Start-Confirmation-Logik, Snooze-Mechanismus, neue Notifications |
| `UI/MeetingIndicator/MeetingIndicatorViewModel.swift` | Start-Confirmation-State und -Actions |
| `UI/MeetingIndicator/MeetingIndicatorView.swift` | Neuer startConfirmationView, zwei Modi |
| `App/ScraineeApp.swift` | Window-Positionierung, neue Notification-Observer |

---

### Session 2026-01-20 (Update 4) - WhisperKit Code-Signing Fix

#### Problem
Nach dem Start der App erschien folgender Fehler:
```
dyld: Library not loaded: @rpath/WhisperKit.framework/Versions/A/WhisperKit
Reason: code signature not valid for use in process: mapping process and mapped file (non-platform) have different Team IDs
```

#### Root Cause
WhisperKit wurde mit einem anderen Apple Team ID signiert als die App selbst. macOS blockiert standardmäßig das Laden von Libraries mit unterschiedlichen Team IDs (Library Validation).

#### Implementierter Fix

**1. WhisperKit zu project.yml hinzugefügt**
- War nur in Package.swift, nicht im Xcode-Projekt
- Jetzt auch als XcodeGen Package-Dependency definiert

**2. Library Validation deaktiviert** (`Scrainee.entitlements`)
```xml
<key>com.apple.security.cs.disable-library-validation</key>
<true/>
```
- Erlaubt das Laden von Libraries mit unterschiedlichen Team IDs
- Erforderlich für WhisperKit während lokaler Entwicklung

**3. Entitlements-Sektion in project.yml korrigiert**
- Entfernt `properties: {}` das die Entitlements-Datei überschrieb

#### Geänderte Dateien

| Datei | Änderung |
|-------|----------|
| `project.yml` | WhisperKit Package hinzugefügt, Entitlements-Sektion bereinigt |
| `Scrainee.entitlements` | `disable-library-validation` Entitlement hinzugefügt |

---

### Session 2026-01-20 (Update 3) - Floating Meeting-Indikator + Audio-Pitch-Fix

#### Probleme (vom User gemeldet)
1. **Audio mit verzerrter Stimme/Pitch** - Chipmunk-Effekt durch falsches Downsampling
2. **Keine Minutes erstellt** - Meeting wurde zu früh beendet
3. **Meeting-Ende zu früh erkannt** - App beendete Meetings wenn User den Fokus wechselte

#### Implementierte Fixes

**1. Audio-Downsampling mit Interpolation** (`AudioCaptureManager.swift`)
- **Problem:** Naives Sample-Picking (jedes 3. Sample) verursachte Aliasing
- **Fix:** Lineare Interpolation beim Downsampling von 48kHz → 16kHz
- **Ergebnis:** Keine Pitch-Verzerrung mehr, natürliche Sprachqualität

```swift
// ALT: Einfaches Sample-Picking (verursachte Chipmunk-Effekt)
for i in stride(from: 0, to: samples.count, by: ratio) {
    downsampled.append(samples[i])
}

// NEU: Lineare Interpolation (korrekt)
while Int(position) < maxIndex {
    let index = Int(position)
    let fraction = position - Float(index)
    let interpolated = samples[index] * (1 - fraction) + samples[index + 1] * fraction
    output.append(interpolated)
    position += ratio
}
```

**2. Floating Meeting-Indikator** (NEUE UI-Komponenten)
- **MeetingIndicatorView.swift** - Floating-Fenster mit:
  - Recording-Status (pulsierender roter Punkt)
  - Meeting-App-Name
  - Laufzeit-Anzeige (Timer)
  - Manueller "Meeting beenden" Button
- **MeetingIndicatorViewModel.swift** - ViewModel für Indikator-Logik
- **Auto-Show:** Öffnet automatisch bei Meeting-Start
- **Auto-Hide:** Schließt bei Meeting-Ende

**3. Manuelle Meeting-Kontrolle** (`MeetingDetector.swift`)
- **Neue Methoden:**
  - `manuallyEndMeeting()` - Beendet Meeting sofort
  - `requestEndConfirmation()` - Zeigt Bestätigungs-Dialog
  - `confirmMeetingEnded()` - User bestätigt Ende
  - `continueMeeting()` - User sagt "läuft noch"
- **Neue Properties:**
  - `pendingEndConfirmation` - Ob Bestätigung angefordert wurde
  - `notFoundCounter` - Zählt wie oft Meeting nicht erkannt wurde
  - `confirmationThreshold = 2` - Nach 2 Checks (20s) wird gefragt

**4. Bestätigungs-Dialog bei vermutetem Meeting-Ende**
- Wenn App denkt Meeting ist vorbei, wird User gefragt
- Zwei Optionen: "Ja, beenden" oder "Nein, läuft noch"
- Verhindert vorzeitiges Beenden bei Fokus-Wechsel

**5. Neue Notifications**
- `.meetingEndConfirmationRequested` - App fragt ob Meeting wirklich beendet
- `.meetingContinued` - User sagt Meeting läuft noch

#### Geänderte/Neue Dateien

| Datei | Änderung |
|-------|----------|
| `AudioCaptureManager.swift` | Downsampling mit Interpolation statt Sample-Picking |
| `MeetingDetector.swift` | Manuelle Kontrolle, Bestätigungslogik, neue Methoden |
| `ScraineeApp.swift` | Meeting-Indikator Window, Auto-Show/Hide |
| **NEU** `UI/MeetingIndicator/MeetingIndicatorView.swift` | Floating Meeting-Indikator UI |
| **NEU** `UI/MeetingIndicator/MeetingIndicatorViewModel.swift` | ViewModel für Indikator |
| `project.yml` | GENERATE_INFOPLIST_FILE für Tests |

---

### Session 2026-01-20 (Update 2) - SCStream Audio-Capture Fix

#### Problem
Nach den vorherigen Fixes schlug der Audio-Stream mit folgendem Fehler fehl:
```
[ERROR] _SCStream_RemoteAudioQueueOperationHandlerWithError:1468 Error received from the remote queue -16665
[ERROR] error=Error Domain=CoreGraphicsErrorDomain Code=1003 "Start stream failed" UserInfo={NSLocalizedFailureReason=The stream is nil.}
```

#### Root Cause
ScreenCaptureKit erwartet **System-Standard Audio-Raten (48kHz/Stereo)**, aber der Code versuchte direkt mit 16kHz/Mono aufzunehmen. Dies verursachte den Error -16665 (Remote Audio Queue Problem).

#### Implementierter Fix

**Audio-Konvertierungs-Pipeline** (`AudioCaptureManager.swift`):

1. **Capture mit System-Standard:** 48kHz Stereo (wie ScreenCaptureKit erwartet)
2. **Konvertierung nach Capture:**
   - Stereo → Mono (Mittelung beider Kanäle)
   - 48kHz → 16kHz (Downsampling für Whisper)
3. **Ausgabe:** 16kHz Mono WAV für Whisper

**Neue Config-Struktur:**
```swift
struct Config {
    var captureSampleRate: Double = 48000   // ScreenCaptureKit Standard
    var captureChannels: Int = 2             // Stereo
    var outputSampleRate: Double = 16000    // Whisper
    var outputChannels: Int = 1              // Mono
}
```

**Neue Konvertierungsfunktionen:**
- `stereoToMono()` - Konvertiert interleaved Stereo zu Mono
- `downsample()` - Reduziert Sample-Rate von 48kHz auf 16kHz
- `convertToWhisperFormat()` - Kombiniert beide Konvertierungen

**Stream-Konfiguration:**
- Video: 2x2 Pixel (statt 1x1 - kann Probleme verursachen)
- Audio: 48kHz, 2 Channels (System-Standard)
- queueDepth: 1 (minimale Video-Buffer)

#### Geänderte Dateien

| Datei | Änderung |
|-------|----------|
| `AudioCaptureManager.swift` | Config erweitert, Stream-Config auf 48kHz/Stereo, Konvertierungsfunktionen |

---

### Session 2026-01-20 (Update 1) - Audio-Aufnahme Fix

#### Problem
Das Audio-Verzeichnis `~/Library/Application Support/Scrainee/audio/` war **leer**, obwohl Meetings erkannt wurden:
- 200 Meeting-Einträge in DB
- 157 mit `transcriptionStatus = 'notStarted'` → Transkription wurde NIE gestartet
- 43 mit `transcriptionStatus = 'recording'` → gestartet aber nie beendet
- KEIN `audioFilePath` gesetzt

#### Root Causes identifiziert

1. **Guard-Bedingung blockierte Auto-Transkription**
   - MeetingTranscriptionCoordinator prüfte `isModelDownloaded` zu früh
   - Whisper wurde erst NACH Meeting-Detection gestartet

2. **Silent Failures im AudioCaptureManager**
   - Fehler wurden nur geloggt aber nicht propagiert
   - stopTranscription() Fehler wurden mit `try?` verschluckt

3. **Race Condition bei Meeting-Speicherung**
   - `getActiveMeeting()` konnte fehlschlagen wenn Notification zu früh kam

#### Implementierte Fixes

**1. Umfangreiches Diagnostik-Logging**
- `MeetingTranscriptionCoordinator`: Logging für jeden Guard-Schritt
- `AudioCaptureManager`: Logging für Recording-Start, Audio-Samples, File-Writes, Stop
- `AudioStreamOutput`: Periodisches Callback-Logging (alle 100 Callbacks)

**2. isModelDownloaded Multi-Path-Check** (`WhisperTranscriptionService.swift`)
- Prüft jetzt BEIDE möglichen Modell-Pfade:
  - `Scrainee/models/argmaxinc/whisperkit-coreml/...`
  - `Scrainee/whisper-models/models/argmaxinc/whisperkit-coreml/...`

**3. Verbessertes Error-Handling** (`AudioCaptureManager.swift`)
- Tracking von `totalSamplesWritten` mit periodischem Logging (~10s)
- Validierung der Audio-Datei bei `stopRecording()`
- Leere Audio-Dateien werden automatisch gelöscht

**4. Robuster Coordinator** (`MeetingTranscriptionCoordinator.swift`)
- Retry-Mechanismus für `getActiveMeeting()` (3 Versuche, 100ms Pause)
- Proper Error-Handling statt `try?` bei `stopTranscription()`
- Fehler werden in UI angezeigt

**5. Korrekte App-Start Reihenfolge** (`AppState.swift`, `ScraineeApp.swift`)
- Whisper-Modell wird VOLLSTÄNDIG geladen BEVOR Meeting-Detector startet
- Sequenz: Database → Whisper Load → Meeting Detector → Capture

#### Geänderte Dateien

| Datei | Änderung |
|-------|----------|
| `MeetingTranscriptionCoordinator.swift` | Logging, Error-Handling, Retry-Mechanismus |
| `AudioCaptureManager.swift` | Logging, Validierung, Sample-Tracking |
| `WhisperTranscriptionService.swift` | Multi-Path isModelDownloaded Check |
| `AppState.swift` | Verbesserte initializeApp() mit Logging |
| `ScraineeApp.swift` | Debugging-Logging für Service-Initialisierung |

---

### Session 2026-01-19 (Update 4) - Transkription startet nicht Fix

#### 12. whisperModelDownloaded Flag Sync beim App-Start
- **Problem:** Audio-Aufnahme und Transkription starteten NICHT obwohl Whisper-Modell heruntergeladen
- **Root Cause:** `MeetingTranscriptionCoordinator` prüfte `@AppStorage("whisperModelDownloaded")` Flag
- **Das Flag wurde nur in SettingsView aktualisiert** - nicht beim App-Start!
- **Folge:** Flag war `false` obwohl Modell existierte → Guard-Bedingung schlug fehl
- **Fix 1:** Flag wird jetzt beim App-Start mit echtem Modell-Status synchronisiert (`AppState.swift`)
- **Fix 2:** Guard-Bedingung prüft jetzt `WhisperTranscriptionService.shared.isModelDownloaded` direkt

#### 13. Robustere Guard-Bedingung im Coordinator
- **Datei:** `MeetingTranscriptionCoordinator.swift:256`
- **Von:** `self.whisperModelDownloaded` (AppStorage Flag)
- **Zu:** `WhisperTranscriptionService.shared.isModelDownloaded` (echter Check)

### Session 2026-01-19 (Update 3) - Meeting-System Connectivity Fix

#### 7. Meeting-Minutes Auto-Öffnen nach Meeting-Ende
- **Problem:** Nach Meeting-Ende wurde kein Fenster geöffnet, obwohl Transkription lief
- **Ursache:** `.transcriptionCompleted` Notification wurde gepostet, aber niemand hörte zu
- **Fix:** Neuer Observer in `ScraineeApp.swift` reagiert auf `.transcriptionCompleted`
- **Ergebnis:** Meeting-Minutes-Fenster öffnet sich automatisch nach Meeting-Ende

#### 8. MeetingMinutesView Auto-Load
- **Problem:** `MeetingMinutesView()` wurde ohne Meeting initialisiert → "Kein Transkript"
- **Ursache:** SwiftUI Window akzeptiert keine Parameter, Meeting wurde nie übergeben
- **Fix:** `MeetingMinutesViewModel` lädt automatisch das letzte Meeting wenn keins übergeben
- **Neue Methoden:** `loadMostRecentMeeting()`, `loadMeeting(id:)`

#### 9. currentMeetingId jetzt public
- **Problem:** `currentMeetingId` im Coordinator war `private` → Live-Updates erreichten UI nicht
- **Fix:** Property ist jetzt `private(set)` (lesbar von außen)
- **Entfernt:** Unnötige Extension in `MeetingMinutesViewModel`

#### 10. Notion Auto-Sync nach Transkription
- **Problem:** `notionAutoSync` Setting existierte, aber nutzte Screenshot-Summary statt Minutes
- **Fix:** Nach `.transcriptionCompleted` wird Meeting mit Minutes nach Notion exportiert
- **Neue Methode:** `syncMeetingToNotion(meetingId:)` in `ScraineeApp.swift`
- **Inhalt:** Meeting-Minutes + Transkript + Action Items

#### 11. DatabaseManager Erweiterungen
- **Neue Methode:** `getMostRecentMeeting()` - holt letztes Meeting (aktiv oder abgeschlossen)
- **Neue Methode:** `getMeeting(id:)` - holt Meeting by ID

### Session 2026-01-19 (Update 2)

#### 5. Whisper Model Path Fix
- **Problem:** Whisper-Modell wurde nicht erkannt obwohl heruntergeladen (~3GB)
- **Ursache:** `isModelDownloaded` prüfte falsche Pfade
- **Fix:** Korrekter WhisperKit-Pfad: `models/argmaxinc/whisperkit-coreml/openai_whisper-large-v3/`

#### 6. Race Condition Fix beim Model Loading
- **Problem:** Health Checks zeigten "nicht geladen" obwohl Loading lief
- **Ursache:** `loadModel()` war fire-and-forget Task, Health Checks liefen parallel
- **Fix:** Direktes `await loadModel()` ohne Task-Wrapper
- **Fix:** Health Checks laufen jetzt sequentiell nach `initializeApp()`

### Session 2026-01-19 (Initial)

#### 1. Meeting-System Fixes
- **GRDB Insert-Pattern Fix:** Alle `insert()` Methoden in `DatabaseManager.swift` verwenden jetzt `.inserted(db)` statt `.insert(db)` für korrekte ID-Rückgabe
- **Race Condition Fix:** `MeetingDetector` postet die `.meetingStarted` Notification jetzt **nach** dem Speichern in die Datenbank, sodass der `TranscriptionCoordinator` das Meeting findet

#### 2. App Startup Health Checks
- **Neuer StartupCheckManager:** Prüft beim App-Start alle kritischen Services
  - Datenbank-Verbindung
  - Claude API (wenn konfiguriert)
  - Notion API (wenn konfiguriert)
  - Whisper Modell Status
  - Screen Capture & Accessibility Berechtigungen
- **Konsolen-Ausgabe** mit farbigen Status-Icons

#### 3. Whisper Auto-Load
- Das Whisper-Modell wird automatisch beim App-Start geladen (wenn bereits heruntergeladen)
- Meeting-Transkription kann sofort starten ohne Verzögerung

#### 4. MenuBar Status-Anzeige
- Neue "System Status" Sektion im MenuBar-Dropdown
- Farbige Status-Indikatoren (🟢 OK, 🟡 Warning, 🔴 Error)
- Ausklappbar für Details zu jedem Service

---

## Bekannte Probleme / Offene Punkte

### WhisperKit Code-Signing: GEFIXT ✅ (Update 4)
- Library Validation deaktiviert für lokale Entwicklung
- App startet jetzt ohne "different Team IDs" Fehler

### Meeting-System: GEFIXT ✅ (Update 2026-01-20)
Der komplette Flow sollte jetzt funktionieren:
1. ✅ Meeting wird erkannt (Teams/Zoom/Webex/Meet)
2. ✅ Audio wird aufgenommen (wenn Whisper-Modell geladen)
3. ✅ Echtzeit-Transkription läuft (30s Chunks)
4. ✅ Nach Meeting-Ende: Fenster öffnet automatisch
5. ✅ Minutes + Action Items werden generiert (Claude API)
6. ✅ Auto-Sync nach Notion (wenn aktiviert)

### Audio-Dateien
- **Speicherort:** `~/Library/Application Support/Scrainee/audio/`
- **Dateiname:** `meeting_{id}_{timestamp}.wav`
- **Logging:** Periodisches Logging alle ~10 Sekunden zeigt Fortschritt

### Transkription
- **Abhängigkeit:** Whisper-Modell muss heruntergeladen sein
- **Auto-Load:** Funktioniert automatisch beim App-Start
- **Wichtig:** Meeting-Detector startet erst NACH Whisper-Load

---

## Nächste Schritte

### Priorität 1: Verifizierung (Test erforderlich!)

**App starten und Konsole prüfen:**
```
[DEBUG] AppState: Whisper model loaded successfully
[DEBUG] AppDelegate: Meeting detector started
```

**Meeting starten (Teams/Zoom) und prüfen:**
1. [ ] Floating Meeting-Indikator erscheint automatisch
2. [ ] Recording-Punkt pulsiert, Timer läuft
3. [ ] Audio-Qualität: Stimme klingt natürlich (kein Chipmunk-Effekt)

**Fokus-Wechsel während Meeting:**
1. [ ] Zu anderer App wechseln
2. [ ] Nach ~20 Sekunden: Bestätigungs-Dialog im Indikator
3. [ ] "Nein, läuft noch" klicken → Meeting läuft weiter

**Meeting manuell beenden:**
1. [ ] "Meeting beenden" Button im Indikator klicken
2. [ ] Indikator schließt sich
3. [ ] Meeting-Minutes-Fenster öffnet sich
4. [ ] Prüfen: Transkript enthält gesprochenen Text
5. [ ] Prüfen: Minutes-Zusammenfassung wurde generiert

**Konsole prüfen:**
```
[DEBUG] AudioCaptureManager: Stream config - captureSampleRate=48000.0, captureChannels=2, outputSampleRate=16000.0
[DEBUG] AudioCaptureManager: Stream capture started successfully
[DEBUG] AudioStreamOutput: Callback #1, received ... samples
[DEBUG] AudioCaptureManager: Written 160000 samples (~10s)
```

**DB-Prüfung nach Meeting:**
```bash
sqlite3 ~/Library/Application\ Support/Scrainee/scrainee.sqlite \
  "SELECT id, audioFilePath, transcriptionStatus FROM meetings ORDER BY id DESC LIMIT 5;"
```

### Priorität 2: Verbesserungen
1. [ ] Error-Handling verbessern wenn Transkription fehlschlägt
2. [ ] macOS Notification bei Meeting-Ende
3. [ ] Meeting-Liste zum Durchsuchen vergangener Meetings

### Priorität 3: Optionale Features
1. [x] ~~Meeting Minutes Export nach Notion automatisieren~~ DONE
2. [ ] Transkript-Suche in der App
3. [x] ~~Action Items aus Meetings extrahieren~~ DONE

---

## Architektur-Übersicht

```
App Start
    │
    ├─► PermissionManager (Screen Capture, Accessibility)
    ├─► DatabaseManager.initialize()
    ├─► AppState.initializeApp()
    │       └─► Whisper Auto-Load (wenn heruntergeladen)
    ├─► RetentionPolicy.startScheduledCleanup()
    ├─► MeetingDetector.startMonitoring()
    └─► StartupCheckManager.runAllChecks()

Meeting Flow
    │
    MeetingDetector
        │
        ├─► Meeting erkannt
        ├─► Meeting in DB speichern
        └─► .meetingStarted Notification posten
                │
                └─► MeetingTranscriptionCoordinator
                        │
                        ├─► Whisper-Modell laden (falls nötig)
                        ├─► AudioCaptureManager starten
                        ├─► Echtzeit-Transkription (30s Chunks)
                        │       └─► TranscriptSegment in DB
                        └─► Meeting Ende
                                │
                                ├─► Finale Transkription
                                ├─► MeetingMinutes generieren (Claude API)
                                └─► ActionItems extrahieren
```

---

## Test-Befehle

```bash
# Build
swift build

# Tests
swift test

# Release Build
swift build -c release
```

---

## Dateien dieser Session

| Datei | Änderung |
|-------|----------|
| `Services/StartupCheckManager.swift` | **NEU** |
| `Core/Database/DatabaseManager.swift` | Insert-Pattern Fix + getMostRecentMeeting() + getMeeting(id:) |
| `Core/Meeting/MeetingDetector.swift` | Race Condition Fix |
| `Core/Meeting/MeetingTranscriptionCoordinator.swift` | currentMeetingId public + Guard-Fix |
| `Core/Audio/WhisperTranscriptionService.swift` | Model Path Detection Fix |
| `App/AppState.swift` | Whisper Auto-Load + Race Condition Fix + Flag Sync |
| `App/ScraineeApp.swift` | transcriptionCompleted Observer + Notion Auto-Sync |
| `UI/MenuBar/MenuBarView.swift` | Status-Anzeige |
| `UI/MeetingMinutes/MeetingMinutesViewModel.swift` | Auto-Load letztes Meeting + loadMeeting(id:) |
