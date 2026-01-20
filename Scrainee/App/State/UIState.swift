// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - DEPENDENCY DOCUMENTATION
// ═══════════════════════════════════════════════════════════════════════════════
//
// FILE: UIState.swift
// PURPOSE: State-Objekt für transiente UI-bezogene Properties.
//          Teil der AppState-Aufteilung für bessere Separation of Concerns.
// LAYER: App/State
//
// ┌─────────────────────────────────────────────────────────────────────────────┐
// │ DEPENDENCIES (was diese Datei NUTZT)                                        │
// ├─────────────────────────────────────────────────────────────────────────────┤
// │ IMPORTS:                                                                    │
// │   • PermissionManager.shared → Services/PermissionManager.swift             │
// └─────────────────────────────────────────────────────────────────────────────┘
//
// ┌─────────────────────────────────────────────────────────────────────────────┐
// │ DEPENDENTS (wer diese Datei NUTZT)                                          │
// ├─────────────────────────────────────────────────────────────────────────────┤
// │ USED BY:                                                                    │
// │   • AppState.swift           → Enthält als @Published Property              │
// │   • ScraineeApp.swift        → Reagiert auf showPermissionAlert             │
// │   • MenuBarView.swift        → Zeigt Fehler und Permission-Section          │
// └─────────────────────────────────────────────────────────────────────────────┘
//
// LAST UPDATED: 2026-01-20
// ═══════════════════════════════════════════════════════════════════════════════

import SwiftUI
import Combine

/// State object for transient UI-related properties
@MainActor
final class UIState: ObservableObject {

    // MARK: - Published Properties

    /// Whether to show permission alert
    @Published var showPermissionAlert = false

    /// Error message to display in UI
    @Published var errorMessage: String?

    // MARK: - Permission Management

    func checkAndUpdatePermissions(isCapturing: Bool, stopCapture: @escaping () async -> Void) async {
        let hasPermission = await PermissionManager.shared.checkScreenCapturePermission()
        if hasPermission && showPermissionAlert {
            showPermissionAlert = false
        } else if !hasPermission && isCapturing {
            // Stop capture if permission was revoked
            await stopCapture()
            showPermissionAlert = true
        }
    }

    // MARK: - Error Handling

    func setError(_ message: String) {
        errorMessage = message
    }

    func clearError() {
        errorMessage = nil
    }
}
