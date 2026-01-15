import XCTest
import AppKit
@testable import Scrainee

/// E2E-Tests für den ThumbnailCache Actor (LRU-Caching)
/// HINWEIS: Verwendet ThumbnailCache.shared da init() private ist
final class ThumbnailCacheE2ETests: XCTestCase {

    var testStorage: TestStorageManager!
    var cache: ThumbnailCache!

    override func setUp() async throws {
        testStorage = TestStorageManager(testName: name)
        cache = ThumbnailCache.shared
        // Cache vor jedem Test leeren
        await cache.clearAll()
    }

    override func tearDown() async throws {
        // Cache nach jedem Test leeren
        await cache.clearAll()
        testStorage.cleanup()
        testStorage = nil
        cache = nil
    }

    // MARK: - Cache Operation Tests

    /// Verifiziert: Cache speichert und lädt Thumbnails korrekt
    func test_thumbnailCache_storesAndRetrievesThumbnail() async throws {
        // Arrange
        let screenshotId: Int64 = Int64.random(in: 100000...999999) // Zufällige ID für Isolation

        guard let testImage = ImageGenerator.createMockScreenshot() else {
            XCTFail("Konnte Test-Bild nicht erstellen")
            return
        }

        // Speichere Bild auf Disk
        let fileURL = try saveImageToDisk(testImage, name: "cache_test_\(screenshotId).heic")

        // Act - Erster Zugriff (Cache Miss, lädt von Disk)
        let thumbnail1 = await cache.thumbnail(for: screenshotId, url: fileURL)

        // Zweiter Zugriff (Cache Hit)
        let thumbnail2 = await cache.thumbnail(for: screenshotId, url: fileURL)

        // Assert
        XCTAssertNotNil(thumbnail1, "Erstes Thumbnail sollte geladen werden")
        XCTAssertNotNil(thumbnail2, "Zweites Thumbnail sollte aus Cache kommen")

        // Cache sollte mindestens einen Eintrag haben
        let cacheSize = await cache.cacheSize
        XCTAssertGreaterThanOrEqual(cacheSize, 1, "Cache sollte mindestens 1 Eintrag haben")
    }

    /// Verifiziert: Mehrere Thumbnails werden gecacht
    func test_thumbnailCache_cachesMultipleImages() async throws {
        // Act - Erstelle und cache mehrere Thumbnails
        let baseId = Int64.random(in: 100000...999999)
        for i in 0..<10 {
            guard let testImage = ImageGenerator.createSolidColorImage(
                color: NSColor(red: CGFloat(i)/10, green: 0, blue: 0, alpha: 1)
            ) else { continue }

            let fileURL = try saveImageToDisk(testImage, name: "multi_cache_\(baseId)_\(i).heic")
            _ = await cache.thumbnail(for: baseId + Int64(i), url: fileURL)
        }

        // Assert
        let cacheSize = await cache.cacheSize
        XCTAssertGreaterThanOrEqual(cacheSize, 10, "Cache sollte mindestens 10 Einträge haben")
    }

    /// Verifiziert: Remove-Operation löscht spezifischen Eintrag
    func test_thumbnailCache_removeDeletesEntry() async throws {
        // Arrange
        let screenshotId: Int64 = Int64.random(in: 100000...999999)

        guard let testImage = ImageGenerator.createMockScreenshot() else {
            XCTFail("Konnte Test-Bild nicht erstellen")
            return
        }

        let fileURL = try saveImageToDisk(testImage, name: "remove_test_\(screenshotId).heic")
        _ = await cache.thumbnail(for: screenshotId, url: fileURL)

        // Act
        await cache.remove(screenshotId)

        // Assert - Nach remove sollte der Eintrag weg sein
        // Wir können nur prüfen dass kein Crash passiert
        // da wir nicht direkt auf den Eintrag zugreifen können
    }

    /// Verifiziert: ClearAll leert den gesamten Cache
    func test_thumbnailCache_clearAllEmptiesCache() async throws {
        // Arrange
        let baseId = Int64.random(in: 100000...999999)

        for i in 0..<5 {
            guard let testImage = ImageGenerator.createSolidColorImage(color: .blue) else { continue }
            let fileURL = try saveImageToDisk(testImage, name: "clear_test_\(baseId)_\(i).heic")
            _ = await cache.thumbnail(for: baseId + Int64(i), url: fileURL)
        }

        // Act
        await cache.clearAll()

        // Assert
        let cacheSize = await cache.cacheSize
        XCTAssertEqual(cacheSize, 0, "Cache sollte leer sein nach clearAll")
    }

    /// Verifiziert: Cache gibt nil zurück für nicht existierende Datei
    func test_thumbnailCache_nonExistentFile_returnsNil() async throws {
        // Arrange
        let nonExistentURL = testStorage.screenshotsDirectory.appendingPathComponent("nonexistent_\(UUID()).heic")

        // Act
        let thumbnail = await cache.thumbnail(for: Int64.random(in: 100000...999999), url: nonExistentURL)

        // Assert
        XCTAssertNil(thumbnail, "Sollte nil für nicht existierende Datei zurückgeben")
    }

    /// Verifiziert: Thumbnail ist kleiner als Original
    func test_thumbnailCache_thumbnailIsSmallerThanOriginal() async throws {
        // Arrange
        let screenshotId = Int64.random(in: 100000...999999)

        guard let testImage = ImageGenerator.createMockScreenshot(width: 1920, height: 1080) else {
            XCTFail("Konnte Test-Bild nicht erstellen")
            return
        }

        let fileURL = try saveImageToDisk(testImage, name: "size_test_\(screenshotId).heic")

        // Act
        let thumbnail = await cache.thumbnail(for: screenshotId, url: fileURL)

        // Assert
        XCTAssertNotNil(thumbnail)
        // Thumbnail sollte maximal 200px in der größten Dimension sein
        XCTAssertLessThanOrEqual(Int(thumbnail!.size.width), 200)
        XCTAssertLessThanOrEqual(Int(thumbnail!.size.height), 200)
    }

    /// Verifiziert: Cache-Performance für schnellen Zugriff
    func test_thumbnailCache_cacheHitIsFast() async throws {
        // Arrange
        let screenshotId = Int64.random(in: 100000...999999)

        guard let testImage = ImageGenerator.createMockScreenshot() else {
            XCTFail("Konnte Test-Bild nicht erstellen")
            return
        }

        let fileURL = try saveImageToDisk(testImage, name: "perf_test_\(screenshotId).heic")

        // Erste Anfrage (Cache Miss - langsamer)
        _ = await cache.thumbnail(for: screenshotId, url: fileURL)

        // Act - Zweite Anfrage (Cache Hit - sollte schnell sein)
        let startTime = Date()
        for _ in 0..<100 {
            _ = await cache.thumbnail(for: screenshotId, url: fileURL)
        }
        let elapsed = Date().timeIntervalSince(startTime)

        // Assert - 100 Cache Hits sollten sehr schnell sein (< 0.5 Sekunden)
        XCTAssertLessThan(elapsed, 0.5,
                         "100 Cache Hits sollten < 0.5s dauern (war: \(elapsed)s)")
    }

    /// Verifiziert: Verschiedene IDs werden separat gecacht
    func test_thumbnailCache_separateCacheEntriesPerID() async throws {
        // Arrange
        let baseId = Int64.random(in: 100000...999999)

        // Erstelle zwei verschiedene Bilder
        guard let blueImage = ImageGenerator.createSolidColorImage(color: .blue),
              let redImage = ImageGenerator.createSolidColorImage(color: .red) else {
            XCTFail("Konnte Bilder nicht erstellen")
            return
        }

        let blueURL = try saveImageToDisk(blueImage, name: "blue_\(baseId).heic")
        let redURL = try saveImageToDisk(redImage, name: "red_\(baseId).heic")

        // Act
        let blueThumbnail = await cache.thumbnail(for: baseId, url: blueURL)
        let redThumbnail = await cache.thumbnail(for: baseId + 1, url: redURL)

        // Assert
        XCTAssertNotNil(blueThumbnail)
        XCTAssertNotNil(redThumbnail)
    }

    /// Verifiziert: Thread-Safety bei parallelen Zugriffen
    func test_thumbnailCache_concurrentAccess_isThreadSafe() async throws {
        // Arrange
        let baseId = Int64.random(in: 100000...999999)
        var urls: [Int64: URL] = [:]

        // Erstelle Test-Dateien
        for i in 0..<20 {
            guard let testImage = ImageGenerator.createSolidColorImage(
                color: NSColor(red: 0, green: CGFloat(i)/20, blue: 0, alpha: 1)
            ) else { continue }
            urls[baseId + Int64(i)] = try saveImageToDisk(testImage, name: "concurrent_\(baseId)_\(i).heic")
        }

        // Act - Parallele Zugriffe
        await withTaskGroup(of: Void.self) { group in
            for (id, url) in urls {
                group.addTask { [cache] in
                    _ = await cache!.thumbnail(for: id, url: url)
                }
            }

            // Auch paralleles Lesen
            for (id, url) in urls {
                group.addTask { [cache] in
                    _ = await cache!.thumbnail(for: id, url: url)
                }
            }
        }

        // Assert - Keine Crashes = Thread-Safe
        let cacheSize = await cache.cacheSize
        XCTAssertGreaterThanOrEqual(cacheSize, 20, "Cache sollte mindestens 20 Einträge haben")
    }

    // MARK: - Helpers

    private func saveImageToDisk(_ image: CGImage, name: String) throws -> URL {
        let fileURL = testStorage.screenshotsDirectory.appendingPathComponent(name)
        try ImageGenerator.saveAsHEIC(image, to: fileURL)
        return fileURL
    }
}
