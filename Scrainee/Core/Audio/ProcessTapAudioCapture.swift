// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - DEPENDENCY DOCUMENTATION
// ═══════════════════════════════════════════════════════════════════════════════
//
// FILE: ProcessTapAudioCapture.swift
// PURPOSE: System-Audio-Capture via Core Audio ProcessTap API (macOS 14.2+)
//          Alternative zu ScreenCaptureKit für zuverlässigeres Audio-Capture
// LAYER: Core/Audio
//
// DEPENDENCIES:
//   - CoreAudio: AudioHardwareCreateProcessTap, CATapDescription
//   - AVFoundation: AVAudioEngine, AVAudioFile
//   - Foundation: FileManager, Date
//
// DEPENDENTS:
//   - AudioCaptureManager: Verwendet dies als primäre Capture-Methode auf macOS 14.2+
//
// AVAILABILITY: macOS 14.2+ (Sonoma)
// FALLBACK: ScreenCaptureKit für ältere Versionen
//
// LAST UPDATED: 2026-01-20
// ═══════════════════════════════════════════════════════════════════════════════

import Foundation
import AVFoundation
import CoreAudio

/// Audio capture using Core Audio Process Tap API (macOS 14.2+)
/// This provides more reliable system audio capture than ScreenCaptureKit
@available(macOS 14.2, *)
actor ProcessTapAudioCapture {

    // MARK: - Types

    struct CaptureConfig {
        var sampleRate: Double = 48000
        var channels: Int = 2
        var outputSampleRate: Double = 16000  // For Whisper
        var chunkDuration: TimeInterval = 30
    }

    enum CaptureError: LocalizedError {
        case tapCreationFailed(OSStatus)
        case aggregateDeviceFailed(OSStatus)
        case engineSetupFailed(Error)
        case notAvailable
        case alreadyRecording

        var errorDescription: String? {
            switch self {
            case .tapCreationFailed(let status):
                return "Failed to create audio tap: \(status)"
            case .aggregateDeviceFailed(let status):
                return "Failed to create aggregate device: \(status)"
            case .engineSetupFailed(let error):
                return "Audio engine setup failed: \(error.localizedDescription)"
            case .notAvailable:
                return "Process tap not available on this macOS version"
            case .alreadyRecording:
                return "Already recording"
            }
        }
    }

    // MARK: - State

    private(set) var isRecording = false
    private var currentMeetingId: Int64?

    private var tapObjectID: AudioObjectID = kAudioObjectUnknown
    private var aggregateDeviceID: AudioObjectID = kAudioObjectUnknown
    private var audioEngine: AVAudioEngine?

    private var audioFileURL: URL?
    private var audioFile: AVAudioFile?

    // Chunk management
    private var chunkBuffer: [Float] = []
    private var chunkStartTime: TimeInterval = 0
    private var config = CaptureConfig()

    private var onChunkCaptured: (@Sendable (AudioChunk) async -> Void)?

    // MARK: - Public API

    func setOnChunkCaptured(_ callback: @escaping @Sendable (AudioChunk) async -> Void) {
        onChunkCaptured = callback
    }

    /// Check if Process Tap API is available
    static var isAvailable: Bool {
        if #available(macOS 14.2, *) {
            return true
        }
        return false
    }

    /// Start capturing system audio
    func startCapture(for meetingId: Int64, config: CaptureConfig = CaptureConfig()) async throws {
        guard !isRecording else {
            throw CaptureError.alreadyRecording
        }

        self.config = config
        self.currentMeetingId = meetingId

        // Create audio file
        let audioURL = try createAudioFileURL(for: meetingId)
        self.audioFileURL = audioURL

        // Setup process tap
        try setupProcessTap()

        // Setup audio engine
        try setupAudioEngine()

        isRecording = true
        print("[DEBUG] ProcessTapAudioCapture: Recording started for meeting \(meetingId)")
    }

    /// Stop capturing and return audio file URL
    func stopCapture() async -> URL? {
        guard isRecording else { return nil }

        // Stop audio engine
        audioEngine?.stop()
        audioEngine = nil

        // Destroy tap and aggregate device
        destroyTap()

        // Finalize file
        audioFile = nil

        // Process remaining buffer
        if !chunkBuffer.isEmpty {
            await processChunk(final: true)
        }

        // Validate file
        var resultURL = audioFileURL
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

        // Reset state
        isRecording = false
        currentMeetingId = nil
        chunkBuffer = []
        audioFileURL = nil

        print("[DEBUG] ProcessTapAudioCapture: Recording stopped")
        return resultURL
    }

    // MARK: - Private Methods

    private func createAudioFileURL(for meetingId: Int64) throws -> URL {
        let audioDirectory = StorageManager.shared.applicationSupportDirectory.appendingPathComponent("audio")
        try FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = dateFormatter.string(from: Date())

        let filename = "meeting_\(meetingId)_\(timestamp).wav"
        return audioDirectory.appendingPathComponent(filename)
    }

    private func setupProcessTap() throws {
        // Create a global tap that captures all system audio
        // We exclude no processes to get everything
        let tapDescription = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        tapDescription.uuid = UUID()
        tapDescription.name = "Scrainee-AudioTap-\(UUID().uuidString.prefix(8))"
        tapDescription.isPrivate = true
        tapDescription.muteBehavior = .unmuted  // Don't mute the system audio
        tapDescription.isExclusive = false  // Allow other taps
        tapDescription.isMixdown = true  // Mix to stereo

        // Create the process tap
        var tapID: AudioObjectID = kAudioObjectUnknown
        let status = AudioHardwareCreateProcessTap(tapDescription, &tapID)

        guard status == noErr else {
            print("[ERROR] ProcessTapAudioCapture: Failed to create tap, status: \(status)")
            throw CaptureError.tapCreationFailed(status)
        }

        self.tapObjectID = tapID
        print("[DEBUG] ProcessTapAudioCapture: Created tap with ID \(tapID)")

        // Create aggregate device including the tap
        try createAggregateDevice(tapUUID: tapDescription.uuid)
    }

    private func createAggregateDevice(tapUUID: UUID?) throws {
        guard let uuid = tapUUID else {
            throw CaptureError.tapCreationFailed(-1)
        }

        // Get the default output device
        var defaultOutputID: AudioObjectID = kAudioObjectUnknown
        var propertySize = UInt32(MemoryLayout<AudioObjectID>.size)
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &propertySize,
            &defaultOutputID
        )

        // Get output device UID
        var outputUID: CFString?
        propertySize = UInt32(MemoryLayout<CFString?>.size)
        propertyAddress.mSelector = kAudioDevicePropertyDeviceUID
        AudioObjectGetPropertyData(
            defaultOutputID,
            &propertyAddress,
            0,
            nil,
            &propertySize,
            &outputUID
        )

        // Build aggregate device properties
        let aggregateUID = "Scrainee-Aggregate-\(UUID().uuidString.prefix(8))"
        let aggregateName = "Scrainee Audio Capture"

        // Tap subdevice
        let tapSubDevice: [String: Any] = [
            kAudioSubTapUIDKey as String: uuid.uuidString
        ]

        let aggregateProperties: [String: Any] = [
            kAudioAggregateDeviceUIDKey as String: aggregateUID,
            kAudioAggregateDeviceNameKey as String: aggregateName,
            kAudioAggregateDeviceIsPrivateKey as String: true,
            kAudioAggregateDeviceTapListKey as String: [tapSubDevice],
            kAudioAggregateDeviceTapAutoStartKey as String: true
        ]

        var aggregateID: AudioObjectID = kAudioObjectUnknown
        let status = AudioHardwareCreateAggregateDevice(
            aggregateProperties as CFDictionary,
            &aggregateID
        )

        guard status == noErr else {
            print("[ERROR] ProcessTapAudioCapture: Failed to create aggregate device, status: \(status)")
            throw CaptureError.aggregateDeviceFailed(status)
        }

        self.aggregateDeviceID = aggregateID
        print("[DEBUG] ProcessTapAudioCapture: Created aggregate device with ID \(aggregateID)")
    }

    private func setupAudioEngine() throws {
        let engine = AVAudioEngine()

        // Set the aggregate device as input
        let audioUnit = engine.inputNode.audioUnit!

        var aggregateID = self.aggregateDeviceID
        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &aggregateID,
            UInt32(MemoryLayout<AudioObjectID>.size)
        )

        if status != noErr {
            print("[WARNING] ProcessTapAudioCapture: Could not set aggregate device: \(status)")
        }

        // Query actual hardware sample rate from aggregate device
        if let hwSampleRate = getDeviceSampleRate(deviceID: aggregateDeviceID) {
            config.sampleRate = hwSampleRate
            print("[DEBUG] ProcessTapAudioCapture: Using hardware sample rate: \(hwSampleRate) Hz")
        } else {
            print("[WARNING] ProcessTapAudioCapture: Could not query hardware sample rate, using default: \(config.sampleRate) Hz")
        }

        // Create explicit capture format matching hardware
        guard let captureFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: config.sampleRate,
            channels: AVAudioChannelCount(config.channels),
            interleaved: false
        ) else {
            throw CaptureError.engineSetupFailed(NSError(domain: "ProcessTapAudioCapture", code: -1, userInfo: [NSLocalizedDescriptionKey: "Could not create capture format"]))
        }

        print("[DEBUG] ProcessTapAudioCapture: Using capture format: \(captureFormat)")

        // Install tap on input node with explicit format
        engine.inputNode.installTap(onBus: 0, bufferSize: 4096, format: captureFormat) { [weak self] buffer, time in
            guard let self = self else { return }

            // Extract float samples from buffer
            guard let channelData = buffer.floatChannelData else { return }
            let frameCount = Int(buffer.frameLength)
            let channelCount = Int(buffer.format.channelCount)

            // Interleave channels if stereo
            var samples: [Float] = []
            samples.reserveCapacity(frameCount * channelCount)

            if channelCount == 2 {
                for frame in 0..<frameCount {
                    samples.append(channelData[0][frame])  // Left
                    samples.append(channelData[1][frame])  // Right
                }
            } else {
                samples = Array(UnsafeBufferPointer(start: channelData[0], count: frameCount))
            }

            // Log amplitude periodically
            let maxAmp = samples.map { abs($0) }.max() ?? 0

            // Process samples asynchronously
            Task {
                await self.handleAudioSamples(samples, maxAmplitude: maxAmp)
            }
        }

        do {
            try engine.start()
            self.audioEngine = engine
            print("[DEBUG] ProcessTapAudioCapture: Audio engine started")
        } catch {
            throw CaptureError.engineSetupFailed(error)
        }
    }

    private var sampleCounter = 0
    private var lastLogTime = Date()

    private func handleAudioSamples(_ samples: [Float], maxAmplitude: Float) async {
        guard isRecording else { return }

        sampleCounter += samples.count

        // Log every 5 seconds
        let now = Date()
        if now.timeIntervalSince(lastLogTime) >= 5.0 {
            print("[DEBUG] ProcessTapAudioCapture: \(sampleCounter) samples, maxAmp: \(String(format: "%.4f", maxAmplitude))")
            if maxAmplitude < 0.01 {
                print("[WARNING] ProcessTapAudioCapture: Audio is silent")
            }
            lastLogTime = now
        }

        // Convert to Whisper format (16kHz Mono)
        let convertedSamples = convertToWhisperFormat(samples)

        // Append to chunk buffer
        chunkBuffer.append(contentsOf: convertedSamples)

        // Write to file
        await writeToAudioFile(samples: convertedSamples)

        // Check if chunk is complete
        let chunkSamples = Int(config.chunkDuration * config.outputSampleRate)
        if chunkBuffer.count >= chunkSamples {
            await processChunk(final: false)
        }
    }

    private func convertToWhisperFormat(_ samples: [Float]) -> [Float] {
        // 1. Stereo → Mono (use max amplitude channel)
        let mono = stereoToMono(samples, channels: config.channels)

        // 2. Downsample to 16kHz
        let downsampled = downsample(mono, from: config.sampleRate, to: config.outputSampleRate)

        return downsampled
    }

    private func stereoToMono(_ samples: [Float], channels: Int) -> [Float] {
        guard channels == 2, samples.count >= 2 else { return samples }

        var mono: [Float] = []
        mono.reserveCapacity(samples.count / 2)

        for i in stride(from: 0, to: samples.count - 1, by: 2) {
            let left = samples[i]
            let right = samples[i + 1]

            // Use channel with higher amplitude to avoid phase cancellation
            if abs(left) >= abs(right) {
                mono.append(left)
            } else {
                mono.append(right)
            }
        }

        return mono
    }

    private func downsample(_ samples: [Float], from sourceSampleRate: Double, to targetSampleRate: Double) -> [Float] {
        guard sourceSampleRate > targetSampleRate, samples.count > 1 else { return samples }

        let ratio = Float(sourceSampleRate / targetSampleRate)
        let outputLength = Int(Float(samples.count) / ratio)
        guard outputLength > 0 else { return [] }

        var output: [Float] = []
        output.reserveCapacity(outputLength)

        var position: Float = 0
        let maxIndex = samples.count - 1

        while Int(position) < maxIndex && output.count < outputLength {
            let index = Int(position)
            let fraction = position - Float(index)
            let interpolated = samples[index] * (1 - fraction) + samples[index + 1] * fraction
            output.append(interpolated)
            position += ratio
        }

        return output
    }

    private func writeToAudioFile(samples: [Float]) async {
        guard let audioURL = audioFileURL else { return }

        if audioFile == nil {
            let format = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: config.outputSampleRate,
                channels: 1,
                interleaved: false
            )!

            do {
                audioFile = try AVAudioFile(forWriting: audioURL, settings: format.settings)
            } catch {
                print("[ERROR] ProcessTapAudioCapture: Could not create audio file: \(error)")
                return
            }
        }

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
            print("[ERROR] ProcessTapAudioCapture: Write failed: \(error)")
        }
    }

    private func processChunk(final: Bool) async {
        guard !chunkBuffer.isEmpty, let meetingId = currentMeetingId else { return }

        let chunkData = chunkBuffer
        let startTime = chunkStartTime
        let endTime = startTime + (Double(chunkBuffer.count) / config.outputSampleRate)

        chunkBuffer = []
        chunkStartTime = endTime

        let chunk = AudioChunk(
            meetingId: meetingId,
            samples: chunkData,
            startTime: startTime,
            endTime: endTime,
            sampleRate: config.outputSampleRate,
            isFinal: final
        )

        if let callback = onChunkCaptured {
            await callback(chunk)
        }
    }

    private func destroyTap() {
        if aggregateDeviceID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            aggregateDeviceID = kAudioObjectUnknown
        }

        if tapObjectID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapObjectID)
            tapObjectID = kAudioObjectUnknown
        }
    }

    // MARK: - Audio Format Helpers

    /// Query the nominal sample rate of an audio device
    private func getDeviceSampleRate(deviceID: AudioObjectID) -> Double? {
        var sampleRate: Float64 = 0
        var propertySize = UInt32(MemoryLayout<Float64>.size)
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &propertySize,
            &sampleRate
        )

        if status == noErr && sampleRate > 0 {
            return sampleRate
        }
        return nil
    }
}
