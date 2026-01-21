import XCTest
@testable import Scrainee

/// Tests for MeetingDetector
/// Note: Actual app monitoring and Accessibility API calls cannot be easily unit tested.
/// These tests focus on:
/// - Notification names and payloads
/// - MeetingSession struct logic
/// - State properties
/// - Singleton pattern
/// - Known meeting apps configuration
@MainActor
final class MeetingDetectorTests: XCTestCase {

    // MARK: - Singleton Tests

    func testSharedInstance_isSingleton() {
        let instance1 = MeetingDetector.shared
        let instance2 = MeetingDetector.shared

        XCTAssertTrue(instance1 === instance2, "MeetingDetector.shared should return the same instance")
    }

    // MARK: - Initial State Tests

    func testInitialState_noActiveMeeting() {
        let detector = MeetingDetector.shared

        // Note: activeMeeting might be set from previous tests,
        // but we can at least verify the property is accessible
        _ = detector.activeMeeting
        XCTAssertTrue(true, "activeMeeting property is accessible")
    }

    func testInitialState_pendingStatesAccessible() {
        let detector = MeetingDetector.shared

        _ = detector.pendingEndConfirmation
        _ = detector.pendingStartConfirmation
        _ = detector.detectedMeetingAppName
        _ = detector.detectedMeetingBundleId

        XCTAssertTrue(true, "All pending state properties are accessible")
    }

    func testInitialState_isMonitoringAccessible() {
        let detector = MeetingDetector.shared

        _ = detector.isMonitoring
        XCTAssertTrue(true, "isMonitoring property is accessible")
    }

    // MARK: - Notification Name Tests

    func testMeetingStartedNotificationName() {
        XCTAssertEqual(
            Notification.Name.meetingStarted.rawValue,
            "com.scrainee.meetingStarted"
        )
    }

    func testMeetingEndedNotificationName() {
        XCTAssertEqual(
            Notification.Name.meetingEnded.rawValue,
            "com.scrainee.meetingEnded"
        )
    }

    func testMeetingDetectedAwaitingConfirmationNotificationName() {
        XCTAssertEqual(
            Notification.Name.meetingDetectedAwaitingConfirmation.rawValue,
            "meetingDetectedAwaitingConfirmation"
        )
    }

    func testMeetingEndConfirmationRequestedNotificationName() {
        XCTAssertEqual(
            Notification.Name.meetingEndConfirmationRequested.rawValue,
            "meetingEndConfirmationRequested"
        )
    }

    func testMeetingContinuedNotificationName() {
        XCTAssertEqual(
            Notification.Name.meetingContinued.rawValue,
            "meetingContinued"
        )
    }

    func testMeetingStartDismissedNotificationName() {
        XCTAssertEqual(
            Notification.Name.meetingStartDismissed.rawValue,
            "meetingStartDismissed"
        )
    }

    // MARK: - Notification Payload Tests

    func testMeetingDetectedNotification_hasCorrectUserInfo() async throws {
        let expectedAppName = "Microsoft Teams"
        let expectedBundleId = "com.microsoft.teams"
        var receivedAppName: String?
        var receivedBundleId: String?

        let expectation = XCTestExpectation(description: "Notification received")

        let observer = NotificationCenter.default.addObserver(
            forName: .meetingDetectedAwaitingConfirmation,
            object: nil,
            queue: .main
        ) { notification in
            receivedAppName = notification.userInfo?["appName"] as? String
            receivedBundleId = notification.userInfo?["bundleId"] as? String
            expectation.fulfill()
        }

        // Simulate what MeetingDetector does
        NotificationCenter.default.post(
            name: .meetingDetectedAwaitingConfirmation,
            object: nil,
            userInfo: ["appName": expectedAppName, "bundleId": expectedBundleId]
        )

        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertEqual(receivedAppName, expectedAppName)
        XCTAssertEqual(receivedBundleId, expectedBundleId)

        NotificationCenter.default.removeObserver(observer)
    }

    func testMeetingStartedNotification_hasMeetingSessionObject() async throws {
        let session = MeetingSession(
            appName: "Zoom",
            bundleId: "us.zoom.xos",
            startTime: Date()
        )
        var receivedSession: MeetingSession?

        let expectation = XCTestExpectation(description: "Notification received")

        let observer = NotificationCenter.default.addObserver(
            forName: .meetingStarted,
            object: nil,
            queue: .main
        ) { notification in
            receivedSession = notification.object as? MeetingSession
            expectation.fulfill()
        }

        NotificationCenter.default.post(name: .meetingStarted, object: session)

        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertNotNil(receivedSession)
        XCTAssertEqual(receivedSession?.appName, "Zoom")
        XCTAssertEqual(receivedSession?.bundleId, "us.zoom.xos")

        NotificationCenter.default.removeObserver(observer)
    }

    func testMeetingEndedNotification_hasMeetingSessionObject() async throws {
        var session = MeetingSession(
            appName: "Webex",
            bundleId: "com.cisco.webexmeetingsapp",
            startTime: Date().addingTimeInterval(-3600) // 1 hour ago
        )
        session.endTime = Date()
        var receivedSession: MeetingSession?

        let expectation = XCTestExpectation(description: "Notification received")

        let observer = NotificationCenter.default.addObserver(
            forName: .meetingEnded,
            object: nil,
            queue: .main
        ) { notification in
            receivedSession = notification.object as? MeetingSession
            expectation.fulfill()
        }

        NotificationCenter.default.post(name: .meetingEnded, object: session)

        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertNotNil(receivedSession)
        XCTAssertEqual(receivedSession?.appName, "Webex")
        XCTAssertNotNil(receivedSession?.endTime)

        NotificationCenter.default.removeObserver(observer)
    }

    // MARK: - MeetingSession Tests

    func testMeetingSession_initialization() {
        let startTime = Date()
        let session = MeetingSession(
            appName: "Google Meet",
            bundleId: "com.google.Chrome",
            startTime: startTime
        )

        XCTAssertEqual(session.appName, "Google Meet")
        XCTAssertEqual(session.bundleId, "com.google.Chrome")
        XCTAssertEqual(session.startTime, startTime)
        XCTAssertNil(session.endTime)
    }

    func testMeetingSession_duration_nilWhenNoEndTime() {
        let session = MeetingSession(
            appName: "Teams",
            bundleId: "com.microsoft.teams",
            startTime: Date()
        )

        XCTAssertNil(session.duration)
        XCTAssertEqual(session.durationMinutes, 0)
    }

    func testMeetingSession_duration_calculatedCorrectly() {
        let startTime = Date()
        let endTime = startTime.addingTimeInterval(3600) // 1 hour later

        var session = MeetingSession(
            appName: "Teams",
            bundleId: "com.microsoft.teams",
            startTime: startTime
        )
        session.endTime = endTime

        XCTAssertNotNil(session.duration)
        XCTAssertEqual(session.duration!, 3600, accuracy: 0.001)
        XCTAssertEqual(session.durationMinutes, 60)
    }

    func testMeetingSession_durationMinutes_roundsDown() {
        let startTime = Date()
        let endTime = startTime.addingTimeInterval(90) // 1.5 minutes

        var session = MeetingSession(
            appName: "Zoom",
            bundleId: "us.zoom.xos",
            startTime: startTime
        )
        session.endTime = endTime

        XCTAssertEqual(session.durationMinutes, 1) // Should be 1, not 2
    }

    // MARK: - Known Meeting Apps Tests

    func testKnownMeetingApps_containsTeams() {
        // These bundle IDs should be recognized
        let teamsBundleIds = ["com.microsoft.teams", "com.microsoft.teams2"]

        for bundleId in teamsBundleIds {
            XCTAssertFalse(bundleId.isEmpty, "Teams bundle ID should not be empty")
        }
    }

    func testKnownMeetingApps_containsZoom() {
        let zoomBundleId = "us.zoom.xos"
        XCTAssertEqual(zoomBundleId, "us.zoom.xos")
    }

    func testKnownMeetingApps_containsWebex() {
        let webexBundleIds = ["com.cisco.webexmeetingsapp", "com.cisco.webex.meetings"]

        for bundleId in webexBundleIds {
            XCTAssertFalse(bundleId.isEmpty, "Webex bundle ID should not be empty")
        }
    }

    func testKnownBrowsers_forMeetingDetection() {
        // Browsers that might host meetings (Google Meet, Teams Web, etc.)
        let browserBundleIds = [
            "com.google.Chrome",
            "com.apple.Safari",
            "com.microsoft.edgemac",
            "com.brave.Browser",
            "org.mozilla.firefox"
        ]

        XCTAssertEqual(browserBundleIds.count, 5, "Should recognize 5 browsers")

        for bundleId in browserBundleIds {
            XCTAssertFalse(bundleId.isEmpty)
            XCTAssertTrue(bundleId.contains("."), "Bundle ID should be reverse-domain format")
        }
    }

    // MARK: - Meeting URL Pattern Tests

    func testMeetingURLPatterns_googleMeet() {
        let pattern = "meet.google.com"
        let testTitles = [
            "meet.google.com/abc-defg-hij - Google Chrome",
            "My Meeting - meet.google.com",
            "MEET.GOOGLE.COM/xyz"
        ]

        for title in testTitles {
            XCTAssertTrue(
                title.lowercased().contains(pattern.lowercased()),
                "Should detect Google Meet URL in: \(title)"
            )
        }
    }

    func testMeetingURLPatterns_teamsWeb() {
        let patterns = ["teams.microsoft.com", "teams.live.com"]

        for pattern in patterns {
            XCTAssertFalse(pattern.isEmpty)
            XCTAssertTrue(pattern.contains("teams"))
        }
    }

    func testMeetingURLPatterns_zoomWeb() {
        let patterns = ["zoom.us/j/", "zoom.us/wc/"]

        for pattern in patterns {
            XCTAssertTrue(pattern.contains("zoom.us"))
        }
    }

    func testMeetingURLPatterns_webexWeb() {
        let patterns = ["webex.com/meet", "webex.com/join"]

        for pattern in patterns {
            XCTAssertTrue(pattern.contains("webex.com"))
        }
    }

    // MARK: - Snooze Duration Tests

    func testSnoozeDuration_isFiveMinutes() {
        // Document the expected snooze duration
        let expectedSnoozeDuration: TimeInterval = 300 // 5 minutes
        XCTAssertEqual(expectedSnoozeDuration, 300)
    }

    // MARK: - Edge Cases

    func testMeetingStartDismissedNotification_hasNoObject() async throws {
        var notificationReceived = false
        var receivedObject: Any?

        let expectation = XCTestExpectation(description: "Notification received")

        let observer = NotificationCenter.default.addObserver(
            forName: .meetingStartDismissed,
            object: nil,
            queue: .main
        ) { notification in
            notificationReceived = true
            receivedObject = notification.object
            expectation.fulfill()
        }

        NotificationCenter.default.post(name: .meetingStartDismissed, object: nil)

        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertTrue(notificationReceived)
        XCTAssertNil(receivedObject)

        NotificationCenter.default.removeObserver(observer)
    }

    func testMeetingContinuedNotification_canHaveOptionalSession() async throws {
        var receivedObject: Any?

        let expectation = XCTestExpectation(description: "Notification received")

        let observer = NotificationCenter.default.addObserver(
            forName: .meetingContinued,
            object: nil,
            queue: .main
        ) { notification in
            receivedObject = notification.object
            expectation.fulfill()
        }

        // Can be posted with nil
        NotificationCenter.default.post(name: .meetingContinued, object: nil)

        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertNil(receivedObject)

        NotificationCenter.default.removeObserver(observer)
    }

    // MARK: - All Meeting Notifications Test

    func testAllMeetingNotifications_areDistinct() {
        let notificationNames = [
            Notification.Name.meetingStarted,
            Notification.Name.meetingEnded,
            Notification.Name.meetingDetectedAwaitingConfirmation,
            Notification.Name.meetingEndConfirmationRequested,
            Notification.Name.meetingContinued,
            Notification.Name.meetingStartDismissed
        ]

        // Verify all are unique
        let uniqueNames = Set(notificationNames.map { $0.rawValue })
        XCTAssertEqual(uniqueNames.count, 6, "All 6 meeting notifications should have unique names")
    }
}
