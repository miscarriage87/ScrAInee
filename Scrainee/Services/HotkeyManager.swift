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
            print("Hotkeys require accessibility permission")
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

        print("Global hotkeys registered")
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
            print("Failed to register hotkey \(id): \(status)")
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
                NotificationCenter.default.post(name: .showQuickAsk, object: nil)
            case .toggleCapture:
                AppState.shared.toggleCapture()
            case .search:
                NotificationCenter.default.post(name: .showSearch, object: nil)
            case .summary:
                NotificationCenter.default.post(name: .showSummary, object: nil)
            case .timeline:
                NotificationCenter.default.post(name: .showTimeline, object: nil)
            case .meetingMinutes:
                NotificationCenter.default.post(name: .showMeetingMinutes, object: nil)
            case .none:
                break
            }
        }

        return noErr
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let showQuickAsk = Notification.Name("com.scrainee.showQuickAsk")
    static let showSearch = Notification.Name("com.scrainee.showSearch")
    static let showSummary = Notification.Name("com.scrainee.showSummary")
    static let showTimeline = Notification.Name("com.scrainee.showTimeline")
    static let showMeetingMinutes = Notification.Name("com.scrainee.showMeetingMinutes")
}
