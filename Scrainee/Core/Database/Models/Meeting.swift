import Foundation
import GRDB

/// Represents a detected meeting session
struct Meeting: Codable, Identifiable {
    var id: Int64?
    var appBundleId: String
    var appName: String
    var startTime: Date
    var endTime: Date?
    var durationSeconds: Int?
    var screenshotCount: Int?
    var transcript: String?
    var aiSummary: String?
    var notionPageId: String?
    var notionPageUrl: String?
    var status: MeetingStatus
    var createdAt: Date?

    // MARK: - Computed Properties

    /// Duration in minutes
    var durationMinutes: Int {
        guard let duration = durationSeconds else { return 0 }
        return duration / 60
    }

    /// Formatted duration string
    var formattedDuration: String {
        guard let seconds = durationSeconds else { return "Laufend..." }
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        if minutes > 0 {
            return "\(minutes)m \(remainingSeconds)s"
        }
        return "\(seconds)s"
    }

    /// Whether the meeting is still active
    var isActive: Bool {
        status == .active
    }
}

// MARK: - Meeting Status

enum MeetingStatus: String, Codable {
    case active = "active"
    case completed = "completed"
    case exported = "exported"
}

// MARK: - Meeting Session (for detection)

struct MeetingSession {
    var appName: String
    var bundleId: String
    var startTime: Date
    var endTime: Date?

    var duration: TimeInterval? {
        guard let end = endTime else { return nil }
        return end.timeIntervalSince(startTime)
    }

    var durationMinutes: Int {
        guard let duration = duration else { return 0 }
        return Int(duration / 60)
    }
}

// MARK: - GRDB Record Conformance

extension Meeting: FetchableRecord, PersistableRecord {
    static var databaseTableName: String { "meetings" }

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let appBundleId = Column(CodingKeys.appBundleId)
        static let appName = Column(CodingKeys.appName)
        static let startTime = Column(CodingKeys.startTime)
        static let endTime = Column(CodingKeys.endTime)
        static let durationSeconds = Column(CodingKeys.durationSeconds)
        static let screenshotCount = Column(CodingKeys.screenshotCount)
        static let transcript = Column(CodingKeys.transcript)
        static let aiSummary = Column(CodingKeys.aiSummary)
        static let notionPageId = Column(CodingKeys.notionPageId)
        static let notionPageUrl = Column(CodingKeys.notionPageUrl)
        static let status = Column(CodingKeys.status)
        static let createdAt = Column(CodingKeys.createdAt)
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

// MARK: - Table Creation

extension Meeting {
    static func createTable(in db: Database) throws {
        try db.create(table: databaseTableName, ifNotExists: true) { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("appBundleId", .text).notNull()
            t.column("appName", .text).notNull()
            t.column("startTime", .datetime).notNull()
            t.column("endTime", .datetime)
            t.column("durationSeconds", .integer)
            t.column("screenshotCount", .integer).defaults(to: 0)
            t.column("transcript", .text)
            t.column("aiSummary", .text)
            t.column("notionPageId", .text)
            t.column("notionPageUrl", .text)
            t.column("status", .text).notNull().defaults(to: "active")
            t.column("createdAt", .datetime).defaults(sql: "CURRENT_TIMESTAMP")
        }

        try db.create(index: "idx_meetings_time", on: databaseTableName, columns: ["startTime"], ifNotExists: true)
        try db.create(index: "idx_meetings_app", on: databaseTableName, columns: ["appBundleId"], ifNotExists: true)
        try db.create(index: "idx_meetings_status", on: databaseTableName, columns: ["status"], ifNotExists: true)
    }
}

// MARK: - Meeting Screenshots Junction Table

struct MeetingScreenshot: Codable {
    var meetingId: Int64
    var screenshotId: Int64
}

extension MeetingScreenshot: FetchableRecord, PersistableRecord {
    static var databaseTableName: String { "meetingScreenshots" }

    static func createTable(in db: Database) throws {
        try db.create(table: databaseTableName, ifNotExists: true) { t in
            t.column("meetingId", .integer)
                .notNull()
                .references("meetings", onDelete: .cascade)
            t.column("screenshotId", .integer)
                .notNull()
                .references("screenshots", onDelete: .cascade)
            t.primaryKey(["meetingId", "screenshotId"])
        }
    }
}
