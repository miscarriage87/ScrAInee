// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - DEPENDENCY DOCUMENTATION
// ═══════════════════════════════════════════════════════════════════════════════
//
// FILE: SettingsValidator.swift | PURPOSE: Settings-Validierung & Backup/Import | LAYER: Services
//
// DEPENDENCIES: Foundation, AppState.shared (fuer Import/Export)
// DEPENDENTS: SettingsView (Validierung), AppState (Validierung bei Aenderungen)
// CHANGE IMPACT: Validierungs-Grenzwerte muessen mit UI-Constraints synchron sein
//
// ENTHAELT AUCH: SettingsBackup (Codable), SettingsManager, SettingsImportError
//
// LAST UPDATED: 2026-01-20
// ═══════════════════════════════════════════════════════════════════════════════

import Foundation

/// Validates settings values and provides helpful error messages
struct SettingsValidator {
    // MARK: - Validation Result

    enum ValidationResult {
        case valid
        case invalid(String)

        var isValid: Bool {
            if case .valid = self { return true }
            return false
        }

        var errorMessage: String? {
            if case .invalid(let message) = self { return message }
            return nil
        }
    }

    // MARK: - Capture Settings

    static func validateCaptureInterval(_ value: Int) -> ValidationResult {
        guard value >= 1 else {
            return .invalid("Intervall muss mindestens 1 Sekunde sein")
        }
        guard value <= 60 else {
            return .invalid("Intervall darf maximal 60 Sekunden sein")
        }
        return .valid
    }

    static func validateMeetingInterval(_ value: Double) -> ValidationResult {
        guard value >= 0.5 else {
            return .invalid("Meeting-Intervall muss mindestens 0.5 Sekunden sein")
        }
        guard value <= 10 else {
            return .invalid("Meeting-Intervall darf maximal 10 Sekunden sein")
        }
        return .valid
    }

    static func validateIdleInterval(_ value: Double) -> ValidationResult {
        guard value >= 5 else {
            return .invalid("Idle-Intervall muss mindestens 5 Sekunden sein")
        }
        guard value <= 120 else {
            return .invalid("Idle-Intervall darf maximal 120 Sekunden sein")
        }
        return .valid
    }

    // MARK: - Storage Settings

    static func validateRetentionDays(_ value: Int) -> ValidationResult {
        guard value >= 1 else {
            return .invalid("Aufbewahrungsdauer muss mindestens 1 Tag sein")
        }
        guard value <= 365 else {
            return .invalid("Aufbewahrungsdauer darf maximal 365 Tage sein")
        }
        return .valid
    }

    static func validateHEICQuality(_ value: Double) -> ValidationResult {
        guard value >= 0.1 else {
            return .invalid("HEIC-Qualitaet muss mindestens 10% sein")
        }
        guard value <= 1.0 else {
            return .invalid("HEIC-Qualitaet darf maximal 100% sein")
        }
        return .valid
    }

    // MARK: - API Key Validation

    static func validateClaudeAPIKey(_ key: String) -> ValidationResult {
        guard !key.isEmpty else {
            return .invalid("API-Key darf nicht leer sein")
        }
        guard key.hasPrefix("sk-ant-") else {
            return .invalid("Ungueltiges API-Key Format. Der Key sollte mit 'sk-ant-' beginnen.")
        }
        guard key.count > 20 else {
            return .invalid("API-Key ist zu kurz")
        }
        return .valid
    }

    static func validateNotionAPIKey(_ key: String) -> ValidationResult {
        guard !key.isEmpty else {
            return .invalid("Notion API-Key darf nicht leer sein")
        }
        guard key.hasPrefix("secret_") || key.hasPrefix("ntn_") else {
            return .invalid("Ungueltiges Notion API-Key Format")
        }
        return .valid
    }

    static func validateNotionDatabaseId(_ id: String) -> ValidationResult {
        guard !id.isEmpty else {
            return .invalid("Database ID darf nicht leer sein")
        }
        // Notion database IDs are UUIDs (32 hex chars, possibly with dashes)
        let cleanId = id.replacingOccurrences(of: "-", with: "")
        guard cleanId.count == 32 else {
            return .invalid("Ungueltige Database ID Laenge")
        }
        guard cleanId.allSatisfy({ $0.isHexDigit }) else {
            return .invalid("Database ID enthaelt ungueltige Zeichen")
        }
        return .valid
    }

    // MARK: - URL Validation

    static func validateURL(_ urlString: String) -> ValidationResult {
        guard !urlString.isEmpty else {
            return .invalid("URL darf nicht leer sein")
        }
        guard let url = URL(string: urlString) else {
            return .invalid("Ungueltige URL")
        }
        guard url.scheme == "http" || url.scheme == "https" else {
            return .invalid("URL muss mit http:// oder https:// beginnen")
        }
        return .valid
    }
}

// MARK: - Settings Backup

struct SettingsBackup: Codable {
    let exportDate: Date
    let appVersion: String

    // Capture Settings
    let captureInterval: Int
    let meetingInterval: Double?
    let idleInterval: Double?

    // Storage Settings
    let retentionDays: Int
    let heicQuality: Double

    // Feature Toggles
    let ocrEnabled: Bool
    let meetingDetectionEnabled: Bool
    let launchAtLogin: Bool

    // Notion Settings (without secrets)
    let notionEnabled: Bool
    let notionAutoSync: Bool

    // Note: API keys are NOT exported for security reasons
}

// MARK: - Settings Manager Extension

extension SettingsManager {
    /// Exports current settings to a backup
    @MainActor
    func exportSettings() throws -> Data {
        let settings = AppState.shared.settingsState
        let backup = SettingsBackup(
            exportDate: Date(),
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
            captureInterval: settings.captureInterval,
            meetingInterval: nil, // TODO: Add when adaptive settings are in AppState
            idleInterval: nil,
            retentionDays: settings.retentionDays,
            heicQuality: settings.heicQuality,
            ocrEnabled: settings.ocrEnabled,
            meetingDetectionEnabled: settings.meetingDetectionEnabled,
            launchAtLogin: settings.launchAtLogin,
            notionEnabled: settings.notionEnabled,
            notionAutoSync: settings.notionAutoSync
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601

        return try encoder.encode(backup)
    }

    /// Imports settings from a backup
    func importSettings(from data: Data) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let backup = try decoder.decode(SettingsBackup.self, from: data)

        // Validate before applying
        guard SettingsValidator.validateCaptureInterval(backup.captureInterval).isValid else {
            throw SettingsImportError.invalidCaptureInterval
        }
        guard SettingsValidator.validateRetentionDays(backup.retentionDays).isValid else {
            throw SettingsImportError.invalidRetentionDays
        }
        guard SettingsValidator.validateHEICQuality(backup.heicQuality).isValid else {
            throw SettingsImportError.invalidHEICQuality
        }

        // Apply settings
        Task { @MainActor in
            let settings = AppState.shared.settingsState
            settings.captureInterval = backup.captureInterval
            settings.retentionDays = backup.retentionDays
            settings.heicQuality = backup.heicQuality
            settings.ocrEnabled = backup.ocrEnabled
            settings.meetingDetectionEnabled = backup.meetingDetectionEnabled
            settings.launchAtLogin = backup.launchAtLogin
            settings.notionEnabled = backup.notionEnabled
            settings.notionAutoSync = backup.notionAutoSync
        }
    }

    /// Resets all settings to defaults
    func resetToDefaults() {
        Task { @MainActor in
            let settings = AppState.shared.settingsState
            settings.captureInterval = 3
            settings.retentionDays = 30
            settings.heicQuality = 0.6
            settings.ocrEnabled = true
            settings.meetingDetectionEnabled = true
            settings.launchAtLogin = false
            settings.notionEnabled = false
            settings.notionAutoSync = true
        }
    }
}

// MARK: - Settings Import Errors

enum SettingsImportError: LocalizedError {
    case invalidCaptureInterval
    case invalidRetentionDays
    case invalidHEICQuality
    case invalidFormat
    case versionMismatch

    var errorDescription: String? {
        switch self {
        case .invalidCaptureInterval:
            return "Ungueltiges Capture-Intervall in der Backup-Datei"
        case .invalidRetentionDays:
            return "Ungueltige Aufbewahrungsdauer in der Backup-Datei"
        case .invalidHEICQuality:
            return "Ungueltige HEIC-Qualitaet in der Backup-Datei"
        case .invalidFormat:
            return "Ungueltige Backup-Datei Format"
        case .versionMismatch:
            return "Backup-Datei Version nicht kompatibel"
        }
    }
}

// MARK: - Settings Manager Singleton

@MainActor
final class SettingsManager: Sendable {
    static let shared = SettingsManager()
    private init() {}
}
