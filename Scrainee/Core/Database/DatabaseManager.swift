import Foundation
import GRDB

/// Manages all database operations for Scrainee
actor DatabaseManager {
    static let shared = DatabaseManager()

    private var dbQueue: DatabaseQueue?
    private var isInitialized = false

    // MARK: - Initialization

    private init() {}

    /// Initializes the database, creating tables if needed
    /// Safe to call multiple times - will only initialize once
    func initialize() async throws {
        // Skip if already initialized
        guard !isInitialized else { return }

        let databaseURL = StorageManager.shared.databaseURL

        // Create database queue
        var config = Configuration()
        config.prepareDatabase { db in
            // Enable foreign keys
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }

        dbQueue = try DatabaseQueue(path: databaseURL.path, configuration: config)

        // Run migrations
        try await migrate()

        isInitialized = true
    }

    // MARK: - Migrations

    private func migrate() async throws {
        guard let db = dbQueue else { throw DatabaseError.notInitialized }

        try await db.write { db in
            // Create tables
            try Screenshot.createTable(in: db)
            try OCRResult.createTable(in: db)
            try Meeting.createTable(in: db)
            try MeetingScreenshot.createTable(in: db)
            try Summary.createTable(in: db)

            // Migration: Add title column to summaries if it doesn't exist
            try self.addColumnIfNotExists(db: db, table: "summaries", column: "title", type: "TEXT")

            // Migration v2: Transcription tables
            try TranscriptSegment.createTable(in: db)
            try TranscriptSegment.createFTSTable(in: db)
            try MeetingMinutes.createTable(in: db)
            try ActionItem.createTable(in: db)

            // Migration: Add transcription columns to meetings if they don't exist
            try Meeting.addTranscriptionColumns(in: db)
        }
    }

    /// Adds a column to a table if it doesn't already exist
    private nonisolated func addColumnIfNotExists(db: Database, table: String, column: String, type: String) throws {
        let columns = try db.columns(in: table)
        let columnExists = columns.contains { $0.name == column }

        if !columnExists {
            try db.execute(sql: "ALTER TABLE \(table) ADD COLUMN \(column) \(type)")
        }
    }

    // MARK: - Screenshot Operations

    /// Inserts a new screenshot and returns its ID
    @discardableResult
    func insert(_ screenshot: Screenshot) async throws -> Int64 {
        guard let db = dbQueue else { throw DatabaseError.notInitialized }

        return try await db.write { db in
            try screenshot.insert(db)
            return db.lastInsertedRowID
        }
    }

    /// Gets a screenshot by ID
    func getScreenshot(id: Int64) async throws -> Screenshot? {
        guard let db = dbQueue else { throw DatabaseError.notInitialized }

        return try await db.read { db in
            try Screenshot.fetchOne(db, key: id)
        }
    }

    /// Gets screenshots in a time range
    func getScreenshots(from startTime: Date, to endTime: Date) async throws -> [Screenshot] {
        guard let db = dbQueue else { throw DatabaseError.notInitialized }

        return try await db.read { db in
            try Screenshot
                .filter(Screenshot.Columns.timestamp >= startTime && Screenshot.Columns.timestamp <= endTime)
                .order(Screenshot.Columns.timestamp.desc)
                .fetchAll(db)
        }
    }

    /// Gets screenshots before a date (for retention cleanup)
    func getScreenshotsBefore(_ date: Date) async throws -> [Screenshot] {
        guard let db = dbQueue else { throw DatabaseError.notInitialized }

        return try await db.read { db in
            try Screenshot
                .filter(Screenshot.Columns.timestamp < date)
                .fetchAll(db)
        }
    }

    /// Deletes screenshots before a date
    func deleteScreenshotsBefore(_ date: Date) async throws -> Int {
        guard let db = dbQueue else { throw DatabaseError.notInitialized }

        return try await db.write { db in
            try Screenshot
                .filter(Screenshot.Columns.timestamp < date)
                .deleteAll(db)
        }
    }

    /// Gets total screenshot count
    func getScreenshotCount() async throws -> Int {
        guard let db = dbQueue else { throw DatabaseError.notInitialized }

        return try await db.read { db in
            try Screenshot.fetchCount(db)
        }
    }

    // MARK: - OCR Operations

    /// Inserts an OCR result
    @discardableResult
    func insert(_ ocrResult: OCRResult) async throws -> Int64 {
        guard let db = dbQueue else { throw DatabaseError.notInitialized }

        return try await db.write { db in
            let record = ocrResult
            try record.insert(db)
            guard let id = record.id else {
                throw DatabaseError.queryFailed("Failed to get inserted OCR result ID")
            }
            return id
        }
    }

    /// Gets OCR result for a screenshot
    func getOCRResult(for screenshotId: Int64) async throws -> OCRResult? {
        guard let db = dbQueue else { throw DatabaseError.notInitialized }

        return try await db.read { db in
            try OCRResult
                .filter(OCRResult.Columns.screenshotId == screenshotId)
                .fetchOne(db)
        }
    }

    /// Searches OCR text using FTS5
    func searchOCR(query: String, limit: Int = 50) async throws -> [SearchResult] {
        guard let db = dbQueue else { throw DatabaseError.notInitialized }

        // Escape FTS5 special characters and add wildcards
        let escapedQuery = query
            .replacingOccurrences(of: "\"", with: "\"\"")
            .split(separator: " ")
            .map { "\"\($0)\"*" }
            .joined(separator: " ")

        let sql = """
            SELECT
                s.id,
                s.filepath,
                s.timestamp,
                s.appName,
                s.appBundleId,
                s.windowTitle,
                o.text,
                highlight(ocrFts, 0, '<mark>', '</mark>') as highlightedText
            FROM ocrFts
            JOIN ocrResults o ON ocrFts.rowid = o.id
            JOIN screenshots s ON o.screenshotId = s.id
            WHERE ocrFts MATCH ?
            ORDER BY rank
            LIMIT ?
        """

        return try await db.read { db in
            try SearchResult.fetchAll(db, sql: sql, arguments: [escapedQuery, limit])
        }
    }

    /// Gets OCR texts for screenshots in a time range
    func getOCRTexts(from startTime: Date, to endTime: Date) async throws -> [(screenshotId: Int64, text: String)] {
        guard let db = dbQueue else { throw DatabaseError.notInitialized }

        let sql = """
            SELECT o.screenshotId, o.text
            FROM ocrResults o
            JOIN screenshots s ON o.screenshotId = s.id
            WHERE s.timestamp >= ? AND s.timestamp <= ?
            ORDER BY s.timestamp
        """

        return try await db.read { db in
            let rows = try Row.fetchAll(db, sql: sql, arguments: [startTime, endTime])
            return rows.map { (screenshotId: $0["screenshotId"], text: $0["text"]) }
        }
    }

    // MARK: - Meeting Operations

    /// Inserts a new meeting
    @discardableResult
    func insert(_ meeting: Meeting) async throws -> Int64 {
        guard let db = dbQueue else { throw DatabaseError.notInitialized }

        return try await db.write { db in
            let record = meeting
            try record.insert(db)
            guard let id = record.id else {
                throw DatabaseError.queryFailed("Failed to get inserted meeting ID")
            }
            return id
        }
    }

    /// Updates a meeting
    func update(_ meeting: Meeting) async throws {
        guard let db = dbQueue else { throw DatabaseError.notInitialized }

        try await db.write { db in
            try meeting.update(db)
        }
    }

    /// Gets active meeting
    func getActiveMeeting() async throws -> Meeting? {
        guard let db = dbQueue else { throw DatabaseError.notInitialized }

        return try await db.read { db in
            try Meeting
                .filter(Meeting.Columns.status == MeetingStatus.active.rawValue)
                .fetchOne(db)
        }
    }

    /// Gets meetings in a time range
    func getMeetings(from startTime: Date, to endTime: Date) async throws -> [Meeting] {
        guard let db = dbQueue else { throw DatabaseError.notInitialized }

        return try await db.read { db in
            try Meeting
                .filter(Meeting.Columns.startTime >= startTime && Meeting.Columns.startTime <= endTime)
                .order(Meeting.Columns.startTime.desc)
                .fetchAll(db)
        }
    }

    /// Links a screenshot to a meeting
    func linkScreenshotToMeeting(screenshotId: Int64, meetingId: Int64) async throws {
        guard let db = dbQueue else { throw DatabaseError.notInitialized }

        try await db.write { db in
            let link = MeetingScreenshot(meetingId: meetingId, screenshotId: screenshotId)
            try link.insert(db)
        }
    }

    // MARK: - Summary Operations

    /// Inserts a summary
    @discardableResult
    func insert(_ summary: Summary) async throws -> Int64 {
        guard let db = dbQueue else { throw DatabaseError.notInitialized }

        return try await db.write { db in
            try summary.insert(db)
            return db.lastInsertedRowID
        }
    }

    /// Gets summaries
    func getSummaries(limit: Int = 20) async throws -> [Summary] {
        guard let db = dbQueue else { throw DatabaseError.notInitialized }

        return try await db.read { db in
            try Summary
                .order(Summary.Columns.createdAt.desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    /// Deletes a summary by ID
    func deleteSummary(id: Int64) async throws {
        guard let db = dbQueue else { throw DatabaseError.notInitialized }

        try await db.write { db in
            try db.execute(sql: "DELETE FROM summaries WHERE id = ?", arguments: [id])
        }
    }

    /// Updates a meeting's Notion link
    func updateMeetingNotionLink(meetingId: Int64, pageId: String, pageUrl: String) async throws {
        guard let db = dbQueue else { throw DatabaseError.notInitialized }

        try await db.write { db in
            try db.execute(
                sql: """
                    UPDATE meetings
                    SET notionPageId = ?, notionPageUrl = ?, status = ?
                    WHERE id = ?
                """,
                arguments: [pageId, pageUrl, MeetingStatus.exported.rawValue, meetingId]
            )
        }
    }

    /// Gets a meeting by ID
    func getMeeting(id: Int64) async throws -> Meeting? {
        guard let db = dbQueue else { throw DatabaseError.notInitialized }

        return try await db.read { db in
            try Meeting.fetchOne(db, key: id)
        }
    }

    /// Gets screenshot count for a meeting
    func getScreenshotCountForMeeting(meetingId: Int64) async throws -> Int {
        guard let db = dbQueue else { throw DatabaseError.notInitialized }

        return try await db.read { db in
            try MeetingScreenshot
                .filter(Column("meetingId") == meetingId)
                .fetchCount(db)
        }
    }

    // MARK: - Gallery Operations

    /// Fetches screenshots with filtering and pagination for Gallery
    func getScreenshots(
        offset: Int,
        limit: Int,
        appFilter: String? = nil,
        dateFrom: Date? = nil,
        dateTo: Date? = nil,
        searchText: String? = nil
    ) async throws -> [Screenshot] {
        guard let db = dbQueue else { throw DatabaseError.notInitialized }

        return try await db.read { db in
            var sql = "SELECT * FROM screenshots WHERE 1=1"
            var arguments: [DatabaseValueConvertible] = []

            if let app = appFilter {
                sql += " AND appName = ?"
                arguments.append(app)
            }

            if let from = dateFrom {
                sql += " AND timestamp >= ?"
                arguments.append(from)
            }

            if let to = dateTo {
                sql += " AND timestamp <= ?"
                arguments.append(to)
            }

            if let search = searchText, !search.isEmpty {
                // Join with OCR results for text search
                sql = """
                    SELECT DISTINCT s.* FROM screenshots s
                    LEFT JOIN ocrResults o ON s.id = o.screenshotId
                    WHERE 1=1
                    """

                // Re-add filters for the joined query
                if appFilter != nil {
                    sql += " AND s.appName = ?"
                    // argument already added
                }

                if dateFrom != nil {
                    sql += " AND s.timestamp >= ?"
                    // argument already added
                }

                if dateTo != nil {
                    sql += " AND s.timestamp <= ?"
                    // argument already added
                }

                sql += " AND (s.windowTitle LIKE ? OR s.appName LIKE ? OR o.text LIKE ?)"
                let searchPattern = "%\(search)%"
                arguments.append(searchPattern)
                arguments.append(searchPattern)
                arguments.append(searchPattern)
            }

            sql += " ORDER BY timestamp DESC LIMIT ? OFFSET ?"
            arguments.append(limit)
            arguments.append(offset)

            return try Screenshot.fetchAll(db, sql: sql, arguments: StatementArguments(arguments))
        }
    }

    /// Gets unique app names from screenshots
    func getUniqueAppNames() async throws -> [String] {
        guard let db = dbQueue else { throw DatabaseError.notInitialized }

        return try await db.read { db in
            try String.fetchAll(db, sql: """
                SELECT DISTINCT appName FROM screenshots
                WHERE appName IS NOT NULL
                ORDER BY appName
                """)
        }
    }

    /// Deletes a screenshot by ID
    func deleteScreenshot(id: Int64) async throws {
        guard let db = dbQueue else { throw DatabaseError.notInitialized }

        try await db.write { db in
            // Delete OCR results first
            try db.execute(sql: "DELETE FROM ocrResults WHERE screenshotId = ?", arguments: [id])
            // Delete screenshot
            try db.execute(sql: "DELETE FROM screenshots WHERE id = ?", arguments: [id])
        }
    }

    /// Deletes a screenshot (convenience method)
    func deleteScreenshot(_ screenshot: Screenshot) async throws {
        guard let id = screenshot.id else {
            throw DatabaseError.queryFailed("Screenshot has no ID")
        }
        
        // Also delete the file from disk
        if screenshot.fileExists {
            try? FileManager.default.removeItem(at: screenshot.fileURL)
        }
        
        try await deleteScreenshot(id: id)
    }

    /// Gets all screenshots
    func getAllScreenshots() async throws -> [Screenshot] {
        guard let db = dbQueue else { throw DatabaseError.notInitialized }

        return try await db.read { db in
            try Screenshot
                .order(Screenshot.Columns.timestamp.desc)
                .fetchAll(db)
        }
    }

    /// Gets OCR text for a specific screenshot
    func getOCRText(for screenshotId: Int64) async throws -> String? {
        guard let db = dbQueue else { throw DatabaseError.notInitialized }

        return try await db.read { db in
            try String.fetchOne(db, sql: """
                SELECT text FROM ocrResults WHERE screenshotId = ? LIMIT 1
                """, arguments: [screenshotId])
        }
    }

    // MARK: - Timeline Operations

    /// Gets screenshots for a specific day, ordered by timestamp
    func getScreenshotsForDay(_ date: Date) async throws -> [Screenshot] {
        guard let db = dbQueue else { throw DatabaseError.notInitialized }

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else {
            throw DatabaseError.queryFailed("Konnte Ende des Tages nicht berechnen")
        }

        return try await db.read { db in
            try Screenshot
                .filter(Screenshot.Columns.timestamp >= startOfDay && Screenshot.Columns.timestamp < endOfDay)
                .order(Screenshot.Columns.timestamp.asc)
                .fetchAll(db)
        }
    }

    /// Gets screenshots around a specific time for the thumbnail strip
    func getScreenshotsAround(time: Date, count: Int) async throws -> [Screenshot] {
        guard let db = dbQueue else { throw DatabaseError.notInitialized }

        let halfCount = count / 2

        return try await db.read { db in
            // Get screenshots before
            let before = try Screenshot
                .filter(Screenshot.Columns.timestamp <= time)
                .order(Screenshot.Columns.timestamp.desc)
                .limit(halfCount)
                .fetchAll(db)
                .reversed()

            // Get screenshots after
            let after = try Screenshot
                .filter(Screenshot.Columns.timestamp > time)
                .order(Screenshot.Columns.timestamp.asc)
                .limit(halfCount)
                .fetchAll(db)

            return Array(before) + Array(after)
        }
    }

    /// Gets the adjacent screenshot (next or previous)
    func getAdjacentScreenshot(from screenshotId: Int64, direction: TimelineDirection) async throws -> Screenshot? {
        guard let db = dbQueue else { throw DatabaseError.notInitialized }

        return try await db.read { db in
            // First get the current screenshot's timestamp
            guard let current = try Screenshot.fetchOne(db, key: screenshotId) else {
                return nil
            }

            switch direction {
            case .next:
                return try Screenshot
                    .filter(Screenshot.Columns.timestamp > current.timestamp)
                    .order(Screenshot.Columns.timestamp.asc)
                    .limit(1)
                    .fetchOne(db)
            case .previous:
                return try Screenshot
                    .filter(Screenshot.Columns.timestamp < current.timestamp)
                    .order(Screenshot.Columns.timestamp.desc)
                    .limit(1)
                    .fetchOne(db)
            }
        }
    }

    /// Gets screenshot closest to a specific time
    func getScreenshotClosestTo(time: Date) async throws -> Screenshot? {
        guard let db = dbQueue else { throw DatabaseError.notInitialized }

        return try await db.read { db in
            // Get one before and one after
            let before = try Screenshot
                .filter(Screenshot.Columns.timestamp <= time)
                .order(Screenshot.Columns.timestamp.desc)
                .limit(1)
                .fetchOne(db)

            let after = try Screenshot
                .filter(Screenshot.Columns.timestamp > time)
                .order(Screenshot.Columns.timestamp.asc)
                .limit(1)
                .fetchOne(db)

            // Return the closest one
            switch (before, after) {
            case (nil, nil):
                return nil
            case (let b?, nil):
                return b
            case (nil, let a?):
                return a
            case (let b?, let a?):
                let beforeDiff = abs(time.timeIntervalSince(b.timestamp))
                let afterDiff = abs(a.timestamp.timeIntervalSince(time))
                return beforeDiff <= afterDiff ? b : a
            }
        }
    }

    /// Gets days that have screenshots (for date picker)
    func getDaysWithScreenshots(inMonth date: Date) async throws -> [Date] {
        guard let db = dbQueue else { throw DatabaseError.notInitialized }

        let calendar = Calendar.current
        guard let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: date)),
              let endOfMonth = calendar.date(byAdding: .month, value: 1, to: startOfMonth) else {
            throw DatabaseError.queryFailed("Konnte Monatsbereich nicht berechnen")
        }

        return try await db.read { db in
            let sql = """
                SELECT DISTINCT date(timestamp) as day
                FROM screenshots
                WHERE timestamp >= ? AND timestamp < ?
                ORDER BY day DESC
                """
            let rows = try Row.fetchAll(db, sql: sql, arguments: [startOfMonth, endOfMonth])
            return rows.compactMap { row -> Date? in
                guard let dayString = row["day"] as? String else { return nil }
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd"
                return formatter.date(from: dayString)
            }
        }
    }

    /// Gets time bounds for a specific day (first and last screenshot)
    func getTimeBoundsForDay(_ date: Date) async throws -> (start: Date, end: Date)? {
        guard let db = dbQueue else { throw DatabaseError.notInitialized }

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else {
            throw DatabaseError.queryFailed("Konnte Ende des Tages nicht berechnen")
        }

        return try await db.read { db in
            let first = try Screenshot
                .filter(Screenshot.Columns.timestamp >= startOfDay && Screenshot.Columns.timestamp < endOfDay)
                .order(Screenshot.Columns.timestamp.asc)
                .limit(1)
                .fetchOne(db)

            let last = try Screenshot
                .filter(Screenshot.Columns.timestamp >= startOfDay && Screenshot.Columns.timestamp < endOfDay)
                .order(Screenshot.Columns.timestamp.desc)
                .limit(1)
                .fetchOne(db)

            guard let firstScreenshot = first, let lastScreenshot = last else {
                return nil
            }

            return (start: firstScreenshot.timestamp, end: lastScreenshot.timestamp)
        }
    }

    // MARK: - Transcript Segment Operations

    /// Inserts a transcript segment
    @discardableResult
    func insert(_ segment: TranscriptSegment) async throws -> Int64 {
        guard let db = dbQueue else { throw DatabaseError.notInitialized }

        return try await db.write { db in
            let inserted = try segment.inserted(db)
            guard let id = inserted.id else {
                throw DatabaseError.queryFailed("Failed to get inserted segment ID")
            }
            return id
        }
    }

    /// Gets transcript segments for a meeting
    func getTranscriptSegments(for meetingId: Int64) async throws -> [TranscriptSegment] {
        guard let db = dbQueue else { throw DatabaseError.notInitialized }

        return try await db.read { db in
            try TranscriptSegment
                .filter(TranscriptSegment.Columns.meetingId == meetingId)
                .order(TranscriptSegment.Columns.startTime.asc)
                .fetchAll(db)
        }
    }

    /// Gets transcript segments in a time range for a meeting
    func getTranscriptSegments(
        for meetingId: Int64,
        from startTime: TimeInterval,
        to endTime: TimeInterval
    ) async throws -> [TranscriptSegment] {
        guard let db = dbQueue else { throw DatabaseError.notInitialized }

        return try await db.read { db in
            try TranscriptSegment
                .filter(TranscriptSegment.Columns.meetingId == meetingId)
                .filter(TranscriptSegment.Columns.startTime >= startTime)
                .filter(TranscriptSegment.Columns.endTime <= endTime)
                .order(TranscriptSegment.Columns.startTime.asc)
                .fetchAll(db)
        }
    }

    /// Gets the full transcript text for a meeting
    func getFullTranscript(for meetingId: Int64) async throws -> String {
        let segments = try await getTranscriptSegments(for: meetingId)
        return segments.map { $0.text }.joined(separator: " ")
    }

    /// Searches transcript segments using FTS5
    func searchTranscripts(query: String, meetingId: Int64? = nil, limit: Int = 50) async throws -> [TranscriptSegment] {
        guard let db = dbQueue else { throw DatabaseError.notInitialized }

        let escapedQuery = query
            .replacingOccurrences(of: "\"", with: "\"\"")
            .split(separator: " ")
            .map { "\"\($0)\"*" }
            .joined(separator: " ")

        // Build SQL and capture values outside the closure
        let finalMeetingId = meetingId
        let finalLimit = limit

        let sql: String
        if finalMeetingId != nil {
            sql = """
                SELECT ts.*
                FROM transcriptFts
                JOIN transcriptSegments ts ON transcriptFts.rowid = ts.id
                WHERE transcriptFts MATCH ?
                AND ts.meetingId = ?
                ORDER BY rank LIMIT ?
            """
        } else {
            sql = """
                SELECT ts.*
                FROM transcriptFts
                JOIN transcriptSegments ts ON transcriptFts.rowid = ts.id
                WHERE transcriptFts MATCH ?
                ORDER BY rank LIMIT ?
            """
        }

        return try await db.read { db in
            if let meetingId = finalMeetingId {
                return try TranscriptSegment.fetchAll(db, sql: sql, arguments: [escapedQuery, meetingId, finalLimit])
            } else {
                return try TranscriptSegment.fetchAll(db, sql: sql, arguments: [escapedQuery, finalLimit])
            }
        }
    }

    /// Deletes all transcript segments for a meeting
    func deleteTranscriptSegments(for meetingId: Int64) async throws -> Int {
        guard let db = dbQueue else { throw DatabaseError.notInitialized }

        return try await db.write { db in
            try TranscriptSegment
                .filter(TranscriptSegment.Columns.meetingId == meetingId)
                .deleteAll(db)
        }
    }

    // MARK: - Meeting Minutes Operations

    /// Inserts or updates meeting minutes
    @discardableResult
    func upsert(_ minutes: MeetingMinutes) async throws -> Int64 {
        guard let db = dbQueue else { throw DatabaseError.notInitialized }

        return try await db.write { db in
            var record = minutes

            // Check if minutes already exist for this meeting
            if let existing = try MeetingMinutes
                .filter(MeetingMinutes.Columns.meetingId == minutes.meetingId)
                .fetchOne(db) {
                record.id = existing.id
                record.version = existing.version + 1
                try record.update(db)
                return existing.id!
            } else {
                try record.insert(db)
                return db.lastInsertedRowID
            }
        }
    }

    /// Gets meeting minutes for a meeting
    func getMeetingMinutes(for meetingId: Int64) async throws -> MeetingMinutes? {
        guard let db = dbQueue else { throw DatabaseError.notInitialized }

        return try await db.read { db in
            try MeetingMinutes
                .filter(MeetingMinutes.Columns.meetingId == meetingId)
                .fetchOne(db)
        }
    }

    /// Updates meeting minutes
    func update(_ minutes: MeetingMinutes) async throws {
        guard let db = dbQueue else { throw DatabaseError.notInitialized }

        try await db.write { db in
            try minutes.update(db)
        }
    }

    /// Finalizes meeting minutes
    func finalizeMeetingMinutes(for meetingId: Int64) async throws {
        guard let db = dbQueue else { throw DatabaseError.notInitialized }

        try await db.write { db in
            try db.execute(
                sql: "UPDATE meetingMinutes SET isFinalized = 1 WHERE meetingId = ?",
                arguments: [meetingId]
            )
        }
    }

    // MARK: - Action Item Operations

    /// Inserts an action item
    @discardableResult
    func insert(_ actionItem: ActionItem) async throws -> Int64 {
        guard let db = dbQueue else { throw DatabaseError.notInitialized }

        return try await db.write { db in
            let inserted = try actionItem.inserted(db)
            guard let id = inserted.id else {
                throw DatabaseError.queryFailed("Failed to get inserted action item ID")
            }
            return id
        }
    }

    /// Inserts multiple action items
    func insert(_ actionItems: [ActionItem]) async throws {
        guard let db = dbQueue else { throw DatabaseError.notInitialized }

        try await db.write { db in
            for item in actionItems {
                _ = try item.inserted(db)
            }
        }
    }

    /// Gets action items for a meeting
    func getActionItems(for meetingId: Int64) async throws -> [ActionItem] {
        guard let db = dbQueue else { throw DatabaseError.notInitialized }

        return try await db.read { db in
            try ActionItem
                .filter(ActionItem.Columns.meetingId == meetingId)
                .order(ActionItem.Columns.priority.asc)
                .order(ActionItem.Columns.createdAt.asc)
                .fetchAll(db)
        }
    }

    /// Gets all active action items (pending or in progress)
    func getActiveActionItems() async throws -> [ActionItem] {
        guard let db = dbQueue else { throw DatabaseError.notInitialized }

        return try await db.read { db in
            try ActionItem
                .filter(ActionItem.Columns.status == ActionItemStatus.pending.rawValue ||
                       ActionItem.Columns.status == ActionItemStatus.inProgress.rawValue)
                .order(ActionItem.Columns.priority.asc)
                .order(ActionItem.Columns.dueDate.asc)
                .fetchAll(db)
        }
    }

    /// Updates an action item
    func update(_ actionItem: ActionItem) async throws {
        guard let db = dbQueue else { throw DatabaseError.notInitialized }

        try await db.write { db in
            try actionItem.update(db)
        }
    }

    /// Updates action item status
    func updateActionItemStatus(id: Int64, status: ActionItemStatus) async throws {
        guard let db = dbQueue else { throw DatabaseError.notInitialized }

        try await db.write { db in
            try db.execute(
                sql: "UPDATE actionItems SET status = ? WHERE id = ?",
                arguments: [status.rawValue, id]
            )
        }
    }

    /// Deletes an action item
    func deleteActionItem(id: Int64) async throws {
        guard let db = dbQueue else { throw DatabaseError.notInitialized }

        try await db.write { db in
            try db.execute(sql: "DELETE FROM actionItems WHERE id = ?", arguments: [id])
        }
    }

    /// Deletes all action items for a meeting
    func deleteActionItems(for meetingId: Int64) async throws -> Int {
        guard let db = dbQueue else { throw DatabaseError.notInitialized }

        return try await db.write { db in
            try ActionItem
                .filter(ActionItem.Columns.meetingId == meetingId)
                .deleteAll(db)
        }
    }

    // MARK: - Meeting Transcription Status

    /// Updates meeting transcription status
    func updateMeetingTranscriptionStatus(meetingId: Int64, status: TranscriptionStatus) async throws {
        guard let db = dbQueue else { throw DatabaseError.notInitialized }

        try await db.write { db in
            try db.execute(
                sql: "UPDATE meetings SET transcriptionStatus = ? WHERE id = ?",
                arguments: [status.rawValue, meetingId]
            )
        }
    }

    /// Updates meeting audio file path
    func updateMeetingAudioPath(meetingId: Int64, path: String?) async throws {
        guard let db = dbQueue else { throw DatabaseError.notInitialized }

        try await db.write { db in
            try db.execute(
                sql: "UPDATE meetings SET audioFilePath = ? WHERE id = ?",
                arguments: [path, meetingId]
            )
        }
    }

    // MARK: - Maintenance

    /// Runs VACUUM to optimize database
    func vacuum() async throws {
        guard let db = dbQueue else { throw DatabaseError.notInitialized }

        try await db.vacuum()
    }

    /// Gets database statistics
    func getStats() async throws -> DatabaseStats {
        guard let db = dbQueue else { throw DatabaseError.notInitialized }

        return try await db.read { db in
            let screenshotCount = try Screenshot.fetchCount(db)
            let ocrCount = try OCRResult.fetchCount(db)
            let meetingCount = try Meeting.fetchCount(db)
            let summaryCount = try Summary.fetchCount(db)

            return DatabaseStats(
                screenshotCount: screenshotCount,
                ocrResultCount: ocrCount,
                meetingCount: meetingCount,
                summaryCount: summaryCount
            )
        }
    }
}

// MARK: - Database Stats

struct DatabaseStats {
    let screenshotCount: Int
    let ocrResultCount: Int
    let meetingCount: Int
    let summaryCount: Int
}

// MARK: - Timeline Direction

enum TimelineDirection {
    case next
    case previous
}

// MARK: - Errors

enum DatabaseError: LocalizedError {
    case notInitialized
    case queryFailed(String)

    var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "Datenbank nicht initialisiert"
        case .queryFailed(let message):
            return "Datenbankabfrage fehlgeschlagen: \(message)"
        }
    }
}
