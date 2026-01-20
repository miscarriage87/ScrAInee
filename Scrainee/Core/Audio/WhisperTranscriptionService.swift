// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - 📋 DEPENDENCY DOCUMENTATION
// ═══════════════════════════════════════════════════════════════════════════════
//
// FILE: WhisperTranscriptionService.swift
// PURPOSE: Lokale Sprach-zu-Text-Transkription mittels WhisperKit (CoreML).
//          Verwaltet Modell-Download, -Laden und Transkription von Audio.
// LAYER: Core/Audio
//
// ┌─────────────────────────────────────────────────────────────────────────────┐
// │ DEPENDENCIES (was diese Datei NUTZT)                                        │
// └─────────────────────────────────────────────────────────────────────────────┘
//
// IMPORTS:
//   - Foundation: FileManager, URL, NSLock
//   - WhisperKit: WhisperKit, WhisperKitConfig, TranscriptionResult
//
// EXTERNAL PACKAGE:
//   - WhisperKit (argmaxinc/WhisperKit): CoreML-basierte Whisper-Implementierung
//   - Modell: openai/whisper-large-v3 (~3 GB)
//
// FILE SYSTEM:
//   - Modell-Pfad: ~/Library/Application Support/Scrainee/models/argmaxinc/
//                  whisperkit-coreml/openai_whisper-large-v3/
//   - Alternative: ~/Library/Application Support/Scrainee/whisper-models/...
//   - Prüft: AudioEncoder.mlmodelc + TextDecoder.mlmodelc
//
// ┌─────────────────────────────────────────────────────────────────────────────┐
// │ DEPENDENTS (wer diese Datei NUTZT)                                          │
// └─────────────────────────────────────────────────────────────────────────────┘
//
// DIREKTE NUTZER:
//
//   MeetingTranscriptionCoordinator.shared:
//     - isModelLoaded: Prüft ob Modell bereit
//     - isModelDownloaded: Prüft ob Modell auf Disk
//     - loadModel(): Lädt Modell in Speicher
//     - transcribe(audioURL:meetingId:): Transkribiert Audio-Datei
//     - transcribeChunk(AudioChunk): Echtzeit-Transkription
//
//   SettingsView.swift:
//     - downloadModel(): Startet Modell-Download
//     - isModelDownloaded: UI-Status
//     - downloadProgress: Download-Fortschritt
//     - loadingStatus: Status-Text
//
//   StartupCheckManager.swift:
//     - isModelDownloaded: Health-Check beim App-Start
//     - isModelLoaded: Prüft Modell-Status
//
//   AppState.swift:
//     - isModelDownloaded: Global verfügbarer Status
//     - isModelLoaded: Global verfügbarer Status
//
// PUBLIC API:
//   - isModelDownloaded: Bool (computed) - Modell auf Disk?
//   - isModelLoaded: Bool (thread-safe) - Modell im RAM?
//   - isTranscribing: Bool (thread-safe) - Transkription aktiv?
//   - downloadProgress: Double (thread-safe) - Download-Fortschritt 0-1
//   - loadingStatus: String (thread-safe) - UI-Statustext
//   - error: String? (thread-safe) - Fehlermeldung
//   - modelSizeDescription: String - "~3 GB"
//
// ┌─────────────────────────────────────────────────────────────────────────────┐
// │ CHANGE IMPACT - KRITISCHE HINWEISE                                          │
// └─────────────────────────────────────────────────────────────────────────────┘
//
// 1. THREAD-SAFETY:
//    - NICHT @MainActor wegen WhisperKit nonisolated Methoden
//    - NSLock für alle State-Properties
//    - @unchecked Sendable für Cross-Actor Nutzung
//
// 2. MODELL-PFADE:
//    - WhisperKit speichert unter argmaxinc/whisperkit-coreml/
//    - getModelPaths() prüft mehrere mögliche Locations
//    - Änderungen am Pfad erfordern Anpassung in isModelDownloaded
//
// 3. AUDIO-ANFORDERUNGEN:
//    - Input: 16kHz Mono Float-Samples (AudioChunk.samples)
//    - AudioCaptureManager liefert bereits konvertiertes Format
//
// 4. TRANSCRIPTION RESULTS:
//    - TranscriptSegment enthält: text, startTime, endTime, confidence, language
//    - confidence ist avgLogprob (negativ, höher = besser)
//    - Leere Texte werden gefiltert
//
// 5. MEMORY MANAGEMENT:
//    - unloadModel() gibt WhisperKit-Instanz frei
//    - Large-v3 Modell benötigt ~3-4 GB RAM während Transkription
//
// LAST UPDATED: 2026-01-20
// ═══════════════════════════════════════════════════════════════════════════════

import Foundation
import WhisperKit

/// Service for local transcription using WhisperKit
/// Note: This class is NOT on MainActor because WhisperKit's transcribe methods
/// are nonisolated and would cause data race errors otherwise.
final class WhisperTranscriptionService: @unchecked Sendable {
    static let shared = WhisperTranscriptionService()

    // MARK: - State (thread-safe via locks)

    private let lock = NSLock()

    private var _isModelLoaded = false
    private var _isTranscribing = false
    private var _downloadProgress: Double = 0
    private var _loadingStatus: String = ""
    private var _error: String?

    var isModelLoaded: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isModelLoaded
    }

    var isTranscribing: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isTranscribing
    }

    var downloadProgress: Double {
        lock.lock()
        defer { lock.unlock() }
        return _downloadProgress
    }

    var loadingStatus: String {
        lock.lock()
        defer { lock.unlock() }
        return _loadingStatus
    }

    var error: String? {
        lock.lock()
        defer { lock.unlock() }
        return _error
    }

    // MARK: - Private State

    private var whisperKit: WhisperKit?
    private let modelName = "openai/whisper-large-v3"
    private let modelVariant = "large-v3"

    // MARK: - Initialization

    private init() {}

    // MARK: - Model Management

    /// Checks if the Whisper model is downloaded
    /// WhisperKit speichert Modelle unter verschiedenen Pfaden je nach Download-Methode
    var isModelDownloaded: Bool {
        let paths = getModelPaths()

        for path in paths {
            let audioEncoderPath = path.appendingPathComponent("AudioEncoder.mlmodelc")
            let textDecoderPath = path.appendingPathComponent("TextDecoder.mlmodelc")

            let exists = FileManager.default.fileExists(atPath: audioEncoderPath.path) &&
                         FileManager.default.fileExists(atPath: textDecoderPath.path)

            if exists {
                return true
            }
        }

        return false
    }

    /// Gets all possible paths where the Whisper model could be stored
    private func getModelPaths() -> [URL] {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let scraineeDir = appSupport.appendingPathComponent("Scrainee")

        let modelSubpath = "models/argmaxinc/whisperkit-coreml/openai_whisper-\(modelVariant)"

        return [
            // Primärer Pfad (direkt unter Scrainee)
            scraineeDir.appendingPathComponent(modelSubpath),
            // Sekundärer Pfad (unter whisper-models)
            scraineeDir.appendingPathComponent("whisper-models").appendingPathComponent(modelSubpath)
        ]
    }

    /// Gets the model size description
    var modelSizeDescription: String {
        "~3 GB"
    }

    /// Gets the base path where models are stored
    private func getModelBasePath() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Scrainee/whisper-models")
    }

    /// Gets the path where models are stored (für WhisperKit downloadBase)
    private func getModelPath() -> URL {
        getModelBasePath()
    }

    // MARK: - State Setters

    private func setIsModelLoaded(_ value: Bool) {
        lock.lock()
        _isModelLoaded = value
        lock.unlock()
    }

    private func setIsTranscribing(_ value: Bool) {
        lock.lock()
        _isTranscribing = value
        lock.unlock()
    }

    private func setDownloadProgress(_ value: Double) {
        lock.lock()
        _downloadProgress = value
        lock.unlock()
    }

    private func setLoadingStatus(_ value: String) {
        lock.lock()
        _loadingStatus = value
        lock.unlock()
    }

    private func setError(_ value: String?) {
        lock.lock()
        _error = value
        lock.unlock()
    }

    /// Downloads the Whisper model
    func downloadModel() async throws {
        guard !isModelDownloaded else {
            print("WhisperTranscriptionService: Model already downloaded")
            return
        }

        setLoadingStatus("Lade Whisper-Modell herunter...")
        setDownloadProgress(0)
        setError(nil)

        do {
            // WhisperKit handles model download automatically when initialized
            let config = WhisperKitConfig(
                model: modelVariant,
                downloadBase: getModelPath().deletingLastPathComponent(),
                verbose: true
            )

            setLoadingStatus("Initialisiere WhisperKit...")

            // This will download the model if not present
            let kit = try await WhisperKit(config)

            // Store for later use
            whisperKit = kit
            setIsModelLoaded(true)
            setDownloadProgress(1.0)
            setLoadingStatus("Modell erfolgreich geladen")

        } catch {
            setError("Modell-Download fehlgeschlagen: \(error.localizedDescription)")
            setLoadingStatus("Fehler beim Laden")
            throw TranscriptionError.modelDownloadFailed(error.localizedDescription)
        }
    }

    /// Loads the model if already downloaded
    func loadModel() async throws {
        guard !isModelLoaded else { return }

        setLoadingStatus("Lade Whisper-Modell...")
        setError(nil)

        do {
            let config = WhisperKitConfig(
                model: modelVariant,
                downloadBase: getModelPath().deletingLastPathComponent(),
                verbose: false
            )

            whisperKit = try await WhisperKit(config)
            setIsModelLoaded(true)
            setLoadingStatus("Modell geladen")

        } catch {
            setError("Modell konnte nicht geladen werden: \(error.localizedDescription)")
            setLoadingStatus("Fehler")
            throw TranscriptionError.modelLoadFailed(error.localizedDescription)
        }
    }

    // MARK: - Transcription

    /// Transcribes an audio file
    func transcribe(audioURL: URL, meetingId: Int64) async throws -> [TranscriptSegment] {
        guard isModelLoaded, let whisperKit = whisperKit else {
            throw TranscriptionError.modelNotLoaded
        }

        setIsTranscribing(true)
        defer { setIsTranscribing(false) }

        do {
            let result = try await whisperKit.transcribe(audioPath: audioURL.path)

            return convertToSegments(result, meetingId: meetingId)

        } catch {
            throw TranscriptionError.transcriptionFailed(error.localizedDescription)
        }
    }

    /// Transcribes an audio chunk (for real-time processing)
    func transcribeChunk(_ chunk: AudioChunk) async throws -> TranscriptSegment? {
        guard isModelLoaded, let whisperKit = whisperKit else {
            throw TranscriptionError.modelNotLoaded
        }

        guard !chunk.samples.isEmpty else { return nil }

        setIsTranscribing(true)
        defer { setIsTranscribing(false) }

        do {
            // Convert chunk to audio samples for WhisperKit
            let audioSamples = chunk.samples

            let result = try await whisperKit.transcribe(audioArray: audioSamples)

            guard let firstResult = result.first, !firstResult.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }

            // Get confidence from first segment if available
            let confidence: Double? = firstResult.segments.first.map { Double($0.avgLogprob) }

            return TranscriptSegment(
                meetingId: chunk.meetingId,
                text: firstResult.text.trimmingCharacters(in: .whitespacesAndNewlines),
                startTime: chunk.startTime,
                endTime: chunk.endTime,
                confidence: confidence,
                language: firstResult.language,
                createdAt: Date()
            )

        } catch {
            print("WhisperTranscriptionService: Chunk transcription failed: \(error)")
            throw TranscriptionError.transcriptionFailed(error.localizedDescription)
        }
    }

    /// Transcribes raw audio samples
    func transcribe(samples: [Float], meetingId: Int64, startTime: TimeInterval, endTime: TimeInterval) async throws -> TranscriptSegment? {
        guard isModelLoaded, let whisperKit = whisperKit else {
            throw TranscriptionError.modelNotLoaded
        }

        guard !samples.isEmpty else { return nil }

        setIsTranscribing(true)
        defer { setIsTranscribing(false) }

        do {
            let result = try await whisperKit.transcribe(audioArray: samples)

            guard let firstResult = result.first, !firstResult.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }

            // Get confidence from first segment if available
            let confidence: Double? = firstResult.segments.first.map { Double($0.avgLogprob) }

            return TranscriptSegment(
                meetingId: meetingId,
                text: firstResult.text.trimmingCharacters(in: .whitespacesAndNewlines),
                startTime: startTime,
                endTime: endTime,
                confidence: confidence,
                language: firstResult.language,
                createdAt: Date()
            )

        } catch {
            throw TranscriptionError.transcriptionFailed(error.localizedDescription)
        }
    }

    // MARK: - Helper Methods

    private func convertToSegments(_ results: [TranscriptionResult], meetingId: Int64) -> [TranscriptSegment] {
        var segments: [TranscriptSegment] = []

        for result in results {
            // Each result may have multiple segments
            for segment in result.segments {
                let transcriptSegment = TranscriptSegment(
                    meetingId: meetingId,
                    text: segment.text.trimmingCharacters(in: .whitespacesAndNewlines),
                    startTime: TimeInterval(segment.start),
                    endTime: TimeInterval(segment.end),
                    confidence: Double(segment.avgLogprob),
                    language: result.language,
                    createdAt: Date()
                )
                segments.append(transcriptSegment)
            }
        }

        return segments
    }

    // MARK: - Cleanup

    /// Unloads the model to free memory
    func unloadModel() {
        whisperKit = nil
        setIsModelLoaded(false)
        setLoadingStatus("")
    }
}

// MARK: - Errors

enum TranscriptionError: LocalizedError {
    case modelNotLoaded
    case modelDownloadFailed(String)
    case modelLoadFailed(String)
    case transcriptionFailed(String)
    case invalidAudioFormat

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "Whisper-Modell nicht geladen"
        case .modelDownloadFailed(let message):
            return "Modell-Download fehlgeschlagen: \(message)"
        case .modelLoadFailed(let message):
            return "Modell konnte nicht geladen werden: \(message)"
        case .transcriptionFailed(let message):
            return "Transkription fehlgeschlagen: \(message)"
        case .invalidAudioFormat:
            return "Ungültiges Audio-Format"
        }
    }
}
