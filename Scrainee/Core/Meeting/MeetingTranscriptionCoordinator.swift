// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - 📋 DEPENDENCY DOCUMENTATION
// ═══════════════════════════════════════════════════════════════════════════════
//
// FILE: MeetingTranscriptionCoordinator.swift
// PURPOSE: Koordiniert Audio-Aufnahme, Transkription und Meeting-Minutes-Generierung.
//          Orchestriert den gesamten Transkriptions-Workflow für Meetings.
// LAYER: Core/Meeting
//
// ┌─────────────────────────────────────────────────────────────────────────────┐
// │ DEPENDENCIES (was diese Datei NUTZT)                                        │
// └─────────────────────────────────────────────────────────────────────────────┘
//
// IMPORTS:
//   - Foundation: Basis-Typen, Date, Task
//   - Combine: Publisher für Notification-Handling
//   - SwiftUI: @AppStorage für Settings
//
// CORE SERVICES (Singletons):
//   - AudioCaptureManager.shared: Audio-Aufnahme via ScreenCaptureKit
//     - startRecording(for:), stopRecording()
//     - setOnChunkCaptured() für Echtzeit-Chunks
//
//   - WhisperTranscriptionService.shared: Lokale Whisper-Transkription
//     - isModelLoaded, isModelDownloaded
//     - loadModel(), transcribe(), transcribeChunk()
//
//   - MeetingMinutesGenerator.shared: AI-gestützte Minutes-Generierung
//     - generateMinutes(), finalizeMinutes()
//
//   - DatabaseManager.shared: Persistenz
//     - updateMeetingTranscriptionStatus()
//     - updateMeetingAudioPath()
//     - insert(TranscriptSegment)
//     - getActionItems(for:)
//     - getActiveMeeting()
//
// NOTIFICATIONS (gehört):
//   - .meetingStarted: Von MeetingDetector - startet Auto-Transkription
//   - .meetingEnded: Von MeetingDetector - stoppt Transkription
//
// APPSTORAGE KEYS:
//   - "autoTranscribe": Bool - Auto-Start bei Meeting-Erkennung
//   - "whisperModelDownloaded": Bool - Modell verfügbar
//   - "liveMinutesEnabled": Bool - Echtzeit-Minutes-Updates
//
// ┌─────────────────────────────────────────────────────────────────────────────┐
// │ DEPENDENTS (wer diese Datei NUTZT)                                          │
// └─────────────────────────────────────────────────────────────────────────────┘
//
// NOTIFICATIONS GESENDET:
//
//   .transcriptionCompleted (object: TranscriptionCompletedInfo)
//     → Aktuell keine aktiven Listener
//     Payload: meetingId, segmentCount, minutes (optional)
//     Wann: Nach stopTranscription() wenn alles abgeschlossen
//
// DIREKTE NUTZER:
//   - MeetingMinutesViewModel.swift: Zugriff auf currentSegments, currentMinutes,
//                                     actionItems, isTranscribing, statusMessage
//   - MeetingMinutesView.swift: EnvironmentObject für UI-State
//
// PUBLISHED STATE:
//   - isTranscribing: Bool - Transkription aktiv
//   - isRecording: Bool - Audio-Aufnahme aktiv
//   - currentSegments: [TranscriptSegment] - Bisherige Segmente
//   - currentMinutes: MeetingMinutes? - Aktuelle generierte Minutes
//   - actionItems: [ActionItem] - Extrahierte Action Items
//   - transcriptionProgress: Double - Fortschritt (Segment-Count)
//   - statusMessage: String - UI-Statustext
//   - error: String? - Fehlermeldung
//
// ┌─────────────────────────────────────────────────────────────────────────────┐
// │ CHANGE IMPACT - KRITISCHE HINWEISE                                          │
// └─────────────────────────────────────────────────────────────────────────────┘
//
// 1. AUTO-TRANSKRIPTION FLOW:
//    - .meetingStarted → prüft autoTranscribe + isModelDownloaded
//    - Retry-Logik (3x) für getActiveMeeting() wegen Race Condition
//    - Meeting muss in DB existieren BEVOR Transkription startet
//
// 2. WHISPER-MODELL:
//    - Muss geladen sein vor startTranscription()
//    - loadModel() wird automatisch aufgerufen wenn downloaded
//
// 3. CHUNK-VERARBEITUNG:
//    - AudioChunk von AudioCaptureManager (30s Chunks, 16kHz Mono)
//    - processAudioChunk() → whisperService.transcribeChunk()
//    - Segmente werden sofort in DB gespeichert
//
// 4. LIVE MINUTES:
//    - Periodische Updates alle 60s + nach je 3 Segmenten
//    - minutesUpdateTask wird bei stopTranscription() gecancelt
//
// 5. THREAD-SAFETY:
//    - @MainActor für alle Published Properties
//    - Notification Handler empfangen auf main queue
//
// LAST UPDATED: 2026-01-20
// ═══════════════════════════════════════════════════════════════════════════════

import Foundation
import Combine
import SwiftUI

/// Coordinates audio capture, transcription, and minutes generation for meetings
@MainActor
final class MeetingTranscriptionCoordinator: ObservableObject {
    static let shared = MeetingTranscriptionCoordinator()

    // MARK: - Published State

    @Published private(set) var isTranscribing = false
    @Published private(set) var isRecording = false
    @Published private(set) var currentSegments: [TranscriptSegment] = []
    @Published private(set) var currentMinutes: MeetingMinutes?
    @Published private(set) var actionItems: [ActionItem] = []
    @Published private(set) var transcriptionProgress: Double = 0
    @Published private(set) var statusMessage: String = ""
    @Published var error: String?

    // MARK: - Settings

    @AppStorage("autoTranscribe") var autoTranscribe = true
    @AppStorage("whisperModelDownloaded") var whisperModelDownloaded = false
    @AppStorage("liveMinutesEnabled") var liveMinutesEnabled = true

    // MARK: - Private State

    private(set) var currentMeetingId: Int64?
    private var meetingStartTime: Date?
    private var segmentsSinceLastUpdate = 0
    private var cancellables = Set<AnyCancellable>()
    private var minutesUpdateTask: Task<Void, Never>?
    private var modelUnloadTask: Task<Void, Never>?

    /// Delay before unloading Whisper model after meeting ends (5 minutes = 300 seconds)
    private let modelUnloadDelay: Duration = .seconds(300)

    // MARK: - Dependencies

    private let audioCapture = AudioCaptureManager.shared
    private let whisperService = WhisperTranscriptionService.shared
    private let minutesGenerator = MeetingMinutesGenerator.shared
    private let databaseManager = DatabaseManager.shared

    // MARK: - Configuration

    private let segmentsPerMinutesUpdate = 3
    private let minutesUpdateInterval: TimeInterval = 60  // seconds

    // MARK: - Initialization

    private init() {
        setupNotificationHandlers()
    }

    // MARK: - Public API

    /// Starts transcription for a meeting
    func startTranscription(for meeting: Meeting) async throws {
        guard let meetingId = meeting.id else {
            throw TranscriptionCoordinatorError.invalidMeeting
        }

        guard !isTranscribing else { return }

        // Cancel any pending model unload since we're starting transcription
        modelUnloadTask?.cancel()
        modelUnloadTask = nil

        // Check if Whisper model is loaded
        if !whisperService.isModelLoaded {
            if whisperService.isModelDownloaded {
                statusMessage = "Lade Whisper-Modell..."
                try await whisperService.loadModel()
            } else {
                throw TranscriptionCoordinatorError.modelNotDownloaded
            }
        }

        // Reset state
        currentMeetingId = meetingId
        meetingStartTime = Date()
        currentSegments = []
        currentMinutes = nil
        actionItems = []
        segmentsSinceLastUpdate = 0
        error = nil

        // Update meeting status
        try await databaseManager.updateMeetingTranscriptionStatus(meetingId: meetingId, status: .recording)

        // Start audio capture with callback for chunks
        statusMessage = "Starte Audio-Aufnahme..."

        // Set up callback for audio chunks
        await audioCapture.setOnChunkCaptured { [weak self] chunk in
            guard let coordinator = self else { return }
            Task { @MainActor in
                await coordinator.processAudioChunk(chunk)
            }
        }

        // Pass app bundle ID for app-specific audio capture
        try await audioCapture.startRecording(for: meetingId, appBundleId: meeting.appBundleId)

        isRecording = true
        isTranscribing = true
        statusMessage = "Transkription läuft..."

        // Start periodic minutes updates if enabled
        if liveMinutesEnabled {
            startPeriodicMinutesUpdates()
        }

    }

    /// Stops transcription and finalizes everything
    func stopTranscription() async throws -> MeetingMinutes? {
        guard isTranscribing, let meetingId = currentMeetingId else {
            return nil
        }

        statusMessage = "Beende Aufnahme..."

        // Cancel periodic updates
        minutesUpdateTask?.cancel()
        minutesUpdateTask = nil

        // Stop audio capture
        let audioURL = await audioCapture.stopRecording()
        isRecording = false

        // Update meeting with audio path
        if let url = audioURL {
            try await databaseManager.updateMeetingAudioPath(meetingId: meetingId, path: url.path)
        }

        // Update status
        try await databaseManager.updateMeetingTranscriptionStatus(meetingId: meetingId, status: .transcribing)
        statusMessage = "Transkribiere verbleibendes Audio..."

        // Transcribe any remaining audio if we have the file
        if let audioURL = audioURL {
            do {
                let segments = try await whisperService.transcribe(audioURL: audioURL, meetingId: meetingId)

                // Save new segments
                for var segment in segments {
                    let id = try await databaseManager.insert(segment)
                    segment.id = id
                    currentSegments.append(segment)
                }
            } catch {
                // Final transcription failed - continue with available segments
            }
        }

        // Generate final minutes
        statusMessage = "Generiere finale Meeting-Minutes..."
        var finalMinutes: MeetingMinutes?

        do {
            finalMinutes = try await minutesGenerator.finalizeMinutes(for: meetingId)
            currentMinutes = finalMinutes

            // Load action items
            actionItems = try await databaseManager.getActionItems(for: meetingId)

        } catch {
            self.error = "Minutes-Generierung fehlgeschlagen: \(error.localizedDescription)"
        }

        // Update meeting status
        try await databaseManager.updateMeetingTranscriptionStatus(meetingId: meetingId, status: .completed)

        // Reset state
        isTranscribing = false
        statusMessage = "Transkription abgeschlossen"

        // Post notification
        NotificationCenter.default.post(
            name: .transcriptionCompleted,
            object: TranscriptionCompletedInfo(
                meetingId: meetingId,
                segmentCount: currentSegments.count,
                minutes: finalMinutes
            )
        )

        // Schedule Whisper model unload after delay to free ~3GB RAM
        scheduleModelUnload()

        return finalMinutes
    }

    /// Schedules unloading the Whisper model after a delay
    /// Cancels if a new transcription starts before the delay expires
    private func scheduleModelUnload() {
        // Cancel any existing unload task
        modelUnloadTask?.cancel()

        modelUnloadTask = Task { [weak self] in
            guard let self = self else { return }

            do {
                try await Task.sleep(for: self.modelUnloadDelay)

                // Only unload if still not transcribing
                if !self.isTranscribing {
                    self.whisperService.unloadModel()
                }
            } catch {
                // Task was cancelled - model stays loaded
            }
        }
    }

    /// Processes an audio chunk for real-time transcription
    func processAudioChunk(_ chunk: AudioChunk) async {
        guard isTranscribing, let _ = currentMeetingId else { return }

        do {
            // Transcribe the chunk
            if let segment = try await whisperService.transcribeChunk(chunk) {
                // Save to database
                var savedSegment = segment
                savedSegment.id = try await databaseManager.insert(segment)

                // Add to current segments
                currentSegments.append(savedSegment)
                segmentsSinceLastUpdate += 1

                // Update progress
                transcriptionProgress = Double(currentSegments.count)

                // Trigger minutes update if needed
                if liveMinutesEnabled && segmentsSinceLastUpdate >= segmentsPerMinutesUpdate {
                    await updateMinutesIncrementally()
                    segmentsSinceLastUpdate = 0
                }
            }
        } catch {
            // Chunk transcription failed - continue with next chunk
        }
    }

    /// Manually triggers a minutes update
    func refreshMinutes() async {
        guard let meetingId = currentMeetingId, !currentSegments.isEmpty else { return }

        do {
            currentMinutes = try await minutesGenerator.generateMinutes(
                for: meetingId,
                segments: currentSegments,
                existingMinutes: currentMinutes,
                isLiveUpdate: true
            )
        } catch {
            // Minutes refresh failed - continue without update
        }
    }

    /// Regenerates minutes from scratch
    func regenerateMinutes() async throws {
        guard let meetingId = currentMeetingId else { return }

        currentMinutes = try await minutesGenerator.generateMinutes(
            for: meetingId,
            segments: currentSegments,
            existingMinutes: nil,
            isLiveUpdate: false
        )
    }

    // MARK: - Private Methods

    private func setupNotificationHandlers() {
        // Handle meeting started
        NotificationCenter.default.publisher(for: .meetingStarted)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let self = self else { return }
                guard self.autoTranscribe else { return }

                let isModelDownloaded = WhisperTranscriptionService.shared.isModelDownloaded
                guard isModelDownloaded else { return }
                guard let session = notification.object as? MeetingSession else { return }

                Task { @MainActor in
                    // Retry-Mechanismus falls DB noch nicht bereit
                    var meeting: Meeting?
                    for attempt in 1...3 {
                        meeting = try? await DatabaseManager.shared.getActiveMeeting()
                        if meeting != nil { break }
                        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
                    }

                    guard let meeting = meeting else {
                        self.error = "Meeting konnte nicht aus Datenbank geladen werden"
                        return
                    }

                    do {
                        try await self.startTranscription(for: meeting)
                    } catch {
                        self.error = "Auto-Start fehlgeschlagen: \(error.localizedDescription)"
                    }
                }
            }
            .store(in: &cancellables)

        // Handle meeting ended
        NotificationCenter.default.publisher(for: .meetingEnded)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                guard self.isTranscribing else { return }

                Task { @MainActor in
                    do {
                        _ = try await self.stopTranscription()
                    } catch {
                        self.error = "Transkription konnte nicht beendet werden: \(error.localizedDescription)"
                    }
                }
            }
            .store(in: &cancellables)
    }

    private func startPeriodicMinutesUpdates() {
        minutesUpdateTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(self?.minutesUpdateInterval ?? 60))

                guard !Task.isCancelled else { break }

                await self?.updateMinutesIncrementally()
            }
        }
    }

    private func updateMinutesIncrementally() async {
        guard let meetingId = currentMeetingId, !currentSegments.isEmpty else { return }

        do {
            currentMinutes = try await minutesGenerator.generateMinutes(
                for: meetingId,
                segments: currentSegments,
                existingMinutes: currentMinutes,
                isLiveUpdate: true
            )
        } catch {
            // Incremental update failed - continue with next iteration
        }
    }
}

// MARK: - Supporting Types

struct TranscriptionCompletedInfo {
    let meetingId: Int64
    let segmentCount: Int
    let minutes: MeetingMinutes?
}

// MARK: - Notifications

extension Notification.Name {
    static let transcriptionCompleted = Notification.Name("transcriptionCompleted")
}

// MARK: - Errors

enum TranscriptionCoordinatorError: LocalizedError {
    case invalidMeeting
    case modelNotDownloaded
    case alreadyTranscribing
    case notTranscribing

    var errorDescription: String? {
        switch self {
        case .invalidMeeting:
            return "Ungültiges Meeting"
        case .modelNotDownloaded:
            return "Whisper-Modell nicht heruntergeladen. Bitte zuerst in den Einstellungen herunterladen."
        case .alreadyTranscribing:
            return "Transkription läuft bereits"
        case .notTranscribing:
            return "Keine aktive Transkription"
        }
    }
}
