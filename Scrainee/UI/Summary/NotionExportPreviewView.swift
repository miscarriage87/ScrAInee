// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - DEPENDENCY DOCUMENTATION
// ═══════════════════════════════════════════════════════════════════════════════
//
// FILE: NotionExportPreviewView.swift | PURPOSE: Notion Export Preview Sheet | LAYER: UI/Summary
//
// DEPENDENCIES:
//   - Summary (Core/Database/Models/Summary.swift) - Summary data model for preview
//
// DEPENDENTS:
//   - SummaryListView.swift - Presented as sheet for export preview
//
// CHANGE IMPACT:
//   - Standalone sheet component - changes affect SummaryListView presentation
//   - Contains embedded: PropertyRow helper view
//
// LAST UPDATED: 2026-01-20
// ═══════════════════════════════════════════════════════════════════════════════

import SwiftUI

struct NotionExportPreviewView: View {
    let summary: Summary
    let onExport: (String) async -> Void
    let onCancel: () -> Void

    @State private var customTitle: String = ""
    @State private var isExporting = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            Divider()

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Title Section
                    titleSection

                    // Preview Section
                    previewSection

                    // Properties Preview
                    propertiesSection
                }
                .padding()
            }

            Divider()

            // Actions
            actionButtons
        }
        .frame(width: 550, height: 600)
        .onAppear {
            // Default title based on time range
            customTitle = summary.title ?? "Zusammenfassung \(summary.formattedTimeRange)"
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            Image(systemName: "square.and.arrow.up")
                .font(.title2)
                .foregroundColor(.accentColor)

            Text("Nach Notion exportieren")
                .font(.title2)
                .fontWeight(.semibold)

            Spacer()

            Button(action: onCancel) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Title Section

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Seitentitel")
                .font(.headline)

            TextField("Titel der Notion-Seite", text: $customTitle)
                .textFieldStyle(.roundedBorder)

            Text("Dieser Titel wird als Name der Notion-Seite verwendet.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }

    // MARK: - Preview Section

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Vorschau des Inhalts")
                    .font(.headline)

                Spacer()

                Text("\(summary.content.count) Zeichen")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Notion-style preview
            VStack(alignment: .leading, spacing: 8) {
                // Title preview
                HStack {
                    Image(systemName: "doc.text.fill")
                        .foregroundColor(.accentColor)
                    Text(customTitle.isEmpty ? "Unbenannt" : customTitle)
                        .font(.headline)
                }
                .padding(.bottom, 4)

                Divider()

                // Content heading
                HStack {
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(width: 4)
                    Text("Zusammenfassung")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }

                // Summary text preview
                Text(summary.content)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(8)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if summary.content.count > 500 {
                    Text("... (gekürzt)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .italic()
                }
            }
            .padding()
            .background(Color(nsColor: .textBackgroundColor))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
            )
        }
    }

    // MARK: - Properties Section

    private var propertiesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Eigenschaften")
                .font(.headline)

            VStack(spacing: 8) {
                PropertyRow(icon: "calendar", label: "Datum", value: summary.startTime.formatted(date: .abbreviated, time: .shortened))

                PropertyRow(icon: "clock", label: "Zeitraum", value: summary.formattedTimeRange)

                if let count = summary.screenshotCount, count > 0 {
                    PropertyRow(icon: "photo", label: "Screenshots", value: "\(count)")
                }

                if summary.totalTokens > 0 {
                    PropertyRow(icon: "number", label: "Tokens", value: "\(summary.totalTokens)")
                }
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
        }
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack {
            Button("Abbrechen") {
                onCancel()
            }
            .keyboardShortcut(.cancelAction)

            Spacer()

            Button(action: {
                Task {
                    isExporting = true
                    await onExport(customTitle)
                    isExporting = false
                }
            }) {
                if isExporting {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Exportiere...")
                    }
                } else {
                    Label("Nach Notion exportieren", systemImage: "square.and.arrow.up")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(customTitle.isEmpty || isExporting)
            .keyboardShortcut(.defaultAction)
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

// MARK: - Property Row

struct PropertyRow: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .frame(width: 20)
                .foregroundColor(.secondary)

            Text(label)
                .foregroundColor(.secondary)

            Spacer()

            Text(value)
                .fontWeight(.medium)
        }
        .font(.caption)
    }
}

// MARK: - Preview

#Preview {
    NotionExportPreviewView(
        summary: Summary(
            id: 1,
            title: nil,
            startTime: Date().addingTimeInterval(-3600),
            endTime: Date(),
            content: "Dies ist eine Beispiel-Zusammenfassung für die Vorschau. Sie enthält wichtige Informationen über die Aktivitäten des letzten Zeitraums.\n\nWeitere Details und Erkenntnisse wurden hier zusammengefasst.",
            screenshotCount: 42,
            createdAt: Date()
        ),
        onExport: { _ in },
        onCancel: {}
    )
}
