@preconcurrency import ScreenCaptureKit
import AppKit

// Accessibility key constant - isolated to avoid concurrency issues
nonisolated(unsafe) private let accessibilityPromptKey = kAXTrustedCheckOptionPrompt

/// Manages system permissions required by Scrainee
@MainActor
final class PermissionManager: Sendable {
    static let shared = PermissionManager()

    private init() {}

    // MARK: - Screen Capture Permission

    /// Checks if screen capture permission is granted
    /// This call will trigger the system permission dialog if not yet granted
    func checkScreenCapturePermission() async -> Bool {
        do {
            // Attempting to get shareable content triggers the permission check
            _ = try await SCShareableContent.current
            return true
        } catch {
            // Permission denied or not yet granted
            return false
        }
    }

    /// Opens System Preferences to the Screen Recording section
    func openScreenCapturePreferences() {
        // Try the new macOS Ventura+ format first
        if let url = URL(string: "x-apple.systempreferences:com.apple.SystemPreferences.ExtensionsPrivacyPolicy?tab=SCREEN_CAPTURE") {
            NSWorkspace.shared.open(url)
        } else if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            // Fallback to older format
            NSWorkspace.shared.open(url)
        }
    }

    /// Request screen capture permission by attempting to access screen content
    /// This will trigger the system permission dialog
    func requestScreenCapturePermission() async -> Bool {
        do {
            // This will trigger the permission dialog if not already granted
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            return !content.displays.isEmpty
        } catch {
            print("Screen capture permission request failed: \(error)")
            return false
        }
    }

    // MARK: - Accessibility Permission

    /// Checks if accessibility permission is granted (needed for window titles)
    nonisolated func checkAccessibilityPermission() -> Bool {
        let key = accessibilityPromptKey.takeUnretainedValue() as String
        let options: NSDictionary = [key: false]
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Prompts user for accessibility permission
    nonisolated func requestAccessibilityPermission() {
        let key = accessibilityPromptKey.takeUnretainedValue() as String
        let options: NSDictionary = [key: true]
        AXIsProcessTrustedWithOptions(options)
    }

    /// Opens System Preferences to the Accessibility section
    func openAccessibilityPreferences() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Full Disk Access (for certain file operations)

    /// Opens System Preferences to Full Disk Access
    func openFullDiskAccessPreferences() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Combined Status

    /// Returns a summary of all required permissions
    func getPermissionStatus() async -> PermissionStatus {
        let screenCapture = await checkScreenCapturePermission()
        let accessibility = checkAccessibilityPermission()

        return PermissionStatus(
            screenCapture: screenCapture,
            accessibility: accessibility
        )
    }
}

// MARK: - Permission Status

struct PermissionStatus {
    let screenCapture: Bool
    let accessibility: Bool

    var allGranted: Bool {
        screenCapture && accessibility
    }

    var missingPermissions: [String] {
        var missing: [String] = []
        if !screenCapture { missing.append("Bildschirmaufnahme") }
        if !accessibility { missing.append("Bedienungshilfen") }
        return missing
    }
}
