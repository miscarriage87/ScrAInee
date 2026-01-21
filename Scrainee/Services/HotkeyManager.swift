// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - DEPENDENCY DOCUMENTATION
// ═══════════════════════════════════════════════════════════════════════════════
//
// FILE: HotkeyManager.swift
// PURPOSE: Manages global keyboard shortcuts using Carbon Event API
// LAYER: Services
//
// ═══════════════════════════════════════════════════════════════════════════════
// DEPENDENCIES (was dieser Service nutzt):
// ═══════════════════════════════════════════════════════════════════════════════
//
// FRAMEWORKS:
//   - AppKit: NSWorkspace (nicht direkt, aber via Carbon)
//   - Carbon.HIToolbox: Global Hotkey Registration (RegisterEventHotKey, etc.)
//
// INTERNAL:
//   - PermissionManager.shared: Accessibility-Permission pruefen vor Registration
//   - AppState.shared.captureState: toggleCapture() bei Cmd+Shift+R
//
// ═══════════════════════════════════════════════════════════════════════════════
// DEPENDENTS (wer diesen Service nutzt):
// ═══════════════════════════════════════════════════════════════════════════════
//
//   - ScraineeApp.swift: registerHotkeys() bei App-Start
//
// ═══════════════════════════════════════════════════════════════════════════════
// NOTIFICATIONS (KRITISCH - von diesem Service gesendet):
// ═══════════════════════════════════════════════════════════════════════════════
//
// Diese Notifications werden bei Tastenkuerzel-Aktivierung gesendet.
// Listener muessen in ScraineeApp.swift registriert sein!
//
// ┌─────────────────────────────────┬──────────────────────┬─────────────────────────────────┐
// │ Notification Name               │ Tastenkuerzel        │ Erwartete Aktion                │
// ├─────────────────────────────────┼──────────────────────┼─────────────────────────────────┤
// │ .windowRequested                │ Cmd+Shift+A          │ Quick Ask (windowId: "quickask")│
// │ .windowRequested                │ Cmd+Shift+F          │ Search (windowId: "search")     │
// │ .windowRequested                │ Cmd+Shift+S          │ Summary (windowId: "summary")   │
// │ .windowRequested                │ Cmd+Shift+T          │ Timeline (windowId: "timeline") │
// │ .windowRequested                │ Cmd+Shift+M          │ Minutes (windowId: "meetingminutes")│
// └─────────────────────────────────┴──────────────────────┴─────────────────────────────────┘
//
// HINWEIS: Cmd+Shift+R (Toggle Capture) ruft direkt AppState.shared.captureState.toggleCapture()
//          auf und sendet KEINE Notification.
//
// ═══════════════════════════════════════════════════════════════════════════════
// LISTENER LOCATIONS:
// ═══════════════════════════════════════════════════════════════════════════════
//
//   - ScraineeApp.swift:
//     * .onReceive(NotificationCenter.default.publisher(for: .windowRequested))
//       → Liest windowId aus userInfo und öffnet entsprechendes Fenster
//
// ═══════════════════════════════════════════════════════════════════════════════
// CHANGE IMPACT:
// ═══════════════════════════════════════════════════════════════════════════════
//
// [KRITISCH] Aenderungen an Notification-Namen brechen die Hotkey-Funktionalitaet!
//            Alle Listener in ScraineeApp.swift muessen synchron angepasst werden.
//
// [KRITISCH] Neue Hotkeys erfordern:
//            1. Neuen Case in HotkeyID enum
//            2. registerHotkey() Aufruf in registerHotkeys()
//            3. Case-Handler in handleHotkey()
//            4. Notification.Name Extension (falls Notification genutzt)
//            5. Listener in ScraineeApp.swift
//
// [WICHTIG]  Accessibility-Permission ist PFLICHT fuer Hotkey-Funktion.
//            Ohne Permission werden keine Hotkeys registriert.
//
// LAST UPDATED: 2026-01-20
// ═══════════════════════════════════════════════════════════════════════════════

import AppKit
import Carbon.HIToolbox

/// Manages global keyboard shortcuts for Scrainee
@MainActor
final class HotkeyManager {
    static let shared = HotkeyManager()

    private var eventHandler: EventHandlerRef?
    private var hotKeyRefs: [EventHotKeyRef?] = []

    // Hotkey IDs
    private enum HotkeyID: UInt32 {
        case quickAsk = 1
        case toggleCapture = 2
        case search = 3
        case summary = 4
        case timeline = 5
        case meetingMinutes = 6
    }

    private init() {}

    // MARK: - Setup

    /// Registers all global hotkeys
    func registerHotkeys() {
        // Only register if accessibility permission is granted
        guard PermissionManager.shared.checkAccessibilityPermission() else {
            FileLogger.shared.warning("Hotkeys require accessibility permission", context: "HotkeyManager")
            return
        }

        // Set up event handler
        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let handlerRef = UnsafeMutablePointer<Any>.allocate(capacity: 1)
        handlerRef.initialize(to: self)

        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData -> OSStatus in
                guard let userData = userData else { return OSStatus(eventNotHandledErr) }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                return manager.handleHotkey(event)
            },
            1,
            &eventSpec,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )

        // Register hotkeys
        // Cmd+Shift+A: Quick Ask
        registerHotkey(id: .quickAsk, keyCode: UInt32(kVK_ANSI_A), modifiers: UInt32(cmdKey | shiftKey))

        // Cmd+Shift+R: Toggle Recording
        registerHotkey(id: .toggleCapture, keyCode: UInt32(kVK_ANSI_R), modifiers: UInt32(cmdKey | shiftKey))

        // Cmd+Shift+F: Search (already in SwiftUI but adding global)
        registerHotkey(id: .search, keyCode: UInt32(kVK_ANSI_F), modifiers: UInt32(cmdKey | shiftKey))

        // Cmd+Shift+S: Summary
        registerHotkey(id: .summary, keyCode: UInt32(kVK_ANSI_S), modifiers: UInt32(cmdKey | shiftKey))

        // Cmd+Shift+T: Timeline
        registerHotkey(id: .timeline, keyCode: UInt32(kVK_ANSI_T), modifiers: UInt32(cmdKey | shiftKey))

        // Cmd+Shift+M: Meeting Minutes
        registerHotkey(id: .meetingMinutes, keyCode: UInt32(kVK_ANSI_M), modifiers: UInt32(cmdKey | shiftKey))

        FileLogger.shared.info("Global hotkeys registered", context: "HotkeyManager")
    }

    /// Unregisters all hotkeys
    func unregisterHotkeys() {
        for ref in hotKeyRefs {
            if let ref = ref {
                UnregisterEventHotKey(ref)
            }
        }
        hotKeyRefs.removeAll()

        if let handler = eventHandler {
            RemoveEventHandler(handler)
            eventHandler = nil
        }
    }

    // MARK: - Private

    private func registerHotkey(id: HotkeyID, keyCode: UInt32, modifiers: UInt32) {
        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x5343524E), id: id.rawValue) // "SCRN"

        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if status == noErr {
            hotKeyRefs.append(hotKeyRef)
        } else {
            FileLogger.shared.error("Failed to register hotkey \(id): \(status)", context: "HotkeyManager")
        }
    }

    private func handleHotkey(_ event: EventRef?) -> OSStatus {
        guard let event = event else { return OSStatus(eventNotHandledErr) }

        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )

        guard status == noErr else { return status }

        Task { @MainActor in
            switch HotkeyID(rawValue: hotKeyID.id) {
            case .quickAsk:
                NotificationCenter.default.post(name: .windowRequested, object: nil, userInfo: ["windowId": "quickask"])
            case .toggleCapture:
                AppState.shared.captureState.toggleCapture()
            case .search:
                NotificationCenter.default.post(name: .windowRequested, object: nil, userInfo: ["windowId": "search"])
            case .summary:
                NotificationCenter.default.post(name: .windowRequested, object: nil, userInfo: ["windowId": "summary"])
            case .timeline:
                NotificationCenter.default.post(name: .windowRequested, object: nil, userInfo: ["windowId": "timeline"])
            case .meetingMinutes:
                NotificationCenter.default.post(name: .windowRequested, object: nil, userInfo: ["windowId": "meetingminutes"])
            case .none:
                break
            }
        }

        return noErr
    }
}

// MARK: - Notification Names

extension Notification.Name {
    /// Generische Window-Request Notification
    /// userInfo: ["windowId": String] - Window ID aus WindowConfig.registry
    /// Beispiel: NotificationCenter.default.post(name: .windowRequested, object: nil, userInfo: ["windowId": "quickask"])
    static let windowRequested = Notification.Name("com.scrainee.windowRequested")
}
