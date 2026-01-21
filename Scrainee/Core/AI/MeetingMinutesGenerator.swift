// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - DEPENDENCY DOCUMENTATION
// ═══════════════════════════════════════════════════════════════════════════════
//
// FILE: MeetingMinutesGenerator | PURPOSE: Meeting-Minutes aus Transkripten | LAYER: Core/AI
//
// DEPENDENCIES: ClaudeAPIClient, DatabaseManager
// DEPENDENTS: MeetingTranscriptionCoordinator, MeetingMinutesViewModel
// CHANGE IMPACT: Aenderungen betreffen Meeting-Minutes-Generierung und Live-Updates
//
// LAST UPDATED: 2026-01-20
// ═══════════════════════════════════════════════════════════════════════════════

import Foundation

/// Generates structured meeting minutes from transcripts using Claude API
@MainActor
final class MeetingMinutesGenerator: ObservableObject {
    static let shared = MeetingMinutesGenerator()

    // MARK: - Published State

    @Published private(set) var isGenerating = false
    @Published private(set) var currentProgress: String = ""
    @Published private(set) var error: String?

    // MARK: - Dependencies

    private let claudeClient = ClaudeAPIClient()
    private let databaseManager = DatabaseManager.shared

    // MARK: - Configuration

    private let minSegmentsForUpdate = 3
    private let model = "claude-sonnet-4-5-20250929"

    // MARK: - Initialization

    private init() {}

    // MARK: - Public API

    /// Generates or updates meeting minutes from transcript segments
    func generateMinutes(
        for meetingId: Int64,
        segments: [TranscriptSegment],
        existingMinutes: MeetingMinutes? = nil,
        isLiveUpdate: Bool = false
    ) async throws -> MeetingMinutes {
        guard !segments.isEmpty else {
            throw MinutesGenerationError.noTranscriptData
        }

        isGenerating = true
        currentProgress = isLiveUpdate ? "Aktualisiere Minutes..." : "Generiere Minutes..."
        defer {
            isGenerating = false
            currentProgress = ""
        }

        // Build the transcript text
        var transcriptLines: [String] = []
        for segment in segments {
            let timestamp = formatTimestamp(segment.startTime)
            transcriptLines.append("[\(timestamp)] \(segment.text)")
        }
        let transcriptText: String = transcriptLines.joined(separator: "\n")

        // Build the prompt
        let prompt = buildPrompt(
            transcript: transcriptText,
            existingMinutes: existingMinutes,
            isLiveUpdate: isLiveUpdate
        )

        // Call Claude API
        do {
            let (responseText, _) = try await claudeClient.analyzeText(prompt: prompt)

            // Parse the response
            let parsedMinutes = try parseMinutesResponse(responseText, meetingId: meetingId, existingMinutes: existingMinutes)

            // Save to database
            let minutesId = try await databaseManager.upsert(parsedMinutes)

            var savedMinutes = parsedMinutes
            savedMinutes.id = minutesId

            return savedMinutes

        } catch {
            self.error = "Minutes-Generierung fehlgeschlagen: \(error.localizedDescription)"
            throw MinutesGenerationError.generationFailed(error.localizedDescription)
        }
    }

    /// Generates minutes with streaming updates
    func streamGenerateMinutes(
        for meetingId: Int64,
        segments: [TranscriptSegment],
        existingMinutes: MeetingMinutes? = nil,
        onUpdate: @escaping (String) -> Void
    ) async throws -> MeetingMinutes {
        guard !segments.isEmpty else {
            throw MinutesGenerationError.noTranscriptData
        }

        isGenerating = true
        currentProgress = "Generiere Minutes (Streaming)..."
        defer {
            isGenerating = false
            currentProgress = ""
        }

        var transcriptLines: [String] = []
        for segment in segments {
            let timestamp = formatTimestamp(segment.startTime)
            transcriptLines.append("[\(timestamp)] \(segment.text)")
        }
        let transcriptText: String = transcriptLines.joined(separator: "\n")

        let prompt = buildPrompt(
            transcript: transcriptText,
            existingMinutes: existingMinutes,
            isLiveUpdate: false
        )

        do {
            // Use non-streaming API and update when complete
            // Note: Full streaming support requires @Sendable callback
            let (responseText, _) = try await claudeClient.analyzeText(prompt: prompt)

            // Notify with final response
            onUpdate(responseText)

            let parsedMinutes = try parseMinutesResponse(responseText, meetingId: meetingId, existingMinutes: existingMinutes)
            let minutesId = try await databaseManager.upsert(parsedMinutes)

            var savedMinutes = parsedMinutes
            savedMinutes.id = minutesId

            return savedMinutes

        } catch {
            self.error = "Streaming-Generierung fehlgeschlagen: \(error.localizedDescription)"
            throw MinutesGenerationError.generationFailed(error.localizedDescription)
        }
    }

    /// Extracts action items from transcript or minutes
    func extractActionItems(
        for meetingId: Int64,
        from text: String
    ) async throws -> [ActionItem] {
        let prompt = """
        Analysiere den folgenden Text und extrahiere alle Action Items (Aufgaben, ToDos).

        Text:
        \(text)

        Für jedes Action Item, extrahiere:
        - title: Kurze Beschreibung der Aufgabe
        - assignee: Verantwortliche Person (falls erwähnt, sonst null)
        - dueDate: Fälligkeitsdatum (falls erwähnt, im Format YYYY-MM-DD, sonst null)
        - priority: low, medium, high oder urgent (basierend auf Kontext)

        Antworte NUR mit einem JSON-Array. Beispiel:
        [
            {"title": "Präsentation erstellen", "assignee": "Max", "dueDate": "2024-01-20", "priority": "high"},
            {"title": "Meeting-Raum buchen", "assignee": null, "dueDate": null, "priority": "medium"}
        ]

        Falls keine Action Items gefunden wurden, antworte mit: []
        """

        do {
            let (responseText, _) = try await claudeClient.analyzeText(prompt: prompt)
            return try parseActionItems(from: responseText, meetingId: meetingId)

        } catch {
            throw MinutesGenerationError.actionItemExtractionFailed(error.localizedDescription)
        }
    }

    /// Finalizes meeting minutes after meeting ends
    func finalizeMinutes(for meetingId: Int64) async throws -> MeetingMinutes {
        // Get all segments for the meeting
        let segments = try await databaseManager.getTranscriptSegments(for: meetingId)
        let existingMinutes = try await databaseManager.getMeetingMinutes(for: meetingId)

        // Generate comprehensive final minutes
        let finalMinutes = try await generateMinutes(
            for: meetingId,
            segments: segments,
            existingMinutes: existingMinutes,
            isLiveUpdate: false
        )

        // Mark as finalized
        try await databaseManager.finalizeMeetingMinutes(for: meetingId)

        // Extract and save action items
        let actionItems = try await extractActionItems(
            for: meetingId,
            from: segments.map { $0.text }.joined(separator: " ")
        )

        if !actionItems.isEmpty {
            try await databaseManager.insert(actionItems)
        }

        return finalMinutes
    }

    // MARK: - Private Methods

    private func buildPrompt(transcript: String, existingMinutes: MeetingMinutes?, isLiveUpdate: Bool) -> String {
        var prompt = """
        Du bist ein professioneller Meeting-Assistent. Analysiere das folgende Transkript und erstelle strukturierte Meeting-Minutes auf Deutsch.

        ## Transkript
        \(transcript)

        """

        if let existing = existingMinutes {
            prompt += """

            ## Bisherige Zusammenfassung
            \(existing.summary ?? "Keine")

            ## Bisherige Kernpunkte
            \(existing.keyPointsList.joined(separator: "\n- "))

            """
        }

        prompt += """

        Erstelle eine \(isLiveUpdate ? "aktualisierte" : "vollständige") Zusammenfassung mit folgender Struktur:

        1. **Zusammenfassung**: 2-3 Sätze, die den Kern des Meetings erfassen
        2. **Kernpunkte**: Die wichtigsten besprochenen Themen (als Liste)
        3. **Action Items**: Aufgaben mit Verantwortlichen, falls erkennbar (als Liste)
        4. **Entscheidungen**: Getroffene Beschlüsse (als Liste)

        Antworte im folgenden JSON-Format:
        {
            "summary": "Zusammenfassung hier",
            "keyPoints": ["Punkt 1", "Punkt 2"],
            "actionItems": ["Action Item 1", "Action Item 2"],
            "decisions": ["Entscheidung 1", "Entscheidung 2"]
        }

        Wichtig:
        - Antworte NUR mit dem JSON, ohne zusätzlichen Text
        - Verwende keine Markdown-Formatierung im JSON
        - Halte die Zusammenfassung prägnant
        - Listen können leer sein, wenn nichts Relevantes vorhanden ist
        """

        return prompt
    }

    private func parseMinutesResponse(_ response: String, meetingId: Int64, existingMinutes: MeetingMinutes?) throws -> MeetingMinutes {
        // Extract JSON from response (handle potential markdown code blocks)
        var jsonString = response.trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove markdown code blocks if present
        if jsonString.hasPrefix("```json") {
            jsonString = String(jsonString.dropFirst(7))
        } else if jsonString.hasPrefix("```") {
            jsonString = String(jsonString.dropFirst(3))
        }

        if jsonString.hasSuffix("```") {
            jsonString = String(jsonString.dropLast(3))
        }

        jsonString = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)

        // Parse JSON
        guard let data = jsonString.data(using: .utf8) else {
            throw MinutesGenerationError.parseError("Konnte Response nicht als UTF-8 dekodieren")
        }

        struct MinutesJSON: Codable {
            let summary: String?
            let keyPoints: [String]?
            let actionItems: [String]?
            let decisions: [String]?
        }

        do {
            let parsed = try JSONDecoder().decode(MinutesJSON.self, from: data)

            var minutes = MeetingMinutes(
                id: existingMinutes?.id,
                meetingId: meetingId,
                summary: parsed.summary,
                version: (existingMinutes?.version ?? 0) + 1,
                isFinalized: false,
                generatedAt: Date(),
                model: model
            )

            if let keyPoints = parsed.keyPoints {
                minutes.setKeyPoints(keyPoints)
            }

            if let actions = parsed.actionItems, let data = try? JSONEncoder().encode(actions) {
                minutes.actionItems = String(data: data, encoding: .utf8)
            }

            if let decisions = parsed.decisions {
                minutes.setDecisions(decisions)
            }

            return minutes

        } catch {
            throw MinutesGenerationError.parseError("JSON-Parsing fehlgeschlagen: \(error.localizedDescription)")
        }
    }

    private func parseActionItems(from response: String, meetingId: Int64) throws -> [ActionItem] {
        var jsonString = response.trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove markdown code blocks
        if jsonString.hasPrefix("```json") {
            jsonString = String(jsonString.dropFirst(7))
        } else if jsonString.hasPrefix("```") {
            jsonString = String(jsonString.dropFirst(3))
        }

        if jsonString.hasSuffix("```") {
            jsonString = String(jsonString.dropLast(3))
        }

        jsonString = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = jsonString.data(using: .utf8) else {
            return []
        }

        struct ActionItemJSON: Codable {
            let title: String
            let assignee: String?
            let dueDate: String?
            let priority: String?
        }

        do {
            let items = try JSONDecoder().decode([ActionItemJSON].self, from: data)

            return items.map { item in
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd"

                return ActionItem(
                    meetingId: meetingId,
                    title: item.title,
                    assignee: item.assignee,
                    dueDate: item.dueDate.flatMap { dateFormatter.date(from: $0) },
                    priority: ActionItemPriority(rawValue: item.priority ?? "medium") ?? .medium,
                    status: .pending
                )
            }

        } catch {
            FileLogger.shared.error("Failed to parse action items: \(error)", context: "MeetingMinutesGenerator")
            return []
        }
    }

    private func formatTimestamp(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", minutes, secs)
    }
}

// MARK: - Errors

enum MinutesGenerationError: LocalizedError {
    case noTranscriptData
    case generationFailed(String)
    case parseError(String)
    case actionItemExtractionFailed(String)

    var errorDescription: String? {
        switch self {
        case .noTranscriptData:
            return "Keine Transkript-Daten vorhanden"
        case .generationFailed(let message):
            return "Minutes-Generierung fehlgeschlagen: \(message)"
        case .parseError(let message):
            return "Parsing-Fehler: \(message)"
        case .actionItemExtractionFailed(let message):
            return "Action-Item-Extraktion fehlgeschlagen: \(message)"
        }
    }
}
