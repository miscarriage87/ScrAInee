// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - DEPENDENCY DOCUMENTATION
// ═══════════════════════════════════════════════════════════════════════════════
//
// FILE: MeetingMinutes.swift | PURPOSE: GRDB Model für AI-generierte Meeting-Protokolle | LAYER: Core/Database
//
// DEPENDENCIES: GRDB.swift
// RELATED: Meeting (Foreign Key: meetingId, 1:1 Beziehung)
// USED BY: DatabaseManager, MeetingMinutesViewModel, SummaryGenerator
// NOTE: JSON-kodierte Arrays für keyPoints, actionItems, decisions
// CHANGE IMPACT: Schema-Änderungen erfordern DB-Migration
//
// LAST UPDATED: 2026-01-20
// ═══════════════════════════════════════════════════════════════════════════════

import Foundation
import GRDB

/// Represents AI-generated meeting minutes
struct MeetingMinutes: Codable, Identifiable, Sendable {
    var id: Int64?
    var meetingId: Int64
    var summary: String?             // AI-generated summary
    var keyPoints: String?           // JSON array of key points
    var actionItems: String?         // JSON array of action items
    var decisions: String?           // JSON array of decisions
    var version: Int                 // For incremental updates
    var isFinalized: Bool
    var generatedAt: Date?
    var model: String?
    var promptTokens: Int?
    var completionTokens: Int?

    // MARK: - Computed Properties

    /// Total tokens used
    var totalTokens: Int {
        (promptTokens ?? 0) + (completionTokens ?? 0)
    }

    /// Decoded key points
    var keyPointsList: [String] {
        guard let data = keyPoints?.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }

    /// Decoded decisions
    var decisionsList: [String] {
        guard let data = decisions?.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }

    // MARK: - Initialization

    init(
        id: Int64? = nil,
        meetingId: Int64,
        summary: String? = nil,
        keyPoints: String? = nil,
        actionItems: String? = nil,
        decisions: String? = nil,
        version: Int = 1,
        isFinalized: Bool = false,
        generatedAt: Date? = Date(),
        model: String? = nil,
        promptTokens: Int? = nil,
        completionTokens: Int? = nil
    ) {
        self.id = id
        self.meetingId = meetingId
        self.summary = summary
        self.keyPoints = keyPoints
        self.actionItems = actionItems
        self.decisions = decisions
        self.version = version
        self.isFinalized = isFinalized
        self.generatedAt = generatedAt
        self.model = model
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
    }

    // MARK: - Helper Methods

    /// Sets key points from array
    mutating func setKeyPoints(_ points: [String]) {
        if let data = try? JSONEncoder().encode(points) {
            keyPoints = String(data: data, encoding: .utf8)
        }
    }

    /// Sets decisions from array
    mutating func setDecisions(_ items: [String]) {
        if let data = try? JSONEncoder().encode(items) {
            decisions = String(data: data, encoding: .utf8)
        }
    }
}

// MARK: - GRDB Record Conformance

extension MeetingMinutes: FetchableRecord, PersistableRecord {
    static var databaseTableName: String { "meetingMinutes" }

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let meetingId = Column(CodingKeys.meetingId)
        static let summary = Column(CodingKeys.summary)
        static let keyPoints = Column(CodingKeys.keyPoints)
        static let actionItems = Column(CodingKeys.actionItems)
        static let decisions = Column(CodingKeys.decisions)
        static let version = Column(CodingKeys.version)
        static let isFinalized = Column(CodingKeys.isFinalized)
        static let generatedAt = Column(CodingKeys.generatedAt)
        static let model = Column(CodingKeys.model)
        static let promptTokens = Column(CodingKeys.promptTokens)
        static let completionTokens = Column(CodingKeys.completionTokens)
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

// MARK: - Table Creation

extension MeetingMinutes {
    static func createTable(in db: Database) throws {
        try db.create(table: databaseTableName, ifNotExists: true) { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("meetingId", .integer)
                .notNull()
                .unique()
                .references("meetings", onDelete: .cascade)
            t.column("summary", .text)
            t.column("keyPoints", .text)
            t.column("actionItems", .text)
            t.column("decisions", .text)
            t.column("version", .integer).notNull().defaults(to: 1)
            t.column("isFinalized", .boolean).notNull().defaults(to: false)
            t.column("generatedAt", .datetime).defaults(sql: "CURRENT_TIMESTAMP")
            t.column("model", .text)
            t.column("promptTokens", .integer)
            t.column("completionTokens", .integer)
        }

        try db.create(index: "idx_minutes_meeting", on: databaseTableName, columns: ["meetingId"], ifNotExists: true)
    }
}
