// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - 📋 DEPENDENCY DOCUMENTATION
// ═══════════════════════════════════════════════════════════════════════════════
//
// FILE: MeetingIndicatorView.swift | PURPOSE: Floating-Indikator für aktive Meetings | LAYER: UI/MeetingIndicator
//
// DEPENDENCIES: MeetingIndicatorViewModel
// DEPENDENTS: ScraineeApp (Window-Registration), MeetingIndicatorWindow
// LISTENS TO: -
// CHANGE IMPACT: UI für Meeting-Status, Start/Ende-Bestätigung, Aufnahme-Steuerung
//
// LAST UPDATED: 2026-01-20
// ═══════════════════════════════════════════════════════════════════════════════

import SwiftUI

/// Floating Indikator der angezeigt wird während ein Meeting läuft
/// Ermöglicht manuelle Kontrolle über Meeting-Ende und zeigt Bestätigungsdialog
struct MeetingIndicatorView: View {
    @StateObject private var viewModel = MeetingIndicatorViewModel()

    var body: some View {
        VStack(spacing: 12) {
            if viewModel.showStartConfirmation {
                // Neuer Start-Bestätigungs-Modus
                startConfirmationView
            } else {
                // Bestehender Recording-Modus
                headerView

                // Bestätigungs-Banner wenn App denkt Meeting ist vorbei
                if viewModel.showEndConfirmation {
                    confirmationBanner
                }

                // Control Buttons
                controlButtons
            }
        }
        .padding(16)
        .frame(width: 320)
        .background(.ultraThinMaterial)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(spacing: 10) {
            // Recording Indicator (pulsierend)
            Circle()
                .fill(Color.red)
                .frame(width: 10, height: 10)
                .opacity(viewModel.isRecording ? 1.0 : 0.3)
                .animation(
                    viewModel.isRecording
                        ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
                        : .default,
                    value: viewModel.isRecording
                )

            // Meeting App Name
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.meetingAppName)
                    .font(.headline)
                    .lineLimit(1)

                Text("Aufnahme läuft")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Duration
            Text(viewModel.duration)
                .font(.system(.title2, design: .monospaced))
                .fontWeight(.medium)
                .foregroundColor(viewModel.isRecording ? .primary : .secondary)
        }
    }

    // MARK: - Confirmation Banner

    private var confirmationBanner: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "questionmark.circle.fill")
                    .foregroundColor(.orange)
                Text("Meeting beendet?")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }

            HStack(spacing: 12) {
                Button(action: { viewModel.confirmMeetingEnded() }) {
                    Text("Ja, beenden")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.red)

                Button(action: { viewModel.dismissEndConfirmation() }) {
                    Text("Nein, läuft noch")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.green)
            }
        }
        .padding(12)
        .background(Color.orange.opacity(0.15))
        .cornerRadius(10)
    }

    // MARK: - Start Confirmation View

    private var startConfirmationView: some View {
        VStack(spacing: 16) {
            // Icon und Titel
            HStack(spacing: 10) {
                Image(systemName: "video.badge.waveform")
                    .font(.title2)
                    .foregroundColor(.blue)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Meeting erkannt")
                        .font(.headline)

                    Text(viewModel.pendingMeetingAppName ?? "Unbekannte App")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }

            // Frage
            Text("Möchtest du dieses Meeting aufnehmen?")
                .font(.body)
                .multilineTextAlignment(.center)

            // Buttons
            HStack(spacing: 12) {
                Button(action: { viewModel.dismissStartConfirmation() }) {
                    Label("Nein", systemImage: "xmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.secondary)

                Button(action: { viewModel.confirmStartRecording() }) {
                    Label("Ja, aufnehmen", systemImage: "record.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
            .controlSize(.large)
        }
    }

    // MARK: - Control Buttons

    private var controlButtons: some View {
        HStack(spacing: 12) {
            // Meeting beenden Button
            Button(action: { viewModel.stopMeeting() }) {
                Label("Meeting beenden", systemImage: "stop.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.large)
        }
    }
}

// MARK: - Preview

#Preview {
    MeetingIndicatorView()
        .padding()
        .frame(width: 350, height: 250)
}
