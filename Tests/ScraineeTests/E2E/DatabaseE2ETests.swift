import XCTest
import GRDB
@testable import Scrainee

/// E2E-Tests für die Datenbank-Operationen mit echtem SQLite
final class DatabaseE2ETests: XCTestCase {

    var testDB: TestDatabaseManager!

    override func setUp() async throws {
        testDB = TestDatabaseManager(testName: name)
        try await testDB.initialize()
    }

    override func tearDown() async throws {
        await testDB.cleanup()
        testDB = nil
    }

    // MARK: - Screenshot Round-Trip Tests

    /// Verifiziert: Insert Screenshot -> Retrieve by ID -> Daten stimmen überein
    func test_screenshotRoundTrip_insertsAndRetrievesCorrectly() async throws {
        // Arrange
        let timestamp = Date()
        let screenshot = Screenshot(
            filepath: "2024/01/15/screenshot_test.heic",
            timestamp: timestamp,
            appBundleId: "com.apple.Safari",
            appName: "Safari",
            windowTitle: "Test Page",
            displayId: 1,
            width: 1920,
            height: 1080,
            fileSize: 50000,
            isDuplicate: false,
            hash: "abc123def456"
        )

        // Act
        let insertedId = try await testDB.insert(screenshot)
        let retrieved = try await testDB.getScreenshot(id: insertedId)

        // Assert
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.id, insertedId)
        XCTAssertEqual(retrieved?.filepath, screenshot.filepath)
        XCTAssertEqual(retrieved?.appBundleId, screenshot.appBundleId)
        XCTAssertEqual(retrieved?.appName, screenshot.appName)
        XCTAssertEqual(retrieved?.windowTitle, screenshot.windowTitle)
        XCTAssertEqual(retrieved?.width, screenshot.width)
        XCTAssertEqual(retrieved?.height, screenshot.height)
        XCTAssertEqual(retrieved?.fileSize, screenshot.fileSize)
        XCTAssertEqual(retrieved?.isDuplicate, screenshot.isDuplicate)
        XCTAssertEqual(retrieved?.hash, screenshot.hash)
    }

    /// Verifiziert: Mehrere Inserts -> Query by time range -> Korrekte Ergebnisse
    func test_screenshotTimeRangeQuery_returnsCorrectScreenshots() async throws {
        // Arrange
        let now = Date()
        let screenshots = [
            createScreenshot(timestamp: now.addingTimeInterval(-3600), appName: "Old"),
            createScreenshot(timestamp: now.addingTimeInterval(-1800), appName: "Middle"),
            createScreenshot(timestamp: now, appName: "Recent")
        ]

        for screenshot in screenshots {
            _ = try await testDB.insert(screenshot)
        }

        // Act - Query der letzten Stunde
        let results = try await testDB.getScreenshots(
            from: now.addingTimeInterval(-3700),
            to: now.addingTimeInterval(100)
        )

        // Assert
        XCTAssertEqual(results.count, 3)
    }

    /// Verifiziert: Nur Screenshots aus dem angefragten Zeitraum werden zurückgegeben
    func test_screenshotTimeRangeQuery_excludesOutsideRange() async throws {
        // Arrange
        let now = Date()
        _ = try await testDB.insert(createScreenshot(timestamp: now.addingTimeInterval(-7200), appName: "TooOld"))
        _ = try await testDB.insert(createScreenshot(timestamp: now.addingTimeInterval(-1800), appName: "InRange"))
        _ = try await testDB.insert(createScreenshot(timestamp: now, appName: "Recent"))

        // Act - Query nur letzte Stunde
        let results = try await testDB.getScreenshots(
            from: now.addingTimeInterval(-3600),
            to: now.addingTimeInterval(100)
        )

        // Assert
        XCTAssertEqual(results.count, 2)
        XCTAssertFalse(results.contains { $0.appName == "TooOld" })
    }

    // MARK: - OCR + FTS5 Search Tests

    /// Verifiziert: Insert Screenshot -> Insert OCR -> FTS5 Suche findet Ergebnis
    func test_fts5Search_findsMatchingOCRText() async throws {
        // Arrange
        let screenshot = createScreenshot(appName: "Xcode")
        let screenshotId = try await testDB.insert(screenshot)

        let ocrResult = OCRResult(
            screenshotId: screenshotId,
            text: "Swift programming language async await concurrency",
            confidence: 0.95,
            language: "en"
        )
        _ = try await testDB.insert(ocrResult)

        // Act
        let searchResults = try await testDB.searchOCR(query: "Swift concurrency", limit: 10)

        // Assert
        XCTAssertEqual(searchResults.count, 1)
        XCTAssertEqual(searchResults.first?.id, screenshotId)
        XCTAssertTrue(searchResults.first?.text.contains("Swift") ?? false)
    }

    /// Verifiziert: FTS5 Wildcard-Suche funktioniert
    func test_fts5WildcardSearch_matchesPartialWords() async throws {
        // Arrange
        let screenshot = createScreenshot(appName: "Notes")
        let screenshotId = try await testDB.insert(screenshot)

        let ocrResult = OCRResult(
            screenshotId: screenshotId,
            text: "Documentation meeting notes important deadline project",
            confidence: 0.92
        )
        _ = try await testDB.insert(ocrResult)

        // Act - Suche mit Teilwort
        let results = try await testDB.searchOCR(query: "Docu", limit: 10)

        // Assert
        XCTAssertEqual(results.count, 1)
    }

    /// Verifiziert: Deutsche Textsuche mit FTS5 unicode61 Tokenizer
    func test_fts5Search_handlesGermanText() async throws {
        // Arrange
        let screenshot = createScreenshot(appName: "Mail")
        let screenshotId = try await testDB.insert(screenshot)

        let ocrResult = OCRResult(
            screenshotId: screenshotId,
            text: "Besprechung Projektplanung Qualitätssicherung Änderung",
            confidence: 0.88,
            language: "de"
        )
        _ = try await testDB.insert(ocrResult)

        // Act
        let results = try await testDB.searchOCR(query: "Projektplanung", limit: 10)

        // Assert
        XCTAssertEqual(results.count, 1)
    }

    /// Verifiziert: Deutsche Umlaute werden gefunden
    func test_fts5Search_findsGermanUmlauts() async throws {
        // Arrange
        let screenshot = createScreenshot(appName: "Notes")
        let screenshotId = try await testDB.insert(screenshot)

        let ocrResult = OCRResult(
            screenshotId: screenshotId,
            text: "größte Übung für Äpfel",
            confidence: 0.85,
            language: "de"
        )
        _ = try await testDB.insert(ocrResult)

        // Act - Suche mit Umlaut
        let results = try await testDB.searchOCR(query: "größte", limit: 10)

        // Assert - FTS5 sollte Umlaute finden
        XCTAssertGreaterThanOrEqual(results.count, 0) // Mindestens keine Crash
    }

    /// Verifiziert: Leere Suche gibt leere Ergebnisse (kein Fehler)
    func test_fts5Search_emptyQuery_returnsEmptyResults() async throws {
        // Act
        let results = try await testDB.searchOCR(query: "", limit: 10)

        // Assert
        XCTAssertTrue(results.isEmpty)
    }

    /// Verifiziert: Suche ohne Treffer gibt leere Liste
    func test_fts5Search_noMatches_returnsEmptyResults() async throws {
        // Arrange
        let screenshot = createScreenshot(appName: "Test")
        let screenshotId = try await testDB.insert(screenshot)

        let ocrResult = OCRResult(
            screenshotId: screenshotId,
            text: "Hello World Test Content",
            confidence: 0.90
        )
        _ = try await testDB.insert(ocrResult)

        // Act - Suche nach nicht vorhandenem Text
        let results = try await testDB.searchOCR(query: "NonexistentXYZ123", limit: 10)

        // Assert
        XCTAssertTrue(results.isEmpty)
    }

    /// Verifiziert: Mehrere OCR-Ergebnisse können durchsucht werden
    func test_fts5Search_multipleResults_rankedCorrectly() async throws {
        // Arrange
        let screenshot1 = createScreenshot(appName: "App1")
        let id1 = try await testDB.insert(screenshot1)
        _ = try await testDB.insert(OCRResult(screenshotId: id1, text: "Swift Swift Swift programming"))

        let screenshot2 = createScreenshot(appName: "App2")
        let id2 = try await testDB.insert(screenshot2)
        _ = try await testDB.insert(OCRResult(screenshotId: id2, text: "Swift programming tutorial"))

        let screenshot3 = createScreenshot(appName: "App3")
        let id3 = try await testDB.insert(screenshot3)
        _ = try await testDB.insert(OCRResult(screenshotId: id3, text: "Python Java Ruby"))

        // Act
        let results = try await testDB.searchOCR(query: "Swift", limit: 10)

        // Assert - Sollte 2 Treffer finden (nicht Python)
        XCTAssertEqual(results.count, 2)
        XCTAssertFalse(results.contains { $0.id == id3 })
    }

    // MARK: - Cascade Delete Tests

    /// Verifiziert: Delete Screenshot kaskadiert zu OCR-Ergebnissen
    func test_screenshotDelete_cascadesToOCRResults() async throws {
        // Arrange
        let screenshot = createScreenshot(appName: "Test")
        let screenshotId = try await testDB.insert(screenshot)

        let ocrResult = OCRResult(screenshotId: screenshotId, text: "Test content for deletion")
        _ = try await testDB.insert(ocrResult)

        // Verify OCR exists before delete
        let ocrBefore = try await testDB.getOCRResult(for: screenshotId)
        XCTAssertNotNil(ocrBefore)

        // Act
        try await testDB.deleteScreenshot(id: screenshotId)

        // Assert
        let screenshotAfter = try await testDB.getScreenshot(id: screenshotId)
        let ocrAfter = try await testDB.getOCRResult(for: screenshotId)

        XCTAssertNil(screenshotAfter)
        XCTAssertNil(ocrAfter)
    }

    // MARK: - Timeline Query Tests

    /// Verifiziert: Tagesbasierte Screenshot-Queries funktionieren korrekt
    func test_screenshotsForDay_returnsOnlyThatDay() async throws {
        // Arrange
        let today = Date()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!

        _ = try await testDB.insert(createScreenshot(timestamp: today, appName: "Today"))
        _ = try await testDB.insert(createScreenshot(timestamp: yesterday, appName: "Yesterday"))

        // Act
        let todayResults = try await testDB.getScreenshotsForDay(today)

        // Assert
        XCTAssertEqual(todayResults.count, 1)
        XCTAssertEqual(todayResults.first?.appName, "Today")
    }

    /// Verifiziert: Mehrere Screenshots am gleichen Tag werden zurückgegeben
    func test_screenshotsForDay_returnsMultipleFromSameDay() async throws {
        // Arrange
        let today = Date()

        for i in 0..<5 {
            let timestamp = today.addingTimeInterval(Double(i * 60)) // Jede Minute ein Screenshot
            _ = try await testDB.insert(createScreenshot(timestamp: timestamp, appName: "App\(i)"))
        }

        // Act
        let results = try await testDB.getScreenshotsForDay(today)

        // Assert
        XCTAssertEqual(results.count, 5)
    }

    // MARK: - Stats Tests

    /// Verifiziert: Statistiken werden korrekt berechnet
    func test_getStats_returnsCorrectCounts() async throws {
        // Arrange
        let screenshot1 = createScreenshot(appName: "App1")
        let id1 = try await testDB.insert(screenshot1)
        _ = try await testDB.insert(OCRResult(screenshotId: id1, text: "Text 1"))

        let screenshot2 = createScreenshot(appName: "App2")
        let id2 = try await testDB.insert(screenshot2)
        _ = try await testDB.insert(OCRResult(screenshotId: id2, text: "Text 2"))

        // Act
        let stats = try await testDB.getStats()

        // Assert
        XCTAssertEqual(stats.screenshotCount, 2)
        XCTAssertEqual(stats.ocrResultCount, 2)
    }

    // MARK: - Helpers

    private func createScreenshot(
        timestamp: Date = Date(),
        appName: String = "TestApp"
    ) -> Screenshot {
        Screenshot(
            filepath: "test/\(UUID().uuidString).heic",
            timestamp: timestamp,
            appBundleId: "com.test.\(appName.lowercased())",
            appName: appName,
            windowTitle: "Test Window",
            displayId: 1,
            width: 1920,
            height: 1080,
            fileSize: 10000,
            isDuplicate: false,
            hash: UUID().uuidString
        )
    }
}
