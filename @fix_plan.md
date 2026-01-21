# Ralph Fix Plan - SCRAINEE

## 🔴 High Priority (MANDATORY - Phase 1: Critical Fixes)

### Crash-Risk: Force-Unwraps

- [x] **FIX-001: DateUtils.swift:104** - Remove force-unwrap ✅
  - Problem: `Calendar.current.date(...)!` can crash
  - Fix: Used guard + fallback for endOfDay(), nil-coalescing for hoursAgo/daysAgo

- [x] **FIX-002: ExportManager.swift:206** - Remove force-unwrap ✅
  - Problem: `meeting.notionPageUrl!` crashes if URL is nil
  - Fix: Used `.map { }` pattern for optional URL handling

- [x] **FIX-003: ClaudeAPIClient.swift:141** - Remove force-cast ✅
  - Problem: `messagesJSON as! [[String: AnyCodable]]` can crash
  - Fix: Used guard + proper EncodingError with context

- [x] **FIX-004: ScreenCaptureManager.swift:535** - Document safe force-cast ✅
  - Problem: `windowElement as! AXUIElement` - actually safe due to AX API design
  - Fix: Added documentation comment explaining why cast is safe (toll-free bridged)

### Data-Loss Risk: Error Handling

- [x] **FIX-005: KeychainService error handling** ✅
  - File: `Scrainee/Services/KeychainService.swift`
  - Problem: All keychain operations used `try?` - errors silently swallowed
  - Fix: All `try?` replaced with `do-catch`, errors logged via FileLogger

- [x] **FIX-006: FileLogger try? fixes** ✅
  - File: `Scrainee/Services/FileLogger.swift`
  - Problem: Logging failures went unnoticed
  - Fix: Critical failures now write to stderr, cleanupOldLogs uses proper error handling, removed force-unwrap in Calendar.date()

- [x] **FIX-007: DatabaseManager cleanup error** ✅
  - File: `Scrainee/Core/Database/DatabaseManager.swift`
  - Line: 538
  - Problem: `try? FileManager.default.removeItem` could leave orphaned files
  - Fix: Now logs warning on failure, continues with DB deletion

## 🟡 Medium Priority (MANDATORY - Phase 1: Tests)

### Critical Components Without Tests (~25% coverage → 80% target)

- [x] **TEST-001: WhisperTranscriptionService tests** ✅
  - Created: `Tests/ScraineeTests/Unit/WhisperTranscriptionServiceTests.swift`
  - 21 tests covering: State properties, thread safety, TranscriptionError, AudioChunk, TranscriptSegment

- [x] **TEST-002: MeetingDetector tests** ✅
  - Created: `Tests/ScraineeTests/Unit/MeetingDetectorTests.swift`
  - 29 tests covering: 6 notifications, MeetingSession struct, state properties, URL patterns, bundle IDs

- [x] **TEST-003: ScreenCaptureManager tests** ✅
  - Extended: `Tests/ScraineeTests/Unit/ScreenCaptureManagerTests.swift`
  - Added 17 new tests (33 → 50 total):
    - AdaptiveCaptureManager integration (3 tests)
    - Multi-monitor scenarios with MockDisplayManager (5 tests)
    - DisplayInfo structure validation (3 tests)
    - simulateDisplayChange hot-plug (2 tests)
    - CaptureError equality (2 tests)
    - Screenshot hash/duplicate edge cases (2 tests)
  - Coverage: CaptureError, states, delegates, multi-monitor, adaptive intervals

- [x] **TEST-004: HotkeyManager tests** ✅
  - Created: `Tests/ScraineeTests/Unit/HotkeyManagerTests.swift`
  - 8 tests covering: Notification names, window ID mappings, notification payloads, singleton, edge cases

- [x] **TEST-005: PermissionManager tests** ✅
  - Created: `Tests/ScraineeTests/Unit/PermissionManagerTests.swift`
  - 13 tests covering: PermissionStatus logic, URL validation, German localization, singleton

- [x] **TEST-006: KeychainService tests** ✅
  - Created: `Tests/ScraineeTests/Unit/KeychainServiceTests.swift`
  - 15 tests covering: Get/set/delete, multiple keys, special chars, unicode, long values, Key enum

### Code Cleanup

- [x] **CLEAN-001: Remove AppState backward-compatibility** ✅
  - File: `Scrainee/App/AppState.swift`
  - Removed: 127 lines of wrapper properties and methods
  - Kept: `checkAndUpdatePermissions()` as coordination method
  - Updated: ScraineeApp.swift, MenuBarView.swift to use sub-state directly

- [x] **CLEAN-002: Remove HotkeyManager deprecated notifications** ✅
  - File: `Scrainee/Services/HotkeyManager.swift`
  - Removed: 5 legacy @deprecated notifications (.showQuickAsk, .showSearch, etc.)
  - Verified: ScraineeApp.swift uses new `.windowRequested` pattern
  - Updated: Dependency documentation header

- [x] **CLEAN-003: Remove ScraineeApp legacy methods** ✅
  - File: `Scrainee/App/ScraineeApp.swift`
  - Removed: 7 legacy wrapper methods (openQuickAskWindow, etc.)
  - Updated: Internal calls to use openWindow/closeWindow directly

- [x] **CLEAN-004: Replace print() with FileLogger (60+ occurrences)** ✅
  - Replaced 60+ print statements in 18 files:
    - ProcessTapAudioCapture.swift, AudioCaptureManager.swift
    - StartupCheckManager.swift, WhisperTranscriptionService.swift
    - MeetingDetector.swift, RetentionPolicy.swift
    - HotkeyManager.swift, PermissionManager.swift
    - ScraineeApp.swift, DisplayManager.swift, MeetingState.swift
    - ClaudeAPIClient.swift, MeetingMinutesGenerator.swift
    - ScreenCaptureManager.swift, AdminViewModel.swift
    - QuickAskView.swift, GalleryViewModel.swift, ContextOverlayView.swift
  - Added FileLogger.log(level:message:context:) method for StartupCheckManager

- [x] **CLEAN-005: Replace DispatchQueue.main with Task @MainActor** ✅
  - Replaced 4 asyncAfter calls with Task + Task.sleep:
    - ScraineeApp.swift: 2 asyncAfter (window positioning)
    - SettingsView.swift: 2 asyncAfter (delayed status updates)
  - Kept: ScraineeApp.swift:122 (WindowAccessorView) - standard NSViewRepresentable pattern

## 🟢 Low Priority / Optional (Phase 2: UI & Polish)

### Accessibility (No VoiceOver support currently)

- [x] **UI-001: MenuBarView accessibility** ✅
  - File: `Scrainee/UI/MenuBar/MenuBarView.swift`
  - Added accessibility to 15+ interactive elements:
    - Toggle button (Play/Pause) with dynamic labels
    - Status indicator with combined label
    - Permission buttons (Systemeinstellungen, Erneut prüfen)
    - MenuButton component with accessibilityHintText parameter
    - All 7 MenuButtons with specific hints
    - All 4 DisclosureGroups with expand/collapse hints
    - StatRow component with combined label
    - System status items with status text
    - Footer buttons (Einstellungen, Beenden)

- [ ] **UI-002: SettingsView accessibility**
  - File: `Sources/Scrainee/UI/Settings/SettingsView.swift`

- [ ] **UI-003: SearchView accessibility**
  - File: `Sources/Scrainee/UI/Search/SearchView.swift`

- [ ] **UI-004: TimelineView accessibility**
  - File: `Sources/Scrainee/UI/Timeline/TimelineView.swift`

- [ ] **UI-005: GalleryView accessibility**
  - File: `Sources/Scrainee/UI/Gallery/ScreenshotGalleryView.swift`

- [ ] **UI-006: QuickAskView accessibility**
  - File: `Sources/Scrainee/UI/QuickAsk/QuickAskView.swift`

### Code Organization

- [ ] **UI-007: Create shared components library**
  - Create: `Sources/Scrainee/UI/Components/`
  - Consolidate duplicates: `MenuButton`, `ActionButton`, `QuickOptionButton`

- [ ] **UI-008: Extract embedded ViewModels**
  - Move: `QuickAskViewModel` → `Sources/Scrainee/UI/QuickAsk/QuickAskViewModel.swift`
  - Move: `SummaryRequestViewModel` → `Sources/Scrainee/UI/Summary/SummaryRequestViewModel.swift`

- [ ] **UI-009: Create LayoutConstants.swift**
  - Create: `Sources/Scrainee/UI/Constants/LayoutConstants.swift`
  - Define: Common spacing, sizes, corner radii (replace magic numbers)

### Feature Completion

- [ ] **FEATURE-001: Export Manager UI integration**
  - File: `Sources/Scrainee/Core/Integration/ExportManager.swift`
  - Status: Code complete but no UI buttons
  - Add: Export buttons in GalleryView, SearchView, MeetingMinutesView

- [ ] **FEATURE-002: Complete SettingsValidator**
  - File: `Sources/Scrainee/Core/Utils/SettingsValidator.swift:185`
  - TODO: `meetingInterval: nil` - Settings export incomplete

## 🚀 Autonomous Features (Phase 3 - Ralph proposes these!)

<!-- Ralph will add autonomous feature proposals here when Phase 1+2 are complete -->
<!-- Format: - [ ] [AUTONOMOUS] Feature description - added by Ralph -->

## ✅ Completed

- [x] Project initialization (2024)
- [x] Screenshot-Capture with OCR
- [x] Meeting detection with user confirmation
- [x] Audio recording (ProcessTap on macOS 14.2+)
- [x] Real-time transcription (Whisper)
- [x] AI summaries (Claude)
- [x] Timeline view (Rewind-style)
- [x] Notion export
- [x] Database indexes for performance (4 indexes)
- [x] ThumbnailCache actor for Timeline
- [x] OCR Semaphore (max 4 parallel tasks)
- [x] WhisperKit auto-unload (5 min inactivity)
- [x] StorageManager caching (60s size cache)
- [x] PRD → Ralph conversion (PROMPT.md, @fix_plan.md, specs/requirements.md)
- [x] **FIX-001 to FIX-004**: All force-unwraps/force-casts fixed (2026-01-20)
- [x] **FIX-005 to FIX-007**: All error handling fixes completed (2026-01-20)
- [x] **CLEAN-001**: AppState backward-compatibility removed (2026-01-20)
- [x] **CLEAN-002**: HotkeyManager deprecated notifications removed (2026-01-20)
- [x] **CLEAN-003**: ScraineeApp legacy methods removed (2026-01-20)
- [x] **CLEAN-004**: 60+ print() statements replaced with FileLogger (2026-01-20)
- [x] **CLEAN-005**: DispatchQueue.main replaced with Task @MainActor (2026-01-20)
- [x] **TEST-006**: KeychainService tests (15 tests, all passing) (2026-01-20)
- [x] **TEST-004**: HotkeyManager tests (8 tests, all passing) (2026-01-20)
- [x] **TEST-005**: PermissionManager tests (13 tests, all passing) (2026-01-20)
- [x] **TEST-001**: WhisperTranscriptionService tests (21 tests, all passing) (2026-01-20)
- [x] **TEST-002**: MeetingDetector tests (29 tests, all passing) (2026-01-20)
- [x] **TEST-003**: ScreenCaptureManager tests (50 tests, all passing) (2026-01-21)
- [x] **UI-001**: MenuBarView accessibility (15+ elements with labels/hints) (2026-01-21)

## Notes

### Critical Dependency: App Initialization Order (NEVER CHANGE!)
```swift
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

### Known Limitations (Do NOT try to fix)
- ScreenCaptureKit Audio fallback (macOS 13-14.1) may produce silent audio
- Multi-Monitor uses sequential capture (Swift 6 Sendable constraint)
- Auto-Meeting-End disabled in `MeetingDetector.swift:57,327-329` (too unreliable)

### Positive Code Quality (Preserve these patterns)
- All ObservableObject classes correctly marked with `@MainActor`
- Excellent `[weak self]` usage (40+ correct cases)
- No empty catch blocks
- Actors for thread-safety (DatabaseManager, HashTracker, OCRSemaphore)

### Testing Philosophy
- Use `spec` parameter when creating mocks to validate method signatures
- Write integration tests for new API endpoints
- Focus on error cases (disk full, DB corruption, API timeouts)
- Target: 80% coverage for Core/ components

### File Locations
| Category | Path |
|----------|------|
| Entry Point | `Sources/Scrainee/App/ScraineeApp.swift` |
| State Management | `Sources/Scrainee/App/AppState.swift` |
| Sub-States | `Sources/Scrainee/App/State/*.swift` |
| Database | `Sources/Scrainee/Core/Database/DatabaseManager.swift` |
| Meeting Detection | `Sources/Scrainee/Core/Meeting/MeetingDetector.swift` |
| Audio Capture | `Sources/Scrainee/Core/Audio/ProcessTapAudioCapture.swift` |
| Transcription | `Sources/Scrainee/Core/Audio/WhisperTranscriptionService.swift` |
| AI Client | `Sources/Scrainee/Core/AI/ClaudeAPIClient.swift` |
| Tests | `Tests/ScraineeTests/` |
