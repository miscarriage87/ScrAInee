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

    private var currentMeetingId: Int64?
    private var meetingStartTime: Date?
    private var segmentsSinceLastUpdate = 0
    private var cancellables = Set<AnyCancellable>()
    private var minutesUpdateTask: Task<Void, Never>?

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

        guard !isTranscribing else {
            print("MeetingTranscriptionCoordinator: Already transcribing")
            return
        }

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
            await MainActor.run {
                guard let self = self else { return }
                Task {
                    await self.processAudioChunk(chunk)
                }
            }
        }

        try await audioCapture.startRecording(for: meetingId)

        isRecording = true
        isTranscribing = true
        statusMessage = "Transkription läuft..."

        // Start periodic minutes updates if enabled
        if liveMinutesEnabled {
            startPeriodicMinutesUpdates()
        }

        print("MeetingTranscriptionCoordinator: Started transcription for meeting \(meetingId)")
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
                print("MeetingTranscriptionCoordinator: Final transcription failed: \(error)")
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
            print("MeetingTranscriptionCoordinator: Failed to finalize minutes: \(error)")
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

        return finalMinutes
    }

    /// Processes an audio chunk for real-time transcription
    func processAudioChunk(_ chunk: AudioChunk) async {
        guard isTranscribing, let meetingId = currentMeetingId else { return }

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
            print("MeetingTranscriptionCoordinator: Chunk transcription failed: \(error)")
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
            print("MeetingTranscriptionCoordinator: Minutes refresh failed: \(error)")
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
                guard let self = self,
                      self.autoTranscribe,
                      self.whisperModelDownloaded,
                      let session = notification.object as? MeetingSession else { return }

                Task { @MainActor in
                    // Get the meeting from database
                    if let meeting = try? await DatabaseManager.shared.getActiveMeeting() {
                        do {
                            try await self.startTranscription(for: meeting)
                        } catch {
                            self.error = "Auto-Start fehlgeschlagen: \(error.localizedDescription)"
                        }
                    }
                }
            }
            .store(in: &cancellables)

        // Handle meeting ended
        NotificationCenter.default.publisher(for: .meetingEnded)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self, self.isTranscribing else { return }

                Task { @MainActor in
                    _ = try? await self.stopTranscription()
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
            print("MeetingTranscriptionCoordinator: Incremental minutes update failed: \(error)")
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
