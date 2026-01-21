// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - DEPENDENCY DOCUMENTATION
// ═══════════════════════════════════════════════════════════════════════════════
//
// FILE: QuickAskView.swift | PURPOSE: AI Quick-Ask Floating Panel | LAYER: UI/QuickAsk
//
// DEPENDENCIES:
//   - ClaudeAPIClient (Core/AI/ClaudeAPIClient.swift) - Claude API for Q&A
//   - SummaryGenerator (Core/AI/SummaryGenerator.swift) - API key validation
//   - DatabaseManager (Core/Database/DatabaseManager.swift) - Context loading (screenshots, OCR, meetings)
//   - KeychainService (Services/KeychainService.swift) - API key retrieval
//   - Screenshot, OCRResult, Meeting, Summary (Core/Database/Models/) - Data models
//
// DEPENDENTS:
//   - ScraineeApp.swift - Window registration with id: "quickask"
//   - MenuBarView.swift - Opens via "Quick Ask" button (Cmd+Shift+A)
//   - HotkeyManager (Services/HotkeyManager.swift) - Global hotkey trigger
//
// CHANGE IMPACT:
//   - Window ID "quickask" used in openWindow() calls
//   - QuickAskViewModel embedded - handles multi-source context aggregation
//   - Floating window style - affects window behavior
//
// LAST UPDATED: 2026-01-20
// ═══════════════════════════════════════════════════════════════════════════════

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
    private var meetingContext: String?
    private var summaryContext: String?
    private var actionItemsContext: String?
    private var hasActiveMeeting = false

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

            // NEU: Meeting-Kontext laden (falls aktives Meeting)
            if let activeMeeting = try await DatabaseManager.shared.getActiveMeeting() {
                hasActiveMeeting = true
                meetingContext = activeMeeting.aiSummary
                contextSummary = "Meeting: \(activeMeeting.appName)"
            }

            // NEU: Letzte Summaries laden
            let recentSummaries = try await DatabaseManager.shared.getSummaries(limit: 3)
            if !recentSummaries.isEmpty {
                summaryContext = recentSummaries.map { summary in
                    "[\(summary.title ?? "Zusammenfassung")]: \(summary.content.prefix(500))"
                }.joined(separator: "\n---\n")
            }

            // NEU: Aktive Action-Items laden
            let activeItems = try await DatabaseManager.shared.getActiveActionItems()
            if !activeItems.isEmpty {
                actionItemsContext = activeItems.prefix(5).map { "- \($0.title)" }.joined(separator: "\n")
            }

            // Generate suggestions based on context
            updateSuggestions()
        } catch {
            FileLogger.shared.error("Failed to load context: \(error)", context: "QuickAskView")
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

        // Build comprehensive context from all available sources
        var contextParts: [String] = []

        // 1. Aktueller Bildschirm-Kontext (OCR)
        let ocrContext = recentOCRTexts.prefix(10).joined(separator: "\n---\n")
        if !ocrContext.isEmpty {
            contextParts.append("### Aktueller Bildschirm (letzte Stunde):\n\(String(ocrContext.prefix(2000)))")
        }

        // 2. Meeting-Kontext (falls vorhanden)
        if let meeting = meetingContext, !meeting.isEmpty {
            contextParts.append("### Aktives Meeting:\n\(meeting)")
        }

        // 3. Letzte Zusammenfassungen
        if let summaries = summaryContext, !summaries.isEmpty {
            contextParts.append("### Letzte Zusammenfassungen:\n\(String(summaries.prefix(1500)))")
        }

        // 4. Offene Action-Items
        if let items = actionItemsContext, !items.isEmpty {
            contextParts.append("### Offene Aufgaben:\n\(items)")
        }

        let fullContext = contextParts.joined(separator: "\n\n")

        let prompt = """
        Du bist ein hilfreicher Assistent mit Zugriff auf den aktuellen Kontext des Nutzers.

        \(fullContext.isEmpty ? "Kein Kontext verfuegbar." : fullContext)

        Frage des Nutzers: \(question)

        Antworte auf Deutsch, kurz und hilfreich. Beziehe dich auf den Kontext wenn relevant. Wenn der Kontext nicht ausreicht, sag das ehrlich.
        """

        do {
            // Pruefe API-Key vor dem Erstellen des Clients
            guard let apiKey = KeychainService.shared.claudeAPIKey, !apiKey.isEmpty else {
                response = "Bitte konfiguriere zuerst deinen Claude API Key in den Einstellungen."
                return
            }

            let client = ClaudeAPIClient(
                apiKey: apiKey,
                model: "claude-sonnet-4-5-20250929",
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
        var dynamicSuggestions: [String] = []

        // Basis-Vorschlaege
        dynamicSuggestions.append("Was war das Hauptthema der letzten Stunde?")
        dynamicSuggestions.append("Fasse die wichtigsten Punkte zusammen")

        // Kontext-abhaengige Vorschlaege
        if hasActiveMeeting {
            dynamicSuggestions.insert("Was wurde im Meeting besprochen?", at: 0)
            dynamicSuggestions.append("Wer hat was gesagt?")
        }

        if actionItemsContext != nil {
            dynamicSuggestions.append("Welche Aufgaben sind offen?")
        } else {
            dynamicSuggestions.append("Gibt es Action Items?")
        }

        if summaryContext != nil {
            dynamicSuggestions.append("Was habe ich heute gemacht?")
        }

        // Maximal 4 Vorschlaege anzeigen
        suggestions = Array(dynamicSuggestions.prefix(4))
    }
}

// MARK: - Preview

#Preview {
    QuickAskView()
}
