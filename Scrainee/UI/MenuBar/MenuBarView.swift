// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - DEPENDENCY DOCUMENTATION
// ═══════════════════════════════════════════════════════════════════════════════
//
// FILE: MenuBarView.swift | PURPOSE: Main Menu Bar UI (Primary User Interface) | LAYER: UI/MenuBar
//
// DEPENDENCIES:
//   - AppState (App/AppState.swift) - Global state: capture status, stats, meeting info
//   - StartupCheckManager (Services/StartupCheckManager.swift) - System health checks display
//   - PermissionManager (Services/PermissionManager.swift) - Permission status & requests
//
// DEPENDENTS:
//   - ScraineeApp.swift - MenuBarExtra content provider
//
// OPENS WINDOWS (via openWindow):
//   - "quickask" -> QuickAskView (Cmd+Shift+A)
//   - "summary" -> SummaryRequestView (Cmd+Shift+S)
//   - "summarylist" -> SummaryListView
//   - "search" -> SearchView (Cmd+Shift+F)
//   - "gallery" -> ScreenshotGalleryView (Cmd+Shift+G)
//   - "timeline" -> TimelineView (Cmd+Shift+T)
//   - "meetingminutes" -> MeetingMinutesView (Cmd+Shift+M)
//   - Settings via SettingsLink (macOS 14+)
//
// CHANGE IMPACT:
//   - CRITICAL: Primary UI entry point - changes affect all user interactions
//   - Window IDs must match ScraineeApp.swift Window() registrations
//   - Contains embedded: MenuButton, StatRow, ShortcutHint components
//
// PROPERTY USAGE (via appState):
//   - captureState: isCapturing, screenshotCount, totalScreenshots, storageUsed, lastCaptureTime, toggleCapture()
//   - meetingState: isMeetingActive, currentMeeting, isGeneratingSummary
//   - uiState: showPermissionAlert
//
// LAST UPDATED: 2026-01-21
// ═══════════════════════════════════════════════════════════════════════════════

import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.openWindow) private var openWindow
    @ObservedObject private var startupChecker = StartupCheckManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with status
            headerSection

            Divider()
                .padding(.vertical, 8)

            // Permission alert if needed
            if appState.uiState.showPermissionAlert {
                permissionSection
                
                Divider()
                    .padding(.vertical, 8)
            }

            // Quick stats
            statsSection

            Divider()
                .padding(.vertical, 8)

            // System status
            systemStatusSection

            Divider()
                .padding(.vertical, 8)

            // Actions
            actionsSection

            Divider()
                .padding(.vertical, 8)

            // Footer
            footerSection
        }
        .padding()
        .frame(width: 280)
        .onAppear {
            // Aktualisiere Stats wenn das Menu geöffnet wird
            Task {
                await appState.captureState.refreshStats()
            }
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Scrainee")
                    .font(.headline)

                HStack(spacing: 6) {
                    Circle()
                        .fill(appState.captureState.isCapturing ? Color.red : Color.gray)
                        .frame(width: 8, height: 8)
                        .accessibilityHidden(true)

                    Text(appState.captureState.isCapturing ? "Aufnahme aktiv" : "Pausiert")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(appState.captureState.isCapturing ? "Aufnahmestatus: Aktiv" : "Aufnahmestatus: Pausiert")
            }

            Spacer()

            // Toggle button
            Button(action: { appState.captureState.toggleCapture() }) {
                Image(systemName: appState.captureState.isCapturing ? "pause.circle.fill" : "play.circle.fill")
                    .font(.title)
                    .foregroundColor(appState.captureState.isCapturing ? .red : .green)
            }
            .buttonStyle(.plain)
            .help(appState.captureState.isCapturing ? "Aufnahme pausieren" : "Aufnahme starten")
            .accessibilityLabel(appState.captureState.isCapturing ? "Aufnahme pausieren" : "Aufnahme starten")
            .accessibilityHint(appState.captureState.isCapturing ? "Stoppt die Screenshot-Aufnahme" : "Startet die Screenshot-Aufnahme")
        }
    }

    // MARK: - Permission Section

    private var permissionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text("Berechtigung erforderlich")
                    .font(.caption)
                    .fontWeight(.semibold)
            }
            
            Text("Scrainee benötigt die Berechtigung für Bildschirmaufnahmen, um Screenshots zu erstellen. Öffnen Sie die Systemeinstellungen und fügen Sie Scrainee zur Liste der erlaubten Apps hinzu.")
                .font(.caption2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            
            VStack(spacing: 4) {
                Button("Systemeinstellungen öffnen") {
                    PermissionManager.shared.openScreenCapturePreferences()
                }
                .buttonStyle(.plain)
                .font(.caption2)
                .padding(.vertical, 6)
                .padding(.horizontal, 12)
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(6)
                .accessibilityLabel("Systemeinstellungen öffnen")
                .accessibilityHint("Öffnet die macOS Systemeinstellungen für Bildschirmaufnahme-Berechtigung")

                Button("Berechtigung erneut prüfen") {
                    Task {
                        await appState.checkAndUpdatePermissions()
                    }
                }
                .buttonStyle(.plain)
                .font(.caption2)
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(Color.green.opacity(0.1))
                .foregroundColor(.green)
                .cornerRadius(4)
                .accessibilityLabel("Berechtigung erneut prüfen")
                .accessibilityHint("Überprüft ob die Bildschirmaufnahme-Berechtigung erteilt wurde")
            }
            
            // Instructions
            VStack(alignment: .leading, spacing: 2) {
                Text("Anweisungen:")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                
                Text("1. Klicken Sie auf 'Systemeinstellungen öffnen'")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Text("2. Aktivieren Sie das Kontrollkästchen neben 'Scrainee'")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Text("3. Kehren Sie hierher zurück und klicken Sie 'Erneut prüfen'")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 4)
        }
        .padding(12)
        .background(Color.orange.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
        .cornerRadius(8)
    }

    // MARK: - System Status Section

    @State private var isStatusExpanded = false

    private var systemStatusSection: some View {
        DisclosureGroup(isExpanded: $isStatusExpanded) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(startupChecker.checkResults) { check in
                    HStack(spacing: 8) {
                        statusCircle(for: check.status)
                            .accessibilityHidden(true)
                        Text(check.service.rawValue)
                            .font(.caption)
                        Spacer()
                        if !check.message.isEmpty {
                            Text(check.message)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(check.service.rawValue): \(accessibilityStatusText(for: check.status))")
                }
            }
            .padding(.leading, 8)
            .padding(.top, 4)
        } label: {
            HStack(spacing: 6) {
                Label("System Status", systemImage: "checkmark.shield")
                    .font(.caption)
                    .fontWeight(.semibold)

                Spacer()

                // Summary indicator
                if startupChecker.hasCompletedInitialCheck {
                    HStack(spacing: 2) {
                        let successCount = startupChecker.checkResults.filter { $0.status == .success }.count
                        let warningCount = startupChecker.checkResults.filter { $0.status == .warning || $0.status == .notConfigured }.count
                        let errorCount = startupChecker.checkResults.filter { $0.status == .error }.count

                        if errorCount > 0 {
                            statusCircle(for: .error)
                            Text("\(errorCount)")
                                .font(.caption2)
                                .foregroundColor(.red)
                        }
                        if warningCount > 0 {
                            statusCircle(for: .warning)
                            Text("\(warningCount)")
                                .font(.caption2)
                                .foregroundColor(.orange)
                        }
                        if successCount > 0 {
                            statusCircle(for: .success)
                            Text("\(successCount)")
                                .font(.caption2)
                                .foregroundColor(.green)
                        }
                    }
                } else if startupChecker.isChecking {
                    ProgressView()
                        .scaleEffect(0.5)
                        .accessibilityLabel("Wird geprüft")
                }
            }
        }
        .accessibilityLabel("System Status")
        .accessibilityHint(isStatusExpanded ? "Zum Einklappen doppeltippen" : "Zum Ausklappen doppeltippen, zeigt Status aller Systemdienste")
    }

    private func statusCircle(for status: StartupCheckManager.CheckStatus) -> some View {
        Circle()
            .fill(colorForStatus(status))
            .frame(width: 8, height: 8)
    }

    private func colorForStatus(_ status: StartupCheckManager.CheckStatus) -> Color {
        switch status {
        case .success:
            return .green
        case .warning, .notConfigured:
            return .orange
        case .error:
            return .red
        case .pending, .checking:
            return .gray
        }
    }

    private func accessibilityStatusText(for status: StartupCheckManager.CheckStatus) -> String {
        switch status {
        case .success:
            return "OK"
        case .warning:
            return "Warnung"
        case .notConfigured:
            return "Nicht konfiguriert"
        case .error:
            return "Fehler"
        case .pending:
            return "Ausstehend"
        case .checking:
            return "Wird geprüft"
        }
    }

    // MARK: - Stats Section

    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            StatRow(icon: "camera.fill", label: "Screenshots (Sitzung)", value: "\(appState.captureState.screenshotCount)")
            StatRow(icon: "photo.stack", label: "Gesamt", value: "\(appState.captureState.totalScreenshots)")
            StatRow(icon: "internaldrive", label: "Speicher", value: appState.captureState.storageUsed)

            if let lastCapture = appState.captureState.lastCaptureTime {
                StatRow(icon: "clock", label: "Letzter Screenshot", value: lastCapture.formatted(.relative(presentation: .named)))
            }

            if appState.meetingState.isMeetingActive {
                HStack(spacing: 6) {
                    Image(systemName: "video.fill")
                        .foregroundColor(.blue)
                    Text("Meeting aktiv: \(appState.meetingState.currentMeeting?.appName ?? "Unbekannt")")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
                .padding(.top, 4)
            }
        }
    }

    // MARK: - Actions Section

    @State private var isAIExpanded = true
    @State private var isScreenshotsExpanded = true
    @State private var isMeetingsExpanded = false

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // KI-Assistent Gruppe
            DisclosureGroup(isExpanded: $isAIExpanded) {
                VStack(alignment: .leading, spacing: 2) {
                    MenuButton(title: "Quick Ask", icon: "sparkles", shortcut: "⌘⇧A", accessibilityHintText: "Stellt eine Frage an die KI über aktuelle Bildschirminhalte") {
                        openWindow(id: "quickask")
                    }

                    MenuButton(title: "Zusammenfassung erstellen", icon: "doc.text", shortcut: "⌘⇧S", accessibilityHintText: "Erstellt eine KI-Zusammenfassung der letzten Screenshots") {
                        openWindow(id: "summary")
                    }

                    MenuButton(title: "Alle Zusammenfassungen", icon: "list.bullet.rectangle", accessibilityHintText: "Zeigt eine Liste aller erstellten Zusammenfassungen") {
                        openWindow(id: "summarylist")
                    }
                }
                .padding(.leading, 8)
            } label: {
                Label("KI-Assistent", systemImage: "brain.head.profile")
                    .font(.caption)
                    .fontWeight(.semibold)
            }
            .accessibilityLabel("KI-Assistent")
            .accessibilityHint(isAIExpanded ? "Zum Einklappen doppeltippen" : "Zum Ausklappen doppeltippen, enthält Quick Ask und Zusammenfassungen")

            // Screenshots Gruppe
            DisclosureGroup(isExpanded: $isScreenshotsExpanded) {
                VStack(alignment: .leading, spacing: 2) {
                    MenuButton(title: "Suchen", icon: "magnifyingglass", shortcut: "⌘⇧F", accessibilityHintText: "Durchsucht alle Screenshots nach Text") {
                        openWindow(id: "search")
                    }

                    MenuButton(title: "Galerie", icon: "photo.on.rectangle.angled", shortcut: "⌘⇧G", accessibilityHintText: "Zeigt alle Screenshots in einer Galerie-Ansicht") {
                        openWindow(id: "gallery")
                    }

                    MenuButton(title: "Timeline", icon: "slider.horizontal.below.rectangle", shortcut: "⌘⇧T", accessibilityHintText: "Zeigt Screenshots in einer chronologischen Zeitleiste") {
                        openWindow(id: "timeline")
                    }
                }
                .padding(.leading, 8)
            } label: {
                Label("Screenshots", systemImage: "photo.stack")
                    .font(.caption)
                    .fontWeight(.semibold)
            }
            .accessibilityLabel("Screenshots")
            .accessibilityHint(isScreenshotsExpanded ? "Zum Einklappen doppeltippen" : "Zum Ausklappen doppeltippen, enthält Suche, Galerie und Timeline")

            // Meetings Gruppe
            DisclosureGroup(isExpanded: $isMeetingsExpanded) {
                VStack(alignment: .leading, spacing: 2) {
                    MenuButton(title: "Meeting Minutes", icon: "person.3", shortcut: "⌘⇧M", accessibilityHintText: "Zeigt Protokolle und Transkripte von Meetings") {
                        openWindow(id: "meetingminutes")
                    }
                }
                .padding(.leading, 8)
            } label: {
                Label("Meetings", systemImage: "video")
                    .font(.caption)
                    .fontWeight(.semibold)
            }
            .accessibilityLabel("Meetings")
            .accessibilityHint(isMeetingsExpanded ? "Zum Einklappen doppeltippen" : "Zum Ausklappen doppeltippen, enthält Meeting Minutes")

            if appState.meetingState.isGeneratingSummary {
                HStack {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Erstelle Zusammenfassung...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 4)
            }
        }
    }

    // MARK: - Footer Section

    private var footerSection: some View {
        HStack {
            if #available(macOS 14.0, *) {
                SettingsLink {
                    Label("Einstellungen", systemImage: "gear")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Einstellungen")
                .accessibilityHint("Öffnet das Einstellungsfenster")
            } else {
                // Fallback on earlier versions
            }

            Spacer()

            Button(action: { NSApplication.shared.terminate(nil) }) {
                Label("Beenden", systemImage: "power")
            }
            .buttonStyle(.plain)
            .foregroundColor(.red)
            .accessibilityLabel("Scrainee beenden")
            .accessibilityHint("Beendet die Anwendung vollständig")
        }
        .font(.caption)
    }
    

}

// MARK: - Menu Button Component

struct MenuButton: View {
    let title: String
    let icon: String
    var shortcut: String? = nil
    var accessibilityHintText: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Label(title, systemImage: icon)
                    .font(.caption)

                Spacer()

                if let shortcut = shortcut {
                    Text(shortcut)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(Color.clear)
        .cornerRadius(4)
        .accessibilityLabel(title)
        .accessibilityHint(accessibilityHintText ?? (shortcut != nil ? "Tastenkürzel: \(shortcut!)" : ""))
    }
}

// MARK: - Stat Row Component

struct StatRow: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .frame(width: 20)
                .foregroundColor(.secondary)
                .accessibilityHidden(true)

            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()

            Text(value)
                .font(.caption)
                .fontWeight(.medium)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}

// MARK: - Shortcut Hint Component

struct ShortcutHint: View {
    let shortcut: String
    let action: String

    var body: some View {
        HStack(spacing: 4) {
            Text(shortcut)
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundColor(.accentColor)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Color.accentColor.opacity(0.1))
                .cornerRadius(3)

            Text(action)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Preview

#Preview {
    MenuBarView()
        .environmentObject(AppState.shared)
}
