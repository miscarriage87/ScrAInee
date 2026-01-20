// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - DEPENDENCY DOCUMENTATION
// ═══════════════════════════════════════════════════════════════════════════════
//
// FILE: SummaryGenerator | PURPOSE: AI-Zusammenfassungen aus Screenshots | LAYER: Core/AI
//
// DEPENDENCIES: ClaudeAPIClient, DatabaseManager, ImageCompressor, KeychainAccess
// DEPENDENTS: AppState, QuickAskView, SummaryRequestView
// CHANGE IMPACT: Aenderungen betreffen Summary-Generierung und Quick-Ask Feature
//
// LAST UPDATED: 2026-01-20
// ═══════════════════════════════════════════════════════════════════════════════

import Foundation
import KeychainAccess

/// Generates AI summaries from screenshots
@MainActor
final class SummaryGenerator {
    private var claudeClient: ClaudeAPIClient?
    private let databaseManager = DatabaseManager.shared
    private let imageCompressor = ImageCompressor()

    // Keychain for API key storage
    private let keychain = Keychain(service: "com.cpohl.scrainee")
    private let apiKeyKey = "claude_api_key"

    // MARK: - Initialization

    init() {
        loadAPIKey()
    }

    // MARK: - API Key Management

    /// Loads API key from keychain
    private func loadAPIKey() {
        if let apiKey = try? keychain.get(apiKeyKey), !apiKey.isEmpty {
            claudeClient = ClaudeAPIClient(apiKey: apiKey)
        }
    }

    /// Saves API key to keychain
    func saveAPIKey(_ apiKey: String) throws {
        try keychain.set(apiKey, key: apiKeyKey)
        claudeClient = ClaudeAPIClient(apiKey: apiKey)
    }

    /// Removes API key from keychain
    func removeAPIKey() throws {
        try keychain.remove(apiKeyKey)
        claudeClient = nil
    }

    /// Checks if API key is configured
    var hasAPIKey: Bool {
        claudeClient != nil
    }

    // MARK: - Summary Generation

    /// Generates a summary for a time range
    /// - Parameters:
    ///   - startTime: Start of the time range
    ///   - endTime: End of the time range
    /// - Returns: Generated summary
    func generateSummary(from startTime: Date, to endTime: Date) async throws -> Summary {
        guard let client = claudeClient else {
            throw ClaudeAPIError.noAPIKey
        }

        // 1. Get screenshots in time range
        let screenshots = try await databaseManager.getScreenshots(from: startTime, to: endTime)

        guard !screenshots.isEmpty else {
            throw SummaryError.noScreenshots
        }

        // 2. Sample screenshots (max 15-20 for API limits)
        let sampledScreenshots = sampleScreenshots(screenshots, maxCount: 15)

        // 3. Load image data (converted to JPEG for Claude API compatibility)
        // Note: Claude API only supports JPEG, PNG, GIF, WebP - NOT HEIC
        var imageData: [Data] = []
        for screenshot in sampledScreenshots {
            if let data = imageCompressor.loadImageDataForAPI(at: screenshot.filepath) {
                imageData.append(data)
            }
        }

        // 4. Get OCR texts for context
        let ocrTexts = try await collectOCRTexts(from: startTime, to: endTime)

        // 5. Build prompt
        let prompt = buildSummaryPrompt(
            screenshotCount: screenshots.count,
            timeRange: formatTimeRange(start: startTime, end: endTime),
            ocrContext: ocrTexts,
            apps: extractUniqueApps(from: screenshots)
        )

        // 6. Call Claude API
        let (summaryText, usage) = try await client.analyzeImages(imageData, prompt: prompt)

        // 7. Create and save summary
        var summary = Summary(
            startTime: startTime,
            endTime: endTime,
            content: summaryText,
            model: "claude-sonnet-4-5-20250929",
            promptTokens: usage?.input_tokens,
            completionTokens: usage?.output_tokens,
            screenshotCount: screenshots.count
        )

        let id = try await databaseManager.insert(summary)
        summary.id = id

        return summary
    }

    /// Generates a quick summary (less images, faster)
    func generateQuickSummary(from startTime: Date, to endTime: Date) async throws -> String {
        guard let client = claudeClient else {
            throw ClaudeAPIError.noAPIKey
        }

        // Get OCR texts only (no images for speed)
        let ocrTexts = try await collectOCRTexts(from: startTime, to: endTime)

        let prompt = """
        Analysiere die folgenden Textausschnitte, die aus Screenshots extrahiert wurden, und erstelle eine kurze Zusammenfassung (max. 5 Saetze).

        Zeitraum: \(formatTimeRange(start: startTime, end: endTime))

        Extrahierte Texte:
        \(ocrTexts.prefix(4000))

        Zusammenfassung:
        """

        let (text, _) = try await client.analyzeText(prompt: prompt)
        return text
    }

    // MARK: - Helpers

    private func sampleScreenshots(_ screenshots: [Screenshot], maxCount: Int) -> [Screenshot] {
        guard screenshots.count > maxCount else { return screenshots }

        // Sample evenly across the time range
        let step = screenshots.count / maxCount
        return stride(from: 0, to: screenshots.count, by: step).prefix(maxCount).map { screenshots[$0] }
    }

    private func buildSummaryPrompt(
        screenshotCount: Int,
        timeRange: String,
        ocrContext: String,
        apps: [String]
    ) -> String {
        """
        Du bist ein Assistent, der Bildschirmaktivitaeten analysiert und zusammenfasst.

        Analysiere diese \(screenshotCount) Screenshots aus dem Zeitraum \(timeRange) und erstelle eine strukturierte Zusammenfassung auf Deutsch.

        Verwendete Programme: \(apps.joined(separator: ", "))

        Zusaetzlicher Kontext aus OCR-Texterkennung:
        ---
        \(ocrContext.prefix(3000))
        ---

        Bitte erstelle eine Zusammenfassung mit folgender Struktur:

        ## Hauptaktivitaeten
        Was wurde hauptsaechlich gemacht? (2-3 Saetze)

        ## Verwendete Programme
        - Welche Programme wurden genutzt und wofuer?

        ## Wichtige Inhalte
        - Dokumentnamen, besuchte Websites, bearbeitete Projekte, wichtige Informationen

        ## Zeitlicher Ablauf
        Grobe chronologische Uebersicht der Aktivitaeten

        Sei praezise und uebersichtlich. Fokussiere auf die wichtigsten Aktivitaeten.
        """
    }

    private func collectOCRTexts(from startTime: Date, to endTime: Date) async throws -> String {
        let ocrData = try await databaseManager.getOCRTexts(from: startTime, to: endTime)

        // Combine texts with timestamps
        return ocrData
            .map { $0.text }
            .joined(separator: "\n---\n")
    }

    private func extractUniqueApps(from screenshots: [Screenshot]) -> [String] {
        let apps = screenshots.compactMap { $0.appName }
        return Array(Set(apps)).sorted()
    }

    private func formatTimeRange(start: Date, end: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "de_DE")

        if Calendar.current.isDate(start, inSameDayAs: end) {
            let timeFormatter = DateFormatter()
            timeFormatter.timeStyle = .short
            return "\(formatter.string(from: start)) - \(timeFormatter.string(from: end))"
        }

        return "\(formatter.string(from: start)) - \(formatter.string(from: end))"
    }
}

// MARK: - Errors

enum SummaryError: LocalizedError {
    case noScreenshots
    case generationFailed(String)

    var errorDescription: String? {
        switch self {
        case .noScreenshots:
            return "Keine Screenshots im ausgewaehlten Zeitraum"
        case .generationFailed(let message):
            return "Zusammenfassung fehlgeschlagen: \(message)"
        }
    }
}
