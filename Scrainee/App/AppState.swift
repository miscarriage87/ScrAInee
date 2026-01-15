import SwiftUI
import Combine

/// Central app state managed as a singleton ObservableObject
@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    // MARK: - Published Properties

    /// Whether screen capture is currently active
    @Published var isCapturing = false

    /// Total number of screenshots taken this session
    @Published var screenshotCount = 0

    /// Total screenshots in database
    @Published var totalScreenshots = 0

    /// Current storage usage formatted string
    @Published var storageUsed: String = "0 MB"

    /// Timestamp of last screenshot
    @Published var lastCaptureTime: Date?

    /// Current capture interval in seconds
    @Published var captureInterval: Int = 3

    /// Name of currently active application
    @Published var currentApp: String = ""

    /// Whether a meeting is currently detected
    @Published var isMeetingActive = false

    /// Current meeting session if any
    @Published var currentMeeting: MeetingSession?

    /// Show permission alert
    @Published var showPermissionAlert = false

    /// Current summary being generated
    @Published var isGeneratingSummary = false

    /// Last generated summary
    @Published var lastSummary: Summary?

    /// Error message to display
    @Published var errorMessage: String?

    // MARK: - Settings

    @AppStorage("captureInterval") var storedCaptureInterval: Int = 3
    @AppStorage("retentionDays") var retentionDays: Int = 30
    @AppStorage("ocrEnabled") var ocrEnabled: Bool = true
    @AppStorage("meetingDetectionEnabled") var meetingDetectionEnabled: Bool = true
    @AppStorage("launchAtLogin") var launchAtLogin: Bool = false
    @AppStorage("heicQuality") var heicQuality: Double = 0.6
    @AppStorage("notionEnabled") var notionEnabled: Bool = false
    @AppStorage("notionAutoSync") var notionAutoSync: Bool = true
    @AppStorage("autoStartCapture") var autoStartCapture: Bool = true

    // MARK: - Private Properties

    private var screenCaptureManager: ScreenCaptureManager?
    private var cancellables = Set<AnyCancellable>()

    /// Current meeting database ID for tracking
    private var currentMeetingDbId: Int64?

    // MARK: - Initialization

    private init() {
        captureInterval = storedCaptureInterval
        setupManagers()
        setupNotifications()
        // Hinweis: Auto-Start und Stats werden erst nach DB-Initialisierung in initializeApp() aufgerufen
    }

    /// Called after database is initialized
    func initializeApp() async {
        // Initialize database first
        do {
            try await DatabaseManager.shared.initialize()
            print("[DEBUG] Datenbank erfolgreich initialisiert")
        } catch {
            print("[ERROR] Datenbank-Initialisierung fehlgeschlagen: \(error)")
            return
        }

        await refreshStats()

        // Auto-start capture wenn aktiviert
        if autoStartCapture {
            await startCapture()
        }
    }

    // MARK: - Setup

    private func setupManagers() {
        screenCaptureManager = ScreenCaptureManager()
        screenCaptureManager?.delegate = self
    }

    private func setupNotifications() {
        // Meeting started
        NotificationCenter.default.publisher(for: .meetingStarted)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                if let meeting = notification.object as? MeetingSession {
                    self?.handleMeetingStarted(meeting)
                }
            }
            .store(in: &cancellables)

        // Meeting ended
        NotificationCenter.default.publisher(for: .meetingEnded)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                if let meeting = notification.object as? MeetingSession {
                    self?.handleMeetingEnded(meeting)
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Capture Control

    func toggleCapture() {
        if isCapturing {
            Task { await stopCapture() }
        } else {
            Task { await startCapture() }
        }
    }

    func startCapture() async {
        guard !isCapturing else { return }

        // Check permission first
        let permissionManager = PermissionManager.shared
        var hasPermission = await permissionManager.checkScreenCapturePermission()
        
        if !hasPermission {
            // Try to request permission
            hasPermission = await permissionManager.requestScreenCapturePermission()
        }
        
        guard hasPermission else {
            showPermissionAlert = true
            return
        }

        do {
            try await screenCaptureManager?.startCapturing(interval: TimeInterval(captureInterval))
            isCapturing = true
            screenshotCount = 0
            // Clear permission alert if capture starts successfully
            showPermissionAlert = false
        } catch {
            errorMessage = "Aufnahme konnte nicht gestartet werden: \(error.localizedDescription)"
        }
    }

    func stopCapture() async {
        guard isCapturing else { return }

        screenCaptureManager?.stopCapturing()
        isCapturing = false
    }

    // MARK: - Stats

    func refreshStats() async {
        do {
            // Try to initialize database if not already done
            try await DatabaseManager.shared.initialize()
            totalScreenshots = try await DatabaseManager.shared.getScreenshotCount()
            storageUsed = StorageManager.shared.formattedStorageUsed
        } catch {
            // Silently ignore if database not ready yet - will be initialized by AppDelegate
            storageUsed = StorageManager.shared.formattedStorageUsed
        }
    }
    
    // MARK: - Permission Management
    
    func checkAndUpdatePermissions() async {
        let hasPermission = await PermissionManager.shared.checkScreenCapturePermission()
        if hasPermission && showPermissionAlert {
            showPermissionAlert = false
        } else if !hasPermission && isCapturing {
            // Stop capture if permission was revoked
            await stopCapture()
            showPermissionAlert = true
        }
    }

    // MARK: - Meeting Handling

    private func handleMeetingStarted(_ meeting: MeetingSession) {
        guard meetingDetectionEnabled else { return }

        isMeetingActive = true
        currentMeeting = meeting

        // Auto-start capture if not already running
        if !isCapturing {
            Task {
                await startCapture()
            }
        }

        // Save meeting to database
        Task {
            await saveMeetingToDatabase(meeting)
        }
    }

    private func handleMeetingEnded(_ meeting: MeetingSession) {
        isMeetingActive = false
        let endTime = Date()

        // Generate summary for meeting and sync to Notion
        if let startTime = currentMeeting?.startTime {
            Task {
                // Update meeting end time in database
                await updateMeetingEndTime(endTime: endTime)

                // Generate summary
                await generateSummary(from: startTime, to: endTime)

                // Sync to Notion if enabled
                if notionEnabled && notionAutoSync, let summary = lastSummary {
                    await syncMeetingToNotion(meeting: meeting, summary: summary)
                }
            }
        }

        currentMeeting = nil
        currentMeetingDbId = nil
    }

    // MARK: - Meeting Database Operations

    private func saveMeetingToDatabase(_ meeting: MeetingSession) async {
        do {
            let dbMeeting = Meeting(
                id: nil,
                appBundleId: meeting.bundleId,
                appName: meeting.appName,
                startTime: meeting.startTime,
                endTime: nil,
                durationSeconds: nil,
                screenshotCount: nil,
                transcript: nil,
                aiSummary: nil,
                notionPageId: nil,
                notionPageUrl: nil,
                status: .active,
                createdAt: nil
            )
            currentMeetingDbId = try await DatabaseManager.shared.insert(dbMeeting)
        } catch {
            print("Failed to save meeting to database: \(error)")
        }
    }

    private func updateMeetingEndTime(endTime: Date) async {
        guard let meetingId = currentMeetingDbId else { return }

        do {
            if var meeting = try await DatabaseManager.shared.getMeeting(id: meetingId) {
                meeting.endTime = endTime
                if let startTime = meeting.startTime as Date? {
                    meeting.durationSeconds = Int(endTime.timeIntervalSince(startTime))
                }
                meeting.screenshotCount = try await DatabaseManager.shared.getScreenshotCountForMeeting(meetingId: meetingId)
                meeting.status = .completed
                try await DatabaseManager.shared.update(meeting)
            }
        } catch {
            print("Failed to update meeting end time: \(error)")
        }
    }

    // MARK: - Notion Integration

    private func syncMeetingToNotion(meeting: MeetingSession, summary: Summary) async {
        guard let meetingId = currentMeetingDbId else { return }

        let notionClient = NotionClient()

        // Check if Notion is configured
        guard notionClient.isConfigured else {
            errorMessage = "Notion nicht konfiguriert. Bitte API Key und Database ID in den Einstellungen eingeben."
            return
        }

        do {
            // Get screenshot count for this meeting
            let screenshotCount = try await DatabaseManager.shared.getScreenshotCountForMeeting(meetingId: meetingId)

            // Create Notion page
            let notionPage = try await notionClient.createMeetingPage(
                meeting: meeting,
                summary: summary.content,
                screenshotCount: screenshotCount
            )

            // Update meeting in database with Notion link
            try await DatabaseManager.shared.updateMeetingNotionLink(
                meetingId: meetingId,
                pageId: notionPage.id,
                pageUrl: notionPage.url
            )

            print("Meeting successfully synced to Notion: \(notionPage.url)")
        } catch {
            errorMessage = "Notion Sync fehlgeschlagen: \(error.localizedDescription)"
        }
    }

    /// Manually sync a meeting to Notion
    func syncCurrentMeetingToNotion() async {
        guard let meeting = currentMeeting, let summary = lastSummary else {
            errorMessage = "Kein Meeting oder Zusammenfassung verfuegbar"
            return
        }

        await syncMeetingToNotion(meeting: meeting, summary: summary)
    }

    // MARK: - Summary Generation

    func generateSummary(from startTime: Date, to endTime: Date) async {
        guard !isGeneratingSummary else { return }

        isGeneratingSummary = true
        defer { isGeneratingSummary = false }

        do {
            let generator = SummaryGenerator()
            let summary = try await generator.generateSummary(from: startTime, to: endTime)
            lastSummary = summary
        } catch {
            errorMessage = "Zusammenfassung konnte nicht erstellt werden: \(error.localizedDescription)"
        }
    }
}

// MARK: - ScreenCaptureManagerDelegate

extension AppState: ScreenCaptureManagerDelegate {
    nonisolated func screenCaptureManager(_ manager: ScreenCaptureManager, didCaptureScreenshot screenshot: Screenshot) {
        Task { @MainActor in
            screenshotCount += 1
            totalScreenshots += 1
            lastCaptureTime = screenshot.timestamp
            currentApp = screenshot.appName ?? ""
        }
    }

    nonisolated func screenCaptureManager(_ manager: ScreenCaptureManager, didFailWithError error: Error) {
        Task { @MainActor in
            errorMessage = "Aufnahmefehler: \(error.localizedDescription)"
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let meetingStarted = Notification.Name("com.scrainee.meetingStarted")
    static let meetingEnded = Notification.Name("com.scrainee.meetingEnded")
    // captureIdleStateChanged is defined in AdaptiveCaptureManager.swift
}
