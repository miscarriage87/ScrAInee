import Foundation
import AVFoundation
import ScreenCaptureKit

/// Manages system audio capture during meetings using ScreenCaptureKit
actor AudioCaptureManager {
    static let shared = AudioCaptureManager()

    // MARK: - State

    private(set) var isRecording = false
    private var currentMeetingId: Int64?
    private var meetingStartTime: Date?

    // ScreenCaptureKit
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
        var sampleRate: Double = 16000      // 16kHz for Whisper
        var channels: Int = 1                // Mono
        var chunkDuration: TimeInterval = 30 // Seconds per chunk
    }

    private var config = Config()

    // MARK: - Initialization

    private init() {}

    // MARK: - Public API

    /// Starts recording audio for a meeting
    func startRecording(for meetingId: Int64, config: Config = Config()) async throws {
        guard !isRecording else {
            print("AudioCaptureManager: Already recording")
            return
        }

        self.config = config
        self.currentMeetingId = meetingId
        self.meetingStartTime = Date()

        // Create audio file
        let audioURL = try createAudioFileURL(for: meetingId)
        self.audioFileURL = audioURL

        // Setup ScreenCaptureKit stream with audio
        try await setupAudioStream()

        isRecording = true
        print("AudioCaptureManager: Started recording for meeting \(meetingId)")
    }

    /// Stops recording and returns the audio file URL
    func stopRecording() async -> URL? {
        guard isRecording else { return nil }

        // Stop the stream
        if let stream = stream {
            do {
                try await stream.stopCapture()
            } catch {
                print("AudioCaptureManager: Error stopping stream: \(error)")
            }
        }

        // Finalize audio file
        audioFile = nil

        // Process any remaining buffer
        if !chunkBuffer.isEmpty {
            await processChunk(final: true)
        }

        let resultURL = audioFileURL

        // Reset state
        isRecording = false
        stream = nil
        streamOutput = nil
        currentMeetingId = nil
        meetingStartTime = nil
        chunkBuffer = []

        print("AudioCaptureManager: Stopped recording")
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

    private func setupAudioStream() async throws {
        // Get shareable content
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)

        guard let display = content.displays.first else {
            throw AudioCaptureError.noDisplayAvailable
        }

        // Create content filter (we need to capture something to get audio)
        let filter = SCContentFilter(display: display, excludingWindows: [])

        // Configure stream for audio capture
        let streamConfig = SCStreamConfiguration()
        streamConfig.capturesAudio = true
        streamConfig.excludesCurrentProcessAudio = false
        streamConfig.sampleRate = Int(config.sampleRate)
        streamConfig.channelCount = config.channels

        // We don't need video, but ScreenCaptureKit requires it
        streamConfig.width = 1
        streamConfig.height = 1
        streamConfig.minimumFrameInterval = CMTime(value: 1, timescale: 1)  // 1 FPS minimum

        // Create stream output handler
        let output = AudioStreamOutput(manager: self)
        self.streamOutput = output

        // Create and start stream
        let stream = SCStream(filter: filter, configuration: streamConfig, delegate: nil)
        try stream.addStreamOutput(output, type: .audio, sampleHandlerQueue: .global(qos: .userInteractive))

        try await stream.startCapture()
        self.stream = stream
    }

    /// Called by StreamOutput when audio samples are received (from CMSampleBuffer)
    func handleAudioSamples(_ sampleBuffer: CMSampleBuffer) async {
        guard isRecording else { return }

        // Extract audio data from sample buffer
        guard let audioBuffer = extractAudioBuffer(from: sampleBuffer) else { return }

        await handleAudioData(audioBuffer)
    }

    /// Called by StreamOutput when audio data is received (already extracted samples)
    func handleAudioData(_ samples: [Float]) async {
        guard isRecording else { return }

        // Append to chunk buffer
        chunkBuffer.append(contentsOf: samples)

        // Write to file
        await writeToAudioFile(samples: samples)

        // Check if chunk is complete
        let chunkSamples = Int(config.chunkDuration * config.sampleRate)
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

    private func writeToAudioFile(samples: [Float]) async {
        guard let audioURL = audioFileURL else { return }

        // Create audio file if not exists
        if audioFile == nil {
            let format = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: config.sampleRate,
                channels: AVAudioChannelCount(config.channels),
                interleaved: false
            )!

            do {
                audioFile = try AVAudioFile(forWriting: audioURL, settings: format.settings)
            } catch {
                print("AudioCaptureManager: Failed to create audio file: \(error)")
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
        } catch {
            print("AudioCaptureManager: Failed to write audio: \(error)")
        }
    }

    private func processChunk(final: Bool) async {
        guard !chunkBuffer.isEmpty, let meetingId = currentMeetingId else { return }

        let chunkData = chunkBuffer
        let startTime = chunkStartTime
        let sampleRate = config.sampleRate
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
