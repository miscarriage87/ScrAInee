import SwiftUI
import Combine
import AppKit

// MARK: - Window Configuration Helper

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
                Image(systemName: appState.isCapturing ? "record.circle.fill" : "record.circle")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(appState.isCapturing ? .red : .secondary, .primary)
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
            await AppState.shared.stopCapture()
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
                AppState.shared.showPermissionAlert = true
            }
        }

        // Check accessibility permission too
        if !permissionManager.checkAccessibilityPermission() {
            // Note: We don't auto-request accessibility permission as it's less critical
            print("Accessibility permission not granted - some features may be limited")
        } else {
            // Register global hotkeys if accessibility is granted
            HotkeyManager.shared.registerHotkeys()
        }

        // Initialize app (includes database and auto-start capture)
        await AppState.shared.initializeApp()

        // Start retention policy
        RetentionPolicy.shared.startScheduledCleanup()

        // Start meeting detector
        MeetingDetector.shared.startMonitoring()

        // Run startup health checks
        Task {
            await StartupCheckManager.shared.runAllChecks()
        }

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
                if hasPermission && AppState.shared.showPermissionAlert {
                    AppState.shared.showPermissionAlert = false
                }
            }
        }
    }

    private func setupWindowNotifications() {
        // Listen for Quick Ask notification
        let quickAskObserver = NotificationCenter.default.addObserver(
            forName: .showQuickAsk,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.openQuickAskWindow()
            }
        }
        windowObservers.append(quickAskObserver)

        // Listen for Search notification
        let searchObserver = NotificationCenter.default.addObserver(
            forName: .showSearch,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.openSearchWindow()
            }
        }
        windowObservers.append(searchObserver)

        // Listen for Summary notification
        let summaryObserver = NotificationCenter.default.addObserver(
            forName: .showSummary,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.openSummaryWindow()
            }
        }
        windowObservers.append(summaryObserver)

        // Listen for Timeline notification
        let timelineObserver = NotificationCenter.default.addObserver(
            forName: .showTimeline,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.openTimelineWindow()
            }
        }
        windowObservers.append(timelineObserver)

        // Listen for Meeting Minutes notification
        let meetingMinutesObserver = NotificationCenter.default.addObserver(
            forName: .showMeetingMinutes,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.openMeetingMinutesWindow()
            }
        }
        windowObservers.append(meetingMinutesObserver)
    }

    // MARK: - Window Opening

    private func configureWindowAsFloating(_ window: NSWindow) {
        window.level = .floating
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func openQuickAskWindow() {
        // Try to find and activate the window, or create new one
        if let window = NSApp.windows.first(where: { $0.title == "Quick Ask" }) {
            configureWindowAsFloating(window)
        } else {
            // Use SwiftUI's openWindow action to create the window
            ScraineeApp.openWindowAction?("quickask")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if let window = NSApp.windows.first(where: { $0.title == "Quick Ask" }) {
                    self.configureWindowAsFloating(window)
                }
            }
        }
    }

    func openSearchWindow() {
        if let window = NSApp.windows.first(where: { $0.title == "Suche" }) {
            configureWindowAsFloating(window)
        } else {
            ScraineeApp.openWindowAction?("search")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if let window = NSApp.windows.first(where: { $0.title == "Suche" }) {
                    self.configureWindowAsFloating(window)
                }
            }
        }
    }

    func openSummaryWindow() {
        if let window = NSApp.windows.first(where: { $0.title == "Zusammenfassung" }) {
            configureWindowAsFloating(window)
        } else {
            ScraineeApp.openWindowAction?("summary")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if let window = NSApp.windows.first(where: { $0.title == "Zusammenfassung" }) {
                    self.configureWindowAsFloating(window)
                }
            }
        }
    }

    func openTimelineWindow() {
        if let window = NSApp.windows.first(where: { $0.title == "Timeline" }) {
            configureWindowAsFloating(window)
        } else {
            ScraineeApp.openWindowAction?("timeline")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if let window = NSApp.windows.first(where: { $0.title == "Timeline" }) {
                    self.configureWindowAsFloating(window)
                }
            }
        }
    }

    func openMeetingMinutesWindow() {
        if let window = NSApp.windows.first(where: { $0.title == "Meeting Minutes" }) {
            configureWindowAsFloating(window)
        } else {
            ScraineeApp.openWindowAction?("meetingminutes")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if let window = NSApp.windows.first(where: { $0.title == "Meeting Minutes" }) {
                    self.configureWindowAsFloating(window)
                }
            }
        }
    }
}
