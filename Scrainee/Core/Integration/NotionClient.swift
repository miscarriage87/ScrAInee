import Foundation
import KeychainAccess

/// Client for interacting with the Notion API
@MainActor
final class NotionClient {
    private let baseURL = URL(string: "https://api.notion.com/v1")!
    private let notionVersion = "2022-06-28"

    private var apiKey: String?
    private var databaseId: String?

    private let keychain = Keychain(service: "com.cpohl.scrainee")

    // MARK: - Initialization

    init() {
        loadCredentials()
    }

    // MARK: - Credential Management

    private func loadCredentials() {
        apiKey = try? keychain.get("notion_api_key")
        databaseId = try? keychain.get("notion_database_id")
    }

    func saveCredentials(apiKey: String, databaseId: String) throws {
        try keychain.set(apiKey, key: "notion_api_key")
        try keychain.set(databaseId, key: "notion_database_id")
        self.apiKey = apiKey
        self.databaseId = databaseId
    }

    var isConfigured: Bool {
        guard let key = apiKey, let dbId = databaseId else { return false }
        return !key.isEmpty && !dbId.isEmpty
    }

    // MARK: - API Methods

    /// Creates a new page for a meeting
    func createMeetingPage(
        meeting: MeetingSession,
        summary: String,
        screenshotCount: Int
    ) async throws -> NotionPage {
        guard let apiKey = apiKey, let databaseId = databaseId else {
            throw NotionError.notConfigured
        }

        let url = baseURL.appendingPathComponent("pages")

        let requestBody = buildMeetingPageRequest(
            databaseId: databaseId,
            meeting: meeting,
            summary: summary,
            screenshotCount: screenshotCount
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(notionVersion, forHTTPHeaderField: "Notion-Version")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NotionError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            if let errorBody = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let message = errorBody["message"] as? String {
                throw NotionError.apiError(message)
            }
            throw NotionError.httpError(httpResponse.statusCode)
        }

        let pageResponse = try JSONDecoder().decode(NotionPageResponse.self, from: data)

        return NotionPage(
            id: pageResponse.id,
            url: pageResponse.url
        )
    }

    /// Updates an existing page
    func updatePage(pageId: String, properties: [String: Any]) async throws {
        guard let apiKey = apiKey else {
            throw NotionError.notConfigured
        }

        let url = baseURL.appendingPathComponent("pages/\(pageId)")

        let requestBody: [String: Any] = ["properties": properties]

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(notionVersion, forHTTPHeaderField: "Notion-Version")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw NotionError.updateFailed
        }
    }

    /// Appends content to a page
    func appendToPage(pageId: String, blocks: [[String: Any]]) async throws {
        guard let apiKey = apiKey else {
            throw NotionError.notConfigured
        }

        let url = baseURL.appendingPathComponent("blocks/\(pageId)/children")

        let requestBody: [String: Any] = ["children": blocks]

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(notionVersion, forHTTPHeaderField: "Notion-Version")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw NotionError.updateFailed
        }
    }

    /// Tests the connection to Notion
    func testConnection() async throws -> Bool {
        guard let apiKey = apiKey else {
            throw NotionError.notConfigured
        }

        let url = baseURL.appendingPathComponent("users/me")

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(notionVersion, forHTTPHeaderField: "Notion-Version")

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            return false
        }

        return httpResponse.statusCode == 200
    }

    // MARK: - Request Building

    private func buildMeetingPageRequest(
        databaseId: String,
        meeting: MeetingSession,
        summary: String,
        screenshotCount: Int
    ) -> [String: Any] {
        let dateFormatter = ISO8601DateFormatter()
        let displayFormatter = DateFormatter()
        displayFormatter.dateFormat = "dd.MM.yyyy HH:mm"

        let title = "\(meeting.appName) Meeting - \(displayFormatter.string(from: meeting.startTime))"

        return [
            "parent": ["database_id": databaseId],
            "properties": [
                "Name": [
                    "title": [
                        ["text": ["content": title]]
                    ]
                ],
                "Date": [
                    "date": [
                        "start": dateFormatter.string(from: meeting.startTime)
                    ]
                ],
                "App": [
                    "select": ["name": meeting.appName]
                ],
                "Duration": [
                    "number": meeting.durationMinutes
                ]
            ],
            "children": buildPageContent(summary: summary, screenshotCount: screenshotCount)
        ]
    }

    private func buildPageContent(summary: String, screenshotCount: Int) -> [[String: Any]] {
        var blocks: [[String: Any]] = []

        // Heading
        blocks.append([
            "object": "block",
            "type": "heading_2",
            "heading_2": [
                "rich_text": [["text": ["content": "Zusammenfassung"]]]
            ]
        ])

        // Summary paragraphs
        let paragraphs = summary.components(separatedBy: "\n\n")
        for paragraph in paragraphs where !paragraph.trimmingCharacters(in: .whitespaces).isEmpty {
            blocks.append([
                "object": "block",
                "type": "paragraph",
                "paragraph": [
                    "rich_text": [["text": ["content": String(paragraph.prefix(2000))]]]
                ]
            ])
        }

        // Divider
        blocks.append([
            "object": "block",
            "type": "divider",
            "divider": [:]
        ])

        // Screenshots info
        blocks.append([
            "object": "block",
            "type": "callout",
            "callout": [
                "icon": ["emoji": "📸"],
                "rich_text": [["text": ["content": "\(screenshotCount) Screenshots aufgenommen"]]]
            ]
        ])

        return blocks
    }

    // MARK: - Summary Export

    /// Exports a standalone summary (not tied to a meeting) to Notion
    func exportSummary(_ summary: Summary, title: String) async throws -> NotionPage {
        guard let apiKey = apiKey, let databaseId = databaseId else {
            throw NotionError.notConfigured
        }

        let url = baseURL.appendingPathComponent("pages")

        let requestBody = buildSummaryPageRequest(
            databaseId: databaseId,
            summary: summary,
            title: title
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(notionVersion, forHTTPHeaderField: "Notion-Version")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NotionError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            if let errorBody = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let message = errorBody["message"] as? String {
                throw NotionError.apiError(message)
            }
            throw NotionError.httpError(httpResponse.statusCode)
        }

        let pageResponse = try JSONDecoder().decode(NotionPageResponse.self, from: data)

        return NotionPage(
            id: pageResponse.id,
            url: pageResponse.url
        )
    }

    private func buildSummaryPageRequest(
        databaseId: String,
        summary: Summary,
        title: String
    ) -> [String: Any] {
        let dateFormatter = ISO8601DateFormatter()

        return [
            "parent": ["database_id": databaseId],
            "properties": [
                "Name": [
                    "title": [
                        ["text": ["content": title]]
                    ]
                ],
                "Date": [
                    "date": [
                        "start": dateFormatter.string(from: summary.startTime),
                        "end": dateFormatter.string(from: summary.endTime)
                    ]
                ]
            ],
            "children": buildSummaryContent(summary: summary)
        ]
    }

    private func buildSummaryContent(summary: Summary) -> [[String: Any]] {
        var blocks: [[String: Any]] = []

        // Heading
        blocks.append([
            "object": "block",
            "type": "heading_2",
            "heading_2": [
                "rich_text": [["text": ["content": "Zusammenfassung"]]]
            ]
        ])

        // Time range info
        blocks.append([
            "object": "block",
            "type": "callout",
            "callout": [
                "icon": ["emoji": "📅"],
                "rich_text": [["text": ["content": "Zeitraum: \(summary.formattedTimeRange)"]]]
            ]
        ])

        // Summary paragraphs
        let paragraphs = summary.content.components(separatedBy: "\n\n")
        for paragraph in paragraphs where !paragraph.trimmingCharacters(in: .whitespaces).isEmpty {
            blocks.append([
                "object": "block",
                "type": "paragraph",
                "paragraph": [
                    "rich_text": [["text": ["content": String(paragraph.prefix(2000))]]]
                ]
            ])
        }

        // Divider
        blocks.append([
            "object": "block",
            "type": "divider",
            "divider": [:]
        ])

        // Stats
        var statsText = ""
        if let count = summary.screenshotCount, count > 0 {
            statsText += "📸 \(count) Screenshots analysiert"
        }
        if summary.totalTokens > 0 {
            if !statsText.isEmpty { statsText += " • " }
            statsText += "🔢 \(summary.totalTokens) Tokens verwendet"
        }

        if !statsText.isEmpty {
            blocks.append([
                "object": "block",
                "type": "callout",
                "callout": [
                    "icon": ["emoji": "ℹ️"],
                    "rich_text": [["text": ["content": statsText]]]
                ]
            ])
        }

        // Footer
        blocks.append([
            "object": "block",
            "type": "callout",
            "callout": [
                "icon": ["emoji": "🤖"],
                "rich_text": [["text": ["content": "Generiert mit ScrAInee"]]]
            ]
        ])

        return blocks
    }

    // MARK: - Meeting Minutes Export

    /// Creates a page with full meeting minutes including transcript
    func exportMeetingWithMinutes(
        meeting: Meeting,
        minutes: MeetingMinutes,
        segments: [TranscriptSegment],
        actionItems: [ActionItem]
    ) async throws -> NotionPage {
        guard let apiKey = apiKey, let databaseId = databaseId else {
            throw NotionError.notConfigured
        }

        let url = baseURL.appendingPathComponent("pages")

        let displayFormatter = DateFormatter()
        displayFormatter.dateFormat = "dd.MM.yyyy HH:mm"

        let title = "\(meeting.appName) Meeting - \(displayFormatter.string(from: meeting.startTime))"

        let requestBody: [String: Any] = [
            "parent": ["database_id": databaseId],
            "properties": buildMeetingMinutesProperties(meeting: meeting, title: title),
            "children": buildMeetingMinutesContent(
                minutes: minutes,
                segments: segments,
                actionItems: actionItems,
                meeting: meeting
            )
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(notionVersion, forHTTPHeaderField: "Notion-Version")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NotionError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            if let errorBody = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let message = errorBody["message"] as? String {
                throw NotionError.apiError(message)
            }
            throw NotionError.httpError(httpResponse.statusCode)
        }

        let pageResponse = try JSONDecoder().decode(NotionPageResponse.self, from: data)

        return NotionPage(
            id: pageResponse.id,
            url: pageResponse.url
        )
    }

    private func buildMeetingMinutesProperties(meeting: Meeting, title: String) -> [String: Any] {
        let dateFormatter = ISO8601DateFormatter()

        var properties: [String: Any] = [
            "Name": [
                "title": [
                    ["text": ["content": title]]
                ]
            ],
            "Date": [
                "date": [
                    "start": dateFormatter.string(from: meeting.startTime)
                ]
            ],
            "App": [
                "select": ["name": meeting.appName]
            ]
        ]

        if let duration = meeting.durationSeconds {
            properties["Duration"] = ["number": duration / 60]
        }

        return properties
    }

    private func buildMeetingMinutesContent(
        minutes: MeetingMinutes,
        segments: [TranscriptSegment],
        actionItems: [ActionItem],
        meeting: Meeting
    ) -> [[String: Any]] {
        var blocks: [[String: Any]] = []

        // Summary section
        blocks.append(heading2("Zusammenfassung"))

        if let summary = minutes.summary {
            blocks.append(paragraph(summary))
        }

        // Key Points section
        let keyPoints = minutes.keyPointsList
        if !keyPoints.isEmpty {
            blocks.append(heading2("Kernpunkte"))
            for point in keyPoints {
                blocks.append(bulletItem(point))
            }
        }

        // Decisions section
        let decisions = minutes.decisionsList
        if !decisions.isEmpty {
            blocks.append(heading2("Entscheidungen"))
            for decision in decisions {
                blocks.append(bulletItem("✅ \(decision)"))
            }
        }

        // Action Items section
        if !actionItems.isEmpty {
            blocks.append(heading2("Action Items"))
            for item in actionItems {
                var text = item.title
                if let assignee = item.assignee {
                    text += " → @\(assignee)"
                }
                if let dueDate = item.formattedDueDate {
                    text += " (bis \(dueDate))"
                }
                blocks.append(todoItem(text, checked: item.status == .completed))
            }
        }

        // Divider before transcript
        blocks.append(divider())

        // Transcript section (collapsible toggle)
        if !segments.isEmpty {
            blocks.append(heading2("Transkript"))

            // Info callout
            let duration = segments.last?.endTime ?? 0
            let minutes = Int(duration) / 60
            let seconds = Int(duration) % 60
            blocks.append(callout("📝", "Transkript-Länge: \(minutes):\(String(format: "%02d", seconds)) Minuten, \(segments.count) Segmente"))

            // Transcript content (limited to avoid API limits)
            let maxSegments = min(segments.count, 50)  // Notion has block limits
            for segment in segments.prefix(maxSegments) {
                let timestamp = formatTimestamp(segment.startTime)
                blocks.append(paragraph("[\(timestamp)] \(segment.text)"))
            }

            if segments.count > maxSegments {
                blocks.append(callout("ℹ️", "Weitere \(segments.count - maxSegments) Segmente wurden ausgelassen."))
            }
        }

        // Footer
        blocks.append(divider())
        blocks.append(callout("🤖", "Generiert mit ScrAInee"))

        return blocks
    }

    // MARK: - Block Helpers

    private func heading2(_ text: String) -> [String: Any] {
        [
            "object": "block",
            "type": "heading_2",
            "heading_2": [
                "rich_text": [["text": ["content": text]]]
            ]
        ]
    }

    private func paragraph(_ text: String) -> [String: Any] {
        [
            "object": "block",
            "type": "paragraph",
            "paragraph": [
                "rich_text": [["text": ["content": String(text.prefix(2000))]]]
            ]
        ]
    }

    private func bulletItem(_ text: String) -> [String: Any] {
        [
            "object": "block",
            "type": "bulleted_list_item",
            "bulleted_list_item": [
                "rich_text": [["text": ["content": String(text.prefix(2000))]]]
            ]
        ]
    }

    private func todoItem(_ text: String, checked: Bool) -> [String: Any] {
        [
            "object": "block",
            "type": "to_do",
            "to_do": [
                "rich_text": [["text": ["content": String(text.prefix(2000))]]],
                "checked": checked
            ]
        ]
    }

    private func callout(_ emoji: String, _ text: String) -> [String: Any] {
        [
            "object": "block",
            "type": "callout",
            "callout": [
                "icon": ["emoji": emoji],
                "rich_text": [["text": ["content": String(text.prefix(2000))]]]
            ]
        ]
    }

    private func divider() -> [String: Any] {
        [
            "object": "block",
            "type": "divider",
            "divider": [:]
        ]
    }

    private func formatTimestamp(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}

// MARK: - Response Types

struct NotionPageResponse: Codable {
    let id: String
    let url: String
}

struct NotionPage {
    let id: String
    let url: String
}

// MARK: - Errors

enum NotionError: LocalizedError {
    case notConfigured
    case invalidResponse
    case httpError(Int)
    case apiError(String)
    case updateFailed

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Notion nicht konfiguriert"
        case .invalidResponse:
            return "Ungueltige Notion-Antwort"
        case .httpError(let code):
            return "Notion HTTP Fehler: \(code)"
        case .apiError(let message):
            return "Notion API Fehler: \(message)"
        case .updateFailed:
            return "Notion Update fehlgeschlagen"
        }
    }
}
