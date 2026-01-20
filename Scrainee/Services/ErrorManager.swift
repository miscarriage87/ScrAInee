// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - DEPENDENCY DOCUMENTATION
// ═══════════════════════════════════════════════════════════════════════════════
//
// FILE: ErrorManager.swift | PURPOSE: Zentrale Fehlerbehandlung & UI-Alerts | LAYER: Services
//
// DEPENDENCIES: SwiftUI (View, Alert), FileLogger.shared (Logging)
// DEPENDENTS: Alle Views via .withErrorHandling() Modifier, Core-Komponenten via handle()
// CHANGE IMPACT: AppError-Aenderungen beeinflussen alle Fehleranzeigen in der App
//
// KENNT ERROR-TYPEN: CaptureError, DatabaseError, ClaudeAPIError, NotionError,
//                    ExportError, CompressionError (siehe init(from:))
//
// LAST UPDATED: 2026-01-20
// ═══════════════════════════════════════════════════════════════════════════════

import SwiftUI
import Combine

/// Centralized error management for Scrainee
@MainActor
final class ErrorManager: ObservableObject {
    static let shared = ErrorManager()

    // MARK: - Published Properties

    /// Currently displayed error (if any)
    @Published var currentError: AppError?

    /// Whether error alert should be shown
    @Published var showErrorAlert = false

    /// History of recent errors
    @Published private(set) var errorHistory: [ErrorLog] = []

    // MARK: - Configuration

    /// Maximum number of errors to keep in history
    private let maxHistorySize = 100

    /// Errors with severity below this will not be shown to user
    var minimumDisplaySeverity: AppError.Severity = .warning

    // MARK: - Initialization

    private init() {}

    // MARK: - Error Handling

    /// Handles an error with context
    func handle(_ error: Error, context: String, showAlert: Bool = true) {
        let appError = AppError(from: error, context: context)
        handleAppError(appError, showAlert: showAlert)
    }

    /// Handles an AppError directly
    func handleAppError(_ error: AppError, showAlert: Bool = true) {
        // Log the error
        FileLogger.shared.log(error: error, context: error.context)

        // Add to history
        let log = ErrorLog(error: error)
        errorHistory.insert(log, at: 0)

        // Trim history if needed
        if errorHistory.count > maxHistorySize {
            errorHistory = Array(errorHistory.prefix(maxHistorySize))
        }

        // Show alert if needed
        if showAlert && error.severity >= minimumDisplaySeverity {
            currentError = error
            showErrorAlert = true
        }
    }

    /// Clears the current error
    func clearCurrentError() {
        currentError = nil
        showErrorAlert = false
    }

    /// Clears error history
    func clearHistory() {
        errorHistory.removeAll()
    }

    /// Gets errors filtered by severity
    func errors(minimumSeverity: AppError.Severity) -> [ErrorLog] {
        errorHistory.filter { $0.error.severity >= minimumSeverity }
    }

    /// Gets errors from the last N minutes
    func recentErrors(minutes: Int) -> [ErrorLog] {
        let cutoff = Date().addingTimeInterval(-Double(minutes * 60))
        return errorHistory.filter { $0.timestamp > cutoff }
    }
}

// MARK: - App Error

struct AppError: Error, Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let severity: Severity
    let context: String
    let underlyingError: Error?
    let timestamp: Date

    enum Severity: Int, Comparable {
        case info = 0
        case warning = 1
        case error = 2
        case critical = 3

        var color: Color {
            switch self {
            case .info: return .blue
            case .warning: return .orange
            case .error: return .red
            case .critical: return .purple
            }
        }

        var icon: String {
            switch self {
            case .info: return "info.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .error: return "xmark.circle.fill"
            case .critical: return "flame.fill"
            }
        }

        static func < (lhs: Severity, rhs: Severity) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    init(title: String, message: String, severity: Severity = .error, context: String = "App", underlyingError: Error? = nil) {
        self.title = title
        self.message = message
        self.severity = severity
        self.context = context
        self.underlyingError = underlyingError
        self.timestamp = Date()
    }

    init(from error: Error, context: String = "App") {
        self.context = context
        self.underlyingError = error
        self.timestamp = Date()

        // Map known error types
        switch error {
        case let captureError as CaptureError:
            self.title = "Aufnahmefehler"
            self.message = captureError.errorDescription ?? "Unbekannter Aufnahmefehler"
            self.severity = .error

        case let dbError as DatabaseError:
            self.title = "Datenbankfehler"
            self.message = dbError.errorDescription ?? "Unbekannter Datenbankfehler"
            self.severity = .error

        case let apiError as ClaudeAPIError:
            self.title = "API Fehler"
            self.message = apiError.errorDescription ?? "Unbekannter API Fehler"
            self.severity = .warning

        case let notionError as NotionError:
            self.title = "Notion Fehler"
            self.message = notionError.errorDescription ?? "Unbekannter Notion Fehler"
            self.severity = .warning

        case let exportError as ExportError:
            self.title = "Export Fehler"
            self.message = exportError.errorDescription ?? "Unbekannter Export Fehler"
            self.severity = .warning

        case let compressionError as CompressionError:
            self.title = "Kompressionsfehler"
            self.message = compressionError.errorDescription ?? "Unbekannter Kompressionsfehler"
            self.severity = .error

        case let localizedError as LocalizedError:
            self.title = "Fehler"
            self.message = localizedError.errorDescription ?? error.localizedDescription
            self.severity = .error

        default:
            self.title = "Fehler"
            self.message = error.localizedDescription
            self.severity = .error
        }
    }
}

// MARK: - Error Log

struct ErrorLog: Identifiable {
    let id = UUID()
    let error: AppError
    let timestamp: Date

    init(error: AppError) {
        self.error = error
        self.timestamp = Date()
    }
}

// MARK: - Error Alert View Modifier

struct ErrorAlertModifier: ViewModifier {
    @ObservedObject var errorManager = ErrorManager.shared

    func body(content: Content) -> some View {
        content
            .alert(
                errorManager.currentError?.title ?? "Fehler",
                isPresented: $errorManager.showErrorAlert,
                presenting: errorManager.currentError
            ) { error in
                Button("OK") {
                    errorManager.clearCurrentError()
                }
            } message: { error in
                Text(error.message)
            }
    }
}

extension View {
    /// Adds global error alert handling
    func withErrorHandling() -> some View {
        modifier(ErrorAlertModifier())
    }
}

// MARK: - Error History View

struct ErrorHistoryView: View {
    @ObservedObject var errorManager = ErrorManager.shared
    @State private var selectedSeverity: AppError.Severity? = nil

    var filteredErrors: [ErrorLog] {
        if let severity = selectedSeverity {
            return errorManager.errors(minimumSeverity: severity)
        }
        return errorManager.errorHistory
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Fehlerprotokoll")
                    .font(.headline)

                Spacer()

                Picker("Filter", selection: $selectedSeverity) {
                    Text("Alle").tag(nil as AppError.Severity?)
                    Text("Info+").tag(AppError.Severity.info as AppError.Severity?)
                    Text("Warnungen+").tag(AppError.Severity.warning as AppError.Severity?)
                    Text("Fehler+").tag(AppError.Severity.error as AppError.Severity?)
                    Text("Kritisch").tag(AppError.Severity.critical as AppError.Severity?)
                }
                .pickerStyle(.segmented)
                .frame(width: 300)

                Button("Loeschen") {
                    errorManager.clearHistory()
                }
                .disabled(errorManager.errorHistory.isEmpty)
            }

            if filteredErrors.isEmpty {
                Text("Keine Fehler")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                List(filteredErrors) { log in
                    ErrorLogRow(log: log)
                }
            }
        }
        .padding()
    }
}

struct ErrorLogRow: View {
    let log: ErrorLog

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: log.error.severity.icon)
                .foregroundColor(log.error.severity.color)
                .font(.title3)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(log.error.title)
                        .fontWeight(.medium)

                    Spacer()

                    Text(log.timestamp, style: .time)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Text(log.error.message)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text("Context: \(log.error.context)")
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.7))
            }
        }
        .padding(.vertical, 4)
    }
}
