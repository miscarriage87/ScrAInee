// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - DEPENDENCY DOCUMENTATION
// ═══════════════════════════════════════════════════════════════════════════════
//
// FILE: Screenshot.swift | PURPOSE: GRDB Model für Screenshot-Metadaten | LAYER: Core/Database
//
// DEPENDENCIES: GRDB.swift, StorageManager (für fileURL)
// USED BY: DatabaseManager, ScreenCaptureManager, GalleryViewModel, TimelineViewModel, SearchViewModel
// CHANGE IMPACT: Schema-Änderungen erfordern DB-Migration in DatabaseManager.migrate()
//
// LAST UPDATED: 2026-01-20
// ═══════════════════════════════════════════════════════════════════════════════

import Foundation
import GRDB

/// Represents a captured screenshot stored in the database
struct Screenshot: Codable, Identifiable {
    var id: Int64?
    var filepath: String
    var timestamp: Date
    var appBundleId: String?
    var appName: String?
    var windowTitle: String?
    var displayId: Int?
    var width: Int
    var height: Int
    var fileSize: Int
    var isDuplicate: Bool
    var hash: String?
    var createdAt: Date?

    // MARK: - Computed Properties

    /// Full URL to the screenshot file
    var fileURL: URL {
        StorageManager.shared.screenshotsDirectory.appendingPathComponent(filepath)
    }

    /// Whether the file exists on disk
    var fileExists: Bool {
        FileManager.default.fileExists(atPath: fileURL.path)
    }
}

// MARK: - GRDB Record Conformance

extension Screenshot: FetchableRecord, PersistableRecord {
    static var databaseTableName: String { "screenshots" }

    // Column definitions
    enum Columns {
        static let id = Column(CodingKeys.id)
        static let filepath = Column(CodingKeys.filepath)
        static let timestamp = Column(CodingKeys.timestamp)
        static let appBundleId = Column(CodingKeys.appBundleId)
        static let appName = Column(CodingKeys.appName)
        static let windowTitle = Column(CodingKeys.windowTitle)
        static let displayId = Column(CodingKeys.displayId)
        static let width = Column(CodingKeys.width)
        static let height = Column(CodingKeys.height)
        static let fileSize = Column(CodingKeys.fileSize)
        static let isDuplicate = Column(CodingKeys.isDuplicate)
        static let hash = Column(CodingKeys.hash)
        static let createdAt = Column(CodingKeys.createdAt)
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

// MARK: - Table Creation

extension Screenshot {
    static func createTable(in db: Database) throws {
        try db.create(table: databaseTableName, ifNotExists: true) { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("filepath", .text).notNull().unique()
            t.column("timestamp", .datetime).notNull()
            t.column("appBundleId", .text)
            t.column("appName", .text)
            t.column("windowTitle", .text)
            t.column("displayId", .integer)
            t.column("width", .integer).notNull()
            t.column("height", .integer).notNull()
            t.column("fileSize", .integer).notNull()
            t.column("isDuplicate", .boolean).notNull().defaults(to: false)
            t.column("hash", .text)
            t.column("createdAt", .datetime).defaults(sql: "CURRENT_TIMESTAMP")
        }

        // Create indexes
        try db.create(index: "idx_screenshots_timestamp", on: databaseTableName, columns: ["timestamp"], ifNotExists: true)
        try db.create(index: "idx_screenshots_app", on: databaseTableName, columns: ["appBundleId"], ifNotExists: true)
        try db.create(index: "idx_screenshots_hash", on: databaseTableName, columns: ["hash"], ifNotExists: true)
    }
}
