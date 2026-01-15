import Foundation
import KeychainAccess

/// Client for interacting with the Notion API
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
