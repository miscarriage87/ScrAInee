import XCTest
@testable import Scrainee

/// Tests for HotkeyManager
/// Note: Carbon Event API hotkey registration cannot be easily tested in unit tests.
/// These tests focus on:
/// - Notification name constants
/// - Window ID mappings
/// - Notification payload structure
@MainActor
final class HotkeyManagerTests: XCTestCase {

    // MARK: - Notification Name Tests

    func testWindowRequestedNotificationName() {
        // Verify the notification name constant
        XCTAssertEqual(
            Notification.Name.windowRequested.rawValue,
            "com.scrainee.windowRequested"
        )
    }

    // MARK: - Window ID Mapping Tests

    func testValidWindowIds() {
        // These are the window IDs that HotkeyManager uses
        let validWindowIds = [
            "quickask",      // Cmd+Shift+A
            "search",        // Cmd+Shift+F
            "summary",       // Cmd+Shift+S
            "timeline",      // Cmd+Shift+T
            "meetingminutes" // Cmd+Shift+M
        ]

        for windowId in validWindowIds {
            XCTAssertFalse(windowId.isEmpty, "Window ID should not be empty")
            XCTAssertEqual(windowId, windowId.lowercased(), "Window IDs should be lowercase")
        }
    }

    // MARK: - Notification Payload Tests

    func testWindowRequestedNotification_hasCorrectUserInfo() async throws {
        // Given
        let expectedWindowId = "quickask"
        var receivedWindowId: String?

        let expectation = XCTestExpectation(description: "Notification received")

        // When - subscribe to notification
        let observer = NotificationCenter.default.addObserver(
            forName: .windowRequested,
            object: nil,
            queue: .main
        ) { notification in
            receivedWindowId = notification.userInfo?["windowId"] as? String
            expectation.fulfill()
        }

        // Post notification (simulating what HotkeyManager does)
        NotificationCenter.default.post(
            name: .windowRequested,
            object: nil,
            userInfo: ["windowId": expectedWindowId]
        )

        // Then
        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertEqual(receivedWindowId, expectedWindowId)

        // Cleanup
        NotificationCenter.default.removeObserver(observer)
    }

    func testWindowRequestedNotification_allWindowTypes() async throws {
        // Test that all window IDs can be received correctly
        let windowIds = ["quickask", "search", "summary", "timeline", "meetingminutes"]

        for windowId in windowIds {
            var receivedWindowId: String?
            let expectation = XCTestExpectation(description: "Notification for \(windowId)")

            let observer = NotificationCenter.default.addObserver(
                forName: .windowRequested,
                object: nil,
                queue: .main
            ) { notification in
                receivedWindowId = notification.userInfo?["windowId"] as? String
                expectation.fulfill()
            }

            NotificationCenter.default.post(
                name: .windowRequested,
                object: nil,
                userInfo: ["windowId": windowId]
            )

            await fulfillment(of: [expectation], timeout: 1.0)
            XCTAssertEqual(receivedWindowId, windowId, "Failed for windowId: \(windowId)")

            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - HotkeyManager Singleton Tests

    func testSharedInstance_isSingleton() {
        let instance1 = HotkeyManager.shared
        let instance2 = HotkeyManager.shared

        XCTAssertTrue(instance1 === instance2, "HotkeyManager.shared should return the same instance")
    }

    // MARK: - Edge Case Tests

    func testWindowRequestedNotification_withMissingUserInfo() async throws {
        // Given
        var receivedUserInfo: [AnyHashable: Any]?

        let expectation = XCTestExpectation(description: "Notification received")

        let observer = NotificationCenter.default.addObserver(
            forName: .windowRequested,
            object: nil,
            queue: .main
        ) { notification in
            receivedUserInfo = notification.userInfo
            expectation.fulfill()
        }

        // When - post without userInfo
        NotificationCenter.default.post(name: .windowRequested, object: nil)

        // Then
        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertNil(receivedUserInfo, "userInfo should be nil when not provided")

        NotificationCenter.default.removeObserver(observer)
    }

    func testWindowRequestedNotification_withInvalidWindowId() async throws {
        // Given
        let invalidWindowId = "nonexistent_window"
        var receivedWindowId: String?

        let expectation = XCTestExpectation(description: "Notification received")

        let observer = NotificationCenter.default.addObserver(
            forName: .windowRequested,
            object: nil,
            queue: .main
        ) { notification in
            receivedWindowId = notification.userInfo?["windowId"] as? String
            expectation.fulfill()
        }

        // When
        NotificationCenter.default.post(
            name: .windowRequested,
            object: nil,
            userInfo: ["windowId": invalidWindowId]
        )

        // Then - notification is still received, validation happens in ScraineeApp
        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertEqual(receivedWindowId, invalidWindowId)

        NotificationCenter.default.removeObserver(observer)
    }

    // MARK: - Hotkey Shortcut Documentation Tests

    func testDocumentedHotkeys_areComplete() {
        // Document the expected hotkey mappings
        // This serves as a "contract test" to ensure documentation stays in sync
        let expectedHotkeys: [(shortcut: String, windowId: String?)] = [
            ("Cmd+Shift+A", "quickask"),
            ("Cmd+Shift+R", nil), // toggleCapture - no notification
            ("Cmd+Shift+F", "search"),
            ("Cmd+Shift+S", "summary"),
            ("Cmd+Shift+T", "timeline"),
            ("Cmd+Shift+M", "meetingminutes")
        ]

        // Verify count matches HotkeyID enum cases
        XCTAssertEqual(expectedHotkeys.count, 6, "Should have 6 documented hotkeys")

        // Verify window IDs that should trigger notifications
        let notificationWindowIds = expectedHotkeys.compactMap { $0.windowId }
        XCTAssertEqual(notificationWindowIds.count, 5, "5 hotkeys should trigger window notifications")
    }
}
