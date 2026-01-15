import Foundation

/// Represents a time segment where the user was active in a specific app
/// Derived from screenshot data, not stored separately in the database
struct ActivitySegment: Identifiable, Equatable {
    let id: UUID
    let appBundleId: String?
    let appName: String?
    let windowTitle: String?
    let startTime: Date
    var endTime: Date
    var screenshotCount: Int

    init(
        appBundleId: String?,
        appName: String?,
        windowTitle: String?,
        startTime: Date,
        endTime: Date = Date(),
        screenshotCount: Int = 1
    ) {
        self.id = UUID()
        self.appBundleId = appBundleId
        self.appName = appName
        self.windowTitle = windowTitle
        self.startTime = startTime
        self.endTime = endTime
        self.screenshotCount = screenshotCount
    }

    // MARK: - Computed Properties

    /// Duration of this segment in seconds
    var duration: TimeInterval {
        endTime.timeIntervalSince(startTime)
    }

    /// Formatted duration string (e.g., "5m" or "1h 23m")
    var formattedDuration: String {
        let minutes = Int(duration / 60)
        let hours = minutes / 60
        let remainingMinutes = minutes % 60

        if hours > 0 {
            return "\(hours)h \(remainingMinutes)m"
        } else if minutes > 0 {
            return "\(minutes)m"
        } else {
            return "<1m"
        }
    }

    /// Display name for the segment (app name or "Unbekannt")
    var displayName: String {
        appName ?? "Unbekannt"
    }

    /// Color for this segment based on app bundle ID hash
    var colorIndex: Int {
        guard let bundleId = appBundleId else { return 0 }
        return abs(bundleId.hashValue) % 12
    }
}

// MARK: - Segment Builder

extension ActivitySegment {
    /// Builds activity segments from a list of screenshots
    /// Groups consecutive screenshots from the same app into segments
    static func buildSegments(from screenshots: [Screenshot], maxGapSeconds: TimeInterval = 120) -> [ActivitySegment] {
        guard !screenshots.isEmpty else { return [] }

        // Sort by timestamp ascending
        let sorted = screenshots.sorted { $0.timestamp < $1.timestamp }

        var segments: [ActivitySegment] = []
        var currentSegment: ActivitySegment?

        for screenshot in sorted {
            if let segment = currentSegment {
                // Check if this screenshot belongs to the current segment
                let timeSinceLastScreenshot = screenshot.timestamp.timeIntervalSince(segment.endTime)
                let sameApp = screenshot.appBundleId == segment.appBundleId

                if sameApp && timeSinceLastScreenshot <= maxGapSeconds {
                    // Extend current segment
                    currentSegment?.endTime = screenshot.timestamp
                    currentSegment?.screenshotCount += 1
                } else {
                    // Finish current segment and start new one
                    segments.append(segment)
                    currentSegment = ActivitySegment(
                        appBundleId: screenshot.appBundleId,
                        appName: screenshot.appName,
                        windowTitle: screenshot.windowTitle,
                        startTime: screenshot.timestamp
                    )
                }
            } else {
                // Start first segment
                currentSegment = ActivitySegment(
                    appBundleId: screenshot.appBundleId,
                    appName: screenshot.appName,
                    windowTitle: screenshot.windowTitle,
                    startTime: screenshot.timestamp
                )
            }
        }

        // Don't forget the last segment
        if let lastSegment = currentSegment {
            segments.append(lastSegment)
        }

        return segments
    }
}
