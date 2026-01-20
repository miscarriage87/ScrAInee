// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - DEPENDENCY DOCUMENTATION
// ═══════════════════════════════════════════════════════════════════════════════
//
// FILE: CaptureState.swift
// PURPOSE: State-Objekt für Screen-Capture-bezogene Properties und Methoden.
//          Teil der AppState-Aufteilung für bessere Separation of Concerns.
// LAYER: App/State
//
// ┌─────────────────────────────────────────────────────────────────────────────┐
// │ DEPENDENCIES (was diese Datei NUTZT)                                        │
// ├─────────────────────────────────────────────────────────────────────────────┤
// │ IMPORTS:                                                                    │
// │   • ScreenCaptureManager     → Core/ScreenCapture/ScreenCaptureManager.swift│
// │   • DatabaseManager.shared   → Core/Database/DatabaseManager.swift          │
// │   • StorageManager.shared    → Core/Storage/StorageManager.swift            │
// │   • PermissionManager.shared → Services/PermissionManager.swift             │
// │   • Screenshot (Model)       → Core/Database/Models/Screenshot.swift        │
// └─────────────────────────────────────────────────────────────────────────────┘
//
// ┌─────────────────────────────────────────────────────────────────────────────┐
// │ DEPENDENTS (wer diese Datei NUTZT)                                          │
// ├─────────────────────────────────────────────────────────────────────────────┤
// │ USED BY:                                                                    │
// │   • AppState.swift           → Enthält als @Published Property              │
// │   • MenuBarView.swift        → UI-Binding für Capture-Status                │
// │   • ContextOverlayView.swift → Zeigt Capture-Indicator                      │
// │   • HotkeyManager.swift      → Ruft toggleCapture() auf                     │
// │   • ScreenCaptureManager     → Updates via Delegate-Callbacks               │
// └─────────────────────────────────────────────────────────────────────────────┘
//
// LAST UPDATED: 2026-01-20
// ═══════════════════════════════════════════════════════════════════════════════

import SwiftUI
import Combine

/// State object for screen capture related properties
@MainActor
final class CaptureState: ObservableObject {

    // MARK: - Published Properties

    /// Whether screen capture is currently active
    @Published var isCapturing = false

    /// Total number of screenshots taken this session
    @Published var screenshotCount = 0

    /// Total screenshots in database
    @Published var totalScreenshots = 0

    /// Current storage usage formatted string
    @Published var storageUsed: String = "0 MB"

    /// Timestamp of last screenshot
    @Published var lastCaptureTime: Date?

    /// Name of currently active application
    @Published var currentApp: String = ""

    // MARK: - Internal Properties

    /// Current capture interval in seconds (synced from SettingsState)
    var captureInterval: Int = 3

    /// Reference to screen capture manager (set by AppState)
    weak var screenCaptureManager: ScreenCaptureManager?

    /// Closure to check if permission alert should be shown (injected by AppState)
    var onPermissionRequired: (() -> Void)?

    /// Closure to report errors (injected by AppState)
    var onError: ((String) -> Void)?

    // MARK: - Capture Control

    func toggleCapture() {
        if isCapturing {
            Task { await stopCapture() }
        } else {
            Task { await startCapture() }
        }
    }

    func startCapture() async {
        guard !isCapturing else { return }

        // Check permission first
        let permissionManager = PermissionManager.shared
        var hasPermission = await permissionManager.checkScreenCapturePermission()

        if !hasPermission {
            // Try to request permission
            hasPermission = await permissionManager.requestScreenCapturePermission()
        }

        guard hasPermission else {
            onPermissionRequired?()
            return
        }

        do {
            try await screenCaptureManager?.startCapturing(interval: TimeInterval(captureInterval))
            isCapturing = true
            screenshotCount = 0
        } catch {
            onError?("Aufnahme konnte nicht gestartet werden: \(error.localizedDescription)")
        }
    }

    func stopCapture() async {
        guard isCapturing else { return }

        screenCaptureManager?.stopCapturing()
        isCapturing = false
    }

    // MARK: - Stats

    func refreshStats() async {
        do {
            try await DatabaseManager.shared.initialize()
            totalScreenshots = try await DatabaseManager.shared.getScreenshotCount()
            storageUsed = StorageManager.shared.formattedStorageUsed
        } catch {
            // Silently ignore if database not ready yet
            storageUsed = StorageManager.shared.formattedStorageUsed
        }
    }

    // MARK: - Delegate Callbacks (called from AppState)

    func handleScreenshotCaptured(_ screenshot: Screenshot) {
        screenshotCount += 1
        totalScreenshots += 1
        lastCaptureTime = screenshot.timestamp
        currentApp = screenshot.appName ?? ""

        // Update storage stats every 10 screenshots for performance
        if screenshotCount % 10 == 0 {
            storageUsed = StorageManager.shared.formattedStorageUsed
        }
    }
}
