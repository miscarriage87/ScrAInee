import Foundation
import GRDB

/// Represents a segment of transcribed audio from a meeting
struct TranscriptSegment: Codable, Identifiable, Sendable {
    var id: Int64?
    var meetingId: Int64
    var text: String
    var startTime: TimeInterval      // Offset from meeting start in seconds
    var endTime: TimeInterval
    var confidence: Double?
    var language: String?            // "de", "en"
    var createdAt: Date?

    // MARK: - Computed Properties

    /// Duration of this segment in seconds
    var duration: TimeInterval {
        endTime - startTime
    }

    /// Formatted timestamp (MM:SS)
    var formattedTimestamp: String {
        let minutes = Int(startTime) / 60
        let seconds = Int(startTime) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    /// Formatted time range (MM:SS - MM:SS)
    var formattedTimeRange: String {
        let startMin = Int(startTime) / 60
        let startSec = Int(startTime) % 60
        let endMin = Int(endTime) / 60
        let endSec = Int(endTime) % 60
        return String(format: "%02d:%02d - %02d:%02d", startMin, startSec, endMin, endSec)
    }

    /// Word count
    var wordCount: Int {
        text.split(separator: " ").count
    }
}

// MARK: - GRDB Record Conformance

extension TranscriptSegment: FetchableRecord, PersistableRecord {
    static var databaseTableName: String { "transcriptSegments" }

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let meetingId = Column(CodingKeys.meetingId)
        static let text = Column(CodingKeys.text)
        static let startTime = Column(CodingKeys.startTime)
        static let endTime = Column(CodingKeys.endTime)
        static let confidence = Column(CodingKeys.confidence)
        static let language = Column(CodingKeys.language)
        static let createdAt = Column(CodingKeys.createdAt)
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

// MARK: - Table Creation

extension TranscriptSegment {
    static func createTable(in db: Database) throws {
        try db.create(table: databaseTableName, ifNotExists: true) { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("meetingId", .integer)
                .notNull()
                .references("meetings", onDelete: .cascade)
            t.column("text", .text).notNull()
            t.column("startTime", .double).notNull()
            t.column("endTime", .double).notNull()
            t.column("confidence", .double)
            t.column("language", .text)
            t.column("createdAt", .datetime).defaults(sql: "CURRENT_TIMESTAMP")
        }

        try db.create(index: "idx_segments_meeting", on: databaseTableName, columns: ["meetingId"], ifNotExists: true)
        try db.create(index: "idx_segments_time", on: databaseTableName, columns: ["startTime", "endTime"], ifNotExists: true)
    }
}

// MARK: - Full-Text Search Table

extension TranscriptSegment {
    /// Creates FTS5 virtual table for transcript search
    static func createFTSTable(in db: Database) throws {
        // Create FTS5 virtual table
        try db.execute(sql: """
            CREATE VIRTUAL TABLE IF NOT EXISTS transcriptFts USING fts5(
                text,
                content='transcriptSegments',
                content_rowid='id',
                tokenize='unicode61'
            )
        """)

        // Triggers to keep FTS in sync
        try db.execute(sql: """
            CREATE TRIGGER IF NOT EXISTS transcript_ai AFTER INSERT ON transcriptSegments BEGIN
                INSERT INTO transcriptFts(rowid, text) VALUES (new.id, new.text);
            END
        """)

        try db.execute(sql: """
            CREATE TRIGGER IF NOT EXISTS transcript_ad AFTER DELETE ON transcriptSegments BEGIN
                INSERT INTO transcriptFts(transcriptFts, rowid, text) VALUES('delete', old.id, old.text);
            END
        """)

        try db.execute(sql: """
            CREATE TRIGGER IF NOT EXISTS transcript_au AFTER UPDATE ON transcriptSegments BEGIN
                INSERT INTO transcriptFts(transcriptFts, rowid, text) VALUES('delete', old.id, old.text);
                INSERT INTO transcriptFts(rowid, text) VALUES (new.id, new.text);
            END
        """)
    }
}
