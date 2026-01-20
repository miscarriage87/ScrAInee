// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - DEPENDENCY DOCUMENTATION
// ═══════════════════════════════════════════════════════════════════════════════
//
// FILE: AppState.swift
// PURPOSE: Zentraler App-State als Singleton ObservableObject. Koordiniert die
//          Sub-State-Objekte (CaptureState, MeetingState, SettingsState, UIState)
//          und reagiert auf System-Events wie Meeting-Erkennung.
// LAYER: App (oberste Schicht - orchestriert alle anderen Layer)
//
// ┌─────────────────────────────────────────────────────────────────────────────┐
// │ DEPENDENCIES (was diese Datei NUTZT)                                        │
// ├─────────────────────────────────────────────────────────────────────────────┤
// │ IMPORTS:                                                                    │
// │   • CaptureState             → App/State/CaptureState.swift                 │
// │   • MeetingState             → App/State/MeetingState.swift                 │
// │   • SettingsState            → App/State/SettingsState.swift                │
// │   • UIState                  → App/State/UIState.swift                      │
// │   • ScreenCaptureManager     → Core/ScreenCapture/ScreenCaptureManager.swift│
// │   • DatabaseManager.shared   → Core/Database/DatabaseManager.swift          │
// │   • WhisperTranscriptionService.shared → Core/Audio/WhisperTranscription... │
// │   • Screenshot (Model)       → Core/Database/Models/Screenshot.swift        │
// │   • MeetingSession (Model)   → Core/Meeting/MeetingDetector.swift           │
// │                                                                             │
// │ LISTENS TO (Notifications):                                                 │
// │   • .meetingStarted          → von MeetingDetector.swift                    │
// │   • .meetingEnded            → von MeetingDetector.swift                    │
// │                                                                             │
// │ PROTOCOLS IMPLEMENTED:                                                      │
// │   • ScreenCaptureManagerDelegate → Empfängt Screenshot-Callbacks            │
// └─────────────────────────────────────────────────────────────────────────────┘
//
// ┌─────────────────────────────────────────────────────────────────────────────┐
// │ DEPENDENTS (wer diese Datei NUTZT)                                          │
// ├─────────────────────────────────────────────────────────────────────────────┤
// │ USED BY (via AppState.shared oder @EnvironmentObject):                      │
// │   • ScraineeApp.swift        → StateObject Initialisierung                  │
// │   • MenuBarView.swift        → UI-State Binding                             │
// │   • SettingsView.swift       → Einstellungen lesen/schreiben                │
// │   • SearchView.swift         → Such-State                                   │
// │   • SummaryRequestView.swift → Summary-Generierung                          │
// │   • SummaryListView.swift    → Summary-Anzeige                              │
// │   • HotkeyManager.swift      → toggleCapture() aufrufen                     │
// │   • SettingsValidator.swift  → State-Validierung                            │
// │   • AdminViewModel.swift     → Admin-Funktionen                             │
// │   • ContextOverlayView.swift → Kontext-Overlay                              │
// │                                                                             │
// │ DEFINES:                                                                    │
// │   • Notification.Name.meetingStarted                                        │
// │   • Notification.Name.meetingEnded                                          │
// └─────────────────────────────────────────────────────────────────────────────┘
//
// ┌─────────────────────────────────────────────────────────────────────────────┐
// │ CHANGE IMPACT                                                               │
// ├─────────────────────────────────────────────────────────────────────────────┤
// │ • Sub-State-Objekte: Änderungen an CaptureState/MeetingState/etc.           │
// │ • Backward-Compatibility: Computed Properties leiten auf Sub-States um      │
// │ • initializeApp(): Reihenfolge kritisch (DB → Whisper → Capture → Meeting)  │
// │ • ScreenCaptureManagerDelegate: Callback-Signatur nicht ändern              │
// │ • Notification.Name Extensions: Von MeetingDetector, Coordinator genutzt    │
// └─────────────────────────────────────────────────────────────────────────────┘
//
// LAST UPDATED: 2026-01-20
// ═══════════════════════════════════════════════════════════════════════════════

import SwiftUI
import Combine

/// Central app state managed as a singleton ObservableObject
@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    // MARK: - Sub-State Objects

    /// State for screen capture related properties
    @Published var captureState = CaptureState()

    /// State for meeting related properties
    @Published var meetingState = MeetingState()

    /// State for persistent app settings
    @Published var settingsState = SettingsState()

    /// State for transient UI-related properties
    @Published var uiState = UIState()

    // MARK: - Backward Compatibility (wird nach vollständiger Migration entfernt)

    /// Whether screen capture is currently active
    var isCapturing: Bool {
        get { captureState.isCapturing }
        set { captureState.isCapturing = newValue }
    }

    /// Total number of screenshots taken this session
    var screenshotCount: Int {
        get { captureState.screenshotCount }
        set { captureState.screenshotCount = newValue }
    }

    /// Total screenshots in database
    var totalScreenshots: Int {
        get { captureState.totalScreenshots }
        set { captureState.totalScreenshots = newValue }
    }

    /// Current storage usage formatted string
    var storageUsed: String {
        get { captureState.storageUsed }
        set { captureState.storageUsed = newValue }
    }

    /// Timestamp of last screenshot
    var lastCaptureTime: Date? {
        get { captureState.lastCaptureTime }
        set { captureState.lastCaptureTime = newValue }
    }

    /// Current capture interval in seconds
    var captureInterval: Int {
        get { settingsState.captureInterval }
        set { settingsState.captureInterval = newValue }
    }

    /// Name of currently active application
    var currentApp: String {
        get { captureState.currentApp }
        set { captureState.currentApp = newValue }
    }

    /// Whether a meeting is currently detected
    var isMeetingActive: Bool {
        get { meetingState.isMeetingActive }
        set { meetingState.isMeetingActive = newValue }
    }

    /// Current meeting session if any
    var currentMeeting: MeetingSession? {
        get { meetingState.currentMeeting }
        set { meetingState.currentMeeting = newValue }
    }

    /// Show permission alert
    var showPermissionAlert: Bool {
        get { uiState.showPermissionAlert }
        set { uiState.showPermissionAlert = newValue }
    }

    /// Current summary being generated
    var isGeneratingSummary: Bool {
        get { meetingState.isGeneratingSummary }
        set { meetingState.isGeneratingSummary = newValue }
    }

    /// Last generated summary
    var lastSummary: Summary? {
        get { meetingState.lastSummary }
        set { meetingState.lastSummary = newValue }
    }

    /// Error message to display
    var errorMessage: String? {
        get { uiState.errorMessage }
        set { uiState.errorMessage = newValue }
    }

    // MARK: - Settings Backward Compatibility

    var storedCaptureInterval: Int {
        get { settingsState.captureInterval }
        set { settingsState.captureInterval = newValue }
    }

    var retentionDays: Int {
        get { settingsState.retentionDays }
        set { settingsState.retentionDays = newValue }
    }

    var ocrEnabled: Bool {
        get { settingsState.ocrEnabled }
        set { settingsState.ocrEnabled = newValue }
    }

    var meetingDetectionEnabled: Bool {
        get { settingsState.meetingDetectionEnabled }
        set { settingsState.meetingDetectionEnabled = newValue }
    }

    var launchAtLogin: Bool {
        get { settingsState.launchAtLogin }
        set { settingsState.launchAtLogin = newValue }
    }

    var heicQuality: Double {
        get { settingsState.heicQuality }
        set { settingsState.heicQuality = newValue }
    }

    var notionEnabled: Bool {
        get { settingsState.notionEnabled }
        set { settingsState.notionEnabled = newValue }
    }

    var notionAutoSync: Bool {
        get { settingsState.notionAutoSync }
        set { settingsState.notionAutoSync = newValue }
    }

    var autoStartCapture: Bool {
        get { settingsState.autoStartCapture }
        set { settingsState.autoStartCapture = newValue }
    }

    // MARK: - Private Properties

    private var screenCaptureManager: ScreenCaptureManager?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    private init() {
        setupManagers()
        setupNotifications()
        setupStateConnections()
    }

    /// Called after database is initialized
    func initializeApp() async {
        // 1. Initialize database first
        do {
            try await DatabaseManager.shared.initialize()
        } catch {
            return
        }

        await captureState.refreshStats()

        // 2. Auto-load Whisper model if already downloaded (BLOCKING await!)
        // WICHTIG: Das muss VOLLSTÄNDIG abgeschlossen sein bevor MeetingDetector startet
        let whisperService = WhisperTranscriptionService.shared
        let isDownloaded = whisperService.isModelDownloaded
        let isLoaded = whisperService.isModelLoaded

        if isDownloaded && !isLoaded {
            do {
                try await whisperService.loadModel()
            } catch {
                // Whisper model load failed - transcription will not be available
            }
        }

        // 3. CRITICAL: Sync whisperModelDownloaded flag with actual model state
        // This ensures MeetingTranscriptionCoordinator's guard condition passes
        let finalDownloadedState = whisperService.isModelDownloaded
        UserDefaults.standard.set(finalDownloadedState, forKey: "whisperModelDownloaded")

        // 4. Auto-start capture wenn aktiviert
        if settingsState.autoStartCapture {
            // Kurze Verzögerung für System-Bereitschaft
            try? await Task.sleep(nanoseconds: 300_000_000) // 0.3 Sekunden
            await captureState.startCapture()
        }
    }

    // MARK: - Setup

    private func setupManagers() {
        screenCaptureManager = ScreenCaptureManager()
        screenCaptureManager?.delegate = self

        // Connect CaptureState to ScreenCaptureManager
        captureState.screenCaptureManager = screenCaptureManager
        captureState.captureInterval = settingsState.captureInterval
    }

    private func setupNotifications() {
        // Meeting started
        NotificationCenter.default.publisher(for: .meetingStarted)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                if let meeting = notification.object as? MeetingSession {
                    Task { @MainActor in
                        await self?.meetingState.handleMeetingStarted(meeting)
                    }
                }
            }
            .store(in: &cancellables)

        // Meeting ended
        NotificationCenter.default.publisher(for: .meetingEnded)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                if let meeting = notification.object as? MeetingSession {
                    Task { @MainActor in
                        await self?.meetingState.handleMeetingEnded(meeting)
                    }
                }
            }
            .store(in: &cancellables)
    }

    private func setupStateConnections() {
        // Connect error handlers
        captureState.onPermissionRequired = { [weak self] in
            self?.uiState.showPermissionAlert = true
        }

        captureState.onError = { [weak self] message in
            self?.uiState.errorMessage = message
        }

        meetingState.onError = { [weak self] message in
            self?.uiState.errorMessage = message
        }

        // Connect meeting start to capture
        meetingState.onMeetingStarted = { [weak self] in
            guard let self = self else { return }
            if !self.captureState.isCapturing {
                await self.captureState.startCapture()
            }
        }

        // Sync settings to sub-states
        meetingState.meetingDetectionEnabled = settingsState.meetingDetectionEnabled
        meetingState.notionEnabled = settingsState.notionEnabled
        meetingState.notionAutoSync = settingsState.notionAutoSync

        // Observe settings changes and sync to sub-states
        settingsState.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.syncSettingsToSubStates()
            }
            .store(in: &cancellables)
    }

    private func syncSettingsToSubStates() {
        captureState.captureInterval = settingsState.captureInterval
        meetingState.meetingDetectionEnabled = settingsState.meetingDetectionEnabled
        meetingState.notionEnabled = settingsState.notionEnabled
        meetingState.notionAutoSync = settingsState.notionAutoSync
    }

    // MARK: - Capture Control (Backward Compatibility)

    func toggleCapture() {
        captureState.toggleCapture()
    }

    func startCapture() async {
        await captureState.startCapture()
    }

    func stopCapture() async {
        await captureState.stopCapture()
    }

    // MARK: - Stats (Backward Compatibility)

    func refreshStats() async {
        await captureState.refreshStats()
    }

    // MARK: - Permission Management (Backward Compatibility)

    func checkAndUpdatePermissions() async {
        await uiState.checkAndUpdatePermissions(
            isCapturing: captureState.isCapturing,
            stopCapture: { [weak self] in
                await self?.captureState.stopCapture()
            }
        )
    }

    // MARK: - Summary Generation (Backward Compatibility)

    func generateSummary(from startTime: Date, to endTime: Date) async {
        await meetingState.generateSummary(from: startTime, to: endTime)
    }

    /// Manually sync a meeting to Notion
    func syncCurrentMeetingToNotion() async {
        await meetingState.syncCurrentMeetingToNotion()
    }
}

// MARK: - ScreenCaptureManagerDelegate

extension AppState: ScreenCaptureManagerDelegate {
    nonisolated func screenCaptureManager(_ manager: ScreenCaptureManager, didCaptureScreenshot screenshot: Screenshot) {
        Task { @MainActor in
            captureState.handleScreenshotCaptured(screenshot)
        }
    }

    nonisolated func screenCaptureManager(_ manager: ScreenCaptureManager, didFailWithError error: Error) {
        Task { @MainActor in
            uiState.errorMessage = "Aufnahmefehler: \(error.localizedDescription)"
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let meetingStarted = Notification.Name("com.scrainee.meetingStarted")
    static let meetingEnded = Notification.Name("com.scrainee.meetingEnded")
    // captureIdleStateChanged is defined in AdaptiveCaptureManager.swift
}
