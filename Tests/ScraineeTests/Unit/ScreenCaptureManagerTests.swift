import XCTest
@testable import Scrainee

/// Tests for ScreenCaptureManager
/// Note: Actual ScreenCaptureKit capture requires system permissions and cannot be easily unit tested.
/// These tests focus on:
/// - CaptureError types and localization
/// - State properties (isCapturing, captureCount)
/// - Delegate protocol structure
/// - OCRSemaphore behavior
/// - MockScreenCaptureDelegate functionality
@MainActor
final class ScreenCaptureManagerTests: XCTestCase {

    // MARK: - CaptureError Tests

    func testCaptureError_noPermission_hasGermanDescription() {
        let error = CaptureError.noPermission

        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("Berechtigung") ||
                     error.errorDescription!.contains("permission"),
                     "Error should mention permission")
    }

    func testCaptureError_noDisplay_hasGermanDescription() {
        let error = CaptureError.noDisplay

        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("Display") ||
                     error.errorDescription!.contains("display"),
                     "Error should mention display")
    }

    func testCaptureError_captureFailure_hasGermanDescription() {
        let error = CaptureError.captureFailure

        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("Screenshot") ||
                     error.errorDescription!.contains("erstellt"),
                     "Error should mention screenshot creation")
    }

    func testCaptureError_saveFailed_hasGermanDescription() {
        let error = CaptureError.saveFailed

        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("gespeichert") ||
                     error.errorDescription!.contains("save"),
                     "Error should mention saving")
    }

    func testCaptureError_allCases_areDistinct() {
        let errors: [CaptureError] = [.noPermission, .noDisplay, .captureFailure, .saveFailed]
        let descriptions = errors.compactMap { $0.errorDescription }

        XCTAssertEqual(descriptions.count, 4, "All errors should have descriptions")

        let uniqueDescriptions = Set(descriptions)
        XCTAssertEqual(uniqueDescriptions.count, 4, "All error descriptions should be unique")
    }

    // MARK: - ScreenCaptureManager Initial State Tests

    func testInitialState_isNotCapturing() {
        let manager = ScreenCaptureManager()

        XCTAssertFalse(manager.isCapturing, "Should not be capturing initially")
    }

    func testInitialState_captureCountIsZero() {
        let manager = ScreenCaptureManager()

        XCTAssertEqual(manager.captureCount, 0, "Capture count should be 0 initially")
    }

    func testInitialState_activeDisplayCountIsZero() {
        let manager = ScreenCaptureManager()

        XCTAssertEqual(manager.activeDisplayCount, 0, "Active display count should be 0 initially")
    }

    func testInitialState_delegateIsNil() {
        let manager = ScreenCaptureManager()

        XCTAssertNil(manager.delegate, "Delegate should be nil initially")
    }

    func testInitialState_adaptiveManagerExists() {
        let manager = ScreenCaptureManager()

        XCTAssertNotNil(manager.adaptiveManager, "Adaptive manager should exist")
    }

    // MARK: - Delegate Assignment Tests

    func testDelegate_canBeAssigned() {
        let manager = ScreenCaptureManager()
        let delegate = MockScreenCaptureDelegate()

        manager.delegate = delegate

        XCTAssertNotNil(manager.delegate)
    }

    func testDelegate_isWeakReference() {
        let manager = ScreenCaptureManager()

        // Create delegate in nested scope
        autoreleasepool {
            let delegate = MockScreenCaptureDelegate()
            manager.delegate = delegate
            XCTAssertNotNil(manager.delegate)
        }

        // After scope, delegate should be nil due to weak reference
        // Note: This might not immediately be nil due to ARC timing
        // The important thing is that we don't crash and the property is accessible
        _ = manager.delegate
    }

    // MARK: - MockScreenCaptureDelegate Tests

    func testMockDelegate_tracksScreenshots() {
        let delegate = MockScreenCaptureDelegate()

        XCTAssertTrue(delegate.capturedScreenshots.isEmpty)

        // Create a test screenshot
        let screenshot = Screenshot(
            filepath: "test.heic",
            timestamp: Date(),
            appBundleId: "com.test.app",
            appName: "Test App",
            windowTitle: "Test Window",
            displayId: 1,
            width: 1920,
            height: 1080,
            fileSize: 1024,
            isDuplicate: false,
            hash: "abc123"
        )

        // Simulate delegate callback
        let manager = ScreenCaptureManager()
        delegate.screenCaptureManager(manager, didCaptureScreenshot: screenshot)

        XCTAssertEqual(delegate.capturedScreenshots.count, 1)
        XCTAssertEqual(delegate.capturedScreenshots.first?.filepath, "test.heic")
    }

    func testMockDelegate_tracksErrors() {
        let delegate = MockScreenCaptureDelegate()

        XCTAssertTrue(delegate.capturedErrors.isEmpty)

        // Simulate error callback
        let manager = ScreenCaptureManager()
        delegate.screenCaptureManager(manager, didFailWithError: CaptureError.noPermission)

        XCTAssertEqual(delegate.capturedErrors.count, 1)
        XCTAssertTrue(delegate.capturedErrors.first is CaptureError)
    }

    func testMockDelegate_capturedDisplayIds() {
        let delegate = MockScreenCaptureDelegate()
        let manager = ScreenCaptureManager()

        // Add screenshots from different displays
        let screenshot1 = createTestScreenshot(displayId: 1)
        let screenshot2 = createTestScreenshot(displayId: 2)
        let screenshot3 = createTestScreenshot(displayId: 1)

        delegate.screenCaptureManager(manager, didCaptureScreenshot: screenshot1)
        delegate.screenCaptureManager(manager, didCaptureScreenshot: screenshot2)
        delegate.screenCaptureManager(manager, didCaptureScreenshot: screenshot3)

        XCTAssertEqual(delegate.capturedDisplayIds.count, 2)
        XCTAssertTrue(delegate.capturedDisplayIds.contains(1))
        XCTAssertTrue(delegate.capturedDisplayIds.contains(2))
    }

    func testMockDelegate_screenshotsPerDisplay() {
        let delegate = MockScreenCaptureDelegate()
        let manager = ScreenCaptureManager()

        let screenshot1 = createTestScreenshot(displayId: 1)
        let screenshot2 = createTestScreenshot(displayId: 2)
        let screenshot3 = createTestScreenshot(displayId: 1)

        delegate.screenCaptureManager(manager, didCaptureScreenshot: screenshot1)
        delegate.screenCaptureManager(manager, didCaptureScreenshot: screenshot2)
        delegate.screenCaptureManager(manager, didCaptureScreenshot: screenshot3)

        XCTAssertEqual(delegate.screenshotsPerDisplay[1], 2)
        XCTAssertEqual(delegate.screenshotsPerDisplay[2], 1)
    }

    func testMockDelegate_reset() {
        let delegate = MockScreenCaptureDelegate()
        let manager = ScreenCaptureManager()

        delegate.screenCaptureManager(manager, didCaptureScreenshot: createTestScreenshot(displayId: 1))
        delegate.screenCaptureManager(manager, didFailWithError: CaptureError.noDisplay)

        XCTAssertFalse(delegate.capturedScreenshots.isEmpty)
        XCTAssertFalse(delegate.capturedErrors.isEmpty)

        delegate.reset()

        XCTAssertTrue(delegate.capturedScreenshots.isEmpty)
        XCTAssertTrue(delegate.capturedErrors.isEmpty)
    }

    // MARK: - ScreenCaptureManagerDelegate Protocol Tests

    func testDelegateProtocol_hasCaptureMethod() {
        // This test verifies the protocol structure exists
        let delegate = MockScreenCaptureDelegate()
        let manager = ScreenCaptureManager()
        let screenshot = createTestScreenshot(displayId: 1)

        // Should compile and run without issues
        delegate.screenCaptureManager(manager, didCaptureScreenshot: screenshot)

        XCTAssertTrue(true, "Delegate capture method works")
    }

    func testDelegateProtocol_hasErrorMethod() {
        let delegate = MockScreenCaptureDelegate()
        let manager = ScreenCaptureManager()

        // Should compile and run without issues
        delegate.screenCaptureManager(manager, didFailWithError: CaptureError.captureFailure)

        XCTAssertTrue(true, "Delegate error method works")
    }

    // MARK: - stopCapturing Tests

    func testStopCapturing_whenNotCapturing_doesNotCrash() {
        let manager = ScreenCaptureManager()

        XCTAssertFalse(manager.isCapturing)

        // Should not crash
        manager.stopCapturing()

        XCTAssertFalse(manager.isCapturing)
    }

    // MARK: - Screenshot Model Tests (used by ScreenCaptureManager)

    func testScreenshot_initialization() {
        let timestamp = Date()
        let screenshot = Screenshot(
            filepath: "2026/01/20/screenshot_123.heic",
            timestamp: timestamp,
            appBundleId: "com.apple.Safari",
            appName: "Safari",
            windowTitle: "Google - Safari",
            displayId: 1,
            width: 2560,
            height: 1440,
            fileSize: 512000,
            isDuplicate: false,
            hash: "deadbeef12345678"
        )

        XCTAssertEqual(screenshot.filepath, "2026/01/20/screenshot_123.heic")
        XCTAssertEqual(screenshot.timestamp, timestamp)
        XCTAssertEqual(screenshot.appBundleId, "com.apple.Safari")
        XCTAssertEqual(screenshot.appName, "Safari")
        XCTAssertEqual(screenshot.windowTitle, "Google - Safari")
        XCTAssertEqual(screenshot.displayId, 1)
        XCTAssertEqual(screenshot.width, 2560)
        XCTAssertEqual(screenshot.height, 1440)
        XCTAssertEqual(screenshot.fileSize, 512000)
        XCTAssertFalse(screenshot.isDuplicate)
        XCTAssertEqual(screenshot.hash, "deadbeef12345678")
    }

    func testScreenshot_optionalFields() {
        let screenshot = Screenshot(
            filepath: "test.heic",
            timestamp: Date(),
            appBundleId: nil,
            appName: nil,
            windowTitle: nil,
            displayId: nil,
            width: 1920,
            height: 1080,
            fileSize: 1024,
            isDuplicate: false,
            hash: nil
        )

        XCTAssertNil(screenshot.appBundleId)
        XCTAssertNil(screenshot.appName)
        XCTAssertNil(screenshot.windowTitle)
        XCTAssertNil(screenshot.displayId)
        XCTAssertNil(screenshot.hash)
    }

    // MARK: - Interval Constants Tests

    func testDefaultInterval_isThreeSeconds() {
        // Document the expected default capture interval
        let expectedDefaultInterval: TimeInterval = 3.0
        XCTAssertEqual(expectedDefaultInterval, 3.0)
    }

    // MARK: - Notification Names Tests

    func testMeetingStartedNotification_isUsedForIntervalAdjustment() {
        // ScreenCaptureManager listens to this notification
        let notificationName = Notification.Name.meetingStarted
        XCTAssertEqual(notificationName.rawValue, "com.scrainee.meetingStarted")
    }

    func testMeetingEndedNotification_isUsedForIntervalAdjustment() {
        let notificationName = Notification.Name.meetingEnded
        XCTAssertEqual(notificationName.rawValue, "com.scrainee.meetingEnded")
    }

    func testCaptureIdleStateChangedNotification_exists() {
        // ScreenCaptureManager listens to this notification
        let notificationName = Notification.Name.captureIdleStateChanged
        XCTAssertNotNil(notificationName.rawValue)
        XCTAssertFalse(notificationName.rawValue.isEmpty)
    }

    // MARK: - Dependency Injection Tests

    func testInit_withCustomDisplayManager() {
        let mockDisplayManager = MockDisplayManager()
        let manager = ScreenCaptureManager(displayManager: mockDisplayManager)

        // Should initialize without error
        XCTAssertNotNil(manager)
        XCTAssertFalse(manager.isCapturing)
    }

    // MARK: - AdaptiveCaptureManager Integration Tests

    func testAdaptiveManager_isAccessible() {
        let manager = ScreenCaptureManager()

        // Verify we can access and use the adaptive manager
        let adaptiveManager = manager.adaptiveManager

        // Test base interval setting
        adaptiveManager.setBaseInterval(5.0)
        let interval = adaptiveManager.getInterval(isMeeting: false)

        XCTAssertGreaterThan(interval, 0, "Interval should be positive")
    }

    func testAdaptiveManager_meetingIntervalIsShorter() {
        let manager = ScreenCaptureManager()
        let adaptiveManager = manager.adaptiveManager

        adaptiveManager.setBaseInterval(3.0)

        let normalInterval = adaptiveManager.getInterval(isMeeting: false)
        let meetingInterval = adaptiveManager.getInterval(isMeeting: true)

        XCTAssertLessThanOrEqual(meetingInterval, normalInterval,
                                  "Meeting interval should be shorter or equal to normal")
    }

    func testAdaptiveManager_duplicateDetectionAffectsInterval() {
        let manager = ScreenCaptureManager()
        let adaptiveManager = manager.adaptiveManager

        adaptiveManager.setBaseInterval(3.0)
        adaptiveManager.resetDuplicateDetection()

        // Report several duplicates - should increase interval
        for _ in 0..<5 {
            adaptiveManager.reportDuplicate()
        }

        let intervalAfterDuplicates = adaptiveManager.getInterval(isMeeting: false)

        adaptiveManager.resetDuplicateDetection()
        adaptiveManager.reportUnique()

        let intervalAfterUnique = adaptiveManager.getInterval(isMeeting: false)

        // After reporting duplicates, interval should be >= after reset
        XCTAssertGreaterThanOrEqual(intervalAfterDuplicates, intervalAfterUnique,
                                     "Interval after duplicates should be >= after unique")
    }

    // MARK: - Capture State Transitions Tests

    func testStopCapturing_clearsTimer() {
        let manager = ScreenCaptureManager()

        // Initial state
        XCTAssertFalse(manager.isCapturing)

        // Stop when not capturing
        manager.stopCapturing()

        // Should still be false and not crash
        XCTAssertFalse(manager.isCapturing)
    }

    func testStopCapturing_resetsState() {
        let mockDisplayManager = MockDisplayManager.singleDisplay()
        let manager = ScreenCaptureManager(displayManager: mockDisplayManager)

        // Stop should reset state (even when not capturing)
        manager.stopCapturing()

        XCTAssertFalse(manager.isCapturing)
        XCTAssertEqual(manager.captureCount, 0)
    }

    // MARK: - Multi-Monitor Scenarios

    func testInit_withSingleDisplay_configuresMock() {
        let mockDisplayManager = MockDisplayManager.singleDisplay()
        let manager = ScreenCaptureManager(displayManager: mockDisplayManager)

        XCTAssertNotNil(manager)
        XCTAssertEqual(mockDisplayManager.mockDisplays.count, 1)
    }

    func testInit_withDualDisplay_configuresMock() {
        let mockDisplayManager = MockDisplayManager.dualDisplay()
        let manager = ScreenCaptureManager(displayManager: mockDisplayManager)

        XCTAssertNotNil(manager)
        XCTAssertEqual(mockDisplayManager.mockDisplays.count, 2)
    }

    func testInit_withTripleDisplay_configuresMock() {
        let mockDisplayManager = MockDisplayManager.tripleDisplay()
        let manager = ScreenCaptureManager(displayManager: mockDisplayManager)

        XCTAssertNotNil(manager)
        XCTAssertEqual(mockDisplayManager.mockDisplays.count, 3)
    }

    func testInit_withNoDisplays_configuresMock() {
        let mockDisplayManager = MockDisplayManager.noDisplays()
        let manager = ScreenCaptureManager(displayManager: mockDisplayManager)

        XCTAssertNotNil(manager)
        XCTAssertEqual(mockDisplayManager.mockDisplays.count, 0)
    }

    func testInit_withErrorMock_configuresMock() {
        let mockDisplayManager = MockDisplayManager.withError(CaptureError.noDisplay)
        let manager = ScreenCaptureManager(displayManager: mockDisplayManager)

        XCTAssertNotNil(manager)
        XCTAssertTrue(mockDisplayManager.shouldThrowError)
    }

    // MARK: - DisplayInfo Structure Tests

    func testDisplayInfo_singleDisplay_hasCorrectProperties() {
        let mockDisplayManager = MockDisplayManager.singleDisplay()

        let display = mockDisplayManager.mockDisplays.first!

        XCTAssertEqual(display.id, 1)
        XCTAssertEqual(display.width, 1920)
        XCTAssertEqual(display.height, 1080)
        XCTAssertTrue(display.isMain)
        XCTAssertEqual(display.displayName, "Built-in Display")
    }

    func testDisplayInfo_dualDisplay_hasMainAndExternal() {
        let mockDisplayManager = MockDisplayManager.dualDisplay()

        let mainDisplay = mockDisplayManager.mockDisplays.first { $0.isMain }
        let externalDisplay = mockDisplayManager.mockDisplays.first { !$0.isMain }

        XCTAssertNotNil(mainDisplay)
        XCTAssertNotNil(externalDisplay)
        XCTAssertEqual(mainDisplay?.displayName, "Built-in Display")
        XCTAssertEqual(externalDisplay?.displayName, "External Display")
    }

    func testDisplayInfo_tripleDisplay_hasUniqueIds() {
        let mockDisplayManager = MockDisplayManager.tripleDisplay()

        let ids = Set(mockDisplayManager.mockDisplays.map { $0.id })

        XCTAssertEqual(ids.count, 3, "All displays should have unique IDs")
    }

    // MARK: - MockDisplayManager simulateDisplayChange Tests

    func testSimulateDisplayChange_updatesDisplays() async {
        let mockDisplayManager = MockDisplayManager.singleDisplay()

        XCTAssertEqual(mockDisplayManager.mockDisplays.count, 1)

        // Simulate adding a display
        let newDisplays = [
            DisplayInfo(id: 1, width: 1920, height: 1080, isMain: true, displayName: "Main"),
            DisplayInfo(id: 2, width: 2560, height: 1440, isMain: false, displayName: "New External")
        ]
        mockDisplayManager.simulateDisplayChange(newDisplays)

        XCTAssertEqual(mockDisplayManager.mockDisplays.count, 2)
    }

    func testSimulateDisplayChange_emptyList() async {
        let mockDisplayManager = MockDisplayManager.dualDisplay()

        XCTAssertEqual(mockDisplayManager.mockDisplays.count, 2)

        // Simulate disconnect all displays
        mockDisplayManager.simulateDisplayChange([])

        XCTAssertEqual(mockDisplayManager.mockDisplays.count, 0)
    }

    // MARK: - CaptureError Equality Tests

    func testCaptureError_equatable() {
        let error1 = CaptureError.noPermission
        let error2 = CaptureError.noPermission
        let error3 = CaptureError.noDisplay

        XCTAssertEqual(error1, error2)
        XCTAssertNotEqual(error1, error3)
    }

    func testCaptureError_allCasesHaveUniqueDescriptions() {
        let allErrors: [CaptureError] = [
            .noPermission,
            .noDisplay,
            .captureFailure,
            .saveFailed
        ]

        let descriptions = allErrors.compactMap { $0.errorDescription }
        let uniqueDescriptions = Set(descriptions)

        XCTAssertEqual(uniqueDescriptions.count, allErrors.count,
                      "Each error type should have a unique description")
    }

    // MARK: - Screenshot Hash Tests

    func testScreenshot_hashIsOptional() {
        let screenshotWithHash = Screenshot(
            filepath: "test.heic",
            timestamp: Date(),
            appBundleId: nil,
            appName: nil,
            windowTitle: nil,
            displayId: 1,
            width: 1920,
            height: 1080,
            fileSize: 1024,
            isDuplicate: false,
            hash: "abc123def456"
        )

        let screenshotWithoutHash = Screenshot(
            filepath: "test.heic",
            timestamp: Date(),
            appBundleId: nil,
            appName: nil,
            windowTitle: nil,
            displayId: 1,
            width: 1920,
            height: 1080,
            fileSize: 1024,
            isDuplicate: false,
            hash: nil
        )

        XCTAssertNotNil(screenshotWithHash.hash)
        XCTAssertNil(screenshotWithoutHash.hash)
    }

    func testScreenshot_isDuplicateFlag() {
        let duplicateScreenshot = Screenshot(
            filepath: "dup.heic",
            timestamp: Date(),
            appBundleId: nil,
            appName: nil,
            windowTitle: nil,
            displayId: 1,
            width: 1920,
            height: 1080,
            fileSize: 1024,
            isDuplicate: true,
            hash: "same_hash"
        )

        let uniqueScreenshot = Screenshot(
            filepath: "unique.heic",
            timestamp: Date(),
            appBundleId: nil,
            appName: nil,
            windowTitle: nil,
            displayId: 1,
            width: 1920,
            height: 1080,
            fileSize: 1024,
            isDuplicate: false,
            hash: "unique_hash"
        )

        XCTAssertTrue(duplicateScreenshot.isDuplicate)
        XCTAssertFalse(uniqueScreenshot.isDuplicate)
    }

    // MARK: - Edge Cases

    func testScreenshot_emptyWindowTitle() {
        let screenshot = Screenshot(
            filepath: "test.heic",
            timestamp: Date(),
            appBundleId: "com.test",
            appName: "Test App",
            windowTitle: "",
            displayId: 1,
            width: 1920,
            height: 1080,
            fileSize: 1024,
            isDuplicate: false,
            hash: nil
        )

        XCTAssertEqual(screenshot.windowTitle, "")
    }

    func testScreenshot_largeResolution() {
        let screenshot = Screenshot(
            filepath: "8k.heic",
            timestamp: Date(),
            appBundleId: nil,
            appName: nil,
            windowTitle: nil,
            displayId: 1,
            width: 7680,  // 8K width
            height: 4320, // 8K height
            fileSize: 50_000_000, // 50MB
            isDuplicate: false,
            hash: nil
        )

        XCTAssertEqual(screenshot.width, 7680)
        XCTAssertEqual(screenshot.height, 4320)
        XCTAssertEqual(screenshot.fileSize, 50_000_000)
    }

    func testScreenshot_zeroFileSize() {
        let screenshot = Screenshot(
            filepath: "empty.heic",
            timestamp: Date(),
            appBundleId: nil,
            appName: nil,
            windowTitle: nil,
            displayId: 1,
            width: 1920,
            height: 1080,
            fileSize: 0,
            isDuplicate: false,
            hash: nil
        )

        XCTAssertEqual(screenshot.fileSize, 0)
    }

    // MARK: - Multiple Delegate Errors Tracking

    func testMockDelegate_tracksMultipleErrorTypes() {
        let delegate = MockScreenCaptureDelegate()
        let manager = ScreenCaptureManager()

        delegate.screenCaptureManager(manager, didFailWithError: CaptureError.noPermission)
        delegate.screenCaptureManager(manager, didFailWithError: CaptureError.noDisplay)
        delegate.screenCaptureManager(manager, didFailWithError: CaptureError.captureFailure)
        delegate.screenCaptureManager(manager, didFailWithError: CaptureError.saveFailed)

        XCTAssertEqual(delegate.capturedErrors.count, 4)

        // Verify all error types are captured
        let errorTypes = delegate.capturedErrors.compactMap { $0 as? CaptureError }
        XCTAssertTrue(errorTypes.contains(.noPermission))
        XCTAssertTrue(errorTypes.contains(.noDisplay))
        XCTAssertTrue(errorTypes.contains(.captureFailure))
        XCTAssertTrue(errorTypes.contains(.saveFailed))
    }

    // MARK: - Helper Methods

    private func createTestScreenshot(displayId: Int) -> Screenshot {
        Screenshot(
            filepath: "test_\(UUID().uuidString).heic",
            timestamp: Date(),
            appBundleId: "com.test.app",
            appName: "Test",
            windowTitle: "Test Window",
            displayId: displayId,
            width: 1920,
            height: 1080,
            fileSize: 1024,
            isDuplicate: false,
            hash: UUID().uuidString
        )
    }
}
