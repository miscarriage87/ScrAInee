// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - DEPENDENCY DOCUMENTATION
// ═══════════════════════════════════════════════════════════════════════════════
//
// FILE: KeychainService.swift | PURPOSE: Sichere Credential-Speicherung | LAYER: Services
//
// DEPENDENCIES: KeychainAccess (Third-Party)
// DEPENDENTS: QuickAskView (claudeAPIKey), ClaudeAPIClient (indirekt), NotionClient (indirekt)
// CHANGE IMPACT: Schluessel-Aenderungen erfordern Migration bestehender Keychain-Eintraege
//
// KEYS: claudeAPIKey, notionAPIKey, notionDatabaseId (siehe Key enum)
//
// LAST UPDATED: 2026-01-20
// ═══════════════════════════════════════════════════════════════════════════════

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
        do {
            return try keychain.get(key.rawValue)
        } catch {
            FileLogger.shared.error("Keychain get failed for '\(key.rawValue)': \(error.localizedDescription)", context: "KeychainService")
            return nil
        }
    }

    func set(_ value: String, for key: Key) throws {
        try keychain.set(value, key: key.rawValue)
    }

    func remove(_ key: Key) throws {
        try keychain.remove(key.rawValue)
    }

    func exists(_ key: Key) -> Bool {
        do {
            return try keychain.get(key.rawValue) != nil
        } catch {
            FileLogger.shared.warning("Keychain exists check failed for '\(key.rawValue)': \(error.localizedDescription)", context: "KeychainService")
            return false
        }
    }

    // MARK: - Convenience Methods

    var claudeAPIKey: String? {
        get { get(.claudeAPIKey) }
        set {
            do {
                if let value = newValue {
                    try set(value, for: .claudeAPIKey)
                } else {
                    try remove(.claudeAPIKey)
                }
            } catch {
                FileLogger.shared.error("Failed to update claudeAPIKey: \(error.localizedDescription)", context: "KeychainService")
            }
        }
    }

    var notionAPIKey: String? {
        get { get(.notionAPIKey) }
        set {
            do {
                if let value = newValue {
                    try set(value, for: .notionAPIKey)
                } else {
                    try remove(.notionAPIKey)
                }
            } catch {
                FileLogger.shared.error("Failed to update notionAPIKey: \(error.localizedDescription)", context: "KeychainService")
            }
        }
    }

    var notionDatabaseId: String? {
        get { get(.notionDatabaseId) }
        set {
            do {
                if let value = newValue {
                    try set(value, for: .notionDatabaseId)
                } else {
                    try remove(.notionDatabaseId)
                }
            } catch {
                FileLogger.shared.error("Failed to update notionDatabaseId: \(error.localizedDescription)", context: "KeychainService")
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
