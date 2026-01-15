import Foundation
import os.log

/// Centralized logging for Scrainee
enum Logger {
    private static let subsystem = "com.cpohl.scrainee"

    // MARK: - Log Categories

    static let capture = os.Logger(subsystem: subsystem, category: "capture")
    static let database = os.Logger(subsystem: subsystem, category: "database")
    static let ocr = os.Logger(subsystem: subsystem, category: "ocr")
    static let ai = os.Logger(subsystem: subsystem, category: "ai")
    static let meeting = os.Logger(subsystem: subsystem, category: "meeting")
    static let notion = os.Logger(subsystem: subsystem, category: "notion")
    static let storage = os.Logger(subsystem: subsystem, category: "storage")
    static let general = os.Logger(subsystem: subsystem, category: "general")

    // MARK: - Convenience Methods

    static func debug(_ message: String, category: os.Logger = general) {
        category.debug("\(message, privacy: .public)")
    }

    static func info(_ message: String, category: os.Logger = general) {
        category.info("\(message, privacy: .public)")
    }

    static func warning(_ message: String, category: os.Logger = general) {
        category.warning("\(message, privacy: .public)")
    }

    static func error(_ message: String, category: os.Logger = general) {
        category.error("\(message, privacy: .public)")
    }

    static func error(_ error: Error, context: String = "", category: os.Logger = general) {
        let message = context.isEmpty ? error.localizedDescription : "\(context): \(error.localizedDescription)"
        category.error("\(message, privacy: .public)")
    }
}
