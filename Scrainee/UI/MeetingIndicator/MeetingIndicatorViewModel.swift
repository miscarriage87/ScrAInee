// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - 📋 DEPENDENCY DOCUMENTATION
// ═══════════════════════════════════════════════════════════════════════════════
//
// FILE: MeetingIndicatorViewModel.swift | PURPOSE: State-Management für Meeting-Indikator | LAYER: UI/MeetingIndicator
//
// DEPENDENCIES: MeetingDetector, MeetingSession
// DEPENDENTS: MeetingIndicatorView
// LISTENS TO: .meetingStarted, .meetingEnded, .meetingEndConfirmationRequested, .meetingContinued, .meetingDetectedAwaitingConfirmation, .meetingStartDismissed (NotificationCenter)
// CHANGE IMPACT: KRITISCH - Koordiniert Meeting-Lifecycle-UI, Start/Ende-Bestätigungen, Duration-Timer
//
// LAST UPDATED: 2026-01-20
// ═══════════════════════════════════════════════════════════════════════════════

import SwiftUI
import Combine

/// ViewModel für den Floating Meeting-Indikator
@MainActor
final class MeetingIndicatorViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var isRecording = false
    @Published var meetingAppName = ""
    @Published var meetingBundleId = ""
    @Published var duration = "00:00"
    @Published var showEndConfirmation = false

    // MARK: - Start Confirmation Properties

    /// Zeigt den Start-Bestätigungs-Dialog an (Meeting erkannt, noch nicht gestartet)
    @Published var showStartConfirmation = false
    /// Name der erkannten App für Start-Bestätigung
    @Published var pendingMeetingAppName: String?

    // MARK: - Private Properties

    private var durationTimer: Timer?
    private var startTime: Date?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init() {
        setupObservers()
        updateFromCurrentState()
    }

    /// Invalidates the timer - must be called before deallocation
    func cleanup() {
        durationTimer?.invalidate()
        durationTimer = nil
    }

    // MARK: - Setup

    private func setupObservers() {
        // Meeting gestartet
        NotificationCenter.default.publisher(for: .meetingStarted)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                if let meeting = notification.object as? MeetingSession {
                    self?.handleMeetingStarted(meeting)
                }
            }
            .store(in: &cancellables)

        // Meeting beendet
        NotificationCenter.default.publisher(for: .meetingEnded)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleMeetingEnded()
            }
            .store(in: &cancellables)

        // Bestätigung angefordert
        NotificationCenter.default.publisher(for: .meetingEndConfirmationRequested)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.showEndConfirmation = true
            }
            .store(in: &cancellables)

        // Meeting fortgesetzt
        NotificationCenter.default.publisher(for: .meetingContinued)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.showEndConfirmation = false
            }
            .store(in: &cancellables)

        // Meeting erkannt - wartet auf Bestätigung
        NotificationCenter.default.publisher(for: .meetingDetectedAwaitingConfirmation)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.handleMeetingDetected(notification)
            }
            .store(in: &cancellables)

        // Meeting-Start abgelehnt
        NotificationCenter.default.publisher(for: .meetingStartDismissed)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.showStartConfirmation = false
                self?.pendingMeetingAppName = nil
            }
            .store(in: &cancellables)
    }

    private func updateFromCurrentState() {
        let detector = MeetingDetector.shared

        // Prüfe auf pending Start-Bestätigung
        if detector.pendingStartConfirmation {
            pendingMeetingAppName = detector.detectedMeetingAppName
            showStartConfirmation = true
        }

        // Prüfe auf aktives Meeting
        if let meeting = detector.activeMeeting {
            handleMeetingStarted(meeting)
        }
        showEndConfirmation = detector.pendingEndConfirmation
    }

    // MARK: - Event Handlers

    private func handleMeetingStarted(_ meeting: MeetingSession) {
        isRecording = true
        meetingAppName = meeting.appName
        meetingBundleId = meeting.bundleId
        startTime = meeting.startTime
        showEndConfirmation = false

        startDurationTimer()
    }

    private func handleMeetingEnded() {
        isRecording = false
        showEndConfirmation = false
        stopDurationTimer()
    }

    /// Behandelt Meeting-Erkennung (noch nicht gestartet, wartet auf Bestätigung)
    private func handleMeetingDetected(_ notification: Notification) {
        let appName = notification.userInfo?["appName"] as? String
        pendingMeetingAppName = appName ?? MeetingDetector.shared.detectedMeetingAppName
        showStartConfirmation = true
    }

    // MARK: - Duration Timer

    private func startDurationTimer() {
        durationTimer?.invalidate()
        updateDuration()

        durationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateDuration()
            }
        }
    }

    private func stopDurationTimer() {
        durationTimer?.invalidate()
        durationTimer = nil
    }

    private func updateDuration() {
        guard let start = startTime else {
            duration = "00:00"
            return
        }

        let elapsed = Date().timeIntervalSince(start)
        let hours = Int(elapsed) / 3600
        let minutes = (Int(elapsed) % 3600) / 60
        let seconds = Int(elapsed) % 60

        if hours > 0 {
            duration = String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            duration = String(format: "%02d:%02d", minutes, seconds)
        }
    }

    // MARK: - Actions

    /// Meeting manuell beenden
    func stopMeeting() {
        MeetingDetector.shared.manuallyEndMeeting()
    }

    /// Bestätigen, dass Meeting beendet ist
    func confirmMeetingEnded() {
        showEndConfirmation = false
        MeetingDetector.shared.confirmMeetingEnded()
    }

    /// Ablehnen - Meeting läuft noch
    func dismissEndConfirmation() {
        showEndConfirmation = false
        MeetingDetector.shared.continueMeeting()
    }

    // MARK: - Start Confirmation Actions

    /// Bestätigt Meeting-Start und beginnt Aufnahme
    func confirmStartRecording() {
        showStartConfirmation = false
        pendingMeetingAppName = nil
        MeetingDetector.shared.confirmMeetingStart()
    }

    /// Lehnt Meeting-Aufnahme ab (Snooze)
    func dismissStartConfirmation() {
        showStartConfirmation = false
        pendingMeetingAppName = nil
        MeetingDetector.shared.dismissMeetingStart()
    }
}
