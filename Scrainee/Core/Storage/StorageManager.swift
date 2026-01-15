import Foundation

/// Manages file system storage for Scrainee
final class StorageManager: @unchecked Sendable {
    static let shared = StorageManager()

    // MARK: - Directories

    /// Main application support directory
    var applicationSupportDirectory: URL {
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let appSupport = paths.first!.appendingPathComponent("Scrainee", isDirectory: true)
        ensureDirectoryExists(appSupport)
        return appSupport
    }

    /// Alias for backward compatibility
    var appSupportDirectory: URL {
        applicationSupportDirectory
    }

    /// Screenshots storage directory
    var screenshotsDirectory: URL {
        let dir = applicationSupportDirectory.appendingPathComponent("screenshots", isDirectory: true)
        ensureDirectoryExists(dir)
        return dir
    }

    /// Database file URL
    var databaseURL: URL {
        applicationSupportDirectory.appendingPathComponent("scrainee.sqlite")
    }

    /// Config file URL
    var configURL: URL {
        applicationSupportDirectory.appendingPathComponent("config.json")
    }

    // MARK: - Initialization

    private init() {
        setupDirectories()
    }

    private func setupDirectories() {
        ensureDirectoryExists(applicationSupportDirectory)
        ensureDirectoryExists(screenshotsDirectory)
    }

    // MARK: - Directory Management

    /// Ensures a directory exists, creating it if necessary
    func ensureDirectoryExists(_ url: URL) {
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    /// Ensures the parent directory of a file exists
    func ensureDirectoryExists(for fileURL: URL) throws {
        let directory = fileURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    // MARK: - Storage Stats

    /// Total size of screenshots directory in bytes
    var screenshotsStorageSize: Int64 {
        calculateDirectorySize(screenshotsDirectory)
    }

    /// Calculates storage used (alias for screenshotsStorageSize for backward compatibility)
    func calculateStorageUsed() -> Int64 {
        screenshotsStorageSize
    }

    /// Total size of database in bytes
    var databaseSize: Int64 {
        let attrs = try? FileManager.default.attributesOfItem(atPath: databaseURL.path)
        return (attrs?[.size] as? Int64) ?? 0
    }

    /// Total storage used by Scrainee in bytes
    var totalStorageUsed: Int64 {
        screenshotsStorageSize + databaseSize
    }

    /// Formatted string of total storage used
    var formattedStorageUsed: String {
        ByteCountFormatter.string(fromByteCount: totalStorageUsed, countStyle: .file)
    }

    /// Formatted string of screenshots storage
    var formattedScreenshotsStorage: String {
        ByteCountFormatter.string(fromByteCount: screenshotsStorageSize, countStyle: .file)
    }

    // MARK: - File Operations

    /// Deletes a screenshot file
    func deleteScreenshot(at relativePath: String) throws {
        let url = screenshotsDirectory.appendingPathComponent(relativePath)
        try FileManager.default.removeItem(at: url)

        // Clean up empty parent directories
        cleanupEmptyDirectories(from: url.deletingLastPathComponent())
    }

    /// Deletes multiple screenshot files
    func deleteScreenshots(at relativePaths: [String]) throws {
        for path in relativePaths {
            try? deleteScreenshot(at: path)
        }
    }

    /// Clears all screenshots
    func clearAllScreenshots() throws {
        try FileManager.default.removeItem(at: screenshotsDirectory)
        ensureDirectoryExists(screenshotsDirectory)
    }

    // MARK: - Cleanup

    /// Removes empty directories up to the screenshots root
    private func cleanupEmptyDirectories(from directory: URL) {
        guard directory.path.hasPrefix(screenshotsDirectory.path),
              directory != screenshotsDirectory else {
            return
        }

        let contents = try? FileManager.default.contentsOfDirectory(atPath: directory.path)
        if contents?.isEmpty == true {
            try? FileManager.default.removeItem(at: directory)
            cleanupEmptyDirectories(from: directory.deletingLastPathComponent())
        }
    }

    // MARK: - Helpers

    private func calculateDirectorySize(_ directory: URL) -> Int64 {
        let resourceKeys: Set<URLResourceKey> = [.isDirectoryKey, .fileSizeKey]
        var totalSize: Int64 = 0

        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles],
            errorHandler: nil
        ) else {
            return 0
        }

        for case let fileURL as URL in enumerator {
            guard let resourceValues = try? fileURL.resourceValues(forKeys: resourceKeys),
                  let isDirectory = resourceValues.isDirectory,
                  !isDirectory,
                  let fileSize = resourceValues.fileSize else {
                continue
            }
            totalSize += Int64(fileSize)
        }

        return totalSize
    }

    // MARK: - Available Space

    /// Available disk space in bytes
    var availableDiskSpace: Int64 {
        let fileURL = applicationSupportDirectory
        do {
            let values = try fileURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            return values.volumeAvailableCapacityForImportantUsage ?? 0
        } catch {
            return 0
        }
    }

    /// Formatted available disk space
    var formattedAvailableDiskSpace: String {
        ByteCountFormatter.string(fromByteCount: availableDiskSpace, countStyle: .file)
    }

    /// Checks if there's enough space for continued capture
    func hasEnoughSpace(minimumGB: Double = 1.0) -> Bool {
        let minimumBytes = Int64(minimumGB * 1_073_741_824) // 1 GB
        return availableDiskSpace > minimumBytes
    }
}
