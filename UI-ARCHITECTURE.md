# Scrainee UI-Architektur Dokumentation

Diese Dokumentation beschreibt alle UI-Elemente, deren Verknüpfung zu Backend-Funktionen und den Datenfluss durch die Anwendung.

---

## Inhaltsverzeichnis

1. [Architektur-Übersicht](#architektur-übersicht)
2. [Fenster-Registry](#fenster-registry)
3. [Hotkey-Registry](#hotkey-registry)
4. [MenuBar (Haupteinstiegspunkt)](#menubar-haupteinstiegspunkt)
5. [Einstellungen (Settings)](#einstellungen-settings)
6. [Suche (Search)](#suche-search)
7. [Quick Ask (AI-Assistent)](#quick-ask-ai-assistent)
8. [Screenshot-Galerie](#screenshot-galerie)
9. [Timeline (Rewind-Style)](#timeline-rewind-style)
10. [Zusammenfassungen (Summary)](#zusammenfassungen-summary)
11. [Meeting Minutes](#meeting-minutes)
12. [Meeting Indicator](#meeting-indicator)
13. [Datenfluss-Diagramme](#datenfluss-diagramme)
14. [State Management](#state-management)

---

## Architektur-Übersicht

```
┌─────────────────────────────────────────────────────────────────┐
│                        UI LAYER (SwiftUI)                       │
│  MenuBarView │ SettingsView │ SearchView │ TimelineView │ ...   │
└─────────────────────────────────────────────────────────────────┘
                              │ @Published / @Binding
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                     VIEWMODEL LAYER                              │
│     AppState │ SearchViewModel │ TimelineViewModel │ ...        │
│                  (@MainActor ObservableObject)                   │
└─────────────────────────────────────────────────────────────────┘
                              │ async/await
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                      SERVICE LAYER                               │
│  ScreenCaptureManager │ MeetingDetector │ HotkeyManager │ ...   │
└─────────────────────────────────────────────────────────────────┘
                              │ actor isolation
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                       DATA LAYER                                 │
│           DatabaseManager (actor) │ StorageManager               │
│                    GRDB / SQLite │ FileSystem                    │
└─────────────────────────────────────────────────────────────────┘
```

**Schlüssel-Dateien:**
- `Scrainee/App/ScraineeApp.swift` - App Entry Point, Window-Definitionen
- `Scrainee/App/AppState.swift` - Zentraler State (@MainActor Singleton)
- `Scrainee/Services/HotkeyManager.swift` - Globale Tastenkürzel

---

## Fenster-Registry

Alle Fenster werden in `ScraineeApp.swift` definiert:

| Window ID | View | Datei | Min. Größe | Öffnungs-Trigger |
|-----------|------|-------|------------|------------------|
| MenuBarExtra | `MenuBarView` | `UI/MenuBar/MenuBarView.swift` | - | Immer sichtbar |
| Settings | `SettingsView` | `UI/Settings/SettingsView.swift` | - | Cmd+, / MenuBar |
| `search` | `SearchView` | `UI/Search/SearchView.swift` | 600×500 | Cmd+Shift+F |
| `summary` | `SummaryRequestView` | `UI/Summary/SummaryRequestView.swift` | 700×600 | Cmd+Shift+S |
| `summarylist` | `SummaryListView` | `UI/Summary/SummaryListView.swift` | 800×600 | MenuBar |
| `quickask` | `QuickAskView` | `UI/QuickAsk/QuickAskView.swift` | - | Cmd+Shift+A |
| `gallery` | `ScreenshotGalleryView` | `UI/Gallery/ScreenshotGalleryView.swift` | 1000×700 | Cmd+Shift+G |
| `timeline` | `TimelineView` | `UI/Timeline/TimelineView.swift` | 1100×750 | Cmd+Shift+T |
| `meetingminutes` | `MeetingMinutesView` | `UI/MeetingMinutes/MeetingMinutesView.swift` | 1000×700 | Cmd+Shift+M |
| `meetingindicator` | `MeetingIndicatorView` | `UI/MeetingIndicator/MeetingIndicatorView.swift` | - | Auto (Meeting) |

### Fenster-Öffnung

```swift
// In ScraineeApp.swift
@Environment(\.openWindow) private var openWindow

// Beispiel: Fenster öffnen
openWindow(id: "search")

// AppDelegate-Integration für Hotkeys
static var openWindowAction: ((String) -> Void)?
```

---

## Hotkey-Registry

**Datei:** `Scrainee/Services/HotkeyManager.swift`

| Shortcut | Aktion | Notification | Ziel |
|----------|--------|--------------|------|
| `Cmd+Shift+A` | Quick Ask öffnen | `.showQuickAsk` | QuickAskView |
| `Cmd+Shift+R` | Aufnahme an/aus | - | `AppState.toggleCapture()` |
| `Cmd+Shift+F` | Suche öffnen | `.showSearch` | SearchView |
| `Cmd+Shift+S` | Zusammenfassung | `.showSummary` | SummaryRequestView |
| `Cmd+Shift+G` | Galerie öffnen | - | ScreenshotGalleryView |
| `Cmd+Shift+T` | Timeline öffnen | `.showTimeline` | TimelineView |
| `Cmd+Shift+M` | Meeting Minutes | `.showMeetingMinutes` | MeetingMinutesView |

**Benötigte Berechtigung:** Accessibility (Bedienungshilfen)

---

## MenuBar (Haupteinstiegspunkt)

**Datei:** `Scrainee/UI/MenuBar/MenuBarView.swift`

### Header-Sektion

| Element | Typ | Aktion | Backend-Aufruf |
|---------|-----|--------|----------------|
| Play/Pause Button | `Button` | Aufnahme starten/stoppen | `appState.toggleCapture()` |
| Status-Kreis | `Circle` | Zeigt Status (Rot=aktiv) | `appState.isCapturing` |

### Permission-Sektion (wenn Berechtigung fehlt)

| Element | Typ | Aktion | Backend-Aufruf |
|---------|-----|--------|----------------|
| "Systemeinstellungen öffnen" | `Button` | Öffnet Einstellungen | `PermissionManager.openScreenCapturePreferences()` |
| "Berechtigung prüfen" | `Button` | Prüft Status | `appState.checkAndUpdatePermissions()` |

### System Status

| Element | Typ | Anzeige | Backend-Quelle |
|---------|-----|---------|----------------|
| DisclosureGroup | `DisclosureGroup` | Erweiterbarer Status | `appState.startupChecks` |
| Status-Kreise | `Circle` | Grün/Orange/Rot | `check.status` |

### Statistiken

| Element | Typ | Anzeige | Backend-Quelle |
|---------|-----|---------|----------------|
| Screenshots (Session) | `Text` | Anzahl | `appState.screenshotCount` |
| Screenshots (Gesamt) | `Text` | Anzahl | `appState.totalScreenshots` |
| Speicherverbrauch | `Text` | Formatiert | `appState.storageUsed` |
| Letzter Screenshot | `Text` | Relative Zeit | `appState.lastCaptureTime` |
| Meeting-Status | `HStack` | App-Name | `appState.currentMeeting?.appName` |

### Aktions-Menü

| Gruppe | Button | Aktion | Window ID |
|--------|--------|--------|-----------|
| **KI-Assistent** | Quick Ask | Öffnet Fenster | `quickask` |
| | Zusammenfassung erstellen | Öffnet Fenster | `summary` |
| | Alle Zusammenfassungen | Öffnet Fenster | `summarylist` |
| **Screenshots** | Suchen | Öffnet Fenster | `search` |
| | Galerie | Öffnet Fenster | `gallery` |
| | Timeline | Öffnet Fenster | `timeline` |
| **Meetings** | Meeting Minutes | Öffnet Fenster | `meetingminutes` |

### Footer

| Element | Typ | Aktion |
|---------|-----|--------|
| Einstellungen | `SettingsLink` | Öffnet Settings |
| Beenden | `Button` | `NSApplication.shared.terminate(nil)` |

---

## Einstellungen (Settings)

**Datei:** `Scrainee/UI/Settings/SettingsView.swift`

### Tab 1: Allgemein (`GeneralSettingsView`)

| Element | Typ | UserDefaults Key | Standard |
|---------|-----|------------------|----------|
| Beim Anmelden starten | `Toggle` | `launchAtLogin` | `false` |
| Auto-Start Aufnahme | `Toggle` | `autoStartCapture` | `true` |
| Bildschirmaufnahme-Status | `PermissionRow` | - | via `PermissionManager` |
| Bedienungshilfen-Status | `PermissionRow` | - | via `PermissionManager` |

### Tab 2: Aufnahme (`CaptureSettingsView`)

| Element | Typ | UserDefaults Key | Optionen |
|---------|-----|------------------|----------|
| Aufnahme-Intervall | `Picker` | `captureInterval` | 1s, 2s, 3s, 5s, 10s |
| Bildqualität | `Slider` | `heicQuality` | 0.0 - 1.0 (60% Standard) |
| OCR aktivieren | `Toggle` | `ocrEnabled` | `true` |

### Tab 3: Transkription (`TranscriptionSettingsView`)

| Element | Typ | Aktion | Backend |
|---------|-----|--------|---------|
| Model Status | `HStack` | Zeigt Download-Status | `WhisperTranscriptionService.shared` |
| Herunterladen | `Button` | Model laden | `downloadModel()` |
| Laden | `Button` | In Memory laden | `loadModel()` |
| Progress | `ProgressView` | Download-Fortschritt | `downloadProgress` |
| Auto-Transkription | `Toggle` | Bei Meetings starten | `autoTranscribe` |
| Live Minutes | `Toggle` | Echtzeit-Notizen | `liveMinutesEnabled` |

### Tab 4: KI (`AISettingsView`)

| Element | Typ | Aktion | Backend |
|---------|-----|--------|---------|
| API Key Input | `SecureField` | Key eingeben | Lokaler State |
| Sichtbarkeit Toggle | `Button` (Eye) | Field-Typ wechseln | `isAPIKeyVisible` |
| Speichern | `Button` | In Keychain speichern | `KeychainService.setAPIKey()` |
| Testen | `Button` | API-Verbindung prüfen | `ClaudeAPIClient.testConnection()` |
| Löschen | `Button` | Aus Keychain entfernen | `KeychainService.deleteAPIKey()` |

**API Key Status:**
- `unknown` - Nicht konfiguriert (?)
- `invalidFormat` - Falsches Format (!)
- `formatValid` - Format OK (✓)
- `testing` - Wird getestet (↻)
- `valid` - Gültig (✓✓)
- `invalid` - Ungültig (✗)

### Tab 5: Integrationen (`IntegrationSettingsView`)

| Element | Typ | Aktion | Backend |
|---------|-----|--------|---------|
| Meeting-Erkennung | `Toggle` | Auto-Detect aktivieren | `meetingDetectionEnabled` |
| Notion API Key | `SecureField` | Key eingeben | Keychain |
| Notion Database ID | `TextField` | DB-ID eingeben | Keychain |
| Speichern | `Button` | Credentials speichern | `saveNotionSettings()` |
| Testen | `Button` | Verbindung prüfen | `NotionClient.testConnection()` |

### Tab 6: Speicher (`StorageSettingsView`)

| Element | Typ | Aktion | Backend |
|---------|-----|--------|---------|
| Speicherverbrauch | `Text` | Zeigt Größe | `StorageManager.getStorageSize()` |
| Screenshot-Anzahl | `Text` | Zeigt Anzahl | `DatabaseManager.getScreenshotCount()` |
| Im Finder anzeigen | `Button` | Ordner öffnen | `NSWorkspace.activateFileViewerSelecting()` |
| Aufbewahrungsdauer | `Picker` | Wählen | 7/14/30/60/90/∞ Tage |
| Jetzt aufräumen | `Button` | Bereinigung starten | `RetentionPolicy.performCleanup()` |
| Alles löschen | `Button` | Bestätigungsdialog | `StorageManager.deleteAllScreenshots()` |

---

## Suche (Search)

**Dateien:**
- View: `Scrainee/UI/Search/SearchView.swift`
- ViewModel: `Scrainee/UI/Search/SearchViewModel.swift`

### UI-Elemente

| Element | Typ | Binding | Aktion |
|---------|-----|---------|--------|
| Suchfeld | `TextField` | `searchText` | Debounced Search |
| Clear Button | `Button` | - | `searchText = ""` |
| Loading Spinner | `ProgressView` | `isLoading` | Während Suche |
| Ergebnis-Liste | `List` | `results` | Zeigt SearchResults |
| Ergebnis-Row | `Button` | - | Öffnet Screenshot |

### Datenfluss

```
TextField.onChange(searchText)
    ↓ 300ms Debounce
SearchViewModel.search(query:)
    ↓ async
DatabaseManager.searchOCR(query:, limit: 100)
    ↓ returns [SearchResult]
@Published var results
    ↓ SwiftUI binding
List updates
```

### SearchResult Row

| Element | Anzeige | Quelle |
|---------|---------|--------|
| Thumbnail | `AsyncThumbnailView` | `result.imagePath` |
| App Name | `Text` | `result.appName` |
| Fenster-Titel | `Text` | `result.windowTitle` |
| Zeitstempel | `Text` | `result.timestamp` (relativ) |
| Gefundener Text | `Text` | `result.matchedText` (highlighted) |

---

## Quick Ask (AI-Assistent)

**Dateien:**
- View: `Scrainee/UI/QuickAsk/QuickAskView.swift`
- ViewModel: `Scrainee/UI/QuickAsk/QuickAskViewModel.swift`

### UI-Elemente

| Element | Typ | Binding | Aktion |
|---------|-----|---------|--------|
| Header mit Sparkles | `Image` | - | AI-Badge |
| Context Indicator | `HStack` | `currentAppName` | Zeigt aktive App |
| Close Button | `Button` | - | `dismiss()` |
| Frage-Feld | `TextField` | `question` | Eingabe |
| Submit Button | `Button` | - | `askQuestion()` |
| Loading State | `ProgressView` | `isLoading` | "Analysiere Kontext..." |
| Antwort | `ScrollView` | `response` | Claude-Antwort |
| Copy Button | `Button` | - | In Clipboard kopieren |
| Neue Frage | `Button` | - | `clearResponse()` |
| Vorschläge | `[Button]` | `suggestions` | Quick-Actions |

### Vorschläge (dynamisch)

| Kontext | Vorschläge |
|---------|------------|
| Standard | "Was war das Hauptthema der letzten Stunde?" |
| Meeting aktiv | "Was wurde im Meeting besprochen?" |
| Nach Meeting | "Welche Aufgaben sind offen?" |
| Allgemein | "Was habe ich heute gemacht?" |

### Datenfluss

```
User tippt Frage → Submit
    ↓
QuickAskViewModel.askQuestion()
    ↓
DatabaseManager.getRecentScreenshots(limit: 20)
    ↓ OCR-Texte sammeln
ClaudeAPIClient.askQuestion(question:, context:)
    ↓ API Call zu Anthropic
@Published var response
    ↓
View zeigt Antwort
```

---

## Screenshot-Galerie

**Dateien:**
- View: `Scrainee/UI/Gallery/ScreenshotGalleryView.swift`
- ViewModel: `Scrainee/UI/Gallery/GalleryViewModel.swift`

### Toolbar

| Element | Typ | Binding | Aktion |
|---------|-----|---------|--------|
| Suchfeld | `TextField` | `searchText` | Filtern |
| Clear | `Button` | - | Reset Search |
| Filter Button | `Button` | - | Öffnet Popover |
| Refresh | `Button` | - | `refresh()` |
| Count | `Text` | `screenshots.count` | Anzahl |

### Filter Popover

| Element | Typ | Binding | Optionen |
|---------|-----|---------|----------|
| App Filter | `Picker` | `filterApp` | Alle Apps |
| Datum von | `DatePicker` | `filterDateFrom` | - |
| Datum bis | `DatePicker` | `filterDateTo` | - |
| Reset | `Button` | - | Alle Filter löschen |
| Apply | `Button` | - | Filter anwenden |

### Screenshot Grid

| Element | Typ | Aktion |
|---------|-----|--------|
| Thumbnail | `ScreenshotThumbnailView` | Klick: Auswählen |
| Selection Border | `RoundedRectangle` | Blau wenn selected |
| Hover: Quick Look | `Button` (Eye) | `openWithQuickLook()` |
| Hover: Finder | `Button` (Folder) | `showInFinder()` |
| Context Menu | `Menu` | Delete, QuickLook, Finder |

### Detail Panel (rechts)

| Element | Typ | Quelle |
|---------|-----|--------|
| Vollbild | `Image` | `selectedScreenshot.imagePath` |
| App | `LabeledContent` | `screenshot.appName` |
| Fenster | `LabeledContent` | `screenshot.windowTitle` |
| Zeit | `LabeledContent` | Formatiert |
| Auflösung | `LabeledContent` | `width × height` |
| Größe | `LabeledContent` | ByteCountFormatter |
| Hash | `LabeledContent` | Erste 16 Zeichen |
| OCR Text | `GroupBox` | `screenshot.ocrText` |

### Aktions-Buttons (Detail)

| Button | Aktion | Backend |
|--------|--------|---------|
| Im Finder | Ordner öffnen | `NSWorkspace.activateFileViewerSelecting()` |
| Quick Look | Vorschau | `NSWorkspace.open()` |
| Löschen | Entfernen | `DatabaseManager.delete()` + `StorageManager.delete()` |

---

## Timeline (Rewind-Style)

**Dateien:**
- View: `Scrainee/UI/Timeline/TimelineView.swift`
- ViewModel: `Scrainee/UI/Timeline/TimelineViewModel.swift`
- Slider: `Scrainee/UI/Timeline/TimelineSliderView.swift`
- Thumbnails: `Scrainee/UI/Timeline/TimelineThumbnailStrip.swift`

### Header

| Element | Typ | Aktion |
|---------|-----|--------|
| Previous Day | `Button` (chevron.left) | `goToPreviousDay()` |
| Current Date | `Button` | Öffnet DatePicker |
| Next Day | `Button` (chevron.right) | `goToNextDay()` |
| Today | `Button` | `goToToday()` |
| App Icon | `Image` | Placeholder |
| App Name | `Text` | `currentAppName` |
| Fenster-Titel | `Text` | `currentWindowTitle` |
| Zeit | `Text` (monospaced) | `currentTimeText` |
| Info Button | `Button` | Zeigt Shortcuts |

### Hauptbereich

| Element | Typ | Binding |
|---------|-----|---------|
| Screenshot Preview | `ScreenshotPreviewView` | `currentScreenshot` |
| Thumbnail Strip | `TimelineThumbnailStrip` | `screenshots`, `currentIndex` |

### Timeline Slider

| Element | Typ | Funktion |
|---------|-----|----------|
| Progress Track | `Shape` | Zeigt Position |
| Activity Segments | `RoundedRectangle` | Farbkodiert nach App |
| Slider Thumb | `Circle` | Draggable |
| Time Labels | `HStack` | Start, Current, End |

### Navigation Buttons

| Button | Shortcut | Aktion |
|--------|----------|--------|
| Jump Backward | `Shift+←` | `jumpBackward()` (10 zurück) |
| Previous | `←` | `goToPrevious()` |
| Position | - | `currentIndex / total` |
| Next | `→` | `goToNext()` |
| Jump Forward | `Shift+→` | `jumpForward()` (10 vor) |

### Keyboard Navigation

```swift
.onKeyPress(.leftArrow) { goToPrevious() }
.onKeyPress(.rightArrow) { goToNext() }
.onKeyPress(.leftArrow, modifiers: .shift) { jumpBackward() }
.onKeyPress(.rightArrow, modifiers: .shift) { jumpForward() }
```

---

## Zusammenfassungen (Summary)

### SummaryRequestView

**Datei:** `Scrainee/UI/Summary/SummaryRequestView.swift`

| Element | Typ | Binding | Aktion |
|---------|-----|---------|--------|
| Start Date | `DatePicker` | `startDate` | - |
| End Date | `DatePicker` | `endDate` | - |
| Letzte Stunde | `Button` | - | `setLastHour()` |
| Letzte 4 Stunden | `Button` | - | `setLastFourHours()` |
| Heute | `Button` | - | `setToday()` |
| Gestern | `Button` | - | `setYesterday()` |
| Zusammenfassung erstellen | `Button` | - | `generateSummary()` |
| Schnell (nur Text) | `Button` | - | `generateQuickSummary()` |
| Loading | `ProgressView` | `isGenerating` | - |
| Screenshot Count | `Text` | `screenshotCount` | - |
| Summary Result | `ScrollView` | `lastSummary` | Mit Copy-Button |

### SummaryListView

**Datei:** `Scrainee/UI/Summary/SummaryListView.swift`

| Element | Typ | Aktion |
|---------|-----|--------|
| Refresh | `Button` | `loadSummaries()` |
| Summary Row | `Button` | Öffnet Detail-Sheet |
| Export | `Button` | Öffnet Notion-Export |
| Delete | `Button` | `deleteSummary()` |

### Datenfluss

```
User wählt Zeitraum → Generate
    ↓
SummaryViewModel.generateSummary()
    ↓
DatabaseManager.getScreenshots(from:, to:)
    ↓ OCR-Texte sammeln
SummaryGenerator.generateSummary(context:)
    ↓
ClaudeAPIClient.generateSummary()
    ↓ API Call
DatabaseManager.insert(summary)
    ↓
@Published var lastSummary
```

---

## Meeting Minutes

**Dateien:**
- View: `Scrainee/UI/MeetingMinutes/MeetingMinutesView.swift`
- ViewModel: `Scrainee/UI/MeetingMinutes/MeetingMinutesViewModel.swift`

### Toolbar

| Element | Typ | Aktion |
|---------|-----|--------|
| Live Badge | `LiveTranscriptionBadge` | Pulsiert wenn aktiv |
| Refresh | `Button` | `refresh()` |
| Regenerate | `Button` | `regenerateMinutes()` |
| Export Menu | `Menu` | Markdown, Notion |

### Left Panel - Transcript

| Element | Typ | Binding |
|---------|-----|---------|
| Titel | `Text` | "Transkript" |
| Count | `Text` | `segments.count` |
| Search | `TextField` | `searchText` |
| Clear | `Button` | Reset Search |
| Segment List | `List` | `segments` |
| Word Count | `Text` | `transcriptWordCount` |
| Duration | `Text` | Formatiert |

### Transcript Segment Row

| Element | Anzeige |
|---------|---------|
| Timestamp | `HH:MM` |
| Text | Segment-Text |

### Right Panel - Minutes (Tabs)

#### Tab: Summary

| Element | Typ | Quelle |
|---------|-----|--------|
| Zusammenfassung | `GroupBox` | `summaryText` |
| Kernpunkte | `List` | `keyPoints` |
| Meeting Info | `LabeledContent` | Details |

#### Tab: Action Items

| Element | Typ | Aktion |
|---------|-----|--------|
| Add Button | `Button` | `showAddActionItemSheet()` |
| Item List | `List` | `actionItems` |
| Checkbox | `Button` | `toggleActionItemStatus()` |
| Delete | `Button` | `deleteActionItem()` |

#### Tab: Decisions

| Element | Typ | Quelle |
|---------|-----|--------|
| Decision List | `List` | `decisions` |

### Action Item Row

| Element | Anzeige | Aktion |
|---------|---------|--------|
| Status Checkbox | circle / checkmark.circle.fill | Toggle |
| Title | Text (strikethrough wenn done) | - |
| Assignee | Label (person) | - |
| Due Date | Label (calendar, rot wenn overdue) | - |
| Priority Badge | PriorityBadge (farbkodiert) | - |
| Delete | Button (trash, rot) | Delete |

### Live Transcription Badge

```swift
// Pulsierend wenn aktiv
Circle().fill(.red)
    .scaleEffect(isAnimating ? 1.2 : 1.0)
    .animation(.easeInOut(duration: 0.5).repeatForever())
```

---

## Meeting Indicator

**Dateien:**
- View: `Scrainee/UI/MeetingIndicator/MeetingIndicatorView.swift`
- ViewModel: `Scrainee/UI/MeetingIndicator/MeetingIndicatorViewModel.swift`

### Recording Mode

| Element | Typ | Binding |
|---------|-----|---------|
| Recording Indicator | `Circle` (pulsierend) | `isRecording` |
| App Name | `Text` | `meetingAppName` |
| Status | `Text` | "Aufnahme läuft" |
| Duration | `Text` | `duration` (HH:MM:SS) |

### Confirmation Banner (wenn Meeting möglicherweise endet)

| Element | Typ | Aktion |
|---------|-----|--------|
| "Meeting beendet?" | `Text` | - |
| Ja, beenden | `Button` | `confirmMeetingEnded()` |
| Nein, läuft noch | `Button` | `dismissEndConfirmation()` |

### Control Buttons

| Button | Aktion |
|--------|--------|
| Meeting beenden | `stopMeeting()` |

### Start Confirmation Mode

| Element | Typ | Aktion |
|---------|-----|--------|
| Video Icon | `Image` | Blau |
| "Meeting erkannt" | `Text` | - |
| App Name | `Text` | `pendingMeetingAppName` |
| "Möchtest du aufnehmen?" | `Text` | - |
| Nein | `Button` | `dismissStartConfirmation()` |
| Ja, aufnehmen | `Button` | `confirmStartRecording()` |

---

## Datenfluss-Diagramme

### Screenshot-Aufnahme

```
Timer fires (Intervall)
    ↓
ScreenCaptureManager.captureScreen()
    ↓
DisplayManager.getDisplays() → [SCDisplay]
    ↓ Parallel für jeden Monitor
ScreenCaptureKit.captureContent()
    ↓
OCRManager.performOCR(image) → String
    ↓
ImageCompressor.compress(image) → HEIC Data
    ↓
StorageManager.save(data) → URL
    ↓
DatabaseManager.insert(screenshot)
    ↓
delegate?.didCaptureScreenshot()
    ↓
AppState.screenshotCount += 1
AppState.lastCaptureTime = Date()
```

### Meeting-Erkennung

```
NSWorkspace.didLaunchApplicationNotification
    ↓
MeetingDetector.handleAppLaunch(bundleId)
    ↓ Prüfe: Teams, Zoom, Meet, Webex
Meeting-App erkannt
    ↓
.meetingDetectedAwaitingConfirmation Notification
    ↓
MeetingIndicatorView zeigt Bestätigung
    ↓
User klickt "Ja, aufnehmen"
    ↓
MeetingDetector.confirmMeetingStart()
    ↓
.meetingStarted Notification
    ↓
├─ AppState.handleMeetingStarted()
├─ MeetingTranscriptionCoordinator.startTranscription()
└─ MeetingIndicatorView zeigt Recording
```

### Suche

```
User tippt in SearchView
    ↓ onChange, 300ms Debounce
SearchViewModel.search(query)
    ↓ Task { }
DatabaseManager.searchOCR(query, limit: 100)
    ↓ SQL LIKE Query
Returns [SearchResult]
    ↓
@Published var results = [SearchResult]
    ↓ SwiftUI Binding
List rendert neu
```

### AI-Zusammenfassung

```
User klickt "Zusammenfassung erstellen"
    ↓
SummaryViewModel.generateSummary(from, to)
    ↓
DatabaseManager.getScreenshots(from, to)
    ↓
OCR-Texte zu Context zusammenfassen
    ↓
ClaudeAPIClient.generateSummary(context)
    ↓ HTTPS POST zu api.anthropic.com
Claude Response
    ↓
DatabaseManager.insert(summary)
    ↓
@Published var lastSummary
    ↓
View zeigt Ergebnis
```

---

## State Management

### AppState (Zentraler State)

**Datei:** `Scrainee/App/AppState.swift`

```swift
@MainActor
class AppState: ObservableObject {
    static let shared = AppState()

    // Capture State
    @Published var isCapturing: Bool = false
    @Published var screenshotCount: Int = 0
    @Published var totalScreenshots: Int = 0
    @Published var storageUsed: String = "0 MB"
    @Published var lastCaptureTime: Date?

    // Meeting State
    @Published var isMeetingActive: Bool = false
    @Published var currentMeeting: MeetingSession?

    // AI State
    @Published var isGeneratingSummary: Bool = false
    @Published var lastSummary: Summary?

    // Error State
    @Published var errorMessage: String?
    @Published var showPermissionAlert: Bool = false

    // Startup Checks
    @Published var startupChecks: [StartupCheck] = []
}
```

### ViewModel Pattern

Alle ViewModels folgen dem gleichen Muster:

```swift
@MainActor
class SomeViewModel: ObservableObject {
    // Published State
    @Published var items: [Item] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    // Dependencies
    private let databaseManager: DatabaseManager

    // Actions
    func loadItems() async {
        isLoading = true
        defer { isLoading = false }

        do {
            items = try await databaseManager.getItems()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
```

### Notification-basierte Kommunikation

```swift
// Definiert in Extensions
extension Notification.Name {
    // Window Events
    static let showQuickAsk = Notification.Name("showQuickAsk")
    static let showSearch = Notification.Name("showSearch")
    static let showTimeline = Notification.Name("showTimeline")
    static let showMeetingMinutes = Notification.Name("showMeetingMinutes")

    // Meeting Events
    static let meetingStarted = Notification.Name("meetingStarted")
    static let meetingEnded = Notification.Name("meetingEnded")
    static let meetingDetectedAwaitingConfirmation = Notification.Name("...")
    static let meetingEndConfirmationRequested = Notification.Name("...")

    // Transcription Events
    static let transcriptionCompleted = Notification.Name("...")
}
```

### Combine Bindings

```swift
// In ViewModel
private var cancellables = Set<AnyCancellable>()

init() {
    // Subscribe to notifications
    NotificationCenter.default.publisher(for: .meetingStarted)
        .receive(on: DispatchQueue.main)
        .sink { [weak self] notification in
            self?.handleMeetingStarted(notification)
        }
        .store(in: &cancellables)

    // Bind to other publishers
    coordinator.$currentSegments
        .receive(on: DispatchQueue.main)
        .assign(to: &$segments)
}
```

---

## Schnellreferenz: Button → Funktion

| UI-Element | Datei | Funktion | Backend-Service |
|------------|-------|----------|-----------------|
| MenuBar Play/Pause | MenuBarView | `toggleCapture()` | ScreenCaptureManager |
| Search Field | SearchView | `search(query:)` | DatabaseManager |
| Quick Ask Submit | QuickAskView | `askQuestion()` | ClaudeAPIClient |
| Generate Summary | SummaryRequestView | `generateSummary()` | SummaryGenerator |
| Timeline Nav | TimelineView | `goToNext()` | TimelineViewModel |
| Gallery Delete | GalleryView | `deleteScreenshot()` | DatabaseManager + StorageManager |
| Meeting Confirm | MeetingIndicatorView | `confirmStartRecording()` | MeetingDetector |
| Action Item Toggle | MeetingMinutesView | `toggleActionItemStatus()` | DatabaseManager |
| Notion Export | MeetingMinutesView | `exportToNotion()` | NotionClient |
| Settings Save API | AISettingsView | `saveAPIKey()` | KeychainService |

---

*Letzte Aktualisierung: 2026-01-20*
