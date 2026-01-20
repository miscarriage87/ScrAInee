// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - DEPENDENCY DOCUMENTATION
// ═══════════════════════════════════════════════════════════════════════════════
//
// FILE: SettingsState.swift
// PURPOSE: State-Objekt für @AppStorage-basierte Einstellungen.
//          Teil der AppState-Aufteilung für bessere Separation of Concerns.
// LAYER: App/State
//
// ┌─────────────────────────────────────────────────────────────────────────────┐
// │ DEPENDENCIES (was diese Datei NUTZT)                                        │
// ├─────────────────────────────────────────────────────────────────────────────┤
// │ IMPORTS:                                                                    │
// │   • SwiftUI (@AppStorage)    → UserDefaults-basierte Persistenz             │
// └─────────────────────────────────────────────────────────────────────────────┘
//
// ┌─────────────────────────────────────────────────────────────────────────────┐
// │ DEPENDENTS (wer diese Datei NUTZT)                                          │
// ├─────────────────────────────────────────────────────────────────────────────┤
// │ USED BY:                                                                    │
// │   • AppState.swift           → Enthält als @Published Property              │
// │   • SettingsView.swift       → Liest/Schreibt alle Einstellungen            │
// │   • SettingsValidator.swift  → Import/Export von Einstellungen              │
// │   • ScreenCaptureManager     → Liest heicQuality, ocrEnabled                │
// │   • AdminViewModel.swift     → Liest retentionDays                          │
// │   • CaptureState.swift       → Liest captureInterval                        │
// │   • MeetingState.swift       → Liest notionEnabled, notionAutoSync          │
// └─────────────────────────────────────────────────────────────────────────────┘
//
// LAST UPDATED: 2026-01-20
// ═══════════════════════════════════════════════════════════════════════════════

import SwiftUI
import Combine

/// State object for persistent app settings
@MainActor
final class SettingsState: ObservableObject {

    // MARK: - Capture Settings

    /// Capture interval in seconds
    @AppStorage("captureInterval") var captureInterval: Int = 3

    /// HEIC compression quality (0.0 - 1.0)
    @AppStorage("heicQuality") var heicQuality: Double = 0.6

    /// Whether OCR is enabled for screenshots
    @AppStorage("ocrEnabled") var ocrEnabled: Bool = true

    /// Whether to auto-start capture on app launch
    @AppStorage("autoStartCapture") var autoStartCapture: Bool = true

    // MARK: - Storage Settings

    /// Number of days to retain screenshots
    @AppStorage("retentionDays") var retentionDays: Int = 30

    // MARK: - Meeting Settings

    /// Whether meeting detection is enabled
    @AppStorage("meetingDetectionEnabled") var meetingDetectionEnabled: Bool = true

    // MARK: - Integration Settings

    /// Whether Notion integration is enabled
    @AppStorage("notionEnabled") var notionEnabled: Bool = false

    /// Whether to auto-sync meetings to Notion
    @AppStorage("notionAutoSync") var notionAutoSync: Bool = true

    // MARK: - General Settings

    /// Whether to launch app at login
    @AppStorage("launchAtLogin") var launchAtLogin: Bool = false
}
