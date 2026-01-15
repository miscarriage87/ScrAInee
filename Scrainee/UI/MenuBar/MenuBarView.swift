import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with status
            headerSection

            Divider()
                .padding(.vertical, 8)

            // Permission alert if needed
            if appState.showPermissionAlert {
                permissionSection
                
                Divider()
                    .padding(.vertical, 8)
            }

            // Quick stats
            statsSection

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
    }

    // MARK: - Header Section

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Scrainee")
                    .font(.headline)

                HStack(spacing: 6) {
                    Circle()
                        .fill(appState.isCapturing ? Color.red : Color.gray)
                        .frame(width: 8, height: 8)

                    Text(appState.isCapturing ? "Aufnahme aktiv" : "Pausiert")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Toggle button
            Button(action: { appState.toggleCapture() }) {
                Image(systemName: appState.isCapturing ? "pause.circle.fill" : "play.circle.fill")
                    .font(.title)
                    .foregroundColor(appState.isCapturing ? .red : .green)
            }
            .buttonStyle(.plain)
            .help(appState.isCapturing ? "Aufnahme pausieren" : "Aufnahme starten")
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

    // MARK: - Stats Section

    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            StatRow(icon: "camera.fill", label: "Screenshots (Sitzung)", value: "\(appState.screenshotCount)")
            StatRow(icon: "photo.stack", label: "Gesamt", value: "\(appState.totalScreenshots)")
            StatRow(icon: "internaldrive", label: "Speicher", value: appState.storageUsed)

            if let lastCapture = appState.lastCaptureTime {
                StatRow(icon: "clock", label: "Letzter Screenshot", value: lastCapture.formatted(.relative(presentation: .named)))
            }

            if appState.isMeetingActive {
                HStack(spacing: 6) {
                    Image(systemName: "video.fill")
                        .foregroundColor(.blue)
                    Text("Meeting aktiv: \(appState.currentMeeting?.appName ?? "Unbekannt")")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
                .padding(.top, 4)
            }
        }
    }

    // MARK: - Actions Section

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Quick Ask - new AI Companion feature
            Button(action: { openWindow(id: "quickask") }) {
                Label("Quick Ask", systemImage: "sparkles")
            }
            .keyboardShortcut("a", modifiers: [.command, .shift])

            Button(action: { openWindow(id: "search") }) {
                Label("Suchen...", systemImage: "magnifyingglass")
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])

            Button(action: { openWindow(id: "summary") }) {
                Label("Zusammenfassung erstellen", systemImage: "doc.text")
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])

            Button(action: { openWindow(id: "gallery") }) {
                Label("Screenshot Galerie", systemImage: "photo.on.rectangle.angled")
            }
            .keyboardShortcut("g", modifiers: [.command, .shift])

            Button(action: { openWindow(id: "timeline") }) {
                Label("Timeline", systemImage: "slider.horizontal.below.rectangle")
            }
            .keyboardShortcut("t", modifiers: [.command, .shift])

            if appState.isGeneratingSummary {
                HStack {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Erstelle Zusammenfassung...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.leading, 20)
            }

            Divider()
                .padding(.vertical, 4)

            // Keyboard shortcuts hint
            Text("Tastaturkuerzel:")
                .font(.caption2)
                .foregroundColor(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                ShortcutHint(shortcut: "⌘⇧A", action: "Quick Ask")
                ShortcutHint(shortcut: "⌘⇧F", action: "Suchen")
                ShortcutHint(shortcut: "⌘⇧G", action: "Galerie")
                ShortcutHint(shortcut: "⌘⇧T", action: "Timeline")
                ShortcutHint(shortcut: "⌘⇧R", action: "Aufnahme")
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Footer Section

    private var footerSection: some View {
        HStack {
            if #available(macOS 14.0, *) {
                SettingsLink {
                    Label("Einstellungen", systemImage: "gear")
                }
                .buttonStyle(.plain)
            } else {
                // Fallback on earlier versions
            }

            Spacer()

            Button(action: { NSApplication.shared.terminate(nil) }) {
                Label("Beenden", systemImage: "power")
            }
            .buttonStyle(.plain)
            .foregroundColor(.red)
        }
        .font(.caption)
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

            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()

            Text(value)
                .font(.caption)
                .fontWeight(.medium)
        }
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
