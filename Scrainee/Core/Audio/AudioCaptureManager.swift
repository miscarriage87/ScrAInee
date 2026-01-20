// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - DEPENDENCY DOCUMENTATION
// ═══════════════════════════════════════════════════════════════════════════════
//
// FILE: AudioCaptureManager.swift
// PURPOSE: System-Audio-Aufnahme während Meetings.
//          Primär: Core Audio ProcessTap (macOS 14.2+) - zuverlässiger
//          Fallback: ScreenCaptureKit (macOS 13+) - weniger zuverlässig für Audio
//          Erfasst Audio, konvertiert zu Whisper-Format (16kHz Mono) und
//          liefert Chunks für Echtzeit-Transkription.
// LAYER: Core/Audio
//
// ┌─────────────────────────────────────────────────────────────────────────────┐
// │ DEPENDENCIES (was diese Datei NUTZT)                                        │
// └─────────────────────────────────────────────────────────────────────────────┘
//
// IMPORTS:
//   - Foundation: Basis-Typen, FileManager, Date
//   - AVFoundation: AVAudioFile, AVAudioFormat, AVAudioPCMBuffer für WAV-Export
//   - ScreenCaptureKit: SCStream, SCShareableContent für Fallback-Audio-Capture
//   - CoreAudio: AudioHardwareCreateProcessTap für primäres Audio-Capture (14.2+)
//
// INTERNAL:
//   - ProcessTapAudioCapture: Primäre Capture-Methode auf macOS 14.2+
//
// STORAGE:
//   - StorageManager.shared.applicationSupportDirectory: Basis-Pfad für Audio-Dateien
//     Audio wird gespeichert unter: ~/Library/Application Support/Scrainee/audio/
//
// CAPTURE STRATEGY:
//   - macOS 14.2+: Core Audio ProcessTap (CATapDescription) - Global Tap
//   - macOS 13.0-14.1: ScreenCaptureKit (Fallback) - weniger zuverlässig
//
// ┌─────────────────────────────────────────────────────────────────────────────┐
// │ DEPENDENTS (wer diese Datei NUTZT)                                          │
// └─────────────────────────────────────────────────────────────────────────────┘
//
// DIREKTE NUTZER:
//   - MeetingTranscriptionCoordinator.shared:
//     - startRecording(for:): Startet Aufnahme für Meeting-ID
//     - stopRecording(): Beendet Aufnahme, gibt Audio-URL zurück
//     - setOnChunkCaptured(): Callback für 30s Audio-Chunks
//
// AUDIO CHUNK CALLBACK:
//   - Callback: (AudioChunk) async -> Void
//   - AudioChunk enthält: meetingId, samples, startTime, endTime, sampleRate, isFinal
//   - Wird alle ~30 Sekunden aufgerufen (Config.chunkDuration)
//   - Samples sind bereits 16kHz Mono (Whisper-ready)
//
// AUDIO OUTPUT:
//   - WAV-Datei: 16kHz, Mono, Float32
//   - Pfad: ~/Library/Application Support/Scrainee/audio/meeting_{id}_{timestamp}.wav
//
// ┌─────────────────────────────────────────────────────────────────────────────┐
// │ CHANGE IMPACT - KRITISCHE HINWEISE                                          │
// └─────────────────────────────────────────────────────────────────────────────┘
//
// 1. AUDIO FORMAT KONVERTIERUNG:
//    - Input: 48kHz Stereo (System-Standard)
//    - Output: 16kHz Mono (Whisper-Anforderung)
//    - convertToWhisperFormat() macht: Stereo→Mono + Downsample 48k→16k
//    - Lineare Interpolation verhindert Aliasing/Chipmunk-Effekt
//
// 2. ACTOR ISOLATION:
//    - AudioCaptureManager ist actor für Thread-Safety
//    - ProcessTapAudioCapture ist ebenfalls actor
//    - AudioStreamOutput ist @unchecked Sendable (ScreenCaptureKit Delegate)
//
// 3. CHUNK MANAGEMENT:
//    - chunkBuffer sammelt Samples bis chunkDuration (30s) erreicht
//    - Bei stopRecording() wird verbleibender Buffer mit isFinal=true gesendet
//
// 4. FILE VALIDATION:
//    - Nach stopRecording() wird Dateigröße geprüft
//    - Leere Dateien (0 bytes) werden gelöscht, nil zurückgegeben
//
// 5. DEBUGGING:
//    - Ausführliches Logging mit [DEBUG] Prefix
//    - Sample-Count Logging alle ~5 Sekunden
//
// LAST UPDATED: 2026-01-20
// ═══════════════════════════════════════════════════════════════════════════════

import Foundation
import AVFoundation
import ScreenCaptureKit
import CoreAudio

/// Manages system audio capture during meetings
/// Uses ProcessTap API on macOS 14.2+ (more reliable), falls back to ScreenCaptureKit on older versions
actor AudioCaptureManager {
    static let shared = AudioCaptureManager()

    // MARK: - Capture Method

    /// Which capture method is being used
    enum CaptureMethod {
        case processTap    // macOS 14.2+ - Core Audio ProcessTap
        case screenCapture // macOS 13+ - ScreenCaptureKit (fallback)
    }

    private(set) var activeCaptureMethod: CaptureMethod?

    // MARK: - State

    private(set) var isRecording = false
    private var currentMeetingId: Int64?
    private var meetingStartTime: Date?

    // ProcessTap capture (macOS 14.2+)
    // Using Any? to avoid availability issues at property declaration level
    private var processTapCaptureStorage: Any?

    @available(macOS 14.2, *)
    private var processTapCapture: ProcessTapAudioCapture? {
        get { processTapCaptureStorage as? ProcessTapAudioCapture }
        set { processTapCaptureStorage = newValue }
    }

    // ScreenCaptureKit (fallback)
    private var stream: SCStream?
    private var streamOutput: AudioStreamOutput?

    // Audio file writing
    private var audioFileURL: URL?
    private var audioFile: AVAudioFile?

    // Chunk management for real-time transcription
    private var chunkBuffer: [Float] = []
    private var chunkStartTime: TimeInterval = 0
    private let chunkDuration: TimeInterval = 30.0  // 30 second chunks

    // Callback for chunk notifications (runs on MainActor)
    private var onChunkCaptured: (@Sendable (AudioChunk) async -> Void)?

    /// Sets the callback for when audio chunks are captured
    func setOnChunkCaptured(_ callback: @escaping @Sendable (AudioChunk) async -> Void) {
        onChunkCaptured = callback
    }

    // MARK: - Configuration

    struct Config {
        // ScreenCaptureKit capture settings (system standard)
        var captureSampleRate: Double = 48000   // 48kHz - ScreenCaptureKit standard
        var captureChannels: Int = 2             // Stereo - ScreenCaptureKit standard

        // Output settings for Whisper
        var outputSampleRate: Double = 16000    // 16kHz for Whisper
        var outputChannels: Int = 1              // Mono for Whisper

        var chunkDuration: TimeInterval = 30     // Seconds per chunk
    }

    private var config = Config()

    // MARK: - Initialization

    private init() {}

    // MARK: - Public API

    /// Starts recording audio for a meeting
    /// - Parameters:
    ///   - meetingId: The database ID of the meeting
    ///   - appBundleId: The bundle identifier of the meeting app (e.g., "com.microsoft.teams2")
    ///   - config: Audio capture configuration
    func startRecording(for meetingId: Int64, appBundleId: String? = nil, config: Config = Config()) async throws {
        guard !isRecording else {
            return
        }

        self.config = config
        self.currentMeetingId = meetingId
        self.meetingStartTime = Date()

        // Try ProcessTap first (macOS 14.2+), fall back to ScreenCaptureKit
        if #available(macOS 14.2, *) {
            do {
                try await startProcessTapRecording(for: meetingId, config: config)
                activeCaptureMethod = .processTap
                isRecording = true
                print("[DEBUG] AudioCaptureManager: Using ProcessTap capture (macOS 14.2+)")
                return
            } catch {
                print("[WARNING] AudioCaptureManager: ProcessTap failed (\(error.localizedDescription)), falling back to ScreenCaptureKit")
            }
        }

        // Fallback: ScreenCaptureKit
        let audioURL = try createAudioFileURL(for: meetingId)
        self.audioFileURL = audioURL

        try await setupAudioStream(forApp: appBundleId)
        activeCaptureMethod = .screenCapture
        isRecording = true
        print("[DEBUG] AudioCaptureManager: Using ScreenCaptureKit capture (fallback)")
    }

    /// Start recording using ProcessTap API (macOS 14.2+)
    @available(macOS 14.2, *)
    private func startProcessTapRecording(for meetingId: Int64, config: Config) async throws {
        let tapCapture = ProcessTapAudioCapture()

        // Forward chunk callback
        if let callback = onChunkCaptured {
            await tapCapture.setOnChunkCaptured(callback)
        }

        let tapConfig = ProcessTapAudioCapture.CaptureConfig(
            sampleRate: config.captureSampleRate,
            channels: config.captureChannels,
            outputSampleRate: config.outputSampleRate,
            chunkDuration: config.chunkDuration
        )

        try await tapCapture.startCapture(for: meetingId, config: tapConfig)
        self.processTapCapture = tapCapture
    }

    /// Stops recording and returns the audio file URL
    func stopRecording() async -> URL? {
        guard isRecording else {
            return nil
        }

        var resultURL: URL? = nil

        // Stop based on capture method
        switch activeCaptureMethod {
        case .processTap:
            if #available(macOS 14.2, *) {
                if let tapCapture = processTapCapture {
                    resultURL = await tapCapture.stopCapture()
                }
                processTapCapture = nil
            }

        case .screenCapture, .none:
            // Stop the ScreenCaptureKit stream
            if let stream = stream {
                do {
                    try await stream.stopCapture()
                } catch {
                    // Stream stop failed - continue with cleanup
                }
            }

            // Finalize audio file
            audioFile = nil

            // Process any remaining buffer
            if !chunkBuffer.isEmpty {
                await processChunk(final: true)
            }

            // Validate audio file
            resultURL = audioFileURL
            if let url = audioFileURL {
                if FileManager.default.fileExists(atPath: url.path) {
                    let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
                    let size = (attrs?[.size] as? Int64) ?? 0

                    if size == 0 {
                        try? FileManager.default.removeItem(at: url)
                        resultURL = nil
                    }
                } else {
                    resultURL = nil
                }
            }
        }

        // Reset state
        isRecording = false
        activeCaptureMethod = nil
        stream = nil
        streamOutput = nil
        currentMeetingId = nil
        meetingStartTime = nil
        chunkBuffer = []
        totalSamplesWritten = 0
        audioFileURL = nil

        return resultURL
    }

    /// Gets the current audio chunk data for real-time processing
    func getCurrentChunkData() async -> Data? {
        guard !chunkBuffer.isEmpty else { return nil }

        // Convert Float array to Data (16-bit PCM)
        let int16Samples = chunkBuffer.map { sample -> Int16 in
            let clamped = max(-1.0, min(1.0, sample))
            return Int16(clamped * Float(Int16.max))
        }

        return int16Samples.withUnsafeBufferPointer { buffer in
            Data(buffer: buffer)
        }
    }

    // MARK: - Private Methods

    private func createAudioFileURL(for meetingId: Int64) throws -> URL {
        let audioDirectory = StorageManager.shared.applicationSupportDirectory.appendingPathComponent("audio")

        // Create directory if needed
        try FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = dateFormatter.string(from: Date())

        let filename = "meeting_\(meetingId)_\(timestamp).wav"
        return audioDirectory.appendingPathComponent(filename)
    }

    /// Known meeting app bundle identifiers
    private static let meetingAppBundleIds: Set<String> = [
        "com.microsoft.teams",
        "com.microsoft.teams2",
        "us.zoom.xos",
        "com.cisco.webexmeetingsapp",
        "com.cisco.webex.meetings"
    ]

    private func setupAudioStream(forApp appBundleId: String? = nil) async throws {
        // Get shareable content - include off-screen windows too for better audio coverage
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)

        guard let display = content.displays.first else {
            throw AudioCaptureError.noDisplayAvailable
        }

        // Erfasse Audio von ALLEN laufenden Apps
        // Dies ist zuverlässiger als app-spezifische Filter, die Audio verlieren können
        let allApps = content.applications
        print("[DEBUG] AudioCaptureManager: Capturing audio from ALL \(allApps.count) running apps")

        // Liste einige Apps zur Diagnose
        let appNames = allApps.prefix(10).map { $0.applicationName }.joined(separator: ", ")
        print("[DEBUG] AudioCaptureManager: Apps include: \(appNames)...")

        let filter = SCContentFilter(display: display, including: allApps, exceptingWindows: [])

        // Configure stream for audio capture
        // WICHTIG: ScreenCaptureKit erfordert System-Standard Raten (48kHz/Stereo)
        // Die Konvertierung zu 16kHz/Mono für Whisper erfolgt NACH dem Capture
        let streamConfig = SCStreamConfiguration()
        streamConfig.capturesAudio = true
        streamConfig.excludesCurrentProcessAudio = true  // Scrainee's eigene Sounds ausschließen
        streamConfig.sampleRate = Int(config.captureSampleRate)  // 48000 Hz (System-Standard)
        streamConfig.channelCount = config.captureChannels        // 2 (Stereo)

        // Minimale Video-Konfiguration - ScreenCaptureKit erfordert Video
        // 1x1 kann Probleme verursachen, daher 2x2 verwenden
        streamConfig.width = 2
        streamConfig.height = 2
        streamConfig.minimumFrameInterval = CMTime(value: 1, timescale: 1)  // 1 FPS minimum
        streamConfig.queueDepth = 1  // Minimale Video-Buffer

        // Create stream output handler
        let output = AudioStreamOutput(manager: self)
        self.streamOutput = output

        // Create and start stream
        let stream = SCStream(filter: filter, configuration: streamConfig, delegate: nil)
        try stream.addStreamOutput(output, type: .audio, sampleHandlerQueue: .global(qos: .userInteractive))

        try await stream.startCapture()
        self.stream = stream
        print("[DEBUG] AudioCaptureManager: Stream capture started successfully")
    }

    /// Called by StreamOutput when audio samples are received (from CMSampleBuffer)
    func handleAudioSamples(_ sampleBuffer: CMSampleBuffer) async {
        guard isRecording else { return }

        // Extract audio data from sample buffer
        guard let audioBuffer = extractAudioBuffer(from: sampleBuffer) else { return }

        await handleAudioData(audioBuffer)
    }

    /// Called by StreamOutput when audio data is received (already extracted samples)
    /// Input: 48kHz Stereo (from ScreenCaptureKit)
    /// Output: 16kHz Mono (for Whisper and file)
    func handleAudioData(_ samples: [Float]) async {
        guard isRecording else { return }

        // Konvertiere 48kHz Stereo → 16kHz Mono für Whisper
        let convertedSamples = convertToWhisperFormat(samples)

        // Append to chunk buffer (16kHz Mono)
        chunkBuffer.append(contentsOf: convertedSamples)

        // Write to file (16kHz Mono)
        await writeToAudioFile(samples: convertedSamples)

        // Check if chunk is complete (basierend auf Output-Sample-Rate)
        let chunkSamples = Int(config.chunkDuration * config.outputSampleRate)
        if chunkBuffer.count >= chunkSamples {
            await processChunk(final: false)
        }
    }

    private func extractAudioBuffer(from sampleBuffer: CMSampleBuffer) -> [Float]? {
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return nil }

        var length = 0
        var dataPointer: UnsafeMutablePointer<Int8>?

        let status = CMBlockBufferGetDataPointer(
            blockBuffer,
            atOffset: 0,
            lengthAtOffsetOut: nil,
            totalLengthOut: &length,
            dataPointerOut: &dataPointer
        )

        guard status == kCMBlockBufferNoErr, let data = dataPointer else { return nil }

        // Assuming 32-bit float format from ScreenCaptureKit
        let floatCount = length / MemoryLayout<Float>.size
        let floatPointer = UnsafeRawPointer(data).bindMemory(to: Float.self, capacity: floatCount)

        return Array(UnsafeBufferPointer(start: floatPointer, count: floatCount))
    }

    // MARK: - Audio Conversion (48kHz Stereo → 16kHz Mono)

    /// Konvertiert Stereo-Audio (interleaved) zu Mono
    /// Verwendet den Kanal mit der höheren Amplitude um Phasen-Auslöschung zu vermeiden
    /// (Bei einfacher Mittelung: wenn L=+0.5 und R=-0.5, dann (L+R)/2 = 0 = Stille!)
    private func stereoToMono(_ samples: [Float], channels: Int) -> [Float] {
        guard channels == 2, samples.count >= 2 else { return samples }

        var mono: [Float] = []
        mono.reserveCapacity(samples.count / 2)

        // Interleaved format: [L0, R0, L1, R1, L2, R2, ...]
        for i in stride(from: 0, to: samples.count - 1, by: 2) {
            let left = samples[i]
            let right = samples[i + 1]

            // Verwende den Kanal mit der höheren Amplitude
            // Verhindert Phasen-Auslöschung bei gegenphasigen Kanälen
            if abs(left) >= abs(right) {
                mono.append(left)
            } else {
                mono.append(right)
            }
        }

        return mono
    }

    /// Downsampled Audio von captureSampleRate auf outputSampleRate (z.B. 48kHz → 16kHz)
    /// Verwendet lineare Interpolation statt einfachem Sample-Picking, um Aliasing/Pitch-Verzerrung zu vermeiden
    private func downsample(_ samples: [Float], from sourceSampleRate: Double, to targetSampleRate: Double) -> [Float] {
        guard sourceSampleRate > targetSampleRate else { return samples }
        guard samples.count > 1 else { return samples }

        let ratio = Float(sourceSampleRate / targetSampleRate)  // 48000 / 16000 = 3.0
        guard ratio > 1 else { return samples }

        // Berechne Output-Länge
        let outputLength = Int(Float(samples.count) / ratio)
        guard outputLength > 0 else { return [] }

        var output: [Float] = []
        output.reserveCapacity(outputLength)

        // Lineare Interpolation für korrektes Resampling ohne Aliasing
        var position: Float = 0
        let maxIndex = samples.count - 1

        while Int(position) < maxIndex && output.count < outputLength {
            let index = Int(position)
            let fraction = position - Float(index)

            // Lineare Interpolation zwischen benachbarten Samples
            // Vermeidet Aliasing-Artefakte (Chipmunk-Effekt) die bei einfachem Sample-Picking entstehen
            let interpolated = samples[index] * (1 - fraction) + samples[index + 1] * fraction
            output.append(interpolated)

            position += ratio
        }

        return output
    }

    /// Konvertiert eingehendes Audio (48kHz Stereo) zu Whisper-Format (16kHz Mono)
    private func convertToWhisperFormat(_ samples: [Float]) -> [Float] {
        // 1. Stereo → Mono
        let mono = stereoToMono(samples, channels: config.captureChannels)

        // 2. 48kHz → 16kHz
        let downsampled = downsample(mono, from: config.captureSampleRate, to: config.outputSampleRate)

        return downsampled
    }

    // Track total samples written for logging
    private var totalSamplesWritten = 0

    private func writeToAudioFile(samples: [Float]) async {
        guard let audioURL = audioFileURL else { return }

        // Create audio file if not exists
        // Audio-Datei wird mit Output-Format (16kHz Mono) erstellt
        if audioFile == nil {
            let format = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: config.outputSampleRate,
                channels: AVAudioChannelCount(config.outputChannels),
                interleaved: false
            )!

            do {
                audioFile = try AVAudioFile(forWriting: audioURL, settings: format.settings)
            } catch {
                return
            }
        }

        // Create PCM buffer and write
        guard let format = audioFile?.processingFormat,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else {
            return
        }

        buffer.frameLength = buffer.frameCapacity
        if let channelData = buffer.floatChannelData?[0] {
            for (index, sample) in samples.enumerated() {
                channelData[index] = sample
            }
        }

        do {
            try audioFile?.write(from: buffer)
            totalSamplesWritten += samples.count
        } catch {
            // Audio write failed - continue without crashing
        }
    }

    private func processChunk(final: Bool) async {
        guard !chunkBuffer.isEmpty, let meetingId = currentMeetingId else { return }

        let chunkData = chunkBuffer
        let startTime = chunkStartTime
        let sampleRate = config.outputSampleRate  // 16kHz für Whisper
        let endTime = startTime + (Double(chunkBuffer.count) / sampleRate)

        // Clear buffer for next chunk
        chunkBuffer = []
        chunkStartTime = endTime

        // Create the chunk
        let chunk = AudioChunk(
            meetingId: meetingId,
            samples: chunkData,
            startTime: startTime,
            endTime: endTime,
            sampleRate: sampleRate,
            isFinal: final
        )

        // Notify via callback
        if let callback = onChunkCaptured {
            await callback(chunk)
        }
    }
}

// MARK: - Stream Output Handler

private final class AudioStreamOutput: NSObject, SCStreamOutput, @unchecked Sendable {
    private weak var manager: AudioCaptureManager?
    private var callbackCount: Int = 0
    private var lastLogTime: Date = Date()

    init(manager: AudioCaptureManager) {
        self.manager = manager
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { return }

        // Extract audio data synchronously before passing to async context
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }

        var length = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer)

        guard let dataPointer = dataPointer, length > 0 else { return }

        // Copy audio samples to a Sendable array
        let sampleCount = length / MemoryLayout<Float>.size
        let floatPointer = UnsafeRawPointer(dataPointer).bindMemory(to: Float.self, capacity: sampleCount)
        let samples = Array(UnsafeBufferPointer(start: floatPointer, count: sampleCount))

        // DIAGNOSTIK: Amplitude-Logging
        callbackCount += 1
        let maxAmplitude = samples.map { abs($0) }.max() ?? 0
        let hasAudio = maxAmplitude > 0.01

        // Log alle 5 Sekunden (ca. 100 Callbacks bei 48kHz)
        let now = Date()
        if now.timeIntervalSince(lastLogTime) >= 5.0 {
            print("[DEBUG] AudioStreamOutput: Callback #\(callbackCount), \(samples.count) samples, maxAmp: \(String(format: "%.4f", maxAmplitude))")
            if !hasAudio {
                print("[WARNING] Audio samples are silent (maxAmp < 0.01) - ScreenCaptureKit liefert möglicherweise kein Audio")
            }
            lastLogTime = now
        }

        Task {
            await manager?.handleAudioData(samples)
        }
    }
}

// MARK: - Audio Chunk

struct AudioChunk: Sendable {
    let meetingId: Int64
    let samples: [Float]
    let startTime: TimeInterval
    let endTime: TimeInterval
    let sampleRate: Double
    let isFinal: Bool

    /// Duration in seconds
    var duration: TimeInterval {
        endTime - startTime
    }

    /// Converts samples to 16-bit PCM data for Whisper
    func toPCMData() -> Data {
        let int16Samples = samples.map { sample -> Int16 in
            let clamped = max(-1.0, min(1.0, sample))
            return Int16(clamped * Float(Int16.max))
        }

        return int16Samples.withUnsafeBufferPointer { buffer in
            Data(buffer: buffer)
        }
    }
}

// MARK: - Errors

enum AudioCaptureError: LocalizedError {
    case noDisplayAvailable
    case streamSetupFailed
    case recordingFailed(String)

    var errorDescription: String? {
        switch self {
        case .noDisplayAvailable:
            return "Kein Display für Audio-Capture verfügbar"
        case .streamSetupFailed:
            return "Audio-Stream konnte nicht eingerichtet werden"
        case .recordingFailed(let message):
            return "Audio-Aufnahme fehlgeschlagen: \(message)"
        }
    }
}
