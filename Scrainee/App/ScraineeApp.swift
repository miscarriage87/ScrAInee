// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - DEPENDENCY DOCUMENTATION
// ═══════════════════════════════════════════════════════════════════════════════
//
// FILE: ScraineeApp.swift
// PURPOSE: App Entry Point (@main). Definiert alle SwiftUI Windows/Scenes,
//          enthält AppDelegate für Lifecycle-Management und Service-Initialisierung.
// LAYER: App (Entry Point - bootstrapped die gesamte Anwendung)
//
// ┌─────────────────────────────────────────────────────────────────────────────┐
// │ DEPENDENCIES (was diese Datei NUTZT)                                        │
// ├─────────────────────────────────────────────────────────────────────────────┤
// │ IMPORTS (Services - in initializeServices()):                               │
// │   • AppState.shared          → App/AppState.swift                           │
// │   • PermissionManager.shared → Services/PermissionManager.swift             │
// │   • HotkeyManager.shared     → Services/HotkeyManager.swift                 │
// │   • RetentionPolicy.shared   → Core/Storage/RetentionPolicy.swift           │
// │   • MeetingDetector.shared   → Core/Meeting/MeetingDetector.swift           │
// │   • StartupCheckManager.shared → Services/StartupCheckManager.swift         │
// │   • WhisperTranscriptionService.shared → Core/Audio/WhisperTranscription... │
// │   • DatabaseManager.shared   → Core/Database/DatabaseManager.swift          │
// │   • NotionClient             → Core/Integration/NotionClient.swift          │
// │                                                                             │
// │ IMPORTS (UI Views):                                                         │
// │   • MenuBarView              → UI/MenuBar/MenuBarView.swift                 │
// │   • SettingsView             → UI/Settings/SettingsView.swift               │
// │   • SearchView               → UI/Search/SearchView.swift                   │
// │   • SummaryRequestView       → UI/Summary/SummaryRequestView.swift          │
// │   • SummaryListView          → UI/Summary/SummaryListView.swift             │
// │   • QuickAskView             → UI/QuickAsk/QuickAskView.swift               │
// │   • ScreenshotGalleryView    → UI/Gallery/ScreenshotGalleryView.swift       │
// │   • ScreenshotTimelineView   → UI/Timeline/ScreenshotTimelineView.swift     │
// │   • MeetingMinutesView       → UI/MeetingMinutes/MeetingMinutesView.swift   │
// │   • MeetingIndicatorView     → UI/MeetingIndicator/MeetingIndicatorView.swift│
// │                                                                             │
// │ LISTENS TO (Notifications):                                                 │
// │   • .windowRequested         → von HotkeyManager.swift (userInfo: windowId) │
// │   • .transcriptionCompleted  → von MeetingTranscriptionCoordinator.swift    │
// │   • .meetingStarted          → von MeetingDetector.swift                    │
// │   • .meetingEnded            → von MeetingDetector.swift                    │
// │   • .meetingDetectedAwaitingConfirmation → von MeetingDetector.swift        │
// │   • .meetingStartDismissed   → von MeetingIndicatorViewModel.swift          │
// │   • NSWorkspace.didWakeNotification → System (Sleep/Wake)                   │
// │                                                                             │
// │ PROTOCOLS IMPLEMENTED: Keine                                                │
// └─────────────────────────────────────────────────────────────────────────────┘
//
// ┌─────────────────────────────────────────────────────────────────────────────┐
// │ DEPENDENTS (wer diese Datei NUTZT)                                          │
// ├─────────────────────────────────────────────────────────────────────────────┤
// │ USED BY:                                                                    │
// │   • System (Entry Point via @main)                                          │
// │   • Alle Views via ScraineeApp.openWindowAction closure                     │
// │                                                                             │
// │ POSTS (Notifications):                                                      │
// │   • Keine (empfängt nur, sendet nicht)                                      │
// │                                                                             │
// │ PROVIDES:                                                                   │
// │   • ScraineeApp.openWindowAction - Static closure für Window-Öffnung        │
// │   • View.floatingWindow() - ViewModifier für floating Windows               │
// │   • WindowAccessor/WindowAccessorView - Helpers für NSWindow-Zugriff        │
// │   • WindowConfig - Zentrale Registry für alle App-Fenster                   │
// └─────────────────────────────────────────────────────────────────────────────┘
//
// ┌─────────────────────────────────────────────────────────────────────────────┐
// │ CHANGE IMPACT                                                               │
// ├─────────────────────────────────────────────────────────────────────────────┤
// │ • Window IDs: Änderung in WindowConfig.registry (zentral!)                  │
// │ • Keyboard Shortcuts: .keyboardShortcut() Änderungen prüfen auf Konflikte   │
// │ • initializeServices() Reihenfolge: KRITISCH!                               │
// │   1. Permissions prüfen                                                     │
// │   2. AppState.initializeApp() (lädt Whisper!)                               │
// │   3. RetentionPolicy starten                                                │
// │   4. MeetingDetector starten (braucht Whisper!)                             │
// │   5. StartupCheckManager                                                    │
// │ • Notification Listener: Hinzufügen/Entfernen in setupWindowNotifications() │
// │ • TranscriptionCompletedInfo: Typ muss mit Coordinator übereinstimmen       │
// └─────────────────────────────────────────────────────────────────────────────┘
//
// LAST UPDATED: 2026-01-20
// ═══════════════════════════════════════════════════════════════════════════════

import SwiftUI
import Combine
import AppKit

// MARK: - Window Configuration

/// Zentrale Registry für alle App-Fenster
struct WindowConfig {
    let id: String
    let title: String
    let isFloating: Bool

    static let registry: [String: WindowConfig] = [
        "quickask": WindowConfig(id: "quickask", title: "Quick Ask", isFloating: true),
        "search": WindowConfig(id: "search", title: "Suche", isFloating: true),
        "summary": WindowConfig(id: "summary", title: "Zusammenfassung", isFloating: true),
        "summarylist": WindowConfig(id: "summarylist", title: "Zusammenfassungen", isFloating: true),
        "timeline": WindowConfig(id: "timeline", title: "Timeline", isFloating: true),
        "meetingminutes": WindowConfig(id: "meetingminutes", title: "Meeting Minutes", isFloating: true),
        "meetingindicator": WindowConfig(id: "meetingindicator", title: "Meeting", isFloating: true),
        "gallery": WindowConfig(id: "gallery", title: "Screenshot Galerie", isFloating: true)
    ]
}

// MARK: - Window Accessor Helper

struct WindowAccessor: ViewModifier {
    let onWindow: (NSWindow) -> Void

    func body(content: Content) -> some View {
        content.background(WindowAccessorView(onWindow: onWindow))
    }
}

struct WindowAccessorView: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                onWindow(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

extension View {
    /// Konfiguriert das Fenster als floating (on-top) und auf dem aktuellen Space
    func floatingWindow() -> some View {
        self.modifier(WindowAccessor { window in
            window.level = .floating
            window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        })
    }
}

@main
struct ScraineeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState.shared
    @Environment(\.openWindow) private var openWindow

    /// Static closure to allow AppDelegate to open SwiftUI windows
    static var openWindowAction: ((String) -> Void)?

    var body: some Scene {
        // Menu Bar App
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState)
                .onAppear {
                    // Initialize the static openWindow action for AppDelegate
                    ScraineeApp.openWindowAction = { [openWindow] windowId in
                        openWindow(id: windowId)
                    }
                }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: appState.captureState.isCapturing ? "record.circle.fill" : "record.circle")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(appState.captureState.isCapturing ? .red : .secondary, .primary)
            }
        }
        .menuBarExtraStyle(.window)

        // Settings Window
        Settings {
            SettingsView()
                .environmentObject(appState)
        }

        // Search Window (accessible via keyboard shortcut)
        Window("Suche", id: "search") {
            SearchView()
                .environmentObject(appState)
                .floatingWindow()
        }
        .keyboardShortcut("f", modifiers: [.command, .shift])
        .defaultSize(width: 600, height: 500)

        // Summary Window
        Window("Zusammenfassung", id: "summary") {
            SummaryRequestView()
                .environmentObject(appState)
                .floatingWindow()
        }
        .defaultSize(width: 700, height: 600)

        // Summary List Window
        Window("Zusammenfassungen", id: "summarylist") {
            SummaryListView()
                .environmentObject(appState)
                .floatingWindow()
        }
        .defaultSize(width: 800, height: 600)

        // Quick Ask Window (floating panel)
        Window("Quick Ask", id: "quickask") {
            QuickAskView()
                .environmentObject(appState)
                .floatingWindow()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.topTrailing)

        // Gallery Window
        Window("Screenshot Galerie", id: "gallery") {
            ScreenshotGalleryView()
                .environmentObject(appState)
                .floatingWindow()
        }
        .keyboardShortcut("g", modifiers: [.command, .shift])
        .defaultSize(width: 1000, height: 700)

        // Timeline Window
        Window("Timeline", id: "timeline") {
            ScreenshotTimelineView()
                .environmentObject(appState)
                .floatingWindow()
        }
        .keyboardShortcut("t", modifiers: [.command, .shift])
        .defaultSize(width: 1100, height: 750)

        // Meeting Minutes Window
        Window("Meeting Minutes", id: "meetingminutes") {
            MeetingMinutesView()
                .environmentObject(appState)
                .floatingWindow()
        }
        .keyboardShortcut("m", modifiers: [.command, .shift])
        .defaultSize(width: 1000, height: 700)

        // Meeting Indicator Window (auto-shows when meeting starts)
        Window("Meeting", id: "meetingindicator") {
            MeetingIndicatorView()
                .environmentObject(appState)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.topTrailing)
    }
}

// MARK: - App Delegate
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowObservers: [Any] = []

    nonisolated func applicationDidFinishLaunching(_ notification: Notification) {
        // Initialize services
        Task { @MainActor in
            await initializeServices()
        }

        // Setup window notification handlers
        Task { @MainActor in
            setupWindowNotifications()
        }
    }

    nonisolated func applicationWillTerminate(_ notification: Notification) {
        // Cleanup
        Task { @MainActor in
            await AppState.shared.captureState.stopCapture()
            HotkeyManager.shared.unregisterHotkeys()
        }

        // Remove observers
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    private func initializeServices() async {
        // Check and request permissions
        let permissionManager = PermissionManager.shared

        // First check if we already have permission
        let hasPermission = await permissionManager.checkScreenCapturePermission()

        if !hasPermission {
            // Try to trigger the permission dialog
            let granted = await permissionManager.requestScreenCapturePermission()

            if !granted {
                AppState.shared.uiState.showPermissionAlert = true
            }
        }

        // Check accessibility permission too
        if permissionManager.checkAccessibilityPermission() {
            // Register global hotkeys if accessibility is granted
            HotkeyManager.shared.registerHotkeys()
        }

        // Initialize app (includes database, Whisper model loading, and auto-start capture)
        // WICHTIG: Whisper muss HIER geladen werden, BEVOR MeetingDetector startet!
        await AppState.shared.initializeApp()

        // Start retention policy
        RetentionPolicy.shared.startScheduledCleanup()

        // Start meeting detector NACH Whisper geladen ist
        // Das ist wichtig, damit der MeetingTranscriptionCoordinator das Modell findet
        MeetingDetector.shared.startMonitoring()

        // Run startup health checks (direkt nach initializeApp, nicht in separatem Task)
        await StartupCheckManager.shared.runAllChecks()

        // Register for sleep/wake notifications to handle permission changes
        registerForSystemNotifications()
    }

    private func registerForSystemNotifications() {
        // Handle system wake - recheck permissions as they might have changed
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard self != nil else { return }
                let hasPermission = await PermissionManager.shared.checkScreenCapturePermission()
                if hasPermission && AppState.shared.uiState.showPermissionAlert {
                    AppState.shared.uiState.showPermissionAlert = false
                }
            }
        }
    }

    private func setupWindowNotifications() {
        // MARK: - Generischer Window-Request Observer (konsolidiert 5 individuelle Observer)
        let windowRequestObserver = NotificationCenter.default.addObserver(
            forName: .windowRequested,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let windowId = notification.userInfo?["windowId"] as? String else { return }
            Task { @MainActor [weak self] in
                self?.openWindow(windowId)
            }
        }
        windowObservers.append(windowRequestObserver)

        // MARK: - Meeting/Transcription Observer (bleiben individuell)

        // Listen for Transcription Completed - auto-open Meeting Minutes window
        let transcriptionObserver = NotificationCenter.default.addObserver(
            forName: .transcriptionCompleted,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let info = notification.object as? TranscriptionCompletedInfo else { return }
            Task { @MainActor [weak self] in
                await self?.handleTranscriptionCompleted(info)
            }
        }
        windowObservers.append(transcriptionObserver)

        // Listen for Meeting Started - auto-open Meeting Indicator window
        let meetingStartedObserver = NotificationCenter.default.addObserver(
            forName: .meetingStarted,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.openWindow("meetingindicator")
            }
        }
        windowObservers.append(meetingStartedObserver)

        // Listen for Meeting Ended - auto-close Meeting Indicator window
        let meetingEndedObserver = NotificationCenter.default.addObserver(
            forName: .meetingEnded,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.closeWindow("meetingindicator")
            }
        }
        windowObservers.append(meetingEndedObserver)

        // Listen for Meeting Detected (awaiting confirmation) - show confirmation dialog
        let meetingDetectedObserver = NotificationCenter.default.addObserver(
            forName: .meetingDetectedAwaitingConfirmation,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.openWindow("meetingindicator")
                // Positioniere Fenster in Mitte-oben des Hauptbildschirms
                try? await Task.sleep(for: .milliseconds(150))
                self?.positionWindowCenterTop("Meeting")
            }
        }
        windowObservers.append(meetingDetectedObserver)

        // Listen for Meeting Start Dismissed - close indicator window
        let meetingDismissedObserver = NotificationCenter.default.addObserver(
            forName: .meetingStartDismissed,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.closeWindow("meetingindicator")
            }
        }
        windowObservers.append(meetingDismissedObserver)
    }

    /// Handles transcription completion: opens Meeting Minutes window and auto-syncs to Notion
    private func handleTranscriptionCompleted(_ info: TranscriptionCompletedInfo) async {
        // Open Meeting Minutes window
        openWindow("meetingminutes")

        // Auto-sync to Notion if enabled
        let settings = AppState.shared.settingsState
        if settings.notionEnabled && settings.notionAutoSync {
            await syncMeetingToNotion(meetingId: info.meetingId)
        }
    }

    /// Syncs a completed meeting to Notion with Minutes, Transcript, and Action Items
    private func syncMeetingToNotion(meetingId: Int64) async {
        let client = NotionClient()

        guard client.isConfigured else {
            FileLogger.shared.warning("Notion Auto-Sync: Notion nicht konfiguriert", context: "ScraineeApp")
            return
        }

        do {
            // Load meeting data
            guard let meeting = try await DatabaseManager.shared.getMeeting(id: meetingId) else {
                FileLogger.shared.warning("Notion Auto-Sync: Meeting nicht gefunden", context: "ScraineeApp")
                return
            }

            // Load minutes
            guard let minutes = try await DatabaseManager.shared.getMeetingMinutes(for: meetingId) else {
                FileLogger.shared.warning("Notion Auto-Sync: Keine Minutes gefunden", context: "ScraineeApp")
                return
            }

            // Load segments and action items
            let segments = try await DatabaseManager.shared.getTranscriptSegments(for: meetingId)
            let actionItems = try await DatabaseManager.shared.getActionItems(for: meetingId)

            // Export to Notion
            let page = try await client.exportMeetingWithMinutes(
                meeting: meeting,
                minutes: minutes,
                segments: segments,
                actionItems: actionItems
            )

            // Update meeting record with Notion link
            try await DatabaseManager.shared.updateMeetingNotionLink(
                meetingId: meetingId,
                pageId: page.id,
                pageUrl: page.url
            )

            FileLogger.shared.info("Notion Auto-Sync: Meeting erfolgreich exportiert nach \(page.url)", context: "ScraineeApp")
        } catch {
            FileLogger.shared.error("Notion Auto-Sync fehlgeschlagen: \(error.localizedDescription)", context: "ScraineeApp")
        }
    }

    // MARK: - Window Positioning

    /// Positioniert ein Fenster in der Mitte oben des Hauptbildschirms
    private func positionWindowCenterTop(_ windowTitle: String) {
        guard let window = NSApp.windows.first(where: { $0.title == windowTitle }),
              let screen = NSScreen.main else { return }

        let screenFrame = screen.visibleFrame
        let windowFrame = window.frame

        // Mitte horizontal, oben vertikal (mit 60px Abstand vom oberen Rand)
        let x = screenFrame.origin.x + (screenFrame.width - windowFrame.width) / 2
        let y = screenFrame.origin.y + screenFrame.height - windowFrame.height - 60

        window.setFrameOrigin(NSPoint(x: x, y: y))
    }

    // MARK: - Window Opening

    private func configureWindowAsFloating(_ window: NSWindow) {
        window.level = .floating
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Generische Methode zum Öffnen eines Fensters über die WindowConfig Registry
    func openWindow(_ windowId: String) {
        guard let config = WindowConfig.registry[windowId] else {
            FileLogger.shared.warning("Unknown window ID '\(windowId)'", context: "ScraineeApp")
            return
        }

        if let window = NSApp.windows.first(where: { $0.title == config.title }) {
            // Fenster existiert bereits - aktivieren
            if config.isFloating {
                configureWindowAsFloating(window)
            } else {
                window.makeKeyAndOrderFront(nil)
            }
        } else {
            // Neues Fenster erstellen über SwiftUI
            ScraineeApp.openWindowAction?(windowId)
            if config.isFloating {
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .milliseconds(100))
                    if let window = NSApp.windows.first(where: { $0.title == config.title }) {
                        self?.configureWindowAsFloating(window)
                    }
                }
            }
        }
    }

    /// Schließt ein Fenster über die WindowConfig Registry
    func closeWindow(_ windowId: String) {
        guard let config = WindowConfig.registry[windowId] else { return }
        if let window = NSApp.windows.first(where: { $0.title == config.title }) {
            window.close()
        }
    }
}
