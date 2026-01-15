import Foundation
import GRDB

/// Represents a search result combining screenshot and OCR data
struct SearchResult: Codable, Identifiable {
    var id: Int64
    var filepath: String
    var timestamp: Date
    var appName: String?
    var appBundleId: String?
    var windowTitle: String?
    var text: String
    var highlightedText: String?

    // MARK: - Computed Properties

    /// Full URL to the screenshot file
    var fileURL: URL {
        StorageManager.shared.screenshotsDirectory.appendingPathComponent(filepath)
    }

    /// Thumbnail URL (same as file URL for now)
    var thumbnailURL: URL {
        fileURL
    }

    /// Formatted timestamp
    var formattedTimestamp: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: timestamp, relativeTo: Date())
    }
}

// MARK: - GRDB Conformance

extension SearchResult: FetchableRecord {
    init(row: Row) {
        id = row["id"]
        filepath = row["filepath"]
        timestamp = row["timestamp"]
        appName = row["appName"]
        appBundleId = row["appBundleId"]
        windowTitle = row["windowTitle"]
        text = row["text"]
        highlightedText = row["highlightedText"]
    }
}
