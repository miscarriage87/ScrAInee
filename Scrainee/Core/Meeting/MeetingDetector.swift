import AppKit
import Combine

/// Detects and monitors meeting applications
@MainActor
final class MeetingDetector: ObservableObject {
    static let shared = MeetingDetector()

    @Published private(set) var activeMeeting: MeetingSession?
    @Published private(set) var isMonitoring = false

    private var appLaunchObserver: NSObjectProtocol?
    private var appTerminateObserver: NSObjectProtocol?
    private var checkTimer: Timer?
    private var currentMeetingStartTime: Date?
    private var cancellables = Set<AnyCancellable>()

    // Known meeting applications
    private let meetingApps: [String: String] = [
        "com.microsoft.teams": "Microsoft Teams",
        "com.microsoft.teams2": "Microsoft Teams",
        "us.zoom.xos": "Zoom",
        "com.cisco.webexmeetingsapp": "Webex",
        "com.cisco.webex.meetings": "Webex",
        "com.google.Chrome": "Google Meet",  // Requires window title check
        "com.apple.Safari": "Google Meet",    // Requires window title check
        "com.microsoft.edgemac": "Google Meet", // Requires window title check
        "com.brave.Browser": "Google Meet"    // Requires window title check
    ]

    // Browser apps that might host meetings
    private let browserBundleIds = [
        "com.google.Chrome",
        "com.apple.Safari",
        "com.microsoft.edgemac",
        "com.brave.Browser",
        "org.mozilla.firefox"
    ]

    // Meeting-related keywords in window titles
    private let meetingKeywords = [
        "meet.google.com",
        "Meeting",
        "Besprechung",
        "Call",
        "Anruf",
        "Video"
    ]

    private init() {}

    // MARK: - Monitoring Control

    /// Starts monitoring for meeting applications
    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true

        // Observe app launches
        appLaunchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            // Extract app info before task to avoid Sendable issues
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let bundleId = app?.bundleIdentifier
            Task { @MainActor [weak self] in
                self?.handleAppLaunch(bundleIdentifier: bundleId)
            }
        }

        // Observe app terminations
        appTerminateObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            // Extract app info before task to avoid Sendable issues
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let bundleId = app?.bundleIdentifier
            Task { @MainActor [weak self] in
                self?.handleAppTerminate(bundleIdentifier: bundleId)
            }
        }

        // Start periodic check
        checkTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkForMeetings()
            }
        }

        // Initial check
        checkForMeetings()

        print("Meeting detector started")
    }

    /// Stops monitoring
    func stopMonitoring() {
        guard isMonitoring else { return }

        if let observer = appLaunchObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        if let observer = appTerminateObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }

        checkTimer?.invalidate()
        checkTimer = nil

        isMonitoring = false
        print("Meeting detector stopped")
    }

    // MARK: - Event Handlers

    private func handleAppLaunch(bundleIdentifier: String?) {
        guard let bundleId = bundleIdentifier else { return }

        if meetingApps.keys.contains(bundleId) {
            print("Meeting app launched: \(bundleId)")
            // Check immediately for meeting status
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(2))
                self?.checkForMeetings()
            }
        }
    }

    private func handleAppTerminate(bundleIdentifier: String?) {
        guard let bundleId = bundleIdentifier else { return }

        // If the meeting app terminated, end the meeting
        if let meeting = activeMeeting, meeting.bundleId == bundleId {
            endMeetingSession()
        }
    }

    // MARK: - Meeting Detection

    private func checkForMeetings() {
        let runningApps = NSWorkspace.shared.runningApplications

        for app in runningApps {
            guard let bundleId = app.bundleIdentifier else { continue }

            // Check native meeting apps
            if let appName = meetingApps[bundleId], !browserBundleIds.contains(bundleId) {
                if isMeetingActive(app: app) {
                    startMeetingSession(app: appName, bundleId: bundleId)
                    return
                }
            }

            // Check browsers for Google Meet, etc.
            if browserBundleIds.contains(bundleId) {
                if let windowTitle = getWindowTitle(for: app),
                   isMeetingWindowTitle(windowTitle) {
                    let appName = detectMeetingApp(from: windowTitle)
                    startMeetingSession(app: appName, bundleId: bundleId)
                    return
                }
            }
        }

        // No meeting detected
        if activeMeeting != nil {
            endMeetingSession()
        }
    }

    private func isMeetingActive(app: NSRunningApplication) -> Bool {
        // Heuristics for detecting active meeting:
        // 1. App is active or owns menu bar
        // 2. Check window title for meeting indicators
        // 3. (Future) Check for camera/microphone usage

        guard app.activationPolicy == .regular else { return false }

        // Check if app is frontmost or recently active
        if app.isActive {
            return true
        }

        // Check window title for meeting indicators
        if let windowTitle = getWindowTitle(for: app) {
            return isMeetingWindowTitle(windowTitle)
        }

        return false
    }

    private func isMeetingWindowTitle(_ title: String) -> Bool {
        let lowercased = title.lowercased()

        for keyword in meetingKeywords {
            if lowercased.contains(keyword.lowercased()) {
                return true
            }
        }

        return false
    }

    private func detectMeetingApp(from windowTitle: String) -> String {
        let lowercased = windowTitle.lowercased()

        if lowercased.contains("meet.google.com") || lowercased.contains("google meet") {
            return "Google Meet"
        }

        if lowercased.contains("teams") {
            return "Microsoft Teams"
        }

        if lowercased.contains("zoom") {
            return "Zoom"
        }

        return "Video Meeting"
    }

    // MARK: - Window Title (Accessibility API)

    private func getWindowTitle(for app: NSRunningApplication) -> String? {
        // Note: Requires Accessibility permission

        let appElement = AXUIElementCreateApplication(app.processIdentifier)

        var windowsRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)

        guard result == .success,
              let windows = windowsRef as? [AXUIElement],
              let firstWindow = windows.first else {
            return nil
        }

        var titleRef: CFTypeRef?
        let titleResult = AXUIElementCopyAttributeValue(firstWindow, kAXTitleAttribute as CFString, &titleRef)

        guard titleResult == .success, let title = titleRef as? String else {
            return nil
        }

        return title
    }

    // MARK: - Meeting Session Management

    private func startMeetingSession(app: String, bundleId: String) {
        // Don't start a new session if one is already active for the same app
        if let existing = activeMeeting, existing.bundleId == bundleId {
            return
        }

        let session = MeetingSession(
            appName: app,
            bundleId: bundleId,
            startTime: Date()
        )

        activeMeeting = session
        currentMeetingStartTime = Date()

        print("Meeting started: \(app)")

        // Save to database FIRST, then notify
        Task {
            await saveMeetingToDatabase(session)
            // Notify AFTER save completed so TranscriptionCoordinator can find the meeting
            await MainActor.run {
                NotificationCenter.default.post(name: .meetingStarted, object: session)
            }
        }
    }

    private func endMeetingSession() {
        guard var meeting = activeMeeting else { return }

        meeting.endTime = Date()

        print("Meeting ended: \(meeting.appName), duration: \(meeting.durationMinutes) minutes")

        // Notify
        NotificationCenter.default.post(name: .meetingEnded, object: meeting)

        // Update database
        Task {
            await updateMeetingInDatabase(meeting)
        }

        activeMeeting = nil
        currentMeetingStartTime = nil
    }

    // MARK: - Database Operations

    private func saveMeetingToDatabase(_ session: MeetingSession) async {
        let meeting = Meeting(
            appBundleId: session.bundleId,
            appName: session.appName,
            startTime: session.startTime,
            status: .active,
            transcriptionStatus: .notStarted
        )

        do {
            _ = try await DatabaseManager.shared.insert(meeting)
        } catch {
            print("Failed to save meeting: \(error)")
        }
    }

    private func updateMeetingInDatabase(_ session: MeetingSession) async {
        do {
            if var meeting = try await DatabaseManager.shared.getActiveMeeting() {
                meeting.endTime = session.endTime
                meeting.durationSeconds = Int(session.duration ?? 0)
                meeting.status = .completed
                try await DatabaseManager.shared.update(meeting)
            }
        } catch {
            print("Failed to update meeting: \(error)")
        }
    }
}
