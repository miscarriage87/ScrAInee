import Foundation
import GRDB
@testable import Scrainee

/// Isolierte Datenbank für E2E-Tests - verwendet temporäres Verzeichnis
actor TestDatabaseManager {
    private var dbQueue: DatabaseQueue?
    private let testDatabaseURL: URL
    private let testDirectory: URL

    init(testName: String) {
        let tempDir = FileManager.default.temporaryDirectory
        let uniqueId = UUID().uuidString
        testDirectory = tempDir.appendingPathComponent("ScraineeTests/\(testName)/\(uniqueId)")
        testDatabaseURL = testDirectory.appendingPathComponent("test.sqlite")
    }

    /// Initialisiert die Test-Datenbank mit allen Tabellen
    func initialize() async throws {
        // Erstelle Test-Verzeichnis
        try FileManager.default.createDirectory(at: testDirectory, withIntermediateDirectories: true)

        // Konfiguriere Datenbank
        var config = Configuration()
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }

        dbQueue = try DatabaseQueue(path: testDatabaseURL.path, configuration: config)

        // Erstelle alle Tabellen
        try await dbQueue?.write { db in
            try Screenshot.createTable(in: db)
            try OCRResult.createTable(in: db)
            try Meeting.createTable(in: db)
            try MeetingScreenshot.createTable(in: db)
            try Summary.createTable(in: db)
        }
    }

    /// Räumt die Test-Datenbank auf
    func cleanup() {
        dbQueue = nil
        try? FileManager.default.removeItem(at: testDirectory)
    }

    // MARK: - Screenshot Operations

    @discardableResult
    func insert(_ screenshot: Screenshot) async throws -> Int64 {
        guard let db = dbQueue else { throw DatabaseError.notInitialized }

        return try await db.write { db in
            let record = try screenshot.inserted(db)
            if let id = record.id {
                return id
            }
            return db.lastInsertedRowID
        }
    }

    func getScreenshot(id: Int64) async throws -> Screenshot? {
        guard let db = dbQueue else { throw DatabaseError.notInitialized }

        return try await db.read { db in
            try Screenshot.fetchOne(db, key: id)
        }
    }

    func getScreenshots(from startTime: Date, to endTime: Date) async throws -> [Screenshot] {
        guard let db = dbQueue else { throw DatabaseError.notInitialized }

        return try await db.read { db in
            try Screenshot
                .filter(Screenshot.Columns.timestamp >= startTime && Screenshot.Columns.timestamp <= endTime)
                .order(Screenshot.Columns.timestamp.desc)
                .fetchAll(db)
        }
    }

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

    func deleteScreenshot(id: Int64) async throws {
        guard let db = dbQueue else { throw DatabaseError.notInitialized }

        try await db.write { db in
            try db.execute(sql: "DELETE FROM ocrResults WHERE screenshotId = ?", arguments: [id])
            try db.execute(sql: "DELETE FROM screenshots WHERE id = ?", arguments: [id])
        }
    }

    func getScreenshotCount() async throws -> Int {
        guard let db = dbQueue else { throw DatabaseError.notInitialized }

        return try await db.read { db in
            try Screenshot.fetchCount(db)
        }
    }

    func getAllScreenshots() async throws -> [Screenshot] {
        guard let db = dbQueue else { throw DatabaseError.notInitialized }

        return try await db.read { db in
            try Screenshot
                .order(Screenshot.Columns.timestamp.desc)
                .fetchAll(db)
        }
    }

    // MARK: - OCR Operations

    @discardableResult
    func insert(_ ocrResult: OCRResult) async throws -> Int64 {
        guard let db = dbQueue else { throw DatabaseError.notInitialized }

        return try await db.write { db in
            let record = try ocrResult.inserted(db)
            if let id = record.id {
                return id
            }
            return db.lastInsertedRowID
        }
    }

    func getOCRResult(for screenshotId: Int64) async throws -> OCRResult? {
        guard let db = dbQueue else { throw DatabaseError.notInitialized }

        return try await db.read { db in
            try OCRResult
                .filter(OCRResult.Columns.screenshotId == screenshotId)
                .fetchOne(db)
        }
    }

    /// FTS5 Volltextsuche
    func searchOCR(query: String, limit: Int = 50) async throws -> [SearchResult] {
        guard let db = dbQueue else { throw DatabaseError.notInitialized }

        // Leere Query gibt leere Ergebnisse
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            return []
        }

        // FTS5 Query erstellen
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

    func getOCRResultCount() async throws -> Int {
        guard let db = dbQueue else { throw DatabaseError.notInitialized }

        return try await db.read { db in
            try OCRResult.fetchCount(db)
        }
    }

    // MARK: - Stats

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
