# Scrainee Abhängigkeits-Dokumentationssystem

Dieses Dokument beschreibt das System zur Dokumentation und Verfolgung von Abhängigkeiten zwischen Dateien/Komponenten, um sicherzustellen, dass bei Änderungen keine abhängigen Komponenten übersehen werden.

---

## Inhaltsverzeichnis

1. [Das Problem](#das-problem)
2. [Die Lösung: Dependency Headers](#die-lösung-dependency-headers)
3. [Header-Format Spezifikation](#header-format-spezifikation)
4. [Beispiele](#beispiele)
5. [Checklisten für Änderungen](#checklisten-für-änderungen)
6. [Kritische Abhängigkeits-Matrix](#kritische-abhängigkeits-matrix)
7. [Claude Code Integration](#claude-code-integration)

---

## Das Problem

Bei Änderungen an einer Datei können leicht abhängige Komponenten übersehen werden:

1. **Notification-Listener vergessen** - Neue Notification posten → Observer nicht hinzugefügt
2. **Singleton State Mismatch** - Property in einem Singleton ändern → abhängige Views nicht aktualisiert
3. **Delegate Callbacks** - Delegate-Protokoll ändern → Implementierungen nicht angepasst
4. **Window Opening Chain** - Neue View erstellen → HotkeyManager und ScraineeApp nicht verknüpft
5. **Database Schema** - Model ändern → Migrations nicht aktualisiert

---

## Die Lösung: Dependency Headers

Jede Swift-Datei erhält einen standardisierten Header-Block, der alle Abhängigkeiten dokumentiert.

### Vorteile

- **Sofort sichtbar** - Beim Öffnen einer Datei sieht man alle Verknüpfungen
- **Maschinenlesbar** - Kann von Tools/Scripts ausgewertet werden
- **Wartbar** - Einfaches Format, das bei Änderungen aktualisiert wird
- **Claude Code kompatibel** - Ich (Claude) kann diese Header lesen und bei Änderungen alle abhängigen Dateien identifizieren

---

## Header-Format Spezifikation

```swift
// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - 📋 DEPENDENCY DOCUMENTATION
// ═══════════════════════════════════════════════════════════════════════════════
//
// FILE: [Dateiname.swift]
// PURPOSE: [Kurze Beschreibung der Hauptaufgabe]
// LAYER: [App | Core | Service | UI | Test]
//
// ┌─────────────────────────────────────────────────────────────────────────────┐
// │ DEPENDENCIES (was diese Datei NUTZT)                                        │
// ├─────────────────────────────────────────────────────────────────────────────┤
// │ IMPORTS:                                                                     │
// │   - DatabaseManager.shared      → Core/Database/DatabaseManager.swift       │
// │   - AppState.shared             → App/AppState.swift                        │
// │                                                                              │
// │ LISTENS TO (Notifications):                                                  │
// │   - .meetingStarted             ← MeetingDetector.swift:439                 │
// │   - .meetingEnded               ← MeetingDetector.swift:452                 │
// │                                                                              │
// │ PROTOCOLS IMPLEMENTED:                                                       │
// │   - ScreenCaptureManagerDelegate ← ScreenCaptureManager.swift:8             │
// └─────────────────────────────────────────────────────────────────────────────┘
//
// ┌─────────────────────────────────────────────────────────────────────────────┐
// │ DEPENDENTS (was diese Datei NUTZT wird von)                                 │
// ├─────────────────────────────────────────────────────────────────────────────┤
// │ USED BY:                                                                     │
// │   - MenuBarView.swift           → @EnvironmentObject                        │
// │   - SettingsView.swift          → @EnvironmentObject                        │
// │   - TimelineViewModel.swift     → Direct call                               │
// │                                                                              │
// │ POSTS (Notifications):                                                       │
// │   - .showQuickAsk               → Listeners: ScraineeApp.swift:253          │
// │                                                                              │
// │ DELEGATES TO:                                                                │
// │   - AppState (via delegate)     → didCaptureScreenshot callback             │
// └─────────────────────────────────────────────────────────────────────────────┘
//
// ┌─────────────────────────────────────────────────────────────────────────────┐
// │ CHANGE IMPACT                                                               │
// ├─────────────────────────────────────────────────────────────────────────────┤
// │ IF YOU MODIFY:                                                              │
// │   - @Published properties → Update all @EnvironmentObject consumers         │
// │   - Notification posting  → Verify all listeners still receive              │
// │   - Delegate protocol     → Update all implementing classes                 │
// │   - Database queries      → Check DatabaseManager migrations                │
// │                                                                              │
// │ CRITICAL SEQUENCES:                                                          │
// │   - initializeApp() must await DatabaseManager.initialize() FIRST           │
// │   - Whisper model must load BEFORE MeetingTranscriptionCoordinator starts   │
// └─────────────────────────────────────────────────────────────────────────────┘
//
// LAST UPDATED: 2026-01-20
// ═══════════════════════════════════════════════════════════════════════════════
```

---

## Beispiele

### Beispiel 1: AppState.swift

```swift
// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - 📋 DEPENDENCY DOCUMENTATION
// ═══════════════════════════════════════════════════════════════════════════════
//
// FILE: AppState.swift
// PURPOSE: Zentraler App-State als @MainActor Singleton ObservableObject
// LAYER: App
//
// ┌─────────────────────────────────────────────────────────────────────────────┐
// │ DEPENDENCIES (was diese Datei NUTZT)                                        │
// ├─────────────────────────────────────────────────────────────────────────────┤
// │ IMPORTS:                                                                     │
// │   - DatabaseManager.shared      → Core/Database/DatabaseManager.swift       │
// │   - ScreenCaptureManager        → Core/ScreenCapture/ScreenCaptureManager   │
// │   - PermissionManager.shared    → Services/PermissionManager.swift          │
// │   - StorageManager.shared       → Core/Storage/StorageManager.swift         │
// │   - SummaryGenerator            → Core/AI/SummaryGenerator.swift            │
// │   - NotionClient                → Core/Integration/NotionClient.swift       │
// │   - WhisperTranscriptionService → Core/Audio/WhisperTranscriptionService    │
// │   - MeetingSession (Model)      → Core/Meeting/MeetingSession.swift         │
// │                                                                              │
// │ LISTENS TO (Notifications):                                                  │
// │   - .meetingStarted             ← MeetingDetector.swift:439                 │
// │   - .meetingEnded               ← MeetingDetector.swift:452                 │
// │                                                                              │
// │ PROTOCOLS IMPLEMENTED:                                                       │
// │   - ScreenCaptureManagerDelegate ← ScreenCaptureManager.swift:8             │
// └─────────────────────────────────────────────────────────────────────────────┘
//
// ┌─────────────────────────────────────────────────────────────────────────────┐
// │ DEPENDENTS (wer diese Datei NUTZT)                                          │
// ├─────────────────────────────────────────────────────────────────────────────┤
// │ USED BY (via @EnvironmentObject):                                           │
// │   - MenuBarView.swift           → UI/MenuBar/                               │
// │   - SettingsView.swift          → UI/Settings/                              │
// │   - SearchView.swift            → UI/Search/                                │
// │   - SummaryRequestView.swift    → UI/Summary/                               │
// │   - QuickAskView.swift          → UI/QuickAsk/                              │
// │   - TimelineView.swift          → UI/Timeline/                              │
// │   - GalleryView.swift           → UI/Gallery/                               │
// │   - MeetingMinutesView.swift    → UI/MeetingMinutes/                        │
// │   - MeetingIndicatorView.swift  → UI/MeetingIndicator/                      │
// │                                                                              │
// │ DIRECT CALLS:                                                                │
// │   - ScraineeApp.swift           → AppState.shared                           │
// │   - HotkeyManager.swift         → toggleCapture()                           │
// └─────────────────────────────────────────────────────────────────────────────┘
//
// ┌─────────────────────────────────────────────────────────────────────────────┐
// │ CHANGE IMPACT                                                               │
// ├─────────────────────────────────────────────────────────────────────────────┤
// │ IF YOU MODIFY:                                                              │
// │   - @Published properties       → 9+ Views müssen neu kompilieren           │
// │   - toggleCapture()             → HotkeyManager Hotkey funktioniert nicht   │
// │   - initializeApp()             → App-Start Reihenfolge beachten!           │
// │   - handleMeetingStarted()      → MeetingDetector Notification prüfen       │
// │                                                                              │
// │ CRITICAL SEQUENCES:                                                          │
// │   1. DatabaseManager.initialize() MUSS VOR allen Queries laufen             │
// │   2. WhisperTranscriptionService.loadModel() ist BLOCKING AWAIT             │
// │   3. autoStartCapture ERST NACH beiden obigen Schritten                     │
// └─────────────────────────────────────────────────────────────────────────────┘
//
// LAST UPDATED: 2026-01-20
// ═══════════════════════════════════════════════════════════════════════════════

import SwiftUI
import Combine

@MainActor
class AppState: ObservableObject {
    // ... rest of implementation
}
```

### Beispiel 2: MeetingDetector.swift

```swift
// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - 📋 DEPENDENCY DOCUMENTATION
// ═══════════════════════════════════════════════════════════════════════════════
//
// FILE: MeetingDetector.swift
// PURPOSE: Erkennt Meeting-Apps (Teams, Zoom, Meet, Webex) und verwaltet Meeting-Status
// LAYER: Core/Meeting
//
// ┌─────────────────────────────────────────────────────────────────────────────┐
// │ DEPENDENCIES (was diese Datei NUTZT)                                        │
// ├─────────────────────────────────────────────────────────────────────────────┤
// │ IMPORTS:                                                                     │
// │   - NSWorkspace                 → System (AppKit)                           │
// │   - Accessibility API           → System (für Fenstertitel)                 │
// │   - DatabaseManager.shared      → Core/Database/DatabaseManager.swift       │
// │                                                                              │
// │ LISTENS TO (System Notifications):                                           │
// │   - NSWorkspace.didLaunchApplicationNotification                            │
// │   - NSWorkspace.didTerminateApplicationNotification                         │
// │   - NSWorkspace.didActivateApplicationNotification                          │
// └─────────────────────────────────────────────────────────────────────────────┘
//
// ┌─────────────────────────────────────────────────────────────────────────────┐
// │ DEPENDENTS (wer diese Datei NUTZT)                                          │
// ├─────────────────────────────────────────────────────────────────────────────┤
// │ POSTS (Notifications) → Listener:                                            │
// │   - .meetingStarted (Zeile 439)                                             │
// │       → AppState.swift:145                                                  │
// │       → ScreenCaptureManager.swift:127                                      │
// │       → MeetingTranscriptionCoordinator.swift:251                           │
// │       → MeetingIndicatorViewModel.swift:78                                  │
// │                                                                              │
// │   - .meetingEnded (Zeile 452)                                               │
// │       → AppState.swift:162                                                  │
// │       → ScreenCaptureManager.swift:135                                      │
// │       → MeetingTranscriptionCoordinator.swift:313                           │
// │       → MeetingIndicatorViewModel.swift:95                                  │
// │                                                                              │
// │   - .meetingDetectedAwaitingConfirmation (Zeile 281)                        │
// │       → MeetingIndicatorViewModel.swift:112                                 │
// │       → ScraineeApp.swift:313                                               │
// │                                                                              │
// │   - .meetingEndConfirmationRequested (Zeile 248)                            │
// │       → MeetingIndicatorViewModel.swift:128                                 │
// │                                                                              │
// │   - .meetingStartDismissed (Zeile 318)                                      │
// │       → MeetingIndicatorViewModel.swift:142                                 │
// │       → ScraineeApp.swift:325                                               │
// └─────────────────────────────────────────────────────────────────────────────┘
//
// ┌─────────────────────────────────────────────────────────────────────────────┐
// │ CHANGE IMPACT                                                               │
// ├─────────────────────────────────────────────────────────────────────────────┤
// │ IF YOU MODIFY:                                                              │
// │   - Notification Names          → ALLE 4+ Listener müssen aktualisiert werden│
// │   - activeMeeting Property      → AppState.currentMeeting synchron halten   │
// │   - Meeting-App Liste           → Keine weiteren Abhängigkeiten             │
// │   - @MainActor entfernen        → POTENTIELLER DEADLOCK!                    │
// │                                                                              │
// │ NEUE NOTIFICATION HINZUFÜGEN:                                               │
// │   1. Notification.Name in Extension definieren                              │
// │   2. Alle relevanten Listener in ScraineeApp.swift hinzufügen               │
// │   3. ViewModel-Listener hinzufügen wenn UI-Reaktion nötig                   │
// └─────────────────────────────────────────────────────────────────────────────┘
//
// LAST UPDATED: 2026-01-20
// ═══════════════════════════════════════════════════════════════════════════════
```

### Beispiel 3: TimelineViewModel.swift

```swift
// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - 📋 DEPENDENCY DOCUMENTATION
// ═══════════════════════════════════════════════════════════════════════════════
//
// FILE: TimelineViewModel.swift
// PURPOSE: ViewModel für Timeline-View - verwaltet Screenshot-Navigation und State
// LAYER: UI/Timeline
//
// ┌─────────────────────────────────────────────────────────────────────────────┐
// │ DEPENDENCIES (was diese Datei NUTZT)                                        │
// ├─────────────────────────────────────────────────────────────────────────────┤
// │ IMPORTS:                                                                     │
// │   - DatabaseManager.shared      → Core/Database/DatabaseManager.swift       │
// │       Methods: getScreenshotsForDay(), getTimeBoundsForDay(),              │
// │                getScreenshotClosestTo(), getActivitySegments()              │
// │   - ThumbnailCache.shared       → Core/Cache/ThumbnailCache.swift           │
// │       Methods: getThumbnail(), preloadThumbnails()                          │
// │   - Screenshot (Model)          → Core/Database/Models/Screenshot.swift     │
// │   - ActivitySegment (Model)     → Core/Database/Models/ActivitySegment.swift│
// └─────────────────────────────────────────────────────────────────────────────┘
//
// ┌─────────────────────────────────────────────────────────────────────────────┐
// │ DEPENDENTS (wer diese Datei NUTZT)                                          │
// ├─────────────────────────────────────────────────────────────────────────────┤
// │ USED BY:                                                                     │
// │   - TimelineView.swift          → @StateObject viewModel                    │
// │   - TimelineSliderView.swift    → Binding<Double> sliderValue               │
// │   - TimelineThumbnailStrip.swift→ screenshots, currentIndex                 │
// └─────────────────────────────────────────────────────────────────────────────┘
//
// ┌─────────────────────────────────────────────────────────────────────────────┐
// │ CHANGE IMPACT                                                               │
// ├─────────────────────────────────────────────────────────────────────────────┤
// │ IF YOU MODIFY:                                                              │
// │   - @Published screenshots      → TimelineThumbnailStrip aktualisiert auto  │
// │   - @Published currentIndex     → Slider und Preview aktualisiert auto      │
// │   - goToNext/Previous()         → Keyboard-Handler in TimelineView          │
// │   - loadScreenshotsForDay()     → Prüfen ob DB-Query sich geändert hat      │
// │                                                                              │
// │ DATABASE QUERIES:                                                            │
// │   - getScreenshotsForDay()      → Kann langsam sein bei vielen Screenshots  │
// │   - Pagination hinzufügen?      → Dann TimelineView anpassen                │
// └─────────────────────────────────────────────────────────────────────────────┘
//
// LAST UPDATED: 2026-01-20
// ═══════════════════════════════════════════════════════════════════════════════
```

---

## Checklisten für Änderungen

### Checkliste: Neue View hinzufügen

```markdown
## Neue View Checkliste

- [ ] View-Datei erstellen in `UI/[Feature]/`
- [ ] ViewModel erstellen (falls nötig)
- [ ] Window in `ScraineeApp.swift` registrieren
- [ ] Window ID vergeben (z.B. "newfeature")
- [ ] Falls Hotkey gewünscht:
  - [ ] HotkeyManager.swift: Neuen Hotkey registrieren
  - [ ] Notification.Name Extension: Neue Notification definieren
  - [ ] ScraineeApp.swift: Observer für Notification hinzufügen
- [ ] Falls AppState benötigt:
  - [ ] `@EnvironmentObject var appState: AppState` hinzufügen
- [ ] Dependency Header hinzufügen
- [ ] UI-ARCHITECTURE.md aktualisieren
```

### Checkliste: Notification ändern/hinzufügen

```markdown
## Notification Checkliste

- [ ] Notification.Name in Extension definieren
- [ ] Sender-Datei: post() Aufruf hinzufügen
- [ ] ALLE Listener identifizieren und aktualisieren:
  - [ ] ScraineeApp.swift (für Window-Öffnung)
  - [ ] AppState.swift (für State-Updates)
  - [ ] Relevante ViewModels
  - [ ] ScreenCaptureManager (falls Capture-relevant)
  - [ ] MeetingTranscriptionCoordinator (falls Meeting-relevant)
- [ ] Dependency Headers in Sender UND allen Listenern aktualisieren
```

### Checkliste: Database Model ändern

```markdown
## Database Model Checkliste

- [ ] Model-Datei ändern in `Core/Database/Models/`
- [ ] DatabaseManager.swift: Migration hinzufügen
- [ ] KRITISCH: Migrations-Reihenfolge prüfen!
- [ ] Alle Queries prüfen die das Model nutzen:
  - [ ] DatabaseManager Query-Methoden
  - [ ] ViewModels die das Model nutzen
- [ ] Falls Property umbenannt: Alle Referenzen suchen
- [ ] Dependency Headers aktualisieren
```

### Checkliste: Delegate-Protokoll ändern

```markdown
## Delegate Protokoll Checkliste

- [ ] Protokoll-Definition ändern
- [ ] ALLE Implementierungen finden und aktualisieren:
  - [ ] `grep -r "ProtocolName" --include="*.swift"`
- [ ] Thread-Safety prüfen:
  - [ ] Ist die Implementierung @MainActor?
  - [ ] Wird in Task { @MainActor in } aufgerufen?
- [ ] Dependency Headers aktualisieren
```

---

## Kritische Abhängigkeits-Matrix

Diese Matrix zeigt die kritischsten Abhängigkeiten, die bei Änderungen beachtet werden müssen:

```
┌────────────────────────┬──────────────────────────────────────────────────────┐
│ WENN DU ÄNDERST...     │ DANN PRÜFE AUCH...                                   │
├────────────────────────┼──────────────────────────────────────────────────────┤
│ AppState.@Published    │ Alle 9+ Views mit @EnvironmentObject                 │
│ AppState.initializeApp │ DatabaseManager, WhisperService, autoStartCapture    │
│ AppState.toggleCapture │ HotkeyManager (Cmd+Shift+R)                          │
├────────────────────────┼──────────────────────────────────────────────────────┤
│ MeetingDetector.post() │ AppState, ScreenCaptureManager, Coordinator, VM      │
│ MeetingDetector.state  │ AppState.currentMeeting synchron halten              │
├────────────────────────┼──────────────────────────────────────────────────────┤
│ DatabaseManager.init   │ AppState.initializeApp() Reihenfolge                 │
│ DatabaseManager.insert │ Alle ViewModels die queries machen                   │
│ Database Schema        │ Migration-Reihenfolge in initialize()                │
├────────────────────────┼──────────────────────────────────────────────────────┤
│ ScreenCaptureManager   │ AppState (delegate), DisplayManager                  │
│ SCM.delegate Protokoll │ AppState Extension (ScreenCaptureManagerDelegate)    │
├────────────────────────┼──────────────────────────────────────────────────────┤
│ HotkeyManager.register │ Accessibility Permissions, ScraineeApp observers     │
│ HotkeyManager.post()   │ ScraineeApp window opening closures                  │
├────────────────────────┼──────────────────────────────────────────────────────┤
│ ScraineeApp.Window()   │ openWindow(id:) Aufrufe, HotkeyManager               │
│ ScraineeApp.observers  │ HotkeyManager, MeetingDetector Notifications         │
├────────────────────────┼──────────────────────────────────────────────────────┤
│ WhisperService.load    │ AppState.initializeApp() BLOCKING AWAIT              │
│ Whisper model path     │ MeetingTranscriptionCoordinator                      │
├────────────────────────┼──────────────────────────────────────────────────────┤
│ DisplayManager.get     │ ScreenCaptureManager Multi-Monitor                   │
│ DisplayManager.notify  │ ScreenCaptureManager Observer                        │
└────────────────────────┴──────────────────────────────────────────────────────┘
```

---

## Claude Code Integration

### Anweisungen für Claude Code (in CLAUDE.md hinzufügen)

```markdown
## Abhängigkeits-Management

### Bei Code-Änderungen

1. **VOR der Änderung:**
   - Lies den Dependency Header der zu ändernden Datei
   - Identifiziere alle DEPENDENTS (wer nutzt diese Datei)
   - Prüfe CHANGE IMPACT Sektion

2. **WÄHREND der Änderung:**
   - Wenn @Published Property geändert wird → alle Consumer prüfen
   - Wenn Notification geändert wird → alle Listener aktualisieren
   - Wenn Protokoll geändert wird → alle Implementierungen anpassen

3. **NACH der Änderung:**
   - Dependency Header aktualisieren (LAST UPDATED Datum)
   - Abhängige Dateien ebenfalls aktualisieren wenn nötig
   - UI-ARCHITECTURE.md aktualisieren falls UI-relevant

### Bei neuen Dateien

1. Dependency Header hinzufügen (siehe DEPENDENCY-DOCS.md)
2. In UI-ARCHITECTURE.md eintragen falls UI-Komponente
3. Relevante existierende Headers aktualisieren (DEPENDENTS Sektion)

### Kritische Änderungen

Bei Änderungen an diesen Dateien IMMER alle Abhängigkeiten prüfen:
- AppState.swift (38+ Dependents)
- DatabaseManager.swift (8+ ViewModels)
- MeetingDetector.swift (5 Notifications, 4+ Listener je)
- ScreenCaptureManager.swift (Delegate, Multi-Monitor)
- ScraineeApp.swift (10+ Window-Observer)
```

### Automatisierte Prüfung (optional)

Ein Script könnte erstellt werden, das bei Commits prüft:

```bash
#!/bin/bash
# check-dependencies.sh

# Prüfe ob geänderte Dateien Dependency Headers haben
for file in $(git diff --name-only --cached | grep ".swift$"); do
    if ! grep -q "DEPENDENCY DOCUMENTATION" "$file"; then
        echo "WARNING: $file hat keinen Dependency Header"
    fi

    # Prüfe ob LAST UPDATED aktuell ist
    if grep -q "LAST UPDATED:" "$file"; then
        last_update=$(grep "LAST UPDATED:" "$file" | sed 's/.*LAST UPDATED: //')
        today=$(date +%Y-%m-%d)
        if [ "$last_update" != "$today" ]; then
            echo "WARNING: $file Dependency Header nicht aktualisiert"
        fi
    fi
done
```

---

## Zusammenfassung

Dieses System stellt sicher, dass:

1. **Jede Datei dokumentiert** was sie nutzt und wer sie nutzt
2. **Änderungs-Auswirkungen** sofort sichtbar sind
3. **Checklisten** verhindern, dass Abhängigkeiten vergessen werden
4. **Claude Code** bei Änderungen automatisch alle relevanten Dateien berücksichtigt
5. **Die Dokumentation aktuell bleibt** durch klare Update-Regeln

---

*Erstellt: 2026-01-20*
