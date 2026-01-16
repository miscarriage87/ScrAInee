import Foundation
import GRDB

/// Represents an action item extracted from meeting minutes
struct ActionItem: Codable, Identifiable, Sendable {
    var id: Int64?
    var meetingId: Int64
    var minutesId: Int64?
    var title: String
    var description: String?
    var assignee: String?
    var dueDate: Date?
    var priority: ActionItemPriority
    var status: ActionItemStatus
    var sourceSegmentId: Int64?      // Reference to transcript segment
    var createdAt: Date?

    // MARK: - Computed Properties

    /// Whether the item is overdue
    var isOverdue: Bool {
        guard let due = dueDate else { return false }
        return due < Date() && status != .completed
    }

    /// Formatted due date
    var formattedDueDate: String? {
        guard let due = dueDate else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: due)
    }

    // MARK: - Initialization

    init(
        id: Int64? = nil,
        meetingId: Int64,
        minutesId: Int64? = nil,
        title: String,
        description: String? = nil,
        assignee: String? = nil,
        dueDate: Date? = nil,
        priority: ActionItemPriority = .medium,
        status: ActionItemStatus = .pending,
        sourceSegmentId: Int64? = nil,
        createdAt: Date? = Date()
    ) {
        self.id = id
        self.meetingId = meetingId
        self.minutesId = minutesId
        self.title = title
        self.description = description
        self.assignee = assignee
        self.dueDate = dueDate
        self.priority = priority
        self.status = status
        self.sourceSegmentId = sourceSegmentId
        self.createdAt = createdAt
    }
}

// MARK: - Action Item Priority

enum ActionItemPriority: String, Codable, CaseIterable, Sendable {
    case low = "low"
    case medium = "medium"
    case high = "high"
    case urgent = "urgent"

    var displayName: String {
        switch self {
        case .low: return "Niedrig"
        case .medium: return "Mittel"
        case .high: return "Hoch"
        case .urgent: return "Dringend"
        }
    }

    var sortOrder: Int {
        switch self {
        case .urgent: return 0
        case .high: return 1
        case .medium: return 2
        case .low: return 3
        }
    }
}

// MARK: - Action Item Status

enum ActionItemStatus: String, Codable, CaseIterable, Sendable {
    case pending = "pending"
    case inProgress = "inProgress"
    case completed = "completed"
    case cancelled = "cancelled"

    var displayName: String {
        switch self {
        case .pending: return "Offen"
        case .inProgress: return "In Bearbeitung"
        case .completed: return "Erledigt"
        case .cancelled: return "Abgebrochen"
        }
    }

    var isActive: Bool {
        self == .pending || self == .inProgress
    }
}

// MARK: - GRDB Record Conformance

extension ActionItem: FetchableRecord, PersistableRecord {
    static var databaseTableName: String { "actionItems" }

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let meetingId = Column(CodingKeys.meetingId)
        static let minutesId = Column(CodingKeys.minutesId)
        static let title = Column(CodingKeys.title)
        static let description = Column(CodingKeys.description)
        static let assignee = Column(CodingKeys.assignee)
        static let dueDate = Column(CodingKeys.dueDate)
        static let priority = Column(CodingKeys.priority)
        static let status = Column(CodingKeys.status)
        static let sourceSegmentId = Column(CodingKeys.sourceSegmentId)
        static let createdAt = Column(CodingKeys.createdAt)
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

// MARK: - Table Creation

extension ActionItem {
    static func createTable(in db: Database) throws {
        try db.create(table: databaseTableName, ifNotExists: true) { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("meetingId", .integer)
                .notNull()
                .references("meetings", onDelete: .cascade)
            t.column("minutesId", .integer)
                .references("meetingMinutes", onDelete: .setNull)
            t.column("title", .text).notNull()
            t.column("description", .text)
            t.column("assignee", .text)
            t.column("dueDate", .datetime)
            t.column("priority", .text).notNull().defaults(to: "medium")
            t.column("status", .text).notNull().defaults(to: "pending")
            t.column("sourceSegmentId", .integer)
                .references("transcriptSegments", onDelete: .setNull)
            t.column("createdAt", .datetime).defaults(sql: "CURRENT_TIMESTAMP")
        }

        try db.create(index: "idx_actionitems_meeting", on: databaseTableName, columns: ["meetingId"], ifNotExists: true)
        try db.create(index: "idx_actionitems_status", on: databaseTableName, columns: ["status"], ifNotExists: true)
        try db.create(index: "idx_actionitems_assignee", on: databaseTableName, columns: ["assignee"], ifNotExists: true)
    }
}
