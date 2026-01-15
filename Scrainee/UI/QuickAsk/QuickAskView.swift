import SwiftUI

/// Quick Ask floating window for asking questions about current context
struct QuickAskView: View {
    @StateObject private var viewModel = QuickAskViewModel()
    @FocusState private var isInputFocused: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header with context info
            headerView

            Divider()

            // Input field
            inputSection

            // Response or suggestions
            if viewModel.isLoading {
                loadingView
            } else if let response = viewModel.response {
                responseView(response)
            } else {
                suggestionsView
            }
        }
        .frame(width: 500)
        .frame(minHeight: 200, maxHeight: 500)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.3), radius: 20)
        .onAppear {
            isInputFocused = true
            Task {
                await viewModel.loadContext()
            }
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            Image(systemName: "sparkles")
                .foregroundColor(.accentColor)

            Text("Quick Ask")
                .font(.headline)

            Spacer()

            // Context indicator
            if let context = viewModel.contextSummary {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                    Text(context)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding()
    }

    // MARK: - Input Section

    private var inputSection: some View {
        HStack(spacing: 12) {
            TextField("Frag mich etwas zum aktuellen Kontext...", text: $viewModel.question)
                .textFieldStyle(.plain)
                .font(.body)
                .focused($isInputFocused)
                .onSubmit {
                    Task { await viewModel.askQuestion() }
                }

            Button(action: { Task { await viewModel.askQuestion() } }) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundColor(viewModel.question.isEmpty ? .secondary : .accentColor)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.question.isEmpty || viewModel.isLoading)
        }
        .padding()
        .background(.thickMaterial)
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Analysiere Kontext...")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Response View

    private func responseView(_ response: String) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(response)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack {
                    Button(action: copyResponse) {
                        Label("Kopieren", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button(action: { viewModel.clearResponse() }) {
                        Label("Neue Frage", systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding()
        }
    }

    // MARK: - Suggestions View

    private var suggestionsView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Vorschlaege")
                .font(.caption)
                .foregroundColor(.secondary)

            ForEach(viewModel.suggestions, id: \.self) { suggestion in
                Button(action: {
                    viewModel.question = suggestion
                    Task { await viewModel.askQuestion() }
                }) {
                    HStack {
                        Image(systemName: "lightbulb")
                            .foregroundColor(.yellow)
                        Text(suggestion)
                            .font(.caption)
                            .foregroundColor(.primary)
                        Spacer()
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(.thinMaterial)
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Actions

    private func copyResponse() {
        guard let response = viewModel.response else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(response, forType: .string)
    }
}

// MARK: - View Model

@MainActor
final class QuickAskViewModel: ObservableObject {
    @Published var question = ""
    @Published var response: String?
    @Published var isLoading = false
    @Published var contextSummary: String?
    @Published var suggestions: [String] = []

    private let summaryGenerator = SummaryGenerator()
    private var recentOCRTexts: [String] = []

    // MARK: - Context Loading

    func loadContext() async {
        // Get recent screenshots and their OCR text
        let lastHour = Calendar.current.date(byAdding: .hour, value: -1, to: Date())!

        do {
            let screenshots = try await DatabaseManager.shared.getScreenshots(from: lastHour, to: Date())

            if let latestScreenshot = screenshots.first {
                contextSummary = latestScreenshot.appName ?? "Unbekannt"
            }

            // Load recent OCR texts for context
            let ocrTexts = try await DatabaseManager.shared.getOCRTexts(from: lastHour, to: Date())
            recentOCRTexts = ocrTexts.map { $0.text }

            // Generate suggestions based on context
            updateSuggestions()
        } catch {
            print("Failed to load context: \(error)")
        }
    }

    // MARK: - Question Handling

    func askQuestion() async {
        guard !question.isEmpty, summaryGenerator.hasAPIKey else {
            if !summaryGenerator.hasAPIKey {
                response = "Bitte konfiguriere zuerst deinen Claude API Key in den Einstellungen."
            }
            return
        }

        isLoading = true
        defer { isLoading = false }

        // Build context from recent OCR texts
        let contextText = recentOCRTexts.prefix(10).joined(separator: "\n---\n")

        let prompt = """
        Du bist ein hilfreicher Assistent. Basierend auf dem aktuellen Bildschirmkontext des Nutzers, beantworte folgende Frage kurz und praezise.

        Aktueller Kontext (extrahierter Text aus Screenshots):
        ---
        \(contextText.prefix(3000))
        ---

        Frage des Nutzers: \(question)

        Antworte auf Deutsch, kurz und hilfreich. Wenn der Kontext nicht ausreicht, sag das ehrlich.
        """

        do {
            let client = ClaudeAPIClient(
                apiKey: KeychainService.shared.claudeAPIKey ?? "",
                model: "claude-sonnet-4-5-20250514",
                maxTokens: 500
            )

            let (text, _) = try await client.analyzeText(prompt: prompt)
            response = text
        } catch {
            response = "Fehler: \(error.localizedDescription)"
        }
    }

    func clearResponse() {
        response = nil
        question = ""
    }

    // MARK: - Suggestions

    private func updateSuggestions() {
        suggestions = [
            "Was war das Hauptthema der letzten Stunde?",
            "Fasse die wichtigsten Punkte zusammen",
            "Welche Aufgaben wurden besprochen?",
            "Gibt es Action Items?"
        ]
    }
}

// MARK: - Preview

#Preview {
    QuickAskView()
}
