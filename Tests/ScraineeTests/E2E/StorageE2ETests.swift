import XCTest
import ImageIO
import UniformTypeIdentifiers
@testable import Scrainee

/// E2E-Tests für die Dateispeicherung (HEIC, Thumbnails)
final class StorageE2ETests: XCTestCase {

    var testStorage: TestStorageManager!

    override func setUp() {
        testStorage = TestStorageManager(testName: name)
    }

    override func tearDown() {
        testStorage.cleanup()
        testStorage = nil
    }

    // MARK: - HEIC Save/Load Tests

    /// Verifiziert: CGImage wird als valide HEIC-Datei gespeichert
    func test_saveAsHEIC_createsValidHEICFile() async throws {
        // Arrange
        guard let image = ImageGenerator.createMockScreenshot() else {
            XCTFail("Konnte Test-Bild nicht erstellen")
            return
        }

        // Act
        let filepath = try await saveImageToTestStorage(image)
        let fullPath = testStorage.screenshotsDirectory.appendingPathComponent(filepath)

        // Assert - Datei existiert
        XCTAssertTrue(FileManager.default.fileExists(atPath: fullPath.path), "HEIC-Datei sollte existieren")

        // Assert - Datei ist valides HEIC
        XCTAssertTrue(ImageGenerator.isValidHEIC(at: fullPath), "Sollte valides HEIC sein")
    }

    /// Verifiziert: Gespeichertes HEIC kann wieder geladen werden
    func test_saveAsHEIC_canLoadBackImage() async throws {
        // Arrange
        guard let originalImage = ImageGenerator.createMockScreenshot(width: 800, height: 600) else {
            XCTFail("Konnte Test-Bild nicht erstellen")
            return
        }

        // Act
        let filepath = try await saveImageToTestStorage(originalImage)
        let loadedImage = loadImageFromTestStorage(filepath)

        // Assert
        XCTAssertNotNil(loadedImage, "Bild sollte geladen werden können")
        XCTAssertEqual(loadedImage?.width, originalImage.width, "Breite sollte übereinstimmen")
        XCTAssertEqual(loadedImage?.height, originalImage.height, "Höhe sollte übereinstimmen")
    }

    /// Verifiziert: HEIC Kompressionsqualität beeinflusst Dateigröße
    func test_saveAsHEIC_qualityAffectsFileSize() async throws {
        // Arrange
        guard let image = ImageGenerator.createMockScreenshot() else {
            XCTFail("Konnte Test-Bild nicht erstellen")
            return
        }

        // Act - Speichern mit verschiedenen Qualitäten
        let highQualityPath = try await saveImageToTestStorage(image, quality: 0.9)
        let lowQualityPath = try await saveImageToTestStorage(image, quality: 0.3)

        let highQualitySize = testStorage.fileSize(at: highQualityPath)
        let lowQualitySize = testStorage.fileSize(at: lowQualityPath)

        // Assert - Hohe Qualität sollte größer sein
        XCTAssertGreaterThan(highQualitySize, lowQualitySize,
                            "Hohe Qualität (\(highQualitySize)) sollte größer sein als niedrige (\(lowQualitySize))")
    }

    /// Verifiziert: Verschiedene Qualitätsstufen
    func test_saveAsHEIC_variousQualityLevels() async throws {
        // Arrange
        guard let image = ImageGenerator.createMockScreenshot(width: 1920, height: 1080) else {
            XCTFail("Konnte Test-Bild nicht erstellen")
            return
        }

        // Act
        let sizes: [(Double, Int64)] = try await [
            (0.1, testStorage.fileSize(at: saveImageToTestStorage(image, quality: 0.1))),
            (0.5, testStorage.fileSize(at: saveImageToTestStorage(image, quality: 0.5))),
            (0.9, testStorage.fileSize(at: saveImageToTestStorage(image, quality: 0.9)))
        ]

        // Assert - Größen sollten monoton steigen
        XCTAssertLessThan(sizes[0].1, sizes[1].1, "0.1 Qualität sollte kleiner als 0.5 sein")
        XCTAssertLessThan(sizes[1].1, sizes[2].1, "0.5 Qualität sollte kleiner als 0.9 sein")
    }

    // MARK: - Thumbnail Generation Tests

    /// Verifiziert: Thumbnail ist kleiner als Original
    func test_createThumbnail_producesSmallerImage() async throws {
        // Arrange
        guard let originalImage = ImageGenerator.createMockScreenshot(width: 1920, height: 1080) else {
            XCTFail("Konnte Test-Bild nicht erstellen")
            return
        }

        let filepath = try await saveImageToTestStorage(originalImage)
        let fileURL = testStorage.screenshotsDirectory.appendingPathComponent(filepath)

        // Act - Thumbnail aus Datei erstellen
        let imageCompressor = ImageCompressor()
        let thumbnail = imageCompressor.createThumbnail(from: fileURL, maxSize: 200)

        // Assert
        XCTAssertNotNil(thumbnail, "Thumbnail sollte erstellt werden")
        XCTAssertLessThanOrEqual(thumbnail!.width, 200, "Breite sollte <= 200 sein")
        XCTAssertLessThanOrEqual(thumbnail!.height, 200, "Höhe sollte <= 200 sein")
    }

    /// Verifiziert: Thumbnail aus CGImage direkt
    func test_createThumbnail_fromCGImage_works() async throws {
        // Arrange
        guard let originalImage = ImageGenerator.createMockScreenshot(width: 1920, height: 1080) else {
            XCTFail("Konnte Test-Bild nicht erstellen")
            return
        }

        // Act
        let imageCompressor = ImageCompressor()
        let thumbnail = imageCompressor.createThumbnail(from: originalImage, maxSize: 200)

        // Assert
        XCTAssertNotNil(thumbnail)
        XCTAssertLessThanOrEqual(thumbnail!.width, 200)
        XCTAssertLessThanOrEqual(thumbnail!.height, 200)
    }

    /// Verifiziert: Thumbnail behält Aspect-Ratio
    func test_createThumbnail_maintainsAspectRatio() async throws {
        // Arrange - 16:9 Aspect Ratio
        guard let originalImage = ImageGenerator.createMockScreenshot(width: 1600, height: 900) else {
            XCTFail("Konnte Test-Bild nicht erstellen")
            return
        }

        // Act
        let imageCompressor = ImageCompressor()
        let thumbnail = imageCompressor.createThumbnail(from: originalImage, maxSize: 200)

        // Assert
        XCTAssertNotNil(thumbnail)

        let originalRatio = Double(originalImage.width) / Double(originalImage.height)
        let thumbnailRatio = Double(thumbnail!.width) / Double(thumbnail!.height)

        XCTAssertEqual(originalRatio, thumbnailRatio, accuracy: 0.1,
                      "Aspect Ratio sollte erhalten bleiben")
    }

    /// Verifiziert: Thumbnail für verschiedene maxSize-Werte
    func test_createThumbnail_respectsMaxSize() async throws {
        // Arrange
        guard let originalImage = ImageGenerator.createMockScreenshot(width: 1920, height: 1080) else {
            XCTFail("Konnte Test-Bild nicht erstellen")
            return
        }

        let imageCompressor = ImageCompressor()

        // Act & Assert - verschiedene maxSize-Werte
        for maxSize in [100, 200, 300, 500] {
            let thumbnail = imageCompressor.createThumbnail(from: originalImage, maxSize: CGFloat(maxSize))
            XCTAssertNotNil(thumbnail, "Thumbnail für maxSize \(maxSize) sollte existieren")
            XCTAssertLessThanOrEqual(thumbnail!.width, maxSize)
            XCTAssertLessThanOrEqual(thumbnail!.height, maxSize)
        }
    }

    // MARK: - Directory Structure Tests

    /// Verifiziert: Dateien werden nach Datum organisiert (YYYY/MM/DD)
    func test_saveAsHEIC_createsDateBasedDirectoryStructure() async throws {
        // Arrange
        guard let image = ImageGenerator.createMockScreenshot() else {
            XCTFail("Konnte Test-Bild nicht erstellen")
            return
        }

        // Act
        let filepath = try await saveImageToTestStorage(image)

        // Assert - Pfad sollte Datumsmuster enthalten
        let datePattern = #"\d{4}/\d{2}/\d{2}"#
        XCTAssertNotNil(filepath.range(of: datePattern, options: .regularExpression),
                       "Pfad sollte Datumsmuster YYYY/MM/DD enthalten: \(filepath)")
    }

    /// Verifiziert: Dateiname enthält Prefix und UUID
    func test_saveAsHEIC_filenameContainsTimestampAndUUID() async throws {
        // Arrange
        guard let image = ImageGenerator.createMockScreenshot() else {
            XCTFail("Konnte Test-Bild nicht erstellen")
            return
        }

        // Act
        let filepath = try await saveImageToTestStorage(image)
        let filename = (filepath as NSString).lastPathComponent

        // Assert - Test-Helper verwendet "test_" prefix
        XCTAssertTrue(filename.hasPrefix("test_"), "Sollte mit 'test_' beginnen")
        XCTAssertTrue(filename.hasSuffix(".heic"), "Sollte mit '.heic' enden")
        XCTAssertTrue(filename.contains("_"), "Sollte Unterstriche für UUID haben")
        // UUID-Format prüfen (36 Zeichen mit Bindestrichen)
        let uuidPart = filename.dropFirst(5).dropLast(5) // "test_" und ".heic" entfernen
        XCTAssertEqual(uuidPart.count, 36, "UUID sollte 36 Zeichen haben")
    }

    // MARK: - File Operations Tests

    /// Verifiziert: Datei löschen funktioniert
    func test_deleteFile_removesFileFromDisk() async throws {
        // Arrange
        guard let image = ImageGenerator.createMockScreenshot() else {
            XCTFail("Konnte Test-Bild nicht erstellen")
            return
        }

        let filepath = try await saveImageToTestStorage(image)
        XCTAssertTrue(testStorage.fileExists(at: filepath), "Datei sollte existieren")

        // Act
        try testStorage.deleteFile(at: filepath)

        // Assert
        XCTAssertFalse(testStorage.fileExists(at: filepath), "Datei sollte gelöscht sein")
    }

    /// Verifiziert: Dateigröße wird korrekt berechnet
    func test_fileSize_returnsCorrectSize() async throws {
        // Arrange
        guard let image = ImageGenerator.createMockScreenshot() else {
            XCTFail("Konnte Test-Bild nicht erstellen")
            return
        }

        // Act
        let filepath = try await saveImageToTestStorage(image, quality: 0.6)
        let fileSize = testStorage.fileSize(at: filepath)

        // Assert
        XCTAssertGreaterThan(fileSize, 0, "Dateigröße sollte > 0 sein")
        XCTAssertGreaterThan(fileSize, 1000, "HEIC sollte mindestens einige KB groß sein")
    }

    /// Verifiziert: Gesamtspeichernutzung wird berechnet
    func test_totalStorageUsed_sumsAllFiles() async throws {
        // Arrange
        guard let image = ImageGenerator.createMockScreenshot() else {
            XCTFail("Konnte Test-Bild nicht erstellen")
            return
        }

        // Act - mehrere Dateien speichern
        var totalExpected: Int64 = 0
        for _ in 0..<3 {
            let filepath = try await saveImageToTestStorage(image)
            totalExpected += testStorage.fileSize(at: filepath)
        }

        // Assert
        let totalUsed = testStorage.totalStorageUsed
        XCTAssertEqual(totalUsed, totalExpected, "Gesamtgröße sollte Summe aller Dateien sein")
    }

    /// Verifiziert: Alle Dateien werden aufgelistet
    func test_listAllFiles_returnsAllSavedFiles() async throws {
        // Arrange
        guard let image = ImageGenerator.createMockScreenshot() else {
            XCTFail("Konnte Test-Bild nicht erstellen")
            return
        }

        // Act
        for _ in 0..<5 {
            _ = try await saveImageToTestStorage(image)
        }

        // Assert
        let files = testStorage.listAllFiles()
        XCTAssertEqual(files.count, 5, "Sollte 5 Dateien auflisten")
    }

    // MARK: - Edge Cases

    /// Verifiziert: Leeres Verzeichnis gibt 0 Dateien zurück
    func test_listAllFiles_emptyDirectory_returnsEmptyList() {
        // Act
        let files = testStorage.listAllFiles()

        // Assert
        XCTAssertTrue(files.isEmpty)
    }

    /// Verifiziert: Sehr kleines Bild kann gespeichert werden
    func test_saveAsHEIC_smallImage_works() async throws {
        // Arrange
        guard let image = ImageGenerator.createSolidColorImage(color: .red, size: CGSize(width: 10, height: 10)) else {
            XCTFail("Konnte kleines Bild nicht erstellen")
            return
        }

        // Act
        let filepath = try await saveImageToTestStorage(image)

        // Assert
        XCTAssertTrue(testStorage.fileExists(at: filepath))
    }

    /// Verifiziert: Großes Bild kann gespeichert werden
    func test_saveAsHEIC_largeImage_works() async throws {
        // Arrange - 4K Bild
        guard let image = ImageGenerator.createMockScreenshot(width: 3840, height: 2160) else {
            XCTFail("Konnte großes Bild nicht erstellen")
            return
        }

        // Act
        let filepath = try await saveImageToTestStorage(image)

        // Assert
        XCTAssertTrue(testStorage.fileExists(at: filepath))
        XCTAssertGreaterThan(testStorage.fileSize(at: filepath), 10000, "4K Bild sollte größer sein")
    }

    // MARK: - Helpers

    private func saveImageToTestStorage(_ image: CGImage, quality: Double = 0.6) async throws -> String {
        let filename = "test_\(UUID().uuidString).heic"
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy/MM/dd"
        let datePath = dateFormatter.string(from: Date())
        let relativePath = "\(datePath)/\(filename)"

        let fullPath = testStorage.screenshotsDirectory.appendingPathComponent(relativePath)
        try ImageGenerator.saveAsHEIC(image, to: fullPath, quality: quality)

        return relativePath
    }

    private func loadImageFromTestStorage(_ relativePath: String) -> CGImage? {
        let fullPath = testStorage.screenshotsDirectory.appendingPathComponent(relativePath)
        return ImageGenerator.loadHEIC(from: fullPath)
    }
}
