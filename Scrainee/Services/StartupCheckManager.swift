import Foundation
import KeychainAccess

/// Manages startup health checks for all critical services
@MainActor
final class StartupCheckManager: ObservableObject {
    static let shared = StartupCheckManager()

    // MARK: - Published Properties

    @Published var checkResults: [ServiceCheck] = []
    @Published var isChecking = false
    @Published var hasCompletedInitialCheck = false

    // MARK: - Types

    struct ServiceCheck: Identifiable {
        let id = UUID()
        let service: ServiceType
        var status: CheckStatus
        var message: String

        init(service: ServiceType, status: CheckStatus = .pending, message: String = "") {
            self.service = service
            self.status = status
            self.message = message
        }
    }

    enum ServiceType: String, CaseIterable {
        case database = "Datenbank"
        case claudeAPI = "Claude API"
        case notionAPI = "Notion"
        case whisperModel = "Whisper Modell"
        case screenCapture = "Bildschirmaufnahme"
        case accessibility = "Bedienungshilfen"

        var isRequired: Bool {
            switch self {
            case .database, .screenCapture:
                return true
            case .claudeAPI, .notionAPI, .whisperModel, .accessibility:
                return false
            }
        }
    }

    enum CheckStatus {
        case pending
        case checking
        case success
        case warning
        case error
        case notConfigured

        var isOK: Bool {
            switch self {
            case .success, .warning, .notConfigured:
                return true
            case .pending, .checking, .error:
                return false
            }
        }
    }

    // MARK: - Initialization

    private init() {
        // Initialize with pending status for all services
        checkResults = ServiceType.allCases.map { ServiceCheck(service: $0) }
    }

    // MARK: - Public Methods

    /// Runs all health checks
    func runAllChecks() async {
        guard !isChecking else { return }

        isChecking = true
        print("StartupCheckManager: Running all health checks...")

        // Run checks in parallel where possible
        await withTaskGroup(of: ServiceCheck.self) { group in
            group.addTask { await self.checkDatabase() }
            group.addTask { await self.checkScreenCapture() }
            group.addTask { await self.checkAccessibility() }
            group.addTask { await self.checkClaudeAPI() }
            group.addTask { await self.checkNotionAPI() }
            group.addTask { await self.checkWhisperModel() }

            for await result in group {
                updateCheck(result)
            }
        }

        isChecking = false
        hasCompletedInitialCheck = true

        printSummary()
    }

    /// Gets the status for a specific service
    func status(for service: ServiceType) -> CheckStatus {
        checkResults.first { $0.service == service }?.status ?? .pending
    }

    /// Returns true if all required services are OK
    var allRequiredServicesOK: Bool {
        checkResults
            .filter { $0.service.isRequired }
            .allSatisfy { $0.status.isOK }
    }

    // MARK: - Individual Checks

    private func checkDatabase() async -> ServiceCheck {
        updateCheckStatus(.database, .checking)

        do {
            // DatabaseManager should already be initialized
            let stats = try await DatabaseManager.shared.getStats()
            return ServiceCheck(
                service: .database,
                status: .success,
                message: "\(stats.screenshotCount) Screenshots"
            )
        } catch {
            return ServiceCheck(
                service: .database,
                status: .error,
                message: "Fehler: \(error.localizedDescription)"
            )
        }
    }

    private func checkScreenCapture() async -> ServiceCheck {
        updateCheckStatus(.screenCapture, .checking)

        let hasPermission = await PermissionManager.shared.checkScreenCapturePermission()
        if hasPermission {
            return ServiceCheck(service: .screenCapture, status: .success, message: "Berechtigung erteilt")
        } else {
            return ServiceCheck(service: .screenCapture, status: .error, message: "Keine Berechtigung")
        }
    }

    private func checkAccessibility() async -> ServiceCheck {
        updateCheckStatus(.accessibility, .checking)

        let hasPermission = PermissionManager.shared.checkAccessibilityPermission()
        if hasPermission {
            return ServiceCheck(service: .accessibility, status: .success, message: "Berechtigung erteilt")
        } else {
            return ServiceCheck(service: .accessibility, status: .warning, message: "Keine Berechtigung (optional)")
        }
    }

    private func checkClaudeAPI() async -> ServiceCheck {
        updateCheckStatus(.claudeAPI, .checking)

        let keychain = Keychain(service: "com.cpohl.scrainee")
        guard let apiKey = try? keychain.get("claude_api_key"), !apiKey.isEmpty else {
            return ServiceCheck(service: .claudeAPI, status: .notConfigured, message: "Nicht konfiguriert")
        }

        let client = ClaudeAPIClient(apiKey: apiKey)
        do {
            try await client.testConnection()
            return ServiceCheck(service: .claudeAPI, status: .success, message: "Verbunden")
        } catch let error as ClaudeAPIError {
            switch error {
            case .invalidAPIKey:
                return ServiceCheck(service: .claudeAPI, status: .error, message: "Ungültiger API-Key")
            case .rateLimited:
                return ServiceCheck(service: .claudeAPI, status: .warning, message: "Rate-Limit erreicht")
            case .noAPIKey:
                return ServiceCheck(service: .claudeAPI, status: .notConfigured, message: "Nicht konfiguriert")
            default:
                return ServiceCheck(service: .claudeAPI, status: .error, message: error.localizedDescription)
            }
        } catch {
            return ServiceCheck(service: .claudeAPI, status: .error, message: "Verbindungsfehler")
        }
    }

    private func checkNotionAPI() async -> ServiceCheck {
        updateCheckStatus(.notionAPI, .checking)

        let client = NotionClient()
        guard client.isConfigured else {
            return ServiceCheck(service: .notionAPI, status: .notConfigured, message: "Nicht konfiguriert")
        }

        do {
            let connected = try await client.testConnection()
            if connected {
                return ServiceCheck(service: .notionAPI, status: .success, message: "Verbunden")
            } else {
                return ServiceCheck(service: .notionAPI, status: .error, message: "Verbindung fehlgeschlagen")
            }
        } catch {
            return ServiceCheck(service: .notionAPI, status: .error, message: "Verbindungsfehler")
        }
    }

    private func checkWhisperModel() async -> ServiceCheck {
        updateCheckStatus(.whisperModel, .checking)

        let whisperService = WhisperTranscriptionService.shared

        if whisperService.isModelLoaded {
            return ServiceCheck(service: .whisperModel, status: .success, message: "Geladen")
        } else if whisperService.isModelDownloaded {
            return ServiceCheck(service: .whisperModel, status: .warning, message: "Heruntergeladen, nicht geladen")
        } else {
            return ServiceCheck(service: .whisperModel, status: .notConfigured, message: "Nicht heruntergeladen")
        }
    }

    // MARK: - Helper Methods

    private func updateCheckStatus(_ service: ServiceType, _ status: CheckStatus) {
        if let index = checkResults.firstIndex(where: { $0.service == service }) {
            checkResults[index].status = status
        }
    }

    private func updateCheck(_ check: ServiceCheck) {
        if let index = checkResults.firstIndex(where: { $0.service == check.service }) {
            checkResults[index] = check
        }
    }

    private func printSummary() {
        print("StartupCheckManager: Health check completed")
        for check in checkResults {
            let statusIcon: String
            switch check.status {
            case .success: statusIcon = "✅"
            case .warning: statusIcon = "⚠️"
            case .error: statusIcon = "❌"
            case .notConfigured: statusIcon = "⚪"
            case .pending, .checking: statusIcon = "🔄"
            }
            print("  \(statusIcon) \(check.service.rawValue): \(check.message)")
        }
    }
}
