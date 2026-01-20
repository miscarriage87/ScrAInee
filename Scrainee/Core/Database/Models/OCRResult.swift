// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - DEPENDENCY DOCUMENTATION
// ═══════════════════════════════════════════════════════════════════════════════
//
// FILE: OCRResult.swift | PURPOSE: GRDB Model für OCR-Textergebnisse mit FTS5 | LAYER: Core/Database
//
// DEPENDENCIES: GRDB.swift
// RELATED: Screenshot (Foreign Key: screenshotId), ocrFts (FTS5 Virtual Table)
// USED BY: DatabaseManager, OCRManager, SearchViewModel
// CHANGE IMPACT: Schema-Änderungen erfordern DB-Migration; FTS5-Trigger in createTable()
//
// LAST UPDATED: 2026-01-20
// ═══════════════════════════════════════════════════════════════════════════════

import Foundation
import GRDB

/// Represents OCR text extracted from a screenshot
struct OCRResult: Codable, Identifiable {
    var id: Int64?
    var screenshotId: Int64
    var text: String
    var confidence: Float?
    var language: String?
    var wordCount: Int?
    var processedAt: Date?

    // MARK: - Initialization

    init(
        id: Int64? = nil,
        screenshotId: Int64,
        text: String,
        confidence: Float? = nil,
        language: String? = nil,
        wordCount: Int? = nil,
        processedAt: Date? = nil
    ) {
        self.id = id
        self.screenshotId = screenshotId
        self.text = text
        self.confidence = confidence
        self.language = language
        self.wordCount = wordCount
        self.processedAt = processedAt ?? Date()
    }
}

// MARK: - GRDB Record Conformance

extension OCRResult: FetchableRecord, PersistableRecord {
    static var databaseTableName: String { "ocrResults" }

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let screenshotId = Column(CodingKeys.screenshotId)
        static let text = Column(CodingKeys.text)
        static let confidence = Column(CodingKeys.confidence)
        static let language = Column(CodingKeys.language)
        static let wordCount = Column(CodingKeys.wordCount)
        static let processedAt = Column(CodingKeys.processedAt)
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

// MARK: - Table Creation

extension OCRResult {
    static func createTable(in db: Database) throws {
        try db.create(table: databaseTableName, ifNotExists: true) { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("screenshotId", .integer)
                .notNull()
                .references("screenshots", onDelete: .cascade)
            t.column("text", .text).notNull()
            t.column("confidence", .double)
            t.column("language", .text)
            t.column("wordCount", .integer)
            t.column("processedAt", .datetime).defaults(sql: "CURRENT_TIMESTAMP")
        }

        try db.create(index: "idx_ocr_screenshot", on: databaseTableName, columns: ["screenshotId"], ifNotExists: true)

        // Create FTS5 virtual table for full-text search
        try db.execute(sql: """
            CREATE VIRTUAL TABLE IF NOT EXISTS ocrFts USING fts5(
                text,
                content='ocrResults',
                content_rowid='id',
                tokenize='unicode61'
            )
        """)

        // Create triggers to keep FTS in sync
        try db.execute(sql: """
            CREATE TRIGGER IF NOT EXISTS ocr_ai AFTER INSERT ON ocrResults BEGIN
                INSERT INTO ocrFts(rowid, text) VALUES (new.id, new.text);
            END
        """)

        try db.execute(sql: """
            CREATE TRIGGER IF NOT EXISTS ocr_ad AFTER DELETE ON ocrResults BEGIN
                INSERT INTO ocrFts(ocrFts, rowid, text) VALUES('delete', old.id, old.text);
            END
        """)

        try db.execute(sql: """
            CREATE TRIGGER IF NOT EXISTS ocr_au AFTER UPDATE ON ocrResults BEGIN
                INSERT INTO ocrFts(ocrFts, rowid, text) VALUES('delete', old.id, old.text);
                INSERT INTO ocrFts(rowid, text) VALUES (new.id, new.text);
            END
        """)

        // Migrate existing OCR data to FTS5 (for data inserted before triggers existed)
        try db.execute(sql: """
            INSERT OR IGNORE INTO ocrFts(rowid, text)
            SELECT id, text FROM ocrResults
        """)
    }
}
