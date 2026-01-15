import Foundation
import GRDB

/// Represents an AI-generated summary
struct Summary: Codable, Identifiable {
    var id: Int64?
    var title: String?
    var startTime: Date
    var endTime: Date
    var content: String
    var model: String?
    var promptTokens: Int?
    var completionTokens: Int?
    var screenshotCount: Int?
    var meetingId: Int64?
    var createdAt: Date?

    // MARK: - Computed Properties

    /// Duration covered by this summary
    var duration: TimeInterval {
        endTime.timeIntervalSince(startTime)
    }

    /// Formatted time range
    var formattedTimeRange: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short

        if Calendar.current.isDate(startTime, inSameDayAs: endTime) {
            let timeFormatter = DateFormatter()
            timeFormatter.timeStyle = .short
            return "\(formatter.string(from: startTime)) - \(timeFormatter.string(from: endTime))"
        }

        return "\(formatter.string(from: startTime)) - \(formatter.string(from: endTime))"
    }

    /// Total tokens used
    var totalTokens: Int {
        (promptTokens ?? 0) + (completionTokens ?? 0)
    }
}

// MARK: - GRDB Record Conformance

extension Summary: FetchableRecord, PersistableRecord {
    static var databaseTableName: String { "summaries" }

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let title = Column(CodingKeys.title)
        static let startTime = Column(CodingKeys.startTime)
        static let endTime = Column(CodingKeys.endTime)
        static let content = Column(CodingKeys.content)
        static let model = Column(CodingKeys.model)
        static let promptTokens = Column(CodingKeys.promptTokens)
        static let completionTokens = Column(CodingKeys.completionTokens)
        static let screenshotCount = Column(CodingKeys.screenshotCount)
        static let meetingId = Column(CodingKeys.meetingId)
        static let createdAt = Column(CodingKeys.createdAt)
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

// MARK: - Table Creation

extension Summary {
    static func createTable(in db: Database) throws {
        try db.create(table: databaseTableName, ifNotExists: true) { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("title", .text)
            t.column("startTime", .datetime).notNull()
            t.column("endTime", .datetime).notNull()
            t.column("content", .text).notNull()
            t.column("model", .text)
            t.column("promptTokens", .integer)
            t.column("completionTokens", .integer)
            t.column("screenshotCount", .integer)
            t.column("meetingId", .integer).references("meetings", onDelete: .setNull)
            t.column("createdAt", .datetime).defaults(sql: "CURRENT_TIMESTAMP")
        }

        try db.create(index: "idx_summaries_time", on: databaseTableName, columns: ["startTime", "endTime"], ifNotExists: true)
        try db.create(index: "idx_summaries_meeting", on: databaseTableName, columns: ["meetingId"], ifNotExists: true)
    }
}
