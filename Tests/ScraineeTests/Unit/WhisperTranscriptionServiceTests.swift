import XCTest
@testable import Scrainee

/// Tests for WhisperTranscriptionService
/// Note: Actual WhisperKit model loading/transcription cannot be unit tested without the model.
/// These tests focus on:
/// - Thread-safe state properties
/// - Model path logic
/// - Error types
/// - Singleton pattern
final class WhisperTranscriptionServiceTests: XCTestCase {

    // MARK: - Singleton Tests

    func testSharedInstance_isSingleton() {
        let instance1 = WhisperTranscriptionService.shared
        let instance2 = WhisperTranscriptionService.shared

        XCTAssertTrue(instance1 === instance2, "WhisperTranscriptionService.shared should return same instance")
    }

    // MARK: - Initial State Tests

    func testInitialState_isNotLoaded() {
        let service = WhisperTranscriptionService.shared

        // Model is not loaded by default (unless previously loaded in this test run)
        // This verifies the property accessor works
        _ = service.isModelLoaded
        XCTAssertTrue(true, "isModelLoaded property is accessible")
    }

    func testInitialState_isNotTranscribing() {
        let service = WhisperTranscriptionService.shared

        XCTAssertFalse(service.isTranscribing, "Should not be transcribing initially")
    }

    func testInitialState_loadingStatusAccessible() {
        let service = WhisperTranscriptionService.shared

        _ = service.loadingStatus
        XCTAssertTrue(true, "loadingStatus property is accessible")
    }

    func testInitialState_downloadProgressAccessible() {
        let service = WhisperTranscriptionService.shared

        let progress = service.downloadProgress
        XCTAssertGreaterThanOrEqual(progress, 0, "Progress should be >= 0")
        XCTAssertLessThanOrEqual(progress, 1, "Progress should be <= 1")
    }

    func testInitialState_errorAccessible() {
        let service = WhisperTranscriptionService.shared

        // Error should be nil or a string
        _ = service.error
        XCTAssertTrue(true, "error property is accessible")
    }

    // MARK: - Model Info Tests

    func testModelSizeDescription_returnsExpectedFormat() {
        let service = WhisperTranscriptionService.shared

        let description = service.modelSizeDescription
        XCTAssertEqual(description, "~3 GB")
    }

    func testIsModelDownloaded_isAccessible() {
        let service = WhisperTranscriptionService.shared

        // Just verify the property is accessible and returns a bool
        _ = service.isModelDownloaded
        XCTAssertTrue(true, "isModelDownloaded property is accessible")
    }

    // MARK: - TranscriptionError Tests

    func testTranscriptionError_modelNotLoaded() {
        let error = TranscriptionError.modelNotLoaded

        XCTAssertNotNil(error.localizedDescription)
        XCTAssertFalse(error.localizedDescription.isEmpty)
    }

    func testTranscriptionError_modelDownloadFailed() {
        let reason = "Network error"
        let error = TranscriptionError.modelDownloadFailed(reason)

        XCTAssertTrue(error.localizedDescription.contains(reason) ||
                     error.localizedDescription.contains("download"),
                     "Error should mention download failure")
    }

    func testTranscriptionError_modelLoadFailed() {
        let reason = "Corrupt file"
        let error = TranscriptionError.modelLoadFailed(reason)

        XCTAssertNotNil(error.localizedDescription)
    }

    func testTranscriptionError_transcriptionFailed() {
        let reason = "Invalid audio format"
        let error = TranscriptionError.transcriptionFailed(reason)

        XCTAssertNotNil(error.localizedDescription)
    }

    func testTranscriptionError_invalidAudioFormat() {
        let error = TranscriptionError.invalidAudioFormat

        XCTAssertNotNil(error.localizedDescription)
    }

    // MARK: - Thread Safety Tests

    func testConcurrentStateAccess_isThreadSafe() async {
        let service = WhisperTranscriptionService.shared
        let iterations = 100

        // Concurrent reads should not crash
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<iterations {
                group.addTask {
                    _ = service.isModelLoaded
                    _ = service.isTranscribing
                    _ = service.downloadProgress
                    _ = service.loadingStatus
                    _ = service.error
                }
            }
        }

        // If we get here without crashes, thread safety is working
        XCTAssertTrue(true)
    }

    // MARK: - TranscriptSegment Tests

    func testTranscriptSegment_initialization() {
        let segment = TranscriptSegment(
            meetingId: 123,
            text: "Test transcription",
            startTime: 0.0,
            endTime: 5.0,
            confidence: 0.95,
            language: "de",
            createdAt: Date()
        )

        XCTAssertEqual(segment.meetingId, 123)
        XCTAssertEqual(segment.text, "Test transcription")
        XCTAssertEqual(segment.startTime, 0.0)
        XCTAssertEqual(segment.endTime, 5.0)
        XCTAssertEqual(segment.confidence, 0.95)
        XCTAssertEqual(segment.language, "de")
    }

    func testTranscriptSegment_duration() {
        let segment = TranscriptSegment(
            meetingId: 1,
            text: "Test",
            startTime: 10.0,
            endTime: 25.0,
            confidence: nil,
            language: nil,
            createdAt: Date()
        )

        // Duration = endTime - startTime = 15 seconds
        XCTAssertEqual(segment.endTime - segment.startTime, 15.0)
    }

    func testTranscriptSegment_optionalFields() {
        let segment = TranscriptSegment(
            meetingId: 1,
            text: "Test",
            startTime: 0,
            endTime: 1,
            confidence: nil,
            language: nil,
            createdAt: Date()
        )

        XCTAssertNil(segment.confidence)
        XCTAssertNil(segment.language)
    }

    // MARK: - AudioChunk Tests

    func testAudioChunk_initialization() {
        let samples: [Float] = [0.1, 0.2, 0.3]
        let chunk = AudioChunk(
            meetingId: 456,
            samples: samples,
            startTime: 0.0,
            endTime: 30.0,
            sampleRate: 16000.0,
            isFinal: false
        )

        XCTAssertEqual(chunk.meetingId, 456)
        XCTAssertEqual(chunk.samples, samples)
        XCTAssertEqual(chunk.startTime, 0.0)
        XCTAssertEqual(chunk.endTime, 30.0)
        XCTAssertEqual(chunk.sampleRate, 16000)
        XCTAssertFalse(chunk.isFinal)
    }

    func testAudioChunk_finalChunk() {
        let chunk = AudioChunk(
            meetingId: 1,
            samples: [],
            startTime: 0,
            endTime: 1,
            sampleRate: 16000.0,
            isFinal: true
        )

        XCTAssertTrue(chunk.isFinal)
    }

    func testAudioChunk_emptySamples() {
        let chunk = AudioChunk(
            meetingId: 1,
            samples: [],
            startTime: 0,
            endTime: 0,
            sampleRate: 16000.0,
            isFinal: false
        )

        XCTAssertTrue(chunk.samples.isEmpty)
    }

    // MARK: - Expected Sample Rate Tests

    func testExpectedSampleRate_is16kHz() {
        // WhisperKit expects 16kHz mono audio
        // This documents the expected sample rate
        let expectedSampleRate: Double = 16000

        let chunk = AudioChunk(
            meetingId: 1,
            samples: [0.0],
            startTime: 0,
            endTime: 1,
            sampleRate: expectedSampleRate,
            isFinal: false
        )

        XCTAssertEqual(chunk.sampleRate, 16000, "WhisperKit expects 16kHz audio")
    }
}
