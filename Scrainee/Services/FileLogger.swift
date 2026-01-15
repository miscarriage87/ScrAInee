import Foundation
import os.log

/// File-based logging system for Scrainee with log file persistence
/// Note: This class uses internal synchronization via DispatchQueue
final class FileLogger: @unchecked Sendable {
    static let shared = FileLogger()

    // MARK: - Log Levels

    enum LogLevel: Int, Comparable {
        case debug = 0
        case info = 1
        case warning = 2
        case error = 3
        case critical = 4

        var prefix: String {
            switch self {
            case .debug: return "DEBUG"
            case .info: return "INFO"
            case .warning: return "WARNING"
            case .error: return "ERROR"
            case .critical: return "CRITICAL"
            }
        }

        var emoji: String {
            switch self {
            case .debug: return "🔍"
            case .info: return "ℹ️"
            case .warning: return "⚠️"
            case .error: return "❌"
            case .critical: return "🔥"
            }
        }

        static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    // MARK: - Properties

    private let fileHandle: FileHandle?
    private let logFileURL: URL
    private let dateFormatter: DateFormatter
    private let queue = DispatchQueue(label: "com.scrainee.logger", qos: .utility)

    /// Minimum log level to record (default: info in release, debug in debug)
    var minimumLogLevel: LogLevel = {
        #if DEBUG
        return .debug
        #else
        return .info
        #endif
    }()

    /// Maximum log file size in bytes (default: 10 MB)
    private let maxLogFileSize: Int64 = 10 * 1024 * 1024

    /// OS Logger for system console
    private let osLogger = os.Logger(subsystem: "com.cpohl.scrainee", category: "app")

    // MARK: - Initialization

    private init() {
        // Setup date formatter
        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")

        // Setup log file
        let logsDirectory = StorageManager.shared.appSupportDirectory.appendingPathComponent("logs")
        try? FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true)

        let dateString = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .none)
            .replacingOccurrences(of: "/", with: "-")
        logFileURL = logsDirectory.appendingPathComponent("scrainee_\(dateString).log")

        // Create file if needed
        if !FileManager.default.fileExists(atPath: logFileURL.path) {
            FileManager.default.createFile(atPath: logFileURL.path, contents: nil)
        }

        // Open file handle
        fileHandle = try? FileHandle(forWritingTo: logFileURL)
        fileHandle?.seekToEndOfFile()

        // Log startup
        info("Scrainee FileLogger initialized", context: "FileLogger")
    }

    deinit {
        try? fileHandle?.close()
    }

    // MARK: - Public Logging Methods

    func debug(_ message: String, context: String = "App", file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .debug, context: context, file: file, function: function, line: line)
    }

    func info(_ message: String, context: String = "App", file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .info, context: context, file: file, function: function, line: line)
    }

    func warning(_ message: String, context: String = "App", file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .warning, context: context, file: file, function: function, line: line)
    }

    func error(_ message: String, context: String = "App", file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .error, context: context, file: file, function: function, line: line)
    }

    func critical(_ message: String, context: String = "App", file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .critical, context: context, file: file, function: function, line: line)
    }

    /// Logs an error with its description
    func log(error: Error, context: String = "App", file: String = #file, function: String = #function, line: Int = #line) {
        let message = "\(error.localizedDescription)"
        log(message, level: .error, context: context, file: file, function: function, line: line)
    }

    // MARK: - Core Logging

    private func log(_ message: String, level: LogLevel, context: String, file: String, function: String, line: Int) {
        guard level >= minimumLogLevel else { return }

        let timestamp = dateFormatter.string(from: Date())
        let filename = URL(fileURLWithPath: file).lastPathComponent
        let logEntry = "[\(timestamp)] \(level.emoji) [\(level.prefix)] [\(context)] \(message) (\(filename):\(line))\n"

        // Write to file asynchronously
        queue.async { [weak self] in
            self?.writeToFile(logEntry)
        }

        // Also log to system console
        switch level {
        case .debug:
            osLogger.debug("\(message, privacy: .public)")
        case .info:
            osLogger.info("\(message, privacy: .public)")
        case .warning:
            osLogger.warning("\(message, privacy: .public)")
        case .error:
            osLogger.error("\(message, privacy: .public)")
        case .critical:
            osLogger.critical("\(message, privacy: .public)")
        }

        #if DEBUG
        print(logEntry, terminator: "")
        #endif
    }

    private func writeToFile(_ entry: String) {
        guard let data = entry.data(using: .utf8) else { return }

        // Check if we need to rotate the log file
        if let fileSize = try? FileManager.default.attributesOfItem(atPath: logFileURL.path)[.size] as? Int64,
           fileSize > maxLogFileSize {
            rotateLogFile()
        }

        fileHandle?.write(data)
    }

    // MARK: - Log File Management

    private func rotateLogFile() {
        // Close current file
        try? fileHandle?.close()

        // Rename to backup
        let backupURL = logFileURL.deletingPathExtension().appendingPathExtension("backup.log")
        try? FileManager.default.removeItem(at: backupURL)
        try? FileManager.default.moveItem(at: logFileURL, to: backupURL)

        // Create new file
        FileManager.default.createFile(atPath: logFileURL.path, contents: nil)
    }

    /// Exports all log files as a single combined log
    func exportLogs() -> URL? {
        let logsDirectory = StorageManager.shared.appSupportDirectory.appendingPathComponent("logs")

        // Get all log files
        guard let logFiles = try? FileManager.default.contentsOfDirectory(at: logsDirectory, includingPropertiesForKeys: [.creationDateKey]) else {
            return nil
        }

        // Combine all logs
        var combinedLog = "=== Scrainee Logs Export ===\n"
        combinedLog += "Export Date: \(Date())\n"
        combinedLog += "============================\n\n"

        for logFile in logFiles.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            if let content = try? String(contentsOf: logFile, encoding: .utf8) {
                combinedLog += "--- \(logFile.lastPathComponent) ---\n"
                combinedLog += content
                combinedLog += "\n"
            }
        }

        // Save to Downloads
        let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        let exportURL = downloadsURL.appendingPathComponent("scrainee_logs_\(ISO8601DateFormatter().string(from: Date())).txt")

        do {
            try combinedLog.write(to: exportURL, atomically: true, encoding: .utf8)
            return exportURL
        } catch {
            self.error("Failed to export logs: \(error.localizedDescription)", context: "Logger")
            return nil
        }
    }

    /// Clears old log files (older than 7 days)
    func cleanupOldLogs() {
        let logsDirectory = StorageManager.shared.appSupportDirectory.appendingPathComponent("logs")

        guard let logFiles = try? FileManager.default.contentsOfDirectory(at: logsDirectory, includingPropertiesForKeys: [.creationDateKey]) else {
            return
        }

        let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date())!

        for logFile in logFiles {
            if let attributes = try? FileManager.default.attributesOfItem(atPath: logFile.path),
               let creationDate = attributes[.creationDate] as? Date,
               creationDate < sevenDaysAgo {
                try? FileManager.default.removeItem(at: logFile)
                info("Deleted old log file: \(logFile.lastPathComponent)", context: "Logger")
            }
        }
    }

    /// Returns the URL of the logs directory
    var logsDirectoryURL: URL {
        StorageManager.shared.appSupportDirectory.appendingPathComponent("logs")
    }
}

// MARK: - Convenience Extensions

extension Logger {
    /// Logs performance timing
    func logPerformance(_ operation: String, duration: TimeInterval, context: String = "Performance") {
        let durationMs = Int(duration * 1000)
        if durationMs > 1000 {
            Logger.warning("[\(context)] \(operation) took \(durationMs)ms (slow)")
        } else {
            Logger.debug("[\(context)] \(operation) took \(durationMs)ms")
        }
    }

    /// Measures and logs execution time of a block
    func measure<T>(_ operation: String, context: String = "Performance", block: () throws -> T) rethrows -> T {
        let start = CFAbsoluteTimeGetCurrent()
        let result = try block()
        let duration = CFAbsoluteTimeGetCurrent() - start
        logPerformance(operation, duration: duration, context: context)
        return result
    }

    /// Async version of measure
    func measureAsync<T>(_ operation: String, context: String = "Performance", block: () async throws -> T) async rethrows -> T {
        let start = CFAbsoluteTimeGetCurrent()
        let result = try await block()
        let duration = CFAbsoluteTimeGetCurrent() - start
        logPerformance(operation, duration: duration, context: context)
        return result
    }
}
