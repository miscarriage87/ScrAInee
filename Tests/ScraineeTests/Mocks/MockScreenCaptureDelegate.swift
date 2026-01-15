import Foundation
@testable import Scrainee

/// Mock delegate for testing ScreenCaptureManager
final class MockScreenCaptureDelegate: ScreenCaptureManagerDelegate {

    // MARK: - Tracking Properties

    var capturedScreenshots: [Screenshot] = []
    var capturedErrors: [Error] = []

    var onCapture: ((Screenshot) -> Void)?
    var onError: ((Error) -> Void)?

    // MARK: - Expectations

    var captureExpectation: (() -> Void)?
    var errorExpectation: (() -> Void)?

    // MARK: - ScreenCaptureManagerDelegate

    func screenCaptureManager(_ manager: ScreenCaptureManager, didCaptureScreenshot screenshot: Screenshot) {
        capturedScreenshots.append(screenshot)
        onCapture?(screenshot)
        captureExpectation?()
    }

    func screenCaptureManager(_ manager: ScreenCaptureManager, didFailWithError error: Error) {
        capturedErrors.append(error)
        onError?(error)
        errorExpectation?()
    }

    // MARK: - Test Helpers

    /// Returns unique display IDs from captured screenshots
    var capturedDisplayIds: Set<Int> {
        Set(capturedScreenshots.compactMap { $0.displayId })
    }

    /// Returns the number of screenshots per display
    var screenshotsPerDisplay: [Int: Int] {
        var result: [Int: Int] = [:]
        for screenshot in capturedScreenshots {
            if let displayId = screenshot.displayId {
                result[displayId, default: 0] += 1
            }
        }
        return result
    }

    /// Resets all tracked data
    func reset() {
        capturedScreenshots.removeAll()
        capturedErrors.removeAll()
    }
}
