import Foundation
import PDFKit
import AppKit

/// Manages export of summaries, meetings, and data to various formats
@MainActor
final class ExportManager: Sendable {
    static let shared = ExportManager()

    // MARK: - Export Formats

    enum ExportFormat: String, CaseIterable {
        case markdown = "md"
        case json = "json"
        case html = "html"
        case pdf = "pdf"

        var displayName: String {
            switch self {
            case .markdown: return "Markdown"
            case .json: return "JSON"
            case .html: return "HTML"
            case .pdf: return "PDF"
            }
        }

        var fileExtension: String { rawValue }
    }

    // MARK: - Export Summary

    /// Exports a summary to the specified format
    func exportSummary(_ summary: Summary, format: ExportFormat) async throws -> URL {
        let content: Data

        switch format {
        case .markdown:
            content = Data(summaryToMarkdown(summary).utf8)
        case .json:
            content = try summaryToJSON(summary)
        case .html:
            content = Data(summaryToHTML(summary).utf8)
        case .pdf:
            content = try summaryToPDF(summary)
        }

        return try saveToFile(
            content: content,
            filename: "summary_\(formatDateForFilename(summary.createdAt ?? Date()))",
            extension: format.fileExtension
        )
    }

    // MARK: - Export Meeting

    /// Exports a meeting to the specified format
    func exportMeeting(_ meeting: Meeting, format: ExportFormat) async throws -> URL {
        let content: Data

        switch format {
        case .markdown:
            content = Data(meetingToMarkdown(meeting).utf8)
        case .json:
            content = try meetingToJSON(meeting)
        case .html:
            content = Data(meetingToHTML(meeting).utf8)
        case .pdf:
            content = try meetingToPDF(meeting)
        }

        return try saveToFile(
            content: content,
            filename: "meeting_\(formatDateForFilename(meeting.startTime))",
            extension: format.fileExtension
        )
    }

    // MARK: - Export Date Range

    /// Exports all data from a date range
    func exportDateRange(from startDate: Date, to endDate: Date, format: ExportFormat) async throws -> URL {
        // Get data
        let screenshots = try await DatabaseManager.shared.getScreenshots(from: startDate, to: endDate)
        let meetings = try await DatabaseManager.shared.getMeetings(from: startDate, to: endDate)

        let export = DateRangeExport(
            startDate: startDate,
            endDate: endDate,
            screenshotCount: screenshots.count,
            meetings: meetings.map { MeetingExport(from: $0) }
        )

        let content: Data

        switch format {
        case .markdown:
            content = Data(dateRangeToMarkdown(export).utf8)
        case .json:
            content = try dateRangeToJSON(export)
        case .html:
            content = Data(dateRangeToHTML(export).utf8)
        case .pdf:
            content = try dateRangeToPDF(export)
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd"

        return try saveToFile(
            content: content,
            filename: "export_\(dateFormatter.string(from: startDate))_\(dateFormatter.string(from: endDate))",
            extension: format.fileExtension
        )
    }

    // MARK: - Full Backup

    /// Exports all data as a backup
    func exportAllData() async throws -> URL {
        let stats = try await DatabaseManager.shared.getStats()

        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        let screenshots = try await DatabaseManager.shared.getScreenshots(from: thirtyDaysAgo, to: Date())
        let meetings = try await DatabaseManager.shared.getMeetings(from: thirtyDaysAgo, to: Date())

        let backup = FullBackup(
            exportDate: Date(),
            stats: BackupStats(
                screenshotCount: stats.screenshotCount,
                ocrResultCount: stats.ocrResultCount,
                meetingCount: stats.meetingCount,
                summaryCount: stats.summaryCount
            ),
            recentScreenshots: screenshots.prefix(100).map { ScreenshotExport(from: $0) },
            meetings: meetings.map { MeetingExport(from: $0) }
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let content = try encoder.encode(backup)

        return try saveToFile(
            content: content,
            filename: "scrainee_backup_\(formatDateForFilename(Date()))",
            extension: "json"
        )
    }

    // MARK: - Markdown Formatters

    private func summaryToMarkdown(_ summary: Summary) -> String {
        """
        # \(summary.title ?? "Zusammenfassung")

        **Zeitraum:** \(formatDateRange(summary.startTime, summary.endTime))
        **Generiert:** \(formatDate(summary.createdAt ?? Date()))

        ---

        ## Zusammenfassung

        \(summary.content)

        ---

        *Erstellt mit Scrainee*
        """
    }

    private func meetingToMarkdown(_ meeting: Meeting) -> String {
        """
        # Meeting: \(meeting.appName)

        **Datum:** \(formatDate(meeting.startTime))
        **Dauer:** \(meeting.formattedDuration)
        **App:** \(meeting.appName)
        **Status:** \(meeting.status.rawValue)

        ---

        ## Zusammenfassung

        \(meeting.aiSummary ?? "Keine Zusammenfassung verfuegbar")

        ---

        **Screenshots:** \(meeting.screenshotCount ?? 0)
        \(meeting.notionPageUrl != nil ? "**Notion:** [\(meeting.notionPageUrl!)](\(meeting.notionPageUrl!))" : "")

        ---

        *Erstellt mit Scrainee*
        """
    }

    private func dateRangeToMarkdown(_ export: DateRangeExport) -> String {
        var md = """
        # Scrainee Export

        **Zeitraum:** \(formatDate(export.startDate)) - \(formatDate(export.endDate))
        **Screenshots:** \(export.screenshotCount)
        **Meetings:** \(export.meetings.count)

        ---

        ## Meetings

        """

        for meeting in export.meetings {
            md += """

            ### \(meeting.appName) - \(formatDate(meeting.startTime))

            - **Dauer:** \(meeting.durationMinutes) Minuten
            - **Status:** \(meeting.status)

            """
        }

        md += """

        ---

        *Exportiert am \(formatDate(Date()))*
        """

        return md
    }

    // MARK: - JSON Formatters

    private func summaryToJSON(_ summary: Summary) throws -> Data {
        let export = SummaryExport(
            title: summary.title,
            content: summary.content,
            startTime: summary.startTime,
            endTime: summary.endTime,
            createdAt: summary.createdAt
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601

        return try encoder.encode(export)
    }

    private func meetingToJSON(_ meeting: Meeting) throws -> Data {
        let export = MeetingExport(from: meeting)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601

        return try encoder.encode(export)
    }

    private func dateRangeToJSON(_ export: DateRangeExport) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601

        return try encoder.encode(export)
    }

    // MARK: - HTML Formatters

    private func summaryToHTML(_ summary: Summary) -> String {
        """
        <!DOCTYPE html>
        <html lang="de">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>\(summary.title ?? "Zusammenfassung")</title>
            <style>
                body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; max-width: 800px; margin: 40px auto; padding: 20px; line-height: 1.6; }
                h1 { color: #333; border-bottom: 2px solid #007AFF; padding-bottom: 10px; }
                .meta { color: #666; font-size: 0.9em; margin-bottom: 20px; }
                .content { background: #f5f5f5; padding: 20px; border-radius: 8px; }
                footer { margin-top: 40px; padding-top: 20px; border-top: 1px solid #ddd; font-size: 0.8em; color: #999; }
            </style>
        </head>
        <body>
            <h1>\(summary.title ?? "Zusammenfassung")</h1>
            <div class="meta">
                <p><strong>Zeitraum:</strong> \(formatDateRange(summary.startTime, summary.endTime))</p>
                <p><strong>Generiert:</strong> \(formatDate(summary.createdAt ?? Date()))</p>
            </div>
            <div class="content">
                \(summary.content.replacingOccurrences(of: "\n", with: "<br>"))
            </div>
            <footer>Erstellt mit Scrainee</footer>
        </body>
        </html>
        """
    }

    private func meetingToHTML(_ meeting: Meeting) -> String {
        """
        <!DOCTYPE html>
        <html lang="de">
        <head>
            <meta charset="UTF-8">
            <title>Meeting: \(meeting.appName)</title>
            <style>
                body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; max-width: 800px; margin: 40px auto; padding: 20px; }
                h1 { color: #333; }
                .meta { background: #f5f5f5; padding: 15px; border-radius: 8px; margin: 20px 0; }
                .summary { margin: 20px 0; }
            </style>
        </head>
        <body>
            <h1>Meeting: \(meeting.appName)</h1>
            <div class="meta">
                <p><strong>Datum:</strong> \(formatDate(meeting.startTime))</p>
                <p><strong>Dauer:</strong> \(meeting.formattedDuration)</p>
                <p><strong>Status:</strong> \(meeting.status.rawValue)</p>
            </div>
            <div class="summary">
                <h2>Zusammenfassung</h2>
                <p>\(meeting.aiSummary ?? "Keine Zusammenfassung verfuegbar")</p>
            </div>
        </body>
        </html>
        """
    }

    private func dateRangeToHTML(_ export: DateRangeExport) -> String {
        var meetingsHTML = ""
        for meeting in export.meetings {
            meetingsHTML += """
                <div class="meeting">
                    <h3>\(meeting.appName) - \(formatDate(meeting.startTime))</h3>
                    <p>Dauer: \(meeting.durationMinutes) Minuten | Status: \(meeting.status)</p>
                </div>
            """
        }

        return """
        <!DOCTYPE html>
        <html lang="de">
        <head>
            <meta charset="UTF-8">
            <title>Scrainee Export</title>
            <style>
                body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; max-width: 800px; margin: 40px auto; padding: 20px; }
                .meeting { background: #f5f5f5; padding: 15px; border-radius: 8px; margin: 10px 0; }
            </style>
        </head>
        <body>
            <h1>Scrainee Export</h1>
            <p><strong>Zeitraum:</strong> \(formatDate(export.startDate)) - \(formatDate(export.endDate))</p>
            <p><strong>Screenshots:</strong> \(export.screenshotCount) | <strong>Meetings:</strong> \(export.meetings.count)</p>
            <h2>Meetings</h2>
            \(meetingsHTML)
        </body>
        </html>
        """
    }

    // MARK: - PDF Formatters

    private func summaryToPDF(_ summary: Summary) throws -> Data {
        let html = summaryToHTML(summary)
        return try htmlToPDF(html)
    }

    private func meetingToPDF(_ meeting: Meeting) throws -> Data {
        let html = meetingToHTML(meeting)
        return try htmlToPDF(html)
    }

    private func dateRangeToPDF(_ export: DateRangeExport) throws -> Data {
        let html = dateRangeToHTML(export)
        return try htmlToPDF(html)
    }

    private func htmlToPDF(_ html: String) throws -> Data {
        // Use NSAttributedString to convert HTML to PDF
        guard let htmlData = html.data(using: .utf8),
              let attributedString = try? NSAttributedString(
                data: htmlData,
                options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue
                ],
                documentAttributes: nil
              ) else {
            throw ExportError.pdfConversionFailed
        }

        // Create PDF using text view
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 612, height: 792)) // Letter size
        textView.textStorage?.setAttributedString(attributedString)

        guard let pdfData = textView.dataWithPDF(inside: textView.bounds) as Data? else {
            throw ExportError.pdfConversionFailed
        }

        return pdfData
    }

    // MARK: - File Operations

    private func saveToFile(content: Data, filename: String, extension ext: String) throws -> URL {
        let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        let fileURL = downloadsURL.appendingPathComponent("\(filename).\(ext)")

        try content.write(to: fileURL)

        return fileURL
    }

    // MARK: - Helpers

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "de_DE")
        return formatter.string(from: date)
    }

    private func formatDateRange(_ start: Date?, _ end: Date?) -> String {
        guard let start = start, let end = end else {
            return "Unbekannt"
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "de_DE")

        return "\(formatter.string(from: start)) - \(formatter.string(from: end))"
    }

    private func formatDateForFilename(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter.string(from: date)
    }
}

// MARK: - Export Types

struct SummaryExport: Codable {
    let title: String?
    let content: String
    let startTime: Date?
    let endTime: Date?
    let createdAt: Date?
}

struct MeetingExport: Codable {
    let appName: String
    let startTime: Date
    let endTime: Date?
    let durationMinutes: Int
    let status: String
    let aiSummary: String?
    let notionPageUrl: String?

    init(from meeting: Meeting) {
        self.appName = meeting.appName
        self.startTime = meeting.startTime
        self.endTime = meeting.endTime
        self.durationMinutes = meeting.durationMinutes
        self.status = meeting.status.rawValue
        self.aiSummary = meeting.aiSummary
        self.notionPageUrl = meeting.notionPageUrl
    }
}

struct ScreenshotExport: Codable {
    let timestamp: Date
    let appName: String?
    let windowTitle: String?

    init(from screenshot: Screenshot) {
        self.timestamp = screenshot.timestamp
        self.appName = screenshot.appName
        self.windowTitle = screenshot.windowTitle
    }
}

struct DateRangeExport: Codable {
    let startDate: Date
    let endDate: Date
    let screenshotCount: Int
    let meetings: [MeetingExport]
}

struct BackupStats: Codable {
    let screenshotCount: Int
    let ocrResultCount: Int
    let meetingCount: Int
    let summaryCount: Int
}

struct FullBackup: Codable {
    let exportDate: Date
    let stats: BackupStats
    let recentScreenshots: [ScreenshotExport]
    let meetings: [MeetingExport]
}

// MARK: - Errors

enum ExportError: LocalizedError {
    case pdfConversionFailed
    case fileWriteFailed
    case invalidData

    var errorDescription: String? {
        switch self {
        case .pdfConversionFailed:
            return "PDF-Konvertierung fehlgeschlagen"
        case .fileWriteFailed:
            return "Datei konnte nicht geschrieben werden"
        case .invalidData:
            return "Ungueltige Daten"
        }
    }
}
