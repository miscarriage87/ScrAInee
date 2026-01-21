# SCRAINEE - Technical Specifications

## 1. System Overview

### 1.1 Product Description
SCRAINEE is a macOS Menu Bar application for automatic screen capture with OCR text recognition, AI-powered summaries, and meeting detection with audio transcription.

### 1.2 Target Platform
- **Operating System:** macOS 13.0+ (Ventura)
- **Architecture:** Apple Silicon (arm64) and Intel (x86_64)
- **Distribution:** Direct download (not App Store due to ScreenCaptureKit requirements)

### 1.3 Technology Stack

| Component | Technology | Version |
|-----------|------------|---------|
| Language | Swift | 5.9+ |
| UI Framework | SwiftUI | Latest |
| Build System | Swift Package Manager | Latest |
| Database | SQLite via GRDB.swift | 6.24+ |
| Keychain | KeychainAccess | 4.2.2+ |
| Screen Capture | ScreenCaptureKit | macOS 13+ |
| OCR | Vision Framework | macOS 13+ |
| Audio Capture | Core Audio ProcessTap | macOS 14.2+ |
| Audio Fallback | ScreenCaptureKit | macOS 13-14.1 |
| Transcription | WhisperKit | Latest |
| AI | Claude API (Anthropic) | claude-sonnet-4-5-20250514 |
| Integration | Notion API | 2022-06-28 |

---

## 2. Architecture

### 2.1 Layer Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     APP LAYER                                    │
│  ScraineeApp (@main) │ AppState (Singleton Coordinator)         │
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

### 2.2 Design Patterns

| Pattern | Usage |
|---------|-------|
| MVVM | ViewModels for all complex Views |
| Singleton | AppState, DatabaseManager, StorageManager |
| Actor | Thread-safe shared state (DatabaseManager, HashTracker) |
| Observer | NotificationCenter for cross-component events |
| Delegate | ScreenCaptureManager → AppState |
| Protocol | Dependency injection (DisplayProviding, ScreenCaptureProviding) |

### 2.3 State Management

```swift
AppState (Singleton, @MainActor)
├── captureState: CaptureState      // Screenshot capture state
│   ├── isCapturing: Bool
│   ├── screenshotCount: Int
│   ├── totalScreenshots: Int
│   └── toggleCapture(), startCapture(), stopCapture()
├── meetingState: MeetingState      // Meeting-related state
│   ├── isMeetingActive: Bool
│   ├── currentMeeting: Meeting?
│   ├── isGeneratingSummary: Bool
│   └── handleMeetingStarted/Ended()
├── settingsState: SettingsState    // @AppStorage persistent settings
│   ├── captureInterval: Int
│   ├── autoStartCapture: Bool
│   └── Various user preferences
└── uiState: UIState                // Transient UI state
    ├── isShowingSettings: Bool
    └── activeWindow: WindowType?
```

---

## 3. Data Models

### 3.1 Database Schema (SQLite + GRDB)

#### Screenshot Table
```sql
CREATE TABLE screenshot (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp DATETIME NOT NULL,
    filePath TEXT NOT NULL,
    thumbnailPath TEXT,
    displayID INTEGER NOT NULL,
    displayName TEXT,
    windowTitle TEXT,
    applicationName TEXT,
    hash TEXT,
    width INTEGER,
    height INTEGER
);

CREATE INDEX idx_screenshot_timestamp ON screenshot(timestamp);
CREATE INDEX idx_screenshot_app_time ON screenshot(applicationName, timestamp);
CREATE INDEX idx_screenshot_display_time ON screenshot(displayID, timestamp);
```

#### OCRResult Table
```sql
CREATE TABLE ocrResult (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    screenshotId INTEGER NOT NULL REFERENCES screenshot(id) ON DELETE CASCADE,
    text TEXT NOT NULL,
    confidence REAL,
    language TEXT
);

CREATE VIRTUAL TABLE ocrResult_fts USING fts5(text, content='ocrResult', content_rowid='id');
```

#### Meeting Table
```sql
CREATE TABLE meeting (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    startTime DATETIME NOT NULL,
    endTime DATETIME,
    applicationName TEXT NOT NULL,
    title TEXT,
    audioFilePath TEXT,
    transcriptText TEXT,
    summaryText TEXT,
    notionPageUrl TEXT,
    status TEXT DEFAULT 'active'
);
```

#### Summary Table
```sql
CREATE TABLE summary (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    meetingId INTEGER REFERENCES meeting(id) ON DELETE CASCADE,
    generatedAt DATETIME NOT NULL,
    promptType TEXT NOT NULL,
    content TEXT NOT NULL,
    model TEXT
);
```

#### ActivitySegment Table
```sql
CREATE TABLE activitySegment (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    startTime DATETIME NOT NULL,
    endTime DATETIME NOT NULL,
    applicationName TEXT NOT NULL,
    displayID INTEGER NOT NULL
);
```

### 3.2 File Storage Structure

```
~/Library/Application Support/Scrainee/
├── scrainee.sqlite              # Main database
├── screenshots/                  # Screenshot images
│   └── YYYY/MM/DD/              # Organized by date
│       └── HH-mm-ss_displayID.heic
├── audio/                        # Meeting audio
│   └── meeting_<id>_<timestamp>.wav
└── logs/                         # Application logs
    └── scrainee_YYYY-MM-DD.log
```

---

## 4. Core Features

### 4.1 Screenshot Capture

**Requirements:**
- Capture all displays simultaneously (sequentially due to Swift 6 constraints)
- Support for Retina and non-Retina displays
- Configurable capture interval (default: 5 seconds)
- Automatic duplicate detection via perceptual hash (dHash)
- HEIC compression (60% quality) for storage efficiency

**Technical Details:**
- Use ScreenCaptureKit `SCShareableContent` for display enumeration
- Use `CGDisplayStream` or `SCScreenshotManager` for capture
- Store in `~/Library/Application Support/Scrainee/screenshots/`
- Maximum 4 parallel OCR tasks (semaphore-controlled)

### 4.2 OCR Text Recognition

**Requirements:**
- Extract text from all captured screenshots
- Support German and English languages
- Full-text search via FTS5
- Confidence scoring for quality filtering

**Technical Details:**
- Vision Framework `VNRecognizeTextRequest`
- Language hints: `["de-DE", "en-US"]`
- Recognition level: `.accurate`
- Store results in SQLite with FTS5 index

### 4.3 Meeting Detection

**Requirements:**
- Auto-detect meeting applications:
  - Microsoft Teams (bundle: `com.microsoft.teams`, `com.microsoft.teams2`)
  - Zoom (bundle: `us.zoom.xos`)
  - Webex (bundle: `com.webex.meetingmanager`)
  - Google Meet (Safari/Chrome with meet.google.com)
- User confirmation before recording starts
- Audio capture during meetings
- Real-time transcription

**Technical Details:**
- Monitor running applications via `NSWorkspace.shared.runningApplications`
- Post `.meetingDetectedAwaitingConfirmation` notification
- On confirmation, start audio capture and increase screenshot frequency

### 4.4 Audio Transcription

**Requirements:**
- On-device transcription (no cloud dependency)
- Real-time transcription during meetings
- Support for German and English
- Auto-unload model after 5 minutes inactivity (~3GB RAM saved)

**Technical Details:**
- WhisperKit with `openai_whisper-base` model
- Audio format: 16kHz mono WAV
- ProcessTap for system audio (macOS 14.2+)
- ScreenCaptureKit fallback for older macOS versions

### 4.5 AI Summaries

**Requirements:**
- Generate meeting summaries from transcripts + screenshots
- Support for different summary types (brief, detailed, action items)
- Notion export integration

**Technical Details:**
- Claude API (claude-sonnet-4-5-20250514)
- API key stored in Keychain
- Structured prompts for consistent output
- Rate limiting and retry logic

### 4.6 Timeline View

**Requirements:**
- Rewind.AI-style chronological navigation
- Time slider with application activity segments
- Thumbnail strip for quick preview
- Keyboard navigation (arrow keys)
- Date picker for historical data

**Technical Details:**
- ThumbnailCache actor for efficient loading
- Lazy loading with prefetching
- Activity segments color-coded by application

---

## 5. User Interface

### 5.1 Menu Bar

**Components:**
- Status icon (recording indicator)
- Quick toggle for capture
- Screenshot count display
- Meeting indicator (when active)
- Quick access to all views

### 5.2 Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| Cmd+Shift+A | Quick Ask - AI question about current context |
| Cmd+Shift+R | Toggle capture on/off |
| Cmd+Shift+F | Open search |
| Cmd+Shift+S | Generate summary |
| Cmd+Shift+G | Open gallery |
| Cmd+Shift+T | Open timeline |

### 5.3 Windows

| Window | Purpose |
|--------|---------|
| SettingsView | User preferences and API configuration |
| SearchView | Full-text search through OCR results |
| GalleryView | Browse screenshots by date/app |
| TimelineView | Chronological screenshot navigation |
| QuickAskView | AI-powered context questions |
| MeetingMinutesView | Meeting transcript and summary |
| SummaryRequestView | Summary generation options |

---

## 6. Security & Privacy

### 6.1 Permissions Required

| Permission | Type | Purpose |
|------------|------|---------|
| Screen Recording | Required | ScreenCaptureKit access |
| Accessibility | Optional | Window title detection |

### 6.2 Data Security

- **API Keys:** Stored in macOS Keychain via KeychainAccess
- **Local Data:** Protected by macOS FileVault (if enabled)
- **No Cloud Storage:** All data remains local
- **Audio Files:** Deleted after meeting summary generation (optional)

### 6.3 Entitlements

```xml
<key>com.apple.security.app-sandbox</key>
<true/>
<key>com.apple.security.cs.disable-library-validation</key>
<true/>  <!-- Required for WhisperKit -->
```

---

## 7. Performance Requirements

### 7.1 Targets

| Metric | Target |
|--------|--------|
| Screenshot capture | < 100ms per display |
| OCR processing | < 500ms per screenshot |
| Timeline scroll | 60 FPS |
| Memory (idle) | < 200MB |
| Memory (with Whisper) | < 3.5GB |
| Database query | < 50ms for 10k screenshots |

### 7.2 Optimizations Implemented

- Database indexes (4 indexes for common queries)
- ThumbnailCache actor with LRU eviction
- OCR semaphore (max 4 parallel tasks)
- WhisperKit auto-unload after 5 min inactivity
- StorageManager size cache (60s TTL)

---

## 8. Error Handling

### 8.1 Strategy

- **Critical errors:** Show user alert via `ErrorManager`
- **Non-critical errors:** Log to `FileLogger`
- **Recovery:** Automatic retry for transient failures

### 8.2 Known Limitations

- ScreenCaptureKit audio fallback (macOS 13-14.1) may produce silent audio
- Multi-monitor capture is sequential (Swift 6 Sendable constraint)
- Private browsing windows are not captured (system limitation)
- DRM-protected content appears black (system limitation)

---

## 9. Testing Requirements

### 9.1 Coverage Targets

| Layer | Target Coverage |
|-------|-----------------|
| Core/ | 80% |
| Services/ | 70% |
| UI/ViewModels | 60% |
| Integration | E2E tests |

### 9.2 Test Types

- **Unit Tests:** All Core components
- **Integration Tests:** Database, Storage, API
- **E2E Tests:** Full capture → OCR → search pipeline
- **Mock Validation:** Use `spec` parameter for signature validation

---

## 10. Build & Deployment

### 10.1 Build Commands

```bash
# Development build
swift build

# Release build
swift build -c release

# Run tests
swift test

# Tests with coverage
swift test --enable-code-coverage

# Generate Xcode project
xcodegen generate

# Open in Xcode
open Scrainee.xcodeproj
```

### 10.2 Dependencies (Package.swift)

```swift
dependencies: [
    .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.24.0"),
    .package(url: "https://github.com/kishikawakatsumi/KeychainAccess.git", from: "4.2.2"),
    .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.9.0"),
]
```

---

## 11. Notification Events

### 11.1 Active Notifications

| Notification | Sender | Listeners |
|--------------|--------|-----------|
| `.windowRequested` | HotkeyManager | ScraineeApp |
| `.meetingStarted` | MeetingDetector | AppState, Coordinator, ScreenCaptureManager |
| `.meetingEnded` | MeetingDetector | AppState, Coordinator |
| `.meetingDetectedAwaitingConfirmation` | MeetingDetector | MeetingIndicatorView |
| `.transcriptionCompleted` | Coordinator | ScraineeApp |

### 11.2 Deprecated Notifications (To Remove)

- 5 legacy window notifications in HotkeyManager (lines 240-249)

---

## 12. API Integrations

### 12.1 Claude API (Anthropic)

- **Endpoint:** `https://api.anthropic.com/v1/messages`
- **Model:** `claude-sonnet-4-5-20250514`
- **Authentication:** API key in Keychain
- **Rate Limits:** Handled with exponential backoff

### 12.2 Notion API

- **Endpoint:** `https://api.notion.com/v1`
- **Version:** `2022-06-28`
- **Authentication:** Integration token in Keychain
- **Database ID:** Stored in Keychain

---

## 13. Appendix

### 13.1 Critical File Paths

| File | Purpose |
|------|---------|
| `App/ScraineeApp.swift` | Entry point, window definitions |
| `App/AppState.swift` | Central state manager |
| `Core/Database/DatabaseManager.swift` | Thread-safe DB access |
| `Core/Meeting/MeetingDetector.swift` | Meeting app detection |
| `Core/Audio/ProcessTapAudioCapture.swift` | Audio capture (macOS 14.2+) |
| `Core/Audio/WhisperTranscriptionService.swift` | On-device transcription |
| `Core/AI/ClaudeAPIClient.swift` | AI integration |
| `Services/KeychainService.swift` | Secure credential storage |

### 13.2 Initialization Order (CRITICAL!)

```swift
// This order MUST NOT change!
func initializeApp() async {
    // 1. Database MUST be first
    try await DatabaseManager.shared.initialize()

    // 2. Whisper BLOCKING load (important for meeting system)
    try await WhisperTranscriptionService.shared.loadModel()

    // 3. Capture can start after both are ready
    if settingsState.autoStartCapture {
        await captureState.startCapture()
    }
}
```
