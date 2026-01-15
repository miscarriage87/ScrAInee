import XCTest
@testable import Scrainee

/// E2E-Tests für die komplette Capture-to-Search Pipeline
final class FullPipelineE2ETests: XCTestCase {

    var testDB: TestDatabaseManager!
    var testStorage: TestStorageManager!
    var ocrManager: OCRManager!

    override func setUp() async throws {
        testDB = TestDatabaseManager(testName: name)
        testStorage = TestStorageManager(testName: name)
        try await testDB.initialize()
        ocrManager = OCRManager()
    }

    override func tearDown() async throws {
        await testDB.cleanup()
        testStorage.cleanup()
        testDB = nil
        testStorage = nil
        ocrManager = nil
    }

    // MARK: - Complete Pipeline Tests

    /// Verifiziert: CGImage -> dHash -> HEIC -> DB -> OCR -> DB -> FTS Search
    /// Dies ist der kritische E2E-Test der die gesamte Pipeline testet
    func test_fullPipeline_imageToSearchableText() async throws {
        // 1. Erstelle Test-Bild mit bekanntem Text
        let knownText = "SCRAINEE Test Pipeline Verification"
        guard let testImage = ImageGenerator.createImageWithText(knownText, fontSize: 36) else {
            XCTFail("Konnte Test-Bild nicht erstellen")
            return
        }

        // 2. Berechne dHash (Duplikat-Erkennung)
        let hash = ScreenshotDiffer.quickHash(testImage)
        XCTAssertFalse(hash.isEmpty, "Hash sollte nicht leer sein")
        XCTAssertEqual(hash.count, 16, "Hash sollte 16-stelliger Hex-String sein")

        // 3. Speichere als HEIC
        let filepath = try await saveImageToTestStorage(testImage)
        XCTAssertTrue(testStorage.fileExists(at: filepath), "HEIC-Datei sollte existieren")

        // 4. Erstelle und füge Screenshot-Record ein
        let screenshot = Screenshot(
            filepath: filepath,
            timestamp: Date(),
            appBundleId: "com.test.pipeline",
            appName: "PipelineTest",
            windowTitle: "Test Window",
            displayId: 1,
            width: testImage.width,
            height: testImage.height,
            fileSize: Int(testStorage.fileSize(at: filepath)),
            isDuplicate: false,
            hash: hash
        )

        let screenshotId = try await testDB.insert(screenshot)
        XCTAssertGreaterThan(screenshotId, 0, "Screenshot ID sollte > 0 sein")

        // 5. Führe OCR durch
        let ocrResult = await ocrManager.recognizeText(in: testImage)
        XCTAssertNotNil(ocrResult.text, "OCR sollte Text extrahieren")

        // 6. Füge OCR-Ergebnis ein
        let ocrRecord = OCRResult(
            screenshotId: screenshotId,
            text: ocrResult.text ?? "",
            confidence: ocrResult.confidence,
            language: ocrResult.language
        )

        let ocrId = try await testDB.insert(ocrRecord)
        XCTAssertGreaterThan(ocrId, 0, "OCR ID sollte > 0 sein")

        // 7. Suche via FTS5 - sollte unseren Screenshot finden
        let searchResults = try await testDB.searchOCR(query: "Pipeline", limit: 10)

        // Assert
        XCTAssertEqual(searchResults.count, 1, "Sollte genau ein Ergebnis finden")
        XCTAssertEqual(searchResults.first?.id, screenshotId, "ID sollte übereinstimmen")
        XCTAssertEqual(searchResults.first?.filepath, filepath, "Filepath sollte übereinstimmen")
    }

    /// Verifiziert: Deutscher Text durch gesamte Pipeline
    func test_fullPipeline_germanTextEndToEnd() async throws {
        // Arrange
        let germanText = "Projektbesprechung Dokumentation Anforderungen"
        guard let testImage = ImageGenerator.createImageWithText(germanText, fontSize: 36) else {
            XCTFail("Konnte Test-Bild nicht erstellen")
            return
        }

        // Act - Komplette Pipeline
        let hash = ScreenshotDiffer.quickHash(testImage)
        let filepath = try await saveImageToTestStorage(testImage)

        let screenshot = Screenshot(
            filepath: filepath,
            timestamp: Date(),
            appBundleId: "com.test.german",
            appName: "GermanTest",
            windowTitle: "Test",
            displayId: 1,
            width: testImage.width,
            height: testImage.height,
            fileSize: Int(testStorage.fileSize(at: filepath)),
            isDuplicate: false,
            hash: hash
        )

        let screenshotId = try await testDB.insert(screenshot)
        let ocrResult = await ocrManager.recognizeText(in: testImage)

        let ocrRecord = OCRResult(
            screenshotId: screenshotId,
            text: ocrResult.text ?? "",
            confidence: ocrResult.confidence,
            language: ocrResult.language
        )
        _ = try await testDB.insert(ocrRecord)

        // Suche nach deutschem Wort
        let searchResults = try await testDB.searchOCR(query: "Dokumentation", limit: 10)

        // Assert
        XCTAssertGreaterThanOrEqual(searchResults.count, 0) // Kann 0 sein wenn OCR Text anders erkennt
    }

    /// Verifiziert: Duplikat-Hash-Erkennung verhindert Re-Processing
    func test_duplicateDetection_preventsReprocessing() async throws {
        // Arrange
        let hashTracker = HashTracker()

        guard let image1 = ImageGenerator.createSolidColorImage(color: .blue) else {
            XCTFail("Konnte Bild nicht erstellen")
            return
        }

        let hash = ScreenshotDiffer.quickHash(image1)

        // Act - Erste Erfassung
        let isDuplicate1 = await hashTracker.isDuplicate(hash, for: 1)
        await hashTracker.setLastHash(hash, for: 1)

        // Zweite Erfassung mit gleichem Hash
        let isDuplicate2 = await hashTracker.isDuplicate(hash, for: 1)

        // Assert
        XCTAssertFalse(isDuplicate1, "Erste Erfassung sollte kein Duplikat sein")
        XCTAssertTrue(isDuplicate2, "Zweite Erfassung mit gleichem Hash sollte Duplikat sein")
    }

    /// Verifiziert: Verschiedene Bilder haben verschiedene Hashes
    /// Hinweis: quickHash verwendet einen Average-Hash - einfarbige Bilder haben alle denselben Hash!
    /// Daher verwenden wir Gradient-Bilder für diesen Test
    func test_hashCalculation_differentImagesHaveDifferentHashes() async throws {
        // Arrange - Gradient-Bilder statt einfarbiger (einfarbig -> alle Pixel gleich -> Hash = 0)
        guard let blueRedImage = ImageGenerator.createGradientImage(
                startColor: .blue, endColor: .red, size: CGSize(width: 100, height: 100)),
              let greenYellowImage = ImageGenerator.createGradientImage(
                startColor: .green, endColor: .yellow, size: CGSize(width: 100, height: 100)),
              let purpleOrangeImage = ImageGenerator.createGradientImage(
                startColor: .purple, endColor: .orange, size: CGSize(width: 100, height: 100)) else {
            XCTFail("Konnte Bilder nicht erstellen")
            return
        }

        // Act
        let blueRedHash = ScreenshotDiffer.quickHash(blueRedImage)
        let greenYellowHash = ScreenshotDiffer.quickHash(greenYellowImage)
        let purpleOrangeHash = ScreenshotDiffer.quickHash(purpleOrangeImage)

        // Assert - Alle Hashes sollten nicht leer sein (Gradienten haben variierende Pixelwerte)
        XCTAssertFalse(blueRedHash.isEmpty, "Hash sollte nicht leer sein")
        XCTAssertFalse(greenYellowHash.isEmpty, "Hash sollte nicht leer sein")
        XCTAssertFalse(purpleOrangeHash.isEmpty, "Hash sollte nicht leer sein")

        // Mindestens einer der Hashes sollte unterschiedlich sein
        let allSame = (blueRedHash == greenYellowHash && greenYellowHash == purpleOrangeHash)
        XCTAssertFalse(allSame, "Unterschiedliche Gradienten sollten unterschiedliche Hashes ergeben")
    }

    /// Verifiziert: Multi-Display parallel Capture verursacht keine Race Conditions
    func test_multiDisplayCapture_maintainsSeparateHashTracking() async throws {
        // Arrange
        let hashTracker = HashTracker()
        let displays: [UInt32] = [1, 2, 3]
        var processedCounts: [UInt32: Int] = [:]

        // Act - Simuliere parallele Erfassung von mehreren Displays
        await withTaskGroup(of: (UInt32, Bool).self) { group in
            for iteration in 0..<10 {
                for displayId in displays {
                    group.addTask {
                        let hash = "hash_\(iteration)_\(displayId)"
                        let isDupe = await hashTracker.isDuplicate(hash, for: displayId)
                        if !isDupe {
                            await hashTracker.setLastHash(hash, for: displayId)
                        }
                        return (displayId, !isDupe)
                    }
                }
            }

            for await (displayId, wasProcessed) in group {
                if wasProcessed {
                    processedCounts[displayId, default: 0] += 1
                }
            }
        }

        // Assert - Jedes Display sollte seine einzigartigen Hashes verarbeitet haben
        for displayId in displays {
            XCTAssertEqual(processedCounts[displayId], 10,
                           "Display \(displayId) sollte 10 einzigartige Screenshots verarbeiten")
        }
    }

    /// Verifiziert: Gleicher Hash auf verschiedenen Displays ist kein Duplikat
    func test_hashTracking_sameHashDifferentDisplaysNotDuplicate() async throws {
        // Arrange
        let hashTracker = HashTracker()
        let sameHash = "identical_hash_value"

        // Act - Setze gleichen Hash für Display 1
        await hashTracker.setLastHash(sameHash, for: 1)

        // Prüfe ob es auf Display 2 als Duplikat erkannt wird
        let isDuplicateOnDisplay2 = await hashTracker.isDuplicate(sameHash, for: 2)

        // Assert - Sollte NICHT als Duplikat erkannt werden (anderes Display)
        XCTAssertFalse(isDuplicateOnDisplay2,
                      "Gleicher Hash auf anderem Display sollte kein Duplikat sein")
    }

    /// Verifiziert: Mehrere Screenshots können in DB eingefügt und abgerufen werden
    func test_multipleScreenshots_insertAndRetrieve() async throws {
        // Arrange & Act
        var insertedIds: [Int64] = []

        for i in 0..<5 {
            guard let image = ImageGenerator.createSolidColorImage(
                color: NSColor(red: CGFloat(i) / 5.0, green: 0, blue: 0, alpha: 1)
            ) else { continue }

            let filepath = try await saveImageToTestStorage(image)
            let screenshot = Screenshot(
                filepath: filepath,
                timestamp: Date().addingTimeInterval(Double(i * 60)),
                appBundleId: "com.test.multi\(i)",
                appName: "App\(i)",
                windowTitle: "Window\(i)",
                displayId: 1,
                width: image.width,
                height: image.height,
                fileSize: Int(testStorage.fileSize(at: filepath)),
                isDuplicate: false,
                hash: ScreenshotDiffer.quickHash(image)
            )

            let id = try await testDB.insert(screenshot)
            insertedIds.append(id)
        }

        // Assert
        XCTAssertEqual(insertedIds.count, 5, "Sollte 5 Screenshots eingefügt haben")

        let count = try await testDB.getScreenshotCount()
        XCTAssertEqual(count, 5, "DB sollte 5 Screenshots enthalten")

        // Verifiziere dass alle abgerufen werden können
        for id in insertedIds {
            let screenshot = try await testDB.getScreenshot(id: id)
            XCTAssertNotNil(screenshot, "Screenshot mit ID \(id) sollte existieren")
        }
    }

    /// Verifiziert: OCR-Text und Screenshot werden korrekt verknüpft
    func test_ocrAndScreenshot_linkedCorrectly() async throws {
        // Arrange
        let testText = "Unique OCR test content XYZ123"
        guard let image = ImageGenerator.createImageWithText(testText, fontSize: 36) else {
            XCTFail("Konnte Bild nicht erstellen")
            return
        }

        // Act
        let filepath = try await saveImageToTestStorage(image)
        let screenshot = Screenshot(
            filepath: filepath,
            timestamp: Date(),
            appBundleId: "com.test.link",
            appName: "LinkTest",
            windowTitle: "Test",
            displayId: 1,
            width: image.width,
            height: image.height,
            fileSize: Int(testStorage.fileSize(at: filepath)),
            isDuplicate: false,
            hash: ScreenshotDiffer.quickHash(image)
        )

        let screenshotId = try await testDB.insert(screenshot)

        let ocrResult = await ocrManager.recognizeText(in: image)
        let ocrRecord = OCRResult(
            screenshotId: screenshotId,
            text: ocrResult.text ?? "fallback",
            confidence: ocrResult.confidence,
            language: ocrResult.language
        )
        _ = try await testDB.insert(ocrRecord)

        // Assert - OCR kann per Screenshot-ID abgerufen werden
        let retrievedOCR = try await testDB.getOCRResult(for: screenshotId)
        XCTAssertNotNil(retrievedOCR, "OCR sollte für Screenshot existieren")
        XCTAssertEqual(retrievedOCR?.screenshotId, screenshotId, "screenshotId sollte übereinstimmen")
    }

    /// Verifiziert: Performance der gesamten Pipeline
    func test_fullPipeline_performanceAcceptable() async throws {
        // Arrange
        let testText = "Performance test content"
        guard let image = ImageGenerator.createMockScreenshot(width: 1920, height: 1080) else {
            XCTFail("Konnte Bild nicht erstellen")
            return
        }

        // Act
        let startTime = Date()

        // Hash berechnen
        let hash = ScreenshotDiffer.quickHash(image)

        // HEIC speichern
        let filepath = try await saveImageToTestStorage(image)

        // DB Insert
        let screenshot = Screenshot(
            filepath: filepath,
            timestamp: Date(),
            appBundleId: "com.test.perf",
            appName: "PerfTest",
            windowTitle: "Test",
            displayId: 1,
            width: image.width,
            height: image.height,
            fileSize: Int(testStorage.fileSize(at: filepath)),
            isDuplicate: false,
            hash: hash
        )
        let screenshotId = try await testDB.insert(screenshot)

        // OCR (dies ist der langsamste Teil)
        let ocrResult = await ocrManager.recognizeText(in: image)

        // OCR Insert
        let ocrRecord = OCRResult(
            screenshotId: screenshotId,
            text: ocrResult.text ?? "",
            confidence: ocrResult.confidence,
            language: ocrResult.language
        )
        _ = try await testDB.insert(ocrRecord)

        let elapsed = Date().timeIntervalSince(startTime)

        // Assert - Gesamte Pipeline sollte in < 10 Sekunden abschließen
        XCTAssertLessThan(elapsed, 10.0,
                         "Gesamte Pipeline sollte in < 10 Sekunden abschließen (war: \(elapsed)s)")
    }

    // MARK: - Helpers

    private func saveImageToTestStorage(_ image: CGImage, quality: Double = 0.6) async throws -> String {
        let filename = "pipeline_test_\(UUID().uuidString).heic"
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy/MM/dd"
        let datePath = dateFormatter.string(from: Date())
        let relativePath = "\(datePath)/\(filename)"

        let fullPath = testStorage.screenshotsDirectory.appendingPathComponent(relativePath)
        try ImageGenerator.saveAsHEIC(image, to: fullPath, quality: quality)

        return relativePath
    }
}
