import Foundation
import KeychainAccess

/// Centralized keychain access for the app
@MainActor
final class KeychainService: Sendable {
    static let shared = KeychainService()

    private let keychain = Keychain(service: "com.cpohl.scrainee")
        .accessibility(.afterFirstUnlock)

    private init() {}

    // MARK: - Keys

    enum Key: String {
        case claudeAPIKey = "claude_api_key"
        case notionAPIKey = "notion_api_key"
        case notionDatabaseId = "notion_database_id"
    }

    // MARK: - Generic Access

    func get(_ key: Key) -> String? {
        try? keychain.get(key.rawValue)
    }

    func set(_ value: String, for key: Key) throws {
        try keychain.set(value, key: key.rawValue)
    }

    func remove(_ key: Key) throws {
        try keychain.remove(key.rawValue)
    }

    func exists(_ key: Key) -> Bool {
        (try? keychain.get(key.rawValue)) != nil
    }

    // MARK: - Convenience Methods

    var claudeAPIKey: String? {
        get { get(.claudeAPIKey) }
        set {
            if let value = newValue {
                try? set(value, for: .claudeAPIKey)
            } else {
                try? remove(.claudeAPIKey)
            }
        }
    }

    var notionAPIKey: String? {
        get { get(.notionAPIKey) }
        set {
            if let value = newValue {
                try? set(value, for: .notionAPIKey)
            } else {
                try? remove(.notionAPIKey)
            }
        }
    }

    var notionDatabaseId: String? {
        get { get(.notionDatabaseId) }
        set {
            if let value = newValue {
                try? set(value, for: .notionDatabaseId)
            } else {
                try? remove(.notionDatabaseId)
            }
        }
    }

    var hasClaudeAPIKey: Bool {
        exists(.claudeAPIKey)
    }

    var hasNotionCredentials: Bool {
        exists(.notionAPIKey) && exists(.notionDatabaseId)
    }

    // MARK: - Clear All

    func clearAll() throws {
        try remove(.claudeAPIKey)
        try remove(.notionAPIKey)
        try remove(.notionDatabaseId)
    }
}
