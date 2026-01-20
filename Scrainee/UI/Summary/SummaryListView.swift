// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - DEPENDENCY DOCUMENTATION
// ═══════════════════════════════════════════════════════════════════════════════
//
// FILE: SummaryListView.swift | PURPOSE: Summary History & Notion Export | LAYER: UI/Summary
//
// DEPENDENCIES:
//   - AppState (App/AppState.swift) - Global app state via @EnvironmentObject
//   - NotionClient (Core/Integration/NotionClient.swift) - Notion API export
//   - DatabaseManager (Core/Database/DatabaseManager.swift) - Summary persistence
//   - Summary (Core/Database/Models/Summary.swift) - Summary data model
//   - NotionExportPreviewView (UI/Summary/NotionExportPreviewView.swift) - Export preview sheet
//
// DEPENDENTS:
//   - ScraineeApp.swift - Window registration with id: "summarylist"
//   - MenuBarView.swift - Opens via "Alle Zusammenfassungen" button
//
// CHANGE IMPACT:
//   - Window ID "summarylist" used in openWindow() calls
//   - Contains embedded: SummaryRowView, SummaryDetailView, SummaryListViewModel
//
// LAST UPDATED: 2026-01-20
// ═══════════════════════════════════════════════════════════════════════════════

import SwiftUI

struct SummaryListView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel = SummaryListViewModel()

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            Divider()

            // Content
            if viewModel.isLoading {
                loadingView
            } else if viewModel.summaries.isEmpty {
                emptyStateView
            } else {
                summaryList
            }
        }
        .frame(minWidth: 700, minHeight: 500)
        .sheet(item: $viewModel.selectedSummaryForExport) { summary in
            NotionExportPreviewView(
                summary: summary,
                onExport: { title in
                    await viewModel.exportToNotion(summary: summary, title: title)
                },
                onCancel: {
                    viewModel.selectedSummaryForExport = nil
                }
            )
        }
        .sheet(item: $viewModel.selectedSummaryForDetail) { summary in
            SummaryDetailView(summary: summary)
        }
        .alert("Fehler", isPresented: $viewModel.showError) {
            Button("OK") {}
        } message: {
            Text(viewModel.errorMessage ?? "Ein Fehler ist aufgetreten")
        }
        .alert("Erfolg", isPresented: $viewModel.showSuccess) {
            Button("OK") {}
            if let url = viewModel.notionPageUrl {
                Button("In Notion öffnen") {
                    NSWorkspace.shared.open(url)
                }
            }
        } message: {
            Text(viewModel.successMessage ?? "Export erfolgreich")
        }
        .onAppear {
            Task {
                await viewModel.loadSummaries()
            }
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            Image(systemName: "list.bullet.rectangle")
                .font(.title2)
                .foregroundColor(.accentColor)

            Text("Zusammenfassungen")
                .font(.title2)
                .fontWeight(.semibold)

            Spacer()

            Button(action: {
                Task { await viewModel.loadSummaries() }
            }) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Aktualisieren")
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Lade Zusammenfassungen...")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("Keine Zusammenfassungen")
                .font(.headline)

            Text("Erstelle eine Zusammenfassung über das Menü oder mit Cmd+Shift+S")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Summary List

    private var summaryList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(viewModel.summaries) { summary in
                    SummaryRowView(
                        summary: summary,
                        onTap: {
                            viewModel.selectedSummaryForDetail = summary
                        },
                        onExport: {
                            viewModel.selectedSummaryForExport = summary
                        },
                        onDelete: {
                            Task { await viewModel.deleteSummary(summary) }
                        }
                    )
                }
            }
            .padding()
        }
    }
}

// MARK: - Summary Row View

struct SummaryRowView: View {
    let summary: Summary
    let onTap: () -> Void
    let onExport: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Icon
            Image(systemName: "doc.text.fill")
                .font(.title2)
                .foregroundColor(.accentColor)
                .frame(width: 32)

            // Content
            VStack(alignment: .leading, spacing: 4) {
                // Titel / Zeitraum
                Text(summary.title ?? summary.formattedTimeRange)
                    .font(.headline)
                    .lineLimit(1)

                // Datum
                if let createdAt = summary.createdAt {
                    Text("Erstellt: \(createdAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // Preview
                Text(summary.content)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)

                // Stats
                HStack(spacing: 16) {
                    if let count = summary.screenshotCount, count > 0 {
                        Label("\(count) Screenshots", systemImage: "photo")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    if summary.totalTokens > 0 {
                        Label("\(summary.totalTokens) Tokens", systemImage: "number")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            // Actions
            if isHovering {
                HStack(spacing: 8) {
                    Button(action: onExport) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .buttonStyle(.borderless)
                    .help("Nach Notion exportieren")

                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.borderless)
                    .help("Löschen")
                }
            }
        }
        .padding()
        .background(isHovering ? Color(nsColor: .selectedControlColor).opacity(0.1) : Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

// MARK: - Summary Detail View

struct SummaryDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let summary: Summary

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(summary.title ?? summary.formattedTimeRange)
                    .font(.headline)

                Spacer()

                Button(action: { copyToClipboard(summary.content) }) {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("In Zwischenablage kopieren")

                Button("Schließen") {
                    dismiss()
                }
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Meta info
                    HStack(spacing: 20) {
                        if let createdAt = summary.createdAt {
                            Label(createdAt.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        if let count = summary.screenshotCount {
                            Label("\(count) Screenshots", systemImage: "photo")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        if summary.totalTokens > 0 {
                            Label("\(summary.totalTokens) Tokens", systemImage: "number")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Divider()

                    // Summary text
                    Text(summary.content)
                        .font(.body)
                        .textSelection(.enabled)
                }
                .padding()
            }
        }
        .frame(width: 600, height: 500)
    }

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

// MARK: - View Model

@MainActor
final class SummaryListViewModel: ObservableObject {
    @Published var summaries: [Summary] = []
    @Published var isLoading = false
    @Published var showError = false
    @Published var errorMessage: String?
    @Published var showSuccess = false
    @Published var successMessage: String?
    @Published var notionPageUrl: URL?
    @Published var selectedSummaryForExport: Summary?
    @Published var selectedSummaryForDetail: Summary?

    private let notionClient = NotionClient()

    func loadSummaries() async {
        isLoading = true
        defer { isLoading = false }

        do {
            summaries = try await DatabaseManager.shared.getSummaries(limit: 100)
        } catch {
            errorMessage = "Fehler beim Laden: \(error.localizedDescription)"
            showError = true
        }
    }

    func deleteSummary(_ summary: Summary) async {
        guard let id = summary.id else { return }

        do {
            try await DatabaseManager.shared.deleteSummary(id: id)
            summaries.removeAll { $0.id == id }
        } catch {
            errorMessage = "Fehler beim Löschen: \(error.localizedDescription)"
            showError = true
        }
    }

    func exportToNotion(summary: Summary, title: String) async {
        guard notionClient.isConfigured else {
            errorMessage = "Notion nicht konfiguriert. Bitte API Key und Database ID in den Einstellungen eingeben."
            showError = true
            selectedSummaryForExport = nil
            return
        }

        do {
            let page = try await notionClient.exportSummary(summary, title: title)
            notionPageUrl = URL(string: page.url)
            successMessage = "Zusammenfassung erfolgreich nach Notion exportiert!"
            showSuccess = true
        } catch {
            errorMessage = "Export fehlgeschlagen: \(error.localizedDescription)"
            showError = true
        }

        selectedSummaryForExport = nil
    }
}

// MARK: - Preview

#Preview {
    SummaryListView()
        .environmentObject(AppState.shared)
}
