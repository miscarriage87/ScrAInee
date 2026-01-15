import Foundation
@testable import Scrainee

/// Isolierter Storage für E2E-Tests - verwendet temporäres Verzeichnis
final class TestStorageManager: @unchecked Sendable {
    let testDirectory: URL
    let screenshotsDirectory: URL
    let databaseURL: URL

    init(testName: String) {
        let tempDir = FileManager.default.temporaryDirectory
        let uniqueId = UUID().uuidString
        testDirectory = tempDir.appendingPathComponent("ScraineeTests/\(testName)/\(uniqueId)")
        screenshotsDirectory = testDirectory.appendingPathComponent("screenshots")
        databaseURL = testDirectory.appendingPathComponent("test.sqlite")

        // Erstelle Verzeichnisse
        try? FileManager.default.createDirectory(at: screenshotsDirectory, withIntermediateDirectories: true)
    }

    /// Räumt alle Test-Dateien auf
    func cleanup() {
        try? FileManager.default.removeItem(at: testDirectory)
    }

    /// Erstellt ein Datumsbasiertes Unterverzeichnis (YYYY/MM/DD)
    func createDateDirectory(for date: Date = Date()) throws -> URL {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy/MM/dd"
        let datePath = dateFormatter.string(from: date)
        let directory = screenshotsDirectory.appendingPathComponent(datePath)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Gibt den relativen Pfad für eine Datei zurück
    func relativePath(for url: URL) -> String {
        url.path.replacingOccurrences(of: screenshotsDirectory.path + "/", with: "")
    }

    /// Prüft ob eine Datei existiert
    func fileExists(at relativePath: String) -> Bool {
        let fullPath = screenshotsDirectory.appendingPathComponent(relativePath)
        return FileManager.default.fileExists(atPath: fullPath.path)
    }

    /// Gibt die Dateigröße zurück
    func fileSize(at relativePath: String) -> Int64 {
        let fullPath = screenshotsDirectory.appendingPathComponent(relativePath)
        let attrs = try? FileManager.default.attributesOfItem(atPath: fullPath.path)
        return (attrs?[.size] as? Int64) ?? 0
    }

    /// Löscht eine Datei
    func deleteFile(at relativePath: String) throws {
        let fullPath = screenshotsDirectory.appendingPathComponent(relativePath)
        try FileManager.default.removeItem(at: fullPath)
    }

    /// Listet alle Dateien im Screenshots-Verzeichnis
    func listAllFiles() -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: screenshotsDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var files: [URL] = []
        for case let fileURL as URL in enumerator {
            if (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
                files.append(fileURL)
            }
        }
        return files
    }

    /// Gesamtgröße aller Dateien
    var totalStorageUsed: Int64 {
        listAllFiles().reduce(0) { total, url in
            let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
            return total + ((attrs?[.size] as? Int64) ?? 0)
        }
    }
}
