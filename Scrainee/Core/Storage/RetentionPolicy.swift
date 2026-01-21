// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - 📋 DEPENDENCY DOCUMENTATION
// ═══════════════════════════════════════════════════════════════════════════════
//
// FILE: RetentionPolicy.swift | PURPOSE: Automatische Screenshot-Bereinigung | LAYER: Core/Storage
//
// DEPENDENCIES: Foundation (Timer, Calendar, Date, UserDefaults),
//               DatabaseManager (.shared - getScreenshotsBefore, deleteScreenshotsBefore, vacuum),
//               StorageManager (.shared - deleteScreenshot, clearAllScreenshots)
// DEPENDENTS: ScraineeApp (startScheduledCleanup bei App-Start), SettingsView (manuelle Cleanup-Trigger),
//             DatabaseManager (vacuum nach Cleanup)
// CHANGE IMPACT: Cleanup-Logik betrifft Datenspeicherung langfristig;
//                .cleanupCompleted Notification informiert UI ueber Ergebnisse;
//                actor-isolated fuer Thread-Safety bei Background-Cleanup
//
// LAST UPDATED: 2026-01-20
// ═══════════════════════════════════════════════════════════════════════════════

import Foundation

/// Manages automatic cleanup of old screenshots based on retention settings
actor RetentionPolicy {
    static let shared = RetentionPolicy()

    private var cleanupTimer: Timer?
    private var isCleanupRunning = false

    private init() {}

    // MARK: - Scheduled Cleanup

    /// Starts the scheduled cleanup process
    nonisolated func startScheduledCleanup() {
        Task {
            await scheduleNextCleanup()
        }
    }

    /// Schedules the next cleanup (runs daily at 3 AM)
    private func scheduleNextCleanup() {
        // Calculate next 3 AM
        let nextCleanupDate = calculateNextCleanupDate()
        let timeInterval = nextCleanupDate.timeIntervalSinceNow

        // Invalidate existing timer first
        cleanupTimer?.invalidate()

        // Schedule timer on main actor
        Task { @MainActor in
            let timer = Timer.scheduledTimer(
                withTimeInterval: timeInterval,
                repeats: false
            ) { [weak self] _ in
                Task {
                    await self?.runScheduledCleanup()
                }
            }
            
            // Store the timer back in the actor
            Task {
                await self.setCleanupTimer(timer)
            }
        }

        FileLogger.shared.info("Next cleanup scheduled for: \(nextCleanupDate)", context: "RetentionPolicy")
    }

    /// Sets the cleanup timer (actor-isolated)
    private func setCleanupTimer(_ timer: Timer) {
        cleanupTimer = timer
    }

    private func runScheduledCleanup() async {
        await performCleanup()

        // Schedule next cleanup (24 hours later)
        scheduleNextCleanup()
    }

    private func calculateNextCleanupDate() -> Date {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = 3
        components.minute = 0
        components.second = 0

        var date = Calendar.current.date(from: components)!

        // If 3 AM has passed today, schedule for tomorrow
        if date < Date() {
            date = Calendar.current.date(byAdding: .day, value: 1, to: date)!
        }

        return date
    }

    // MARK: - Cleanup Execution

    /// Performs the cleanup process
    nonisolated func performCleanup() async {
        // Check if already running
        let shouldRun = await checkAndSetRunning()
        guard shouldRun else {
            FileLogger.shared.debug("Cleanup already in progress, skipping...", context: "RetentionPolicy")
            return
        }

        defer {
            Task { await self.setNotRunning() }
        }

        // Get retention days from UserDefaults
        let retentionDays = UserDefaults.standard.integer(forKey: "retentionDays")

        // Skip if retention is unlimited (0)
        guard retentionDays > 0 else {
            FileLogger.shared.debug("Retention is unlimited, skipping cleanup", context: "RetentionPolicy")
            return
        }

        let cutoffDate = Calendar.current.date(byAdding: .day, value: -retentionDays, to: Date())!

        FileLogger.shared.info("Starting cleanup for screenshots older than \(cutoffDate)", context: "RetentionPolicy")

        do {
            // 1. Get old screenshots
            let oldScreenshots = try await DatabaseManager.shared.getScreenshotsBefore(cutoffDate)

            guard !oldScreenshots.isEmpty else {
                FileLogger.shared.debug("No old screenshots to clean up", context: "RetentionPolicy")
                return
            }

            FileLogger.shared.info("Found \(oldScreenshots.count) screenshots to delete", context: "RetentionPolicy")

            // 2. Delete files
            var deletedCount = 0
            var failedCount = 0

            for screenshot in oldScreenshots {
                do {
                    try StorageManager.shared.deleteScreenshot(at: screenshot.filepath)
                    deletedCount += 1
                } catch {
                    failedCount += 1
                    FileLogger.shared.warning("Failed to delete file: \(screenshot.filepath) - \(error)", context: "RetentionPolicy")
                }
            }

            // 3. Delete from database (CASCADE will handle OCR results)
            let dbDeletedCount = try await DatabaseManager.shared.deleteScreenshotsBefore(cutoffDate)

            // 4. Run VACUUM to reclaim space
            try await DatabaseManager.shared.vacuum()

            FileLogger.shared.info("Cleanup completed: \(deletedCount) files deleted, \(dbDeletedCount) DB records removed, \(failedCount) failures", context: "RetentionPolicy")

            // 5. Notify about completion
            let finalDeletedCount = deletedCount
            let finalDbDeletedCount = dbDeletedCount
            let finalFailedCount = failedCount
            
            await MainActor.run {
                NotificationCenter.default.post(name: .cleanupCompleted, object: CleanupResult(
                    filesDeleted: finalDeletedCount,
                    dbRecordsDeleted: finalDbDeletedCount,
                    failures: finalFailedCount
                ))
            }

        } catch {
            FileLogger.shared.error("Cleanup error: \(error)", context: "RetentionPolicy")
        }
    }

    // MARK: - Manual Cleanup

    /// Performs cleanup for a specific number of days
    func cleanupOlderThan(days: Int) async throws -> CleanupResult {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
        return try await cleanupBefore(date: cutoffDate)
    }

    /// Performs cleanup for screenshots before a specific date
    func cleanupBefore(date: Date) async throws -> CleanupResult {
        let oldScreenshots = try await DatabaseManager.shared.getScreenshotsBefore(date)

        var deletedFiles = 0
        var failures = 0

        for screenshot in oldScreenshots {
            do {
                try StorageManager.shared.deleteScreenshot(at: screenshot.filepath)
                deletedFiles += 1
            } catch {
                failures += 1
            }
        }

        let dbDeleted = try await DatabaseManager.shared.deleteScreenshotsBefore(date)
        try await DatabaseManager.shared.vacuum()

        return CleanupResult(filesDeleted: deletedFiles, dbRecordsDeleted: dbDeleted, failures: failures)
    }

    /// Cleans up all screenshots (danger!)
    func cleanupAll() async throws -> CleanupResult {
        let count = try await DatabaseManager.shared.getScreenshotCount()

        try StorageManager.shared.clearAllScreenshots()

        // This will delete all screenshots due to no date filter
        let cutoffDate = Date.distantFuture
        let dbDeleted = try await DatabaseManager.shared.deleteScreenshotsBefore(cutoffDate)

        try await DatabaseManager.shared.vacuum()

        return CleanupResult(filesDeleted: count, dbRecordsDeleted: dbDeleted, failures: 0)
    }

    // MARK: - State Management

    private func checkAndSetRunning() -> Bool {
        if isCleanupRunning {
            return false
        }
        isCleanupRunning = true
        return true
    }

    private func setNotRunning() {
        isCleanupRunning = false
    }

    // MARK: - Storage Analysis

    /// Gets estimated storage that would be freed by cleanup
    func estimateCleanupSize(olderThanDays: Int) async throws -> Int64 {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -olderThanDays, to: Date())!
        let screenshots = try await DatabaseManager.shared.getScreenshotsBefore(cutoffDate)

        return screenshots.reduce(0) { $0 + Int64($1.fileSize) }
    }
}

// MARK: - Cleanup Result

struct CleanupResult {
    let filesDeleted: Int
    let dbRecordsDeleted: Int
    let failures: Int

    var totalDeleted: Int {
        filesDeleted
    }

    var hasFailures: Bool {
        failures > 0
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let cleanupCompleted = Notification.Name("com.scrainee.cleanupCompleted")
}
