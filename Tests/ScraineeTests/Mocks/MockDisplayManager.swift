import Foundation
import Combine
@testable import Scrainee

/// Mock implementation of DisplayProviding for testing
final class MockDisplayManager: DisplayProviding, @unchecked Sendable {

    // MARK: - Properties

    var mockDisplays: [DisplayInfo] = []
    var shouldThrowError = false
    var errorToThrow: Error = CaptureError.noDisplay

    private let displaysChangedSubject = PassthroughSubject<[DisplayInfo], Never>()

    // MARK: - DisplayProviding

    var displaysChangedPublisher: AnyPublisher<[DisplayInfo], Never> {
        displaysChangedSubject.eraseToAnyPublisher()
    }

    func getAvailableDisplays() async throws -> [DisplayInfo] {
        if shouldThrowError {
            throw errorToThrow
        }
        return mockDisplays
    }

    // MARK: - Test Helpers

    /// Simulates a display configuration change (hot-plug event)
    func simulateDisplayChange(_ displays: [DisplayInfo]) {
        mockDisplays = displays
        displaysChangedSubject.send(displays)
    }

    // MARK: - Factory Methods

    /// Creates a mock with a single display
    static func singleDisplay() -> MockDisplayManager {
        let mock = MockDisplayManager()
        mock.mockDisplays = [
            DisplayInfo(
                id: 1,
                width: 1920,
                height: 1080,
                isMain: true,
                displayName: "Built-in Display"
            )
        ]
        return mock
    }

    /// Creates a mock with dual displays
    static func dualDisplay() -> MockDisplayManager {
        let mock = MockDisplayManager()
        mock.mockDisplays = [
            DisplayInfo(
                id: 1,
                width: 1920,
                height: 1080,
                isMain: true,
                displayName: "Built-in Display"
            ),
            DisplayInfo(
                id: 2,
                width: 2560,
                height: 1440,
                isMain: false,
                displayName: "External Display"
            )
        ]
        return mock
    }

    /// Creates a mock with triple displays
    static func tripleDisplay() -> MockDisplayManager {
        let mock = MockDisplayManager()
        mock.mockDisplays = [
            DisplayInfo(
                id: 1,
                width: 1920,
                height: 1080,
                isMain: true,
                displayName: "Built-in Display"
            ),
            DisplayInfo(
                id: 2,
                width: 2560,
                height: 1440,
                isMain: false,
                displayName: "Dell U2720Q"
            ),
            DisplayInfo(
                id: 3,
                width: 3840,
                height: 2160,
                isMain: false,
                displayName: "LG UltraFine"
            )
        ]
        return mock
    }

    /// Creates a mock with no displays (error case)
    static func noDisplays() -> MockDisplayManager {
        let mock = MockDisplayManager()
        mock.mockDisplays = []
        return mock
    }

    /// Creates a mock that throws an error
    static func withError(_ error: Error = CaptureError.noDisplay) -> MockDisplayManager {
        let mock = MockDisplayManager()
        mock.shouldThrowError = true
        mock.errorToThrow = error
        return mock
    }
}
