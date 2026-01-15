import Foundation

/// Date formatting utilities
enum DateUtils {
    // MARK: - Formatters

    static let shortDateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "de_DE")
        return formatter
    }()

    static let shortTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "de_DE")
        return formatter
    }()

    static let mediumDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.locale = Locale(identifier: "de_DE")
        return formatter
    }()

    nonisolated(unsafe) static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    nonisolated(unsafe) static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.locale = Locale(identifier: "de_DE")
        return formatter
    }()

    // MARK: - Formatting

    static func formatShortDateTime(_ date: Date) -> String {
        shortDateTimeFormatter.string(from: date)
    }

    static func formatShortTime(_ date: Date) -> String {
        shortTimeFormatter.string(from: date)
    }

    static func formatMediumDate(_ date: Date) -> String {
        mediumDateFormatter.string(from: date)
    }

    static func formatRelative(_ date: Date) -> String {
        relativeFormatter.localizedString(for: date, relativeTo: Date())
    }

    static func formatTimeRange(start: Date, end: Date) -> String {
        if Calendar.current.isDate(start, inSameDayAs: end) {
            return "\(formatShortDateTime(start)) - \(formatShortTime(end))"
        }
        return "\(formatShortDateTime(start)) - \(formatShortDateTime(end))"
    }

    static func formatDuration(seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60

        if hours > 0 {
            return String(format: "%dh %dm", hours, minutes)
        } else if minutes > 0 {
            return String(format: "%dm %ds", minutes, secs)
        } else {
            return String(format: "%ds", secs)
        }
    }

    // MARK: - Date Calculations

    static func startOfDay(_ date: Date = Date()) -> Date {
        Calendar.current.startOfDay(for: date)
    }

    static func endOfDay(_ date: Date = Date()) -> Date {
        let start = startOfDay(date)
        return Calendar.current.date(byAdding: .day, value: 1, to: start)!.addingTimeInterval(-1)
    }

    static func hoursAgo(_ hours: Int, from date: Date = Date()) -> Date {
        Calendar.current.date(byAdding: .hour, value: -hours, to: date)!
    }

    static func daysAgo(_ days: Int, from date: Date = Date()) -> Date {
        Calendar.current.date(byAdding: .day, value: -days, to: date)!
    }

    static func yesterday() -> Date {
        daysAgo(1)
    }
}
