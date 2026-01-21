// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - 📋 DEPENDENCY DOCUMENTATION
// ═══════════════════════════════════════════════════════════════════════════════
//
// FILE: MeetingDetector.swift
// PURPOSE: Erkennt und überwacht Meeting-Anwendungen (Teams, Zoom, Webex, Google Meet).
//          Verwaltet den Meeting-Lebenszyklus mit Benutzer-Bestätigung für Start/Ende.
// LAYER: Core/Meeting
//
// ┌─────────────────────────────────────────────────────────────────────────────┐
// │ DEPENDENCIES (was diese Datei NUTZT)                                        │
// └─────────────────────────────────────────────────────────────────────────────┘
//
// IMPORTS:
//   - AppKit: NSWorkspace für App-Launch/Terminate-Überwachung, NSRunningApplication
//   - Combine: Publisher für @Published State
//
// DATABASE:
//   - DatabaseManager.shared: Meeting speichern/aktualisieren
//     - insert(Meeting)
//     - getActiveMeeting()
//     - update(Meeting)
//
// SYSTEM NOTIFICATIONS (gehört):
//   - NSWorkspace.didLaunchApplicationNotification: App gestartet
//   - NSWorkspace.didTerminateApplicationNotification: App beendet
//
// ACCESSIBILITY API:
//   - AXUIElement: Fenstertitel für Browser-Meeting-Erkennung
//   - Erfordert Accessibility-Berechtigung
//
// ┌─────────────────────────────────────────────────────────────────────────────┐
// │ DEPENDENTS (wer diese Datei NUTZT)                                          │
// └─────────────────────────────────────────────────────────────────────────────┘
//
// NOTIFICATIONS GESENDET:
//
//   .meetingDetectedAwaitingConfirmation (userInfo: appName, bundleId)
//     → MeetingIndicatorViewModel: Zeigt Start-Bestätigungs-Dialog
//     → ScraineeApp: Zeigt Meeting-Overlay
//     Wann: Meeting-App erkannt, wartet auf User-Bestätigung
//
//   .meetingStarted (object: MeetingSession)
//     → MeetingTranscriptionCoordinator: Startet Auto-Transkription
//     → AppState: Aktualisiert meetingActive State
//     → ScreenCaptureManager: Passt Capture-Intervall an
//     Wann: User bestätigt Meeting-Start NACHDEM DB-Eintrag erstellt
//
//   .meetingEnded (object: MeetingSession)
//     → MeetingTranscriptionCoordinator: Stoppt Transkription
//     → AppState: Aktualisiert meetingActive State
//     Wann: Meeting beendet (manuell oder App geschlossen)
//
//   .meetingEndConfirmationRequested (object: MeetingSession?)
//     → MeetingIndicatorViewModel: Zeigt Ende-Bestätigungs-Dialog
//     Wann: App denkt Meeting ist beendet, wartet auf Bestätigung
//     HINWEIS: Aktuell DEAKTIVIERT (nur manuelles Ende)
//
//   .meetingContinued (object: MeetingSession?)
//     → MeetingIndicatorViewModel: Schließt Ende-Dialog
//     Wann: User sagt "Meeting läuft noch"
//
//   .meetingStartDismissed (object: nil)
//     → MeetingIndicatorViewModel: Schließt Start-Dialog
//     Wann: User lehnt Meeting-Aufnahme ab (Snooze 5min)
//
// DIREKTE NUTZER:
//   - ScraineeApp.swift: startMonitoring() beim App-Start
//   - MeetingIndicatorViewModel.swift: confirmMeetingStart(), dismissMeetingStart(),
//                                       manuallyEndMeeting(), activeMeeting
//   - ContextOverlayView.swift: activeMeeting für Status-Anzeige
//
// STATE SYNCHRONISATION MIT APPSTATE:
//   - AppState.meetingActive wird via Notification.Name.meetingStarted/.meetingEnded gesetzt
//   - MeetingDetector.activeMeeting ist die Source of Truth für Meeting-Session
//   - MeetingIndicatorViewModel observiert MeetingDetector direkt
//
// ┌─────────────────────────────────────────────────────────────────────────────┐
// │ CHANGE IMPACT - KRITISCHE HINWEISE                                          │
// └─────────────────────────────────────────────────────────────────────────────┘
//
// WARNUNG: Änderungen an Notifications haben weitreichende Auswirkungen!
//
// 1. NOTIFICATION TIMING:
//    - .meetingStarted wird NACH DB-Insert gesendet (wichtig für Coordinator!)
//    - TranscriptionCoordinator hat Retry-Logik für getActiveMeeting()
//
// 2. SNOOZE-LOGIK:
//    - snoozedApps Dictionary mit 5-Minuten TTL
//    - Bei dismissMeetingStart() wird App temporär ignoriert
//
// 3. PENDING STATES:
//    - pendingStartConfirmation blockiert neue Meeting-Checks
//    - pendingEndConfirmation blockiert automatische Checks (aktuell unused)
//
// 4. THREAD-SAFETY:
//    - @MainActor für alle UI-relevanten Operationen
//    - NSWorkspace Notifications werden auf main queue dispatched
//
// LAST UPDATED: 2026-01-20
// ═══════════════════════════════════════════════════════════════════════════════

import AppKit
import Combine

/// Detects and monitors meeting applications
@MainActor
final class MeetingDetector: ObservableObject {
    static let shared = MeetingDetector()

    @Published private(set) var activeMeeting: MeetingSession?
    @Published private(set) var isMonitoring = false
    /// Zeigt an, ob eine Bestätigung für Meeting-Ende angefordert wurde
    @Published private(set) var pendingEndConfirmation = false

    // MARK: - Start Confirmation Properties

    /// Zeigt an, ob ein Meeting erkannt wurde und auf Benutzer-Bestätigung wartet
    @Published private(set) var pendingStartConfirmation = false
    /// Name der erkannten Meeting-App (für UI-Anzeige)
    @Published private(set) var detectedMeetingAppName: String?
    /// Bundle-ID der erkannten Meeting-App
    @Published private(set) var detectedMeetingBundleId: String?

    private var appLaunchObserver: NSObjectProtocol?
    private var appTerminateObserver: NSObjectProtocol?
    private var checkTimer: Timer?
    private var currentMeetingStartTime: Date?
    private var cancellables = Set<AnyCancellable>()
    /// Counter für aufeinanderfolgende "Meeting nicht gefunden" Checks
    private var notFoundCounter = 0
    /// Anzahl der Checks bevor Bestätigung angefordert wird
    private let confirmationThreshold = 2

    /// Snooze-Liste: Bundle-IDs die temporär ignoriert werden (mit Zeitstempel)
    private var snoozedApps: [String: Date] = [:]
    /// Snooze-Dauer in Sekunden (5 Minuten)
    private let snoozeDuration: TimeInterval = 300

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

    // Meeting-related URLs in browser window titles (nur spezifische Meeting-Plattformen)
    private let meetingURLPatterns = [
        "meet.google.com",
        "teams.microsoft.com",
        "teams.live.com",
        "zoom.us/j/",
        "zoom.us/wc/",
        "webex.com/meet",
        "webex.com/join"
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

        FileLogger.shared.info("Meeting detector started", context: "MeetingDetector")
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
        FileLogger.shared.info("Meeting detector stopped", context: "MeetingDetector")
    }

    // MARK: - Event Handlers

    private func handleAppLaunch(bundleIdentifier: String?) {
        guard let bundleId = bundleIdentifier else { return }

        if meetingApps.keys.contains(bundleId) {
            FileLogger.shared.info("Meeting app launched: \(bundleId)", context: "MeetingDetector")
            // Check immediately for meeting status
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(2))
                self?.checkForMeetings()
            }
        }
    }

    private func handleAppTerminate(bundleIdentifier: String?) {
        guard let bundleId = bundleIdentifier else { return }

        // If pending start confirmation for this app, cancel it
        if pendingStartConfirmation && detectedMeetingBundleId == bundleId {
            pendingStartConfirmation = false
            detectedMeetingAppName = nil
            detectedMeetingBundleId = nil
            NotificationCenter.default.post(name: .meetingStartDismissed, object: nil)
        }

        // If the meeting app terminated, end the meeting
        if let meeting = activeMeeting, meeting.bundleId == bundleId {
            endMeetingSession()
        }
    }

    // MARK: - Meeting Detection

    private func checkForMeetings() {
        // Wenn Bestätigung pending ist, keine automatischen Checks durchführen
        guard !pendingEndConfirmation else { return }

        // Wenn bereits eine Start-Bestätigung pending ist, nicht erneut fragen
        guard !pendingStartConfirmation else { return }

        let runningApps = NSWorkspace.shared.runningApplications
        var meetingFound = false

        for app in runningApps {
            guard let bundleId = app.bundleIdentifier else { continue }

            // Skip snoozed apps
            if isAppSnoozed(bundleId) {
                continue
            }

            // Check native meeting apps
            if let appName = meetingApps[bundleId], !browserBundleIds.contains(bundleId) {
                if isMeetingActive(app: app) {
                    // Wenn bereits ein Meeting aktiv ist für diese App, nichts tun
                    if let existing = activeMeeting, existing.bundleId == bundleId {
                        meetingFound = true
                        notFoundCounter = 0
                        return
                    }
                    // Ansonsten: Bestätigung anfordern statt direkt starten
                    requestStartConfirmation(app: appName, bundleId: bundleId)
                    return
                }
            }

            // Check browsers for Google Meet, etc.
            if browserBundleIds.contains(bundleId) {
                if let windowTitle = getWindowTitle(for: app),
                   isMeetingWindowTitle(windowTitle) {
                    let appName = detectMeetingApp(from: windowTitle)
                    // Wenn bereits ein Meeting aktiv ist für diese App, nichts tun
                    if let existing = activeMeeting, existing.bundleId == bundleId {
                        meetingFound = true
                        notFoundCounter = 0
                        return
                    }
                    // Ansonsten: Bestätigung anfordern statt direkt starten
                    requestStartConfirmation(app: appName, bundleId: bundleId)
                    return
                }
            }
        }

        // Meeting-Ende wird NUR manuell durch den Benutzer ausgelöst
        // Die automatische Erkennung war zu unzuverlässig (Fokus-Wechsel etc.)
        // Daher: Keine automatische "Meeting beendet?"-Nachfrage mehr
    }

    // MARK: - Manual Control

    /// Beendet das Meeting sofort und manuell (ohne Bestätigung)
    func manuallyEndMeeting() {
        pendingEndConfirmation = false
        notFoundCounter = 0
        endMeetingSession()
    }

    /// Fordert eine Bestätigung vom User an, ob das Meeting wirklich beendet ist
    private func requestEndConfirmation() {
        guard !pendingEndConfirmation else { return }

        pendingEndConfirmation = true

        // Notification an UI senden
        NotificationCenter.default.post(name: .meetingEndConfirmationRequested, object: activeMeeting)
    }

    /// User bestätigt: Meeting ist wirklich beendet
    func confirmMeetingEnded() {
        pendingEndConfirmation = false
        notFoundCounter = 0
        endMeetingSession()
    }

    /// User sagt: Meeting läuft noch weiter
    func continueMeeting() {
        pendingEndConfirmation = false
        notFoundCounter = 0

        // Notification dass Meeting fortgesetzt wird
        NotificationCenter.default.post(name: .meetingContinued, object: activeMeeting)
    }

    // MARK: - Start Confirmation

    /// Fordert eine Bestätigung vom User an, ob das Meeting aufgenommen werden soll
    private func requestStartConfirmation(app: String, bundleId: String) {
        guard !pendingStartConfirmation else { return }

        pendingStartConfirmation = true
        detectedMeetingAppName = app
        detectedMeetingBundleId = bundleId

        // Notification an UI senden
        NotificationCenter.default.post(name: .meetingDetectedAwaitingConfirmation, object: nil,
                                        userInfo: ["appName": app, "bundleId": bundleId])
    }

    /// User bestätigt: Meeting soll aufgenommen werden
    func confirmMeetingStart() {
        guard pendingStartConfirmation,
              let appName = detectedMeetingAppName,
              let bundleId = detectedMeetingBundleId else {
            return
        }

        pendingStartConfirmation = false
        let savedAppName = appName
        let savedBundleId = bundleId
        detectedMeetingAppName = nil
        detectedMeetingBundleId = nil

        // Jetzt tatsächlich das Meeting starten
        startMeetingSession(app: savedAppName, bundleId: savedBundleId)
    }

    /// User lehnt Meeting-Aufnahme ab - App wird für X Minuten ignoriert
    func dismissMeetingStart() {
        guard let bundleId = detectedMeetingBundleId else { return }

        pendingStartConfirmation = false
        snoozedApps[bundleId] = Date()
        detectedMeetingAppName = nil
        detectedMeetingBundleId = nil

        NotificationCenter.default.post(name: .meetingStartDismissed, object: nil)
    }

    /// Prüft ob eine App in der Snooze-Liste ist (und ob Snooze abgelaufen)
    private func isAppSnoozed(_ bundleId: String) -> Bool {
        guard let snoozeTime = snoozedApps[bundleId] else { return false }
        let elapsed = Date().timeIntervalSince(snoozeTime)
        if elapsed > snoozeDuration {
            snoozedApps.removeValue(forKey: bundleId)
            return false
        }
        return true
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

        // Nur spezifische Meeting-URLs erkennen (keine generischen Keywords)
        for urlPattern in meetingURLPatterns {
            if lowercased.contains(urlPattern.lowercased()) {
                return true
            }
        }

        return false
    }

    private func detectMeetingApp(from windowTitle: String) -> String {
        let lowercased = windowTitle.lowercased()

        if lowercased.contains("meet.google.com") {
            return "Google Meet"
        }

        if lowercased.contains("teams.microsoft.com") || lowercased.contains("teams.live.com") {
            return "Microsoft Teams (Web)"
        }

        if lowercased.contains("zoom.us") {
            return "Zoom (Web)"
        }

        if lowercased.contains("webex.com") {
            return "Webex (Web)"
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

        FileLogger.shared.info("Meeting started: \(app)", context: "MeetingDetector")

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

        FileLogger.shared.info("Meeting ended: \(meeting.appName), duration: \(meeting.durationMinutes) minutes", context: "MeetingDetector")

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
            FileLogger.shared.error("Failed to save meeting: \(error)", context: "MeetingDetector")
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
            FileLogger.shared.error("Failed to update meeting: \(error)", context: "MeetingDetector")
        }
    }
}

// MARK: - Notifications

extension Notification.Name {
    /// Wird gepostet wenn die App denkt, dass ein Meeting beendet ist und Bestätigung vom User erfordert
    static let meetingEndConfirmationRequested = Notification.Name("meetingEndConfirmationRequested")
    /// Wird gepostet wenn der User bestätigt, dass das Meeting noch läuft
    static let meetingContinued = Notification.Name("meetingContinued")
    /// Wird gepostet wenn ein Meeting erkannt wurde und auf Benutzer-Bestätigung wartet
    static let meetingDetectedAwaitingConfirmation = Notification.Name("meetingDetectedAwaitingConfirmation")
    /// Wird gepostet wenn der User die Meeting-Aufnahme abgelehnt hat
    static let meetingStartDismissed = Notification.Name("meetingStartDismissed")
}
