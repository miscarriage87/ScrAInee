// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - 📋 DEPENDENCY DOCUMENTATION
// ═══════════════════════════════════════════════════════════════════════════════
//
// FILE: DisplayManager.swift | PURPOSE: Multi-Monitor-Management & Hash-Tracking | LAYER: Core/ScreenCapture
//
// DEPENDENCIES: ScreenCaptureKit (SCShareableContent, SCDisplay), AppKit (NSScreen, NSApplication),
//               Combine (PassthroughSubject), IOKit (Display-Namen)
// DEPENDENTS: ScreenCaptureManager (DisplayProviding, HashTracker), MockDisplayManager (Tests),
//             CaptureToStorageTests, DisplayManagerTests
// CHANGE IMPACT: DisplayProviding-Protokoll-Aenderungen erfordern Updates in ScreenCaptureManager
//                und MockDisplayManager; HashTracker ist actor-isolated fuer Thread-Safety
//
// LAST UPDATED: 2026-01-20
// ═══════════════════════════════════════════════════════════════════════════════

@preconcurrency import ScreenCaptureKit
import AppKit
import Combine

// MARK: - Display Info Model

/// Represents a display configuration for capture
struct DisplayInfo: Identifiable, Equatable, Sendable {
    let id: UInt32  // CGDirectDisplayID
    let width: Int
    let height: Int
    let isMain: Bool
    let displayName: String

    var displayId: UInt32 { id }

    var resolution: String {
        "\(width) x \(height)"
    }
}

// MARK: - Display Providing Protocol

/// Protocol for dependency injection in tests
protocol DisplayProviding: AnyObject, Sendable {
    func getAvailableDisplays() async throws -> [DisplayInfo]
}

// MARK: - Display Manager

/// Manages display enumeration and hot-plug events for multi-monitor support
@MainActor
final class DisplayManager: ObservableObject, DisplayProviding {

    // MARK: - Singleton

    static let shared = DisplayManager()

    // MARK: - Published Properties

    @Published private(set) var displays: [DisplayInfo] = []
    @Published private(set) var isMultiMonitor: Bool = false
    @Published private(set) var mainDisplay: DisplayInfo?

    // MARK: - Combine

    private let displaysChangedSubject = PassthroughSubject<[DisplayInfo], Never>()

    var displaysChangedPublisher: AnyPublisher<[DisplayInfo], Never> {
        displaysChangedSubject.eraseToAnyPublisher()
    }

    // MARK: - Private Properties

    nonisolated(unsafe) private var displayReconfigurationObserver: Any?

    // MARK: - Initialization

    private init() {
        setupDisplayReconfigurationObserver()
        Task {
            await refreshDisplays()
        }
    }

    deinit {
        if let observer = displayReconfigurationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Public Methods

    /// Gets all available displays using ScreenCaptureKit
    nonisolated func getAvailableDisplays() async throws -> [DisplayInfo] {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        )

        return content.displays.map { scDisplay in
            DisplayInfo(
                id: scDisplay.displayID,
                width: scDisplay.width,
                height: scDisplay.height,
                isMain: CGDisplayIsMain(scDisplay.displayID) != 0,
                displayName: Self.getDisplayName(for: scDisplay.displayID)
            )
        }.sorted { $0.isMain && !$1.isMain } // Main display first
    }

    /// Refreshes the list of available displays
    func refreshDisplays() async {
        do {
            let availableDisplays = try await getAvailableDisplays()
            displays = availableDisplays
            isMultiMonitor = availableDisplays.count > 1
            mainDisplay = availableDisplays.first { $0.isMain }
            displaysChangedSubject.send(availableDisplays)

            if isMultiMonitor {
                FileLogger.shared.info("\(availableDisplays.count) Displays erkannt", context: "DisplayManager")
                for display in availableDisplays {
                    FileLogger.shared.debug("  - \(display.displayName) (\(display.resolution))\(display.isMain ? " [Main]" : "")", context: "DisplayManager")
                }
            }
        } catch {
            FileLogger.shared.error("Fehler beim Enumerieren der Displays: \(error)", context: "DisplayManager")
        }
    }

    /// Gets a specific display by ID
    func getDisplay(by id: UInt32) -> DisplayInfo? {
        displays.first { $0.id == id }
    }

    /// Gets all SCDisplay objects for capture
    func getSCDisplays() async throws -> [SCDisplay] {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        )
        return content.displays
    }

    // MARK: - Private Methods

    /// Sets up observer for display configuration changes (hot-plug)
    private func setupDisplayReconfigurationObserver() {
        displayReconfigurationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                FileLogger.shared.info("Display-Konfiguration geändert", context: "DisplayManager")
                await self?.refreshDisplays()
            }
        }
    }

    /// Gets the localized display name for a given display ID
    private nonisolated static func getDisplayName(for displayID: UInt32) -> String {
        // Try to get localized display name from NSScreen
        for screen in NSScreen.screens {
            if let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32,
               screenNumber == displayID {
                return screen.localizedName
            }
        }

        // Fallback: Try to get display name from IOKit
        if let name = getIOKitDisplayName(for: displayID) {
            return name
        }

        // Last resort fallback
        let isMain = CGDisplayIsMain(displayID) != 0
        return isMain ? "Hauptbildschirm" : "Display \(displayID)"
    }

    /// Gets display name from IOKit (for external displays)
    private nonisolated static func getIOKitDisplayName(for displayID: CGDirectDisplayID) -> String? {
        var iterator: io_iterator_t = 0
        let result = IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("IODisplayConnect"),
            &iterator
        )

        guard result == kIOReturnSuccess else { return nil }
        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer { IOObjectRelease(service) }

            if let info = IODisplayCreateInfoDictionary(service, IOOptionBits(kIODisplayOnlyPreferredName))?.takeRetainedValue() as? [String: Any],
               let vendorID = info[kDisplayVendorID] as? UInt32,
               let productID = info[kDisplayProductID] as? UInt32,
               let names = info[kDisplayProductName] as? [String: String],
               let name = names.values.first {

                // Match by checking if this service corresponds to our display
                // This is a simplified check - IOKit display matching is complex
                if vendorID != 0 || productID != 0 {
                    return name
                }
            }

            service = IOIteratorNext(iterator)
        }

        return nil
    }
}

// MARK: - Hash Tracker Actor

/// Thread-safe actor for tracking perceptual hashes per display
/// Enables parallel capture without race conditions
actor HashTracker {

    // MARK: - Properties

    /// Stores last hash for each display ID
    private var lastHashes: [UInt32: String] = [:]

    /// Stores last capture timestamp per display
    private var lastCaptureTimes: [UInt32: Date] = [:]

    // MARK: - Public Methods

    /// Gets the last hash for a specific display
    func getLastHash(for displayId: UInt32) -> String? {
        lastHashes[displayId]
    }

    /// Sets the hash for a specific display
    func setLastHash(_ hash: String, for displayId: UInt32) {
        lastHashes[displayId] = hash
        lastCaptureTimes[displayId] = Date()
    }

    /// Checks if a hash is duplicate for the given display
    func isDuplicate(_ hash: String, for displayId: UInt32) -> Bool {
        guard let lastHash = lastHashes[displayId] else {
            return false
        }
        return hash == lastHash
    }

    /// Resets all stored hashes
    func reset() {
        lastHashes.removeAll()
        lastCaptureTimes.removeAll()
    }

    /// Removes hash for a specific display (e.g., when display disconnected)
    func removeHash(for displayId: UInt32) {
        lastHashes.removeValue(forKey: displayId)
        lastCaptureTimes.removeValue(forKey: displayId)
    }

    /// Gets all tracked display IDs
    func trackedDisplayIds() -> Set<UInt32> {
        Set(lastHashes.keys)
    }

    /// Gets capture statistics
    func getStats() -> (displayCount: Int, totalCaptures: Int) {
        (lastHashes.count, lastCaptureTimes.count)
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let displaysChanged = Notification.Name("displaysChanged")
}
