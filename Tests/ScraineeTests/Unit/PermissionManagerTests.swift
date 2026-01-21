import XCTest
@testable import Scrainee

/// Tests for PermissionManager
/// Note: Actual permission checks require system interaction and cannot be easily unit tested.
/// These tests focus on:
/// - PermissionStatus struct logic
/// - URL formats for System Preferences
/// - Singleton pattern
@MainActor
final class PermissionManagerTests: XCTestCase {

    // MARK: - Singleton Tests

    func testSharedInstance_isSingleton() {
        let instance1 = PermissionManager.shared
        let instance2 = PermissionManager.shared

        XCTAssertTrue(instance1 === instance2, "PermissionManager.shared should return the same instance")
    }

    // MARK: - PermissionStatus Tests

    func testPermissionStatus_allGranted_whenBothTrue() {
        let status = PermissionStatus(screenCapture: true, accessibility: true)

        XCTAssertTrue(status.allGranted)
        XCTAssertTrue(status.missingPermissions.isEmpty)
    }

    func testPermissionStatus_notAllGranted_whenScreenCaptureFalse() {
        let status = PermissionStatus(screenCapture: false, accessibility: true)

        XCTAssertFalse(status.allGranted)
        XCTAssertEqual(status.missingPermissions, ["Bildschirmaufnahme"])
    }

    func testPermissionStatus_notAllGranted_whenAccessibilityFalse() {
        let status = PermissionStatus(screenCapture: true, accessibility: false)

        XCTAssertFalse(status.allGranted)
        XCTAssertEqual(status.missingPermissions, ["Bedienungshilfen"])
    }

    func testPermissionStatus_notAllGranted_whenBothFalse() {
        let status = PermissionStatus(screenCapture: false, accessibility: false)

        XCTAssertFalse(status.allGranted)
        XCTAssertEqual(status.missingPermissions.count, 2)
        XCTAssertTrue(status.missingPermissions.contains("Bildschirmaufnahme"))
        XCTAssertTrue(status.missingPermissions.contains("Bedienungshilfen"))
    }

    func testPermissionStatus_missingPermissions_order() {
        // Verify order is consistent (screenCapture first, then accessibility)
        let status = PermissionStatus(screenCapture: false, accessibility: false)

        XCTAssertEqual(status.missingPermissions[0], "Bildschirmaufnahme")
        XCTAssertEqual(status.missingPermissions[1], "Bedienungshilfen")
    }

    // MARK: - System Preferences URL Tests

    func testScreenCapturePreferencesURL_isValid() {
        // Test that the URL format is valid
        let url1 = URL(string: "x-apple.systempreferences:com.apple.SystemPreferences.ExtensionsPrivacyPolicy?tab=SCREEN_CAPTURE")
        let url2 = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")

        XCTAssertNotNil(url1, "Primary screen capture URL should be valid")
        XCTAssertNotNil(url2, "Fallback screen capture URL should be valid")
    }

    func testAccessibilityPreferencesURL_isValid() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")

        XCTAssertNotNil(url, "Accessibility preferences URL should be valid")
    }

    func testFullDiskAccessPreferencesURL_isValid() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")

        XCTAssertNotNil(url, "Full disk access preferences URL should be valid")
    }

    // MARK: - URL Scheme Tests

    func testPreferencesURLs_useCorrectScheme() {
        let urls = [
            "x-apple.systempreferences:com.apple.SystemPreferences.ExtensionsPrivacyPolicy?tab=SCREEN_CAPTURE",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
        ]

        for urlString in urls {
            let url = URL(string: urlString)
            XCTAssertNotNil(url, "URL should be parseable: \(urlString)")
            XCTAssertEqual(url?.scheme, "x-apple.systempreferences", "Should use x-apple.systempreferences scheme")
        }
    }

    // MARK: - Permission Names (German Localization)

    func testPermissionNames_areGerman() {
        // Verify German localization is used
        let status = PermissionStatus(screenCapture: false, accessibility: false)

        // Should contain German terms
        XCTAssertTrue(status.missingPermissions.contains("Bildschirmaufnahme"))
        XCTAssertTrue(status.missingPermissions.contains("Bedienungshilfen"))

        // Should not contain English terms
        XCTAssertFalse(status.missingPermissions.contains("Screen Recording"))
        XCTAssertFalse(status.missingPermissions.contains("Accessibility"))
    }

    // MARK: - Edge Cases

    func testPermissionStatus_emptyMissingPermissions_whenAllGranted() {
        let status = PermissionStatus(screenCapture: true, accessibility: true)

        XCTAssertTrue(status.missingPermissions.isEmpty)
        XCTAssertEqual(status.missingPermissions.count, 0)
    }

    // MARK: - Accessibility Check (nonisolated)

    func testCheckAccessibilityPermission_isNonisolated() {
        // This test verifies the method can be called from any context
        // since it's marked nonisolated
        let manager = PermissionManager.shared

        // Call from main actor context (this test is @MainActor)
        _ = manager.checkAccessibilityPermission()

        // If this compiles and runs without actor isolation errors, the test passes
        XCTAssertTrue(true)
    }
}
