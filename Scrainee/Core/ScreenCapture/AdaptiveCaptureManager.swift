import Foundation
import Combine

/// Manages adaptive capture intervals based on user activity and meeting state
final class AdaptiveCaptureManager: ObservableObject {
    // MARK: - Configuration

    struct CaptureConfig {
        /// Base capture interval for normal operation
        var baseInterval: TimeInterval = 3.0

        /// Faster capture during meetings
        var meetingInterval: TimeInterval = 1.0

        /// Slower capture during idle periods
        var idleInterval: TimeInterval = 10.0

        /// Time in seconds before considering the user idle
        var idleThreshold: TimeInterval = 60.0

        /// Minimum difference in dHash to save a screenshot (0-64)
        /// Lower = more duplicates filtered, Higher = more screenshots saved
        var duplicateThreshold: Int = 5
    }

    // MARK: - Published Properties

    @Published private(set) var currentInterval: TimeInterval = 3.0
    @Published private(set) var isIdle: Bool = false
    @Published private(set) var skippedDuplicates: Int = 0

    // MARK: - Private Properties

    private var config = CaptureConfig()
    private var lastActivityTime = Date()
    private var lastImageHash: UInt64?
    private var activityCheckTimer: Timer?

    // MARK: - Initialization

    init(config: CaptureConfig = CaptureConfig()) {
        self.config = config
        startActivityMonitoring()
    }

    deinit {
        activityCheckTimer?.invalidate()
    }

    // MARK: - Activity Tracking

    /// Records user activity (called when mouse moves, keyboard input, etc.)
    func recordActivity() {
        lastActivityTime = Date()
        if isIdle {
            isIdle = false
            updateInterval(isMeeting: false) // Will recalculate based on new idle state
        }
    }

    /// Returns the appropriate capture interval based on current state
    func getInterval(isMeeting: Bool) -> TimeInterval {
        updateInterval(isMeeting: isMeeting)
        return currentInterval
    }

    // MARK: - Duplicate Detection

    /// Checks if the new image is too similar to the previous one
    /// Returns true if the image should be skipped
    func shouldSkipDuplicate(imageHash: UInt64) -> Bool {
        defer { lastImageHash = imageHash }

        guard let previousHash = lastImageHash else {
            return false // First image, always capture
        }

        let distance = hammingDistance(previousHash, imageHash)

        if distance < config.duplicateThreshold {
            skippedDuplicates += 1
            return true
        }

        return false
    }

    /// Reports that a duplicate was detected and skipped
    func reportDuplicate() {
        skippedDuplicates += 1
    }

    /// Reports that a unique screenshot was captured (resets activity timer)
    func reportUnique() {
        recordActivity()
    }

    /// Resets the duplicate detection (call when starting a new capture session)
    func resetDuplicateDetection() {
        lastImageHash = nil
        skippedDuplicates = 0
    }

    // MARK: - Private Methods

    private func updateInterval(isMeeting: Bool) {
        let newInterval: TimeInterval

        if isMeeting {
            // During meetings, capture more frequently
            newInterval = config.meetingInterval
        } else if isIdle {
            // When idle, capture less frequently
            newInterval = config.idleInterval
        } else {
            // Normal operation
            newInterval = config.baseInterval
        }

        if newInterval != currentInterval {
            currentInterval = newInterval
        }
    }

    private func startActivityMonitoring() {
        // Check idle status every 10 seconds
        activityCheckTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            self?.checkIdleStatus()
        }
    }

    private func checkIdleStatus() {
        let idleTime = Date().timeIntervalSince(lastActivityTime)
        let wasIdle = isIdle
        isIdle = idleTime > config.idleThreshold

        if isIdle != wasIdle {
            // Idle state changed, but don't change interval here
            // The interval will be updated on next getInterval() call
            NotificationCenter.default.post(
                name: .captureIdleStateChanged,
                object: isIdle
            )
        }
    }

    /// Calculate Hamming distance between two hashes
    private func hammingDistance(_ hash1: UInt64, _ hash2: UInt64) -> Int {
        let xor = hash1 ^ hash2
        return xor.nonzeroBitCount
    }
}

// MARK: - Configuration Updates

extension AdaptiveCaptureManager {
    /// Updates the base interval
    func setBaseInterval(_ interval: TimeInterval) {
        config.baseInterval = max(1.0, min(60.0, interval))
        updateInterval(isMeeting: false)
    }

    /// Updates the meeting interval
    func setMeetingInterval(_ interval: TimeInterval) {
        config.meetingInterval = max(0.5, min(10.0, interval))
    }

    /// Updates the idle interval
    func setIdleInterval(_ interval: TimeInterval) {
        config.idleInterval = max(5.0, min(120.0, interval))
    }

    /// Updates the idle threshold
    func setIdleThreshold(_ threshold: TimeInterval) {
        config.idleThreshold = max(10.0, min(600.0, threshold))
    }

    /// Updates the duplicate threshold
    func setDuplicateThreshold(_ threshold: Int) {
        config.duplicateThreshold = max(0, min(64, threshold))
    }
}

// MARK: - Statistics

extension AdaptiveCaptureManager {
    struct CaptureStats {
        var currentInterval: TimeInterval
        var isIdle: Bool
        var skippedDuplicates: Int
        var idleTime: TimeInterval
    }

    func getStats() -> CaptureStats {
        CaptureStats(
            currentInterval: currentInterval,
            isIdle: isIdle,
            skippedDuplicates: skippedDuplicates,
            idleTime: Date().timeIntervalSince(lastActivityTime)
        )
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let captureIdleStateChanged = Notification.Name("com.scrainee.captureIdleStateChanged")
    static let captureIntervalChanged = Notification.Name("com.scrainee.captureIntervalChanged")
}
