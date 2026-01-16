import SwiftUI

struct SummaryRequestView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel = SummaryRequestViewModel()

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            Divider()

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Time range selection
                    timeRangeSection

                    // Quick options
                    quickOptionsSection

                    // Generate button
                    generateSection

                    // Result
                    if viewModel.isGenerating {
                        generatingView
                    } else if let summary = viewModel.summary {
                        summaryResultView(summary)
                    }
                }
                .padding()
            }
        }
        .frame(minWidth: 600, minHeight: 500)
        .alert("Fehler", isPresented: $viewModel.showError) {
            Button("OK") {}
        } message: {
            Text(viewModel.errorMessage ?? "Ein Fehler ist aufgetreten")
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.title2)
                .foregroundColor(.accentColor)

            Text("Zusammenfassung erstellen")
                .font(.title2)
                .fontWeight(.semibold)

            Spacer()
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Time Range Section

    private var timeRangeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Zeitraum")
                .font(.headline)

            HStack(spacing: 20) {
                VStack(alignment: .leading) {
                    Text("Von")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    DatePicker("", selection: $viewModel.startDate, displayedComponents: [.date, .hourAndMinute])
                        .labelsHidden()
                }

                VStack(alignment: .leading) {
                    Text("Bis")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    DatePicker("", selection: $viewModel.endDate, displayedComponents: [.date, .hourAndMinute])
                        .labelsHidden()
                }
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }

    // MARK: - Quick Options

    private var quickOptionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Schnellauswahl")
                .font(.headline)

            HStack(spacing: 12) {
                QuickOptionButton(title: "Letzte Stunde", icon: "clock") {
                    viewModel.setLastHour()
                }

                QuickOptionButton(title: "Letzte 4 Stunden", icon: "clock.arrow.2.circlepath") {
                    viewModel.setLastFourHours()
                }

                QuickOptionButton(title: "Heute", icon: "calendar") {
                    viewModel.setToday()
                }

                QuickOptionButton(title: "Gestern", icon: "calendar.day.timeline.left") {
                    viewModel.setYesterday()
                }
            }
        }
    }

    // MARK: - Generate Section

    private var generateSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button(action: { Task { await viewModel.generateSummary() } }) {
                    Label("Zusammenfassung erstellen", systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isGenerating || !viewModel.hasAPIKey)

                Button(action: { Task { await viewModel.generateQuickSummary() } }) {
                    Label("Schnell (nur Text)", systemImage: "bolt")
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.isGenerating || !viewModel.hasAPIKey)
            }

            if !viewModel.hasAPIKey {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                    Text("Bitte konfiguriere deinen Claude API Key in den Einstellungen.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - Generating View

    private var generatingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)

            Text("Erstelle Zusammenfassung...")
                .font(.headline)

            Text("Analysiere \(viewModel.screenshotCount) Screenshots")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }

    // MARK: - Summary Result

    private func summaryResultView(_ summary: Summary) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Zusammenfassung")
                    .font(.headline)

                Spacer()

                Text(summary.formattedTimeRange)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Button(action: { copyToClipboard(summary.content) }) {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("In Zwischenablage kopieren")
            }

            ScrollView {
                Text(summary.content)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 300)

            HStack {
                if summary.totalTokens > 0 {
                    Text("\(summary.totalTokens) Tokens verwendet")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Text("\(summary.screenshotCount ?? 0) Screenshots analysiert")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }

    // MARK: - Helpers

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

// MARK: - Quick Option Button

struct QuickOptionButton: View {
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.title3)
                Text(title)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.bordered)
    }
}

// MARK: - View Model

@MainActor
final class SummaryRequestViewModel: ObservableObject {
    @Published var startDate = Calendar.current.date(byAdding: .hour, value: -1, to: Date())!
    @Published var endDate = Date()
    @Published var isGenerating = false
    @Published var summary: Summary?
    @Published var screenshotCount = 0
    @Published var showError = false
    @Published var errorMessage: String?

    private let summaryGenerator = SummaryGenerator()

    var hasAPIKey: Bool {
        summaryGenerator.hasAPIKey
    }

    // MARK: - Quick Options

    func setLastHour() {
        endDate = Date()
        startDate = Calendar.current.date(byAdding: .hour, value: -1, to: endDate)!
    }

    func setLastFourHours() {
        endDate = Date()
        startDate = Calendar.current.date(byAdding: .hour, value: -4, to: endDate)!
    }

    func setToday() {
        endDate = Date()
        startDate = Calendar.current.startOfDay(for: Date())
    }

    func setYesterday() {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        startDate = Calendar.current.startOfDay(for: yesterday)
        endDate = Calendar.current.startOfDay(for: Date())
    }

    // MARK: - Summary Generation

    func generateSummary() async {
        guard !isGenerating else { return }

        isGenerating = true
        summary = nil

        do {
            // Get screenshot count first
            let screenshots = try await DatabaseManager.shared.getScreenshots(from: startDate, to: endDate)
            screenshotCount = screenshots.count

            let result = try await summaryGenerator.generateSummary(from: startDate, to: endDate)
            summary = result
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }

        isGenerating = false
    }

    func generateQuickSummary() async {
        guard !isGenerating else { return }

        isGenerating = true
        summary = nil

        do {
            // Get screenshot count
            let screenshots = try await DatabaseManager.shared.getScreenshots(from: startDate, to: endDate)
            screenshotCount = screenshots.count

            let text = try await summaryGenerator.generateQuickSummary(from: startDate, to: endDate)
            var newSummary = Summary(
                startTime: startDate,
                endTime: endDate,
                content: text,
                model: "claude-sonnet-4-5-20250514",
                screenshotCount: screenshots.count
            )

            // Save to database
            let id = try await DatabaseManager.shared.insert(newSummary)
            newSummary.id = id

            summary = newSummary
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }

        isGenerating = false
    }
}

// MARK: - Preview

#Preview {
    SummaryRequestView()
        .environmentObject(AppState.shared)
}
