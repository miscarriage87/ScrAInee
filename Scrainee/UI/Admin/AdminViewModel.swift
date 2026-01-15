import SwiftUI
import Combine

/// ViewModel for the Admin Dashboard
@MainActor
class AdminViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var stats = AppStats()
    @Published var dailyStats: [DailyStat] = []
    @Published var storageBreakdown: [StorageItem] = []
    @Published var recentMeetings: [Meeting] = []
    @Published var isLoading = false
    @Published var lastUpdate = Date()
    @Published var errorMessage: String?

    // MARK: - Stats Structure

    struct AppStats {
        var totalScreenshots: Int = 0
        var totalMeetings: Int = 0
        var storageUsedBytes: Int64 = 0
        var averageDailyScreenshots: Int = 0
        var ocrProcessed: Int = 0
        var aiSummariesGenerated: Int = 0
        var notionPagesCreated: Int = 0
        var estimatedAPICost: Double = 0

        var formattedStorage: String {
            ByteCountFormatter.string(fromByteCount: storageUsedBytes, countStyle: .file)
        }
    }

    // MARK: - Data Loading

    func loadAllStats() async {
        isLoading = true
        defer {
            isLoading = false
            lastUpdate = Date()
        }

        // Load all stats in parallel
        async let screenshotStats = loadScreenshotStats()
        async let meetingStats = loadMeetingStats()
        async let storageStats = loadStorageStats()
        async let dailyData = loadDailyStats()
        async let meetings = loadRecentMeetings()

        let (screenshots, meetings_stats, storage, daily, recent) = await (
            screenshotStats, meetingStats, storageStats, dailyData, meetings
        )

        // Update stats
        stats.totalScreenshots = screenshots.total
        stats.ocrProcessed = screenshots.withOCR
        stats.averageDailyScreenshots = screenshots.dailyAverage
        stats.totalMeetings = meetings_stats.total
        stats.notionPagesCreated = meetings_stats.exported
        stats.aiSummariesGenerated = meetings_stats.withSummary
        stats.storageUsedBytes = storage
        stats.estimatedAPICost = calculateEstimatedCost()

        dailyStats = daily
        storageBreakdown = calculateStorageBreakdown()
        recentMeetings = recent
    }

    // MARK: - Screenshot Stats

    private func loadScreenshotStats() async -> (total: Int, withOCR: Int, dailyAverage: Int) {
        do {
            let dbStats = try await DatabaseManager.shared.getStats()
            let total = dbStats.screenshotCount
            let withOCR = dbStats.ocrResultCount

            // Calculate daily average (last 30 days)
            let dailyAverage = total > 0 ? total / 30 : 0

            return (total, withOCR, dailyAverage)
        } catch {
            return (0, 0, 0)
        }
    }

    // MARK: - Meeting Stats

    private func loadMeetingStats() async -> (total: Int, exported: Int, withSummary: Int) {
        do {
            let dbStats = try await DatabaseManager.shared.getStats()

            // Get meetings with Notion export
            let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
            let meetings = try await DatabaseManager.shared.getMeetings(from: thirtyDaysAgo, to: Date())

            let exported = meetings.filter { $0.notionPageId != nil }.count
            let withSummary = meetings.filter { $0.aiSummary != nil }.count

            return (dbStats.meetingCount, exported, withSummary)
        } catch {
            return (0, 0, 0)
        }
    }

    // MARK: - Storage Stats

    private func loadStorageStats() async -> Int64 {
        let storageManager = StorageManager.shared
        return Int64(storageManager.calculateStorageUsed())
    }

    // MARK: - Daily Stats

    private func loadDailyStats() async -> [DailyStat] {
        do {
            let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
            let screenshots = try await DatabaseManager.shared.getScreenshots(from: thirtyDaysAgo, to: Date())

            // Group by day
            var countsByDay: [Date: Int] = [:]
            let calendar = Calendar.current

            for screenshot in screenshots {
                let day = calendar.startOfDay(for: screenshot.timestamp)
                countsByDay[day, default: 0] += 1
            }

            // Convert to DailyStat array
            return countsByDay.map { DailyStat(date: $0.key, count: $0.value) }
                .sorted { $0.date < $1.date }
        } catch {
            return []
        }
    }

    // MARK: - Recent Meetings

    private func loadRecentMeetings() async -> [Meeting] {
        do {
            let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
            return try await DatabaseManager.shared.getMeetings(from: thirtyDaysAgo, to: Date())
        } catch {
            return []
        }
    }

    // MARK: - Helper Methods

    private func calculateEstimatedCost() -> Double {
        // Estimate based on summary count and average screenshots per summary
        let summaryCount = stats.aiSummariesGenerated
        let avgScreenshotsPerSummary = 20 // Estimate

        return CostEstimator.estimateCost(
            screenshotCount: summaryCount * avgScreenshotsPerSummary,
            estimatedOutputTokens: summaryCount * 500
        )
    }

    private func calculateStorageBreakdown() -> [StorageItem] {
        let storageManager = StorageManager.shared
        let screenshotsSize = storageManager.calculateStorageUsed()
        let databaseSize = getDatabaseSize()

        return [
            StorageItem(category: "Screenshots", size: Double(screenshotsSize)),
            StorageItem(category: "Datenbank", size: Double(databaseSize)),
            StorageItem(category: "Sonstiges", size: 1024 * 1024) // 1MB placeholder
        ]
    }

    private func getDatabaseSize() -> Int64 {
        let databaseURL = StorageManager.shared.databaseURL
        return (try? FileManager.default.attributesOfItem(atPath: databaseURL.path)[.size] as? Int64) ?? 0
    }

    // MARK: - Actions

    func vacuumDatabase() async {
        isLoading = true
        defer { isLoading = false }

        do {
            try await DatabaseManager.shared.vacuum()
            await loadAllStats()
        } catch {
            errorMessage = "Datenbankoptimierung fehlgeschlagen: \(error.localizedDescription)"
        }
    }

    func cleanupOldData() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let retentionDays = AppState.shared.retentionDays
            let cutoffDate = Calendar.current.date(byAdding: .day, value: -retentionDays, to: Date()) ?? Date()

            // Get screenshots to delete
            let screenshotsToDelete = try await DatabaseManager.shared.getScreenshotsBefore(cutoffDate)

            // Delete files
            let storageManager = StorageManager.shared
            for screenshot in screenshotsToDelete {
                let url = storageManager.screenshotsDirectory.appendingPathComponent(screenshot.filepath)
                try? FileManager.default.removeItem(at: url)
            }

            // Delete from database
            let deletedCount = try await DatabaseManager.shared.deleteScreenshotsBefore(cutoffDate)

            print("Cleaned up \(deletedCount) old screenshots")
            await loadAllStats()
        } catch {
            errorMessage = "Bereinigung fehlgeschlagen: \(error.localizedDescription)"
        }
    }

    func exportStats() async {
        // Create stats export
        let export = StatsExport(
            exportDate: Date(),
            stats: stats,
            dailyStats: dailyStats,
            meetingCount: recentMeetings.count
        )

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601

            let data = try encoder.encode(export)

            // Save to Downloads folder
            let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
            let filename = "scrainee_stats_\(ISO8601DateFormatter().string(from: Date())).json"
            let fileURL = downloadsURL.appendingPathComponent(filename)

            try data.write(to: fileURL)

            // Open in Finder
            NSWorkspace.shared.activateFileViewerSelecting([fileURL])
        } catch {
            errorMessage = "Export fehlgeschlagen: \(error.localizedDescription)"
        }
    }

    func showLogs() {
        // Open log file location
        let logURL = StorageManager.shared.appSupportDirectory.appendingPathComponent("logs")
        NSWorkspace.shared.activateFileViewerSelecting([logURL])
    }
}

// MARK: - Supporting Types

struct DailyStat: Identifiable {
    let id = UUID()
    let date: Date
    let count: Int
}

struct StorageItem: Identifiable {
    let id = UUID()
    let category: String
    let size: Double
}

struct StatsExport: Codable {
    let exportDate: Date
    let totalScreenshots: Int
    let totalMeetings: Int
    let storageUsedBytes: Int64
    let ocrProcessed: Int
    let aiSummariesGenerated: Int
    let notionPagesCreated: Int
    let estimatedAPICost: Double
    let dailyStats: [DailyStatExport]
    let meetingCount: Int

    init(exportDate: Date, stats: AdminViewModel.AppStats, dailyStats: [DailyStat], meetingCount: Int) {
        self.exportDate = exportDate
        self.totalScreenshots = stats.totalScreenshots
        self.totalMeetings = stats.totalMeetings
        self.storageUsedBytes = stats.storageUsedBytes
        self.ocrProcessed = stats.ocrProcessed
        self.aiSummariesGenerated = stats.aiSummariesGenerated
        self.notionPagesCreated = stats.notionPagesCreated
        self.estimatedAPICost = stats.estimatedAPICost
        self.dailyStats = dailyStats.map { DailyStatExport(date: $0.date, count: $0.count) }
        self.meetingCount = meetingCount
    }
}

struct DailyStatExport: Codable {
    let date: Date
    let count: Int
}
