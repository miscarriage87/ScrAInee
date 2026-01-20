// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - DEPENDENCY DOCUMENTATION
// ═══════════════════════════════════════════════════════════════════════════════
//
// FILE: MeetingState.swift
// PURPOSE: State-Objekt für Meeting-bezogene Properties und Methoden.
//          Teil der AppState-Aufteilung für bessere Separation of Concerns.
// LAYER: App/State
//
// ┌─────────────────────────────────────────────────────────────────────────────┐
// │ DEPENDENCIES (was diese Datei NUTZT)                                        │
// ├─────────────────────────────────────────────────────────────────────────────┤
// │ IMPORTS:                                                                    │
// │   • DatabaseManager.shared   → Core/Database/DatabaseManager.swift          │
// │   • SummaryGenerator         → Core/AI/SummaryGenerator.swift               │
// │   • NotionClient             → Core/Integration/NotionClient.swift          │
// │   • Meeting (Model)          → Core/Database/Models/Meeting.swift           │
// │   • MeetingSession (Model)   → Core/Meeting/MeetingDetector.swift           │
// │   • Summary (Model)          → Core/Database/Models/Summary.swift           │
// │                                                                             │
// │ LISTENS TO (via AppState):                                                  │
// │   • .meetingStarted          → von MeetingDetector.swift                    │
// │   • .meetingEnded            → von MeetingDetector.swift                    │
// └─────────────────────────────────────────────────────────────────────────────┘
//
// ┌─────────────────────────────────────────────────────────────────────────────┐
// │ DEPENDENTS (wer diese Datei NUTZT)                                          │
// ├─────────────────────────────────────────────────────────────────────────────┤
// │ USED BY:                                                                    │
// │   • AppState.swift           → Enthält als @Published Property              │
// │   • MenuBarView.swift        → Zeigt Meeting-Status                         │
// │   • AdaptiveCaptureManager   → Prüft isMeetingActive                        │
// │   • ScreenCaptureManager     → Prüft isMeetingActive für Intervall          │
// └─────────────────────────────────────────────────────────────────────────────┘
//
// LAST UPDATED: 2026-01-20
// ═══════════════════════════════════════════════════════════════════════════════

import SwiftUI
import Combine

/// State object for meeting related properties
@MainActor
final class MeetingState: ObservableObject {

    // MARK: - Published Properties

    /// Whether a meeting is currently detected
    @Published var isMeetingActive = false

    /// Current meeting session if any
    @Published var currentMeeting: MeetingSession?

    /// Whether a summary is being generated
    @Published var isGeneratingSummary = false

    /// Last generated summary
    @Published var lastSummary: Summary?

    // MARK: - Internal Properties

    /// Current meeting database ID for tracking
    var currentMeetingDbId: Int64?

    /// Closure to report errors (injected by AppState)
    var onError: ((String) -> Void)?

    /// Closure to start capture when meeting starts (injected by AppState)
    var onMeetingStarted: (() async -> Void)?

    /// Whether meeting detection is enabled (synced from SettingsState)
    var meetingDetectionEnabled: Bool = true

    /// Whether Notion sync is enabled (synced from SettingsState)
    var notionEnabled: Bool = false

    /// Whether auto-sync to Notion is enabled (synced from SettingsState)
    var notionAutoSync: Bool = true

    // MARK: - Meeting Handling

    func handleMeetingStarted(_ meeting: MeetingSession) async {
        guard meetingDetectionEnabled else { return }

        isMeetingActive = true
        currentMeeting = meeting

        // Auto-start capture if not already running
        await onMeetingStarted?()

        // Save meeting to database
        await saveMeetingToDatabase(meeting)
    }

    func handleMeetingEnded(_ meeting: MeetingSession) async {
        isMeetingActive = false
        let endTime = Date()

        // Generate summary for meeting and sync to Notion
        if let startTime = currentMeeting?.startTime {
            // Update meeting end time in database
            await updateMeetingEndTime(endTime: endTime)

            // Generate summary
            await generateSummary(from: startTime, to: endTime)

            // Sync to Notion if enabled
            if notionEnabled && notionAutoSync, let summary = lastSummary {
                await syncMeetingToNotion(meeting: meeting, summary: summary)
            }
        }

        currentMeeting = nil
        currentMeetingDbId = nil
    }

    // MARK: - Meeting Database Operations

    private func saveMeetingToDatabase(_ meeting: MeetingSession) async {
        do {
            let dbMeeting = Meeting(
                id: nil,
                appBundleId: meeting.bundleId,
                appName: meeting.appName,
                startTime: meeting.startTime,
                endTime: nil,
                durationSeconds: nil,
                screenshotCount: nil,
                transcript: nil,
                aiSummary: nil,
                notionPageId: nil,
                notionPageUrl: nil,
                status: .active,
                transcriptionStatus: .notStarted,
                audioFilePath: nil,
                createdAt: nil
            )
            currentMeetingDbId = try await DatabaseManager.shared.insert(dbMeeting)
        } catch {
            print("Failed to save meeting to database: \(error)")
        }
    }

    private func updateMeetingEndTime(endTime: Date) async {
        guard let meetingId = currentMeetingDbId else { return }

        do {
            if var meeting = try await DatabaseManager.shared.getMeeting(id: meetingId) {
                meeting.endTime = endTime
                if let startTime = meeting.startTime as Date? {
                    meeting.durationSeconds = Int(endTime.timeIntervalSince(startTime))
                }
                meeting.screenshotCount = try await DatabaseManager.shared.getScreenshotCountForMeeting(meetingId: meetingId)
                meeting.status = .completed
                try await DatabaseManager.shared.update(meeting)
            }
        } catch {
            print("Failed to update meeting end time: \(error)")
        }
    }

    // MARK: - Notion Integration

    private func syncMeetingToNotion(meeting: MeetingSession, summary: Summary) async {
        guard let meetingId = currentMeetingDbId else { return }

        let notionClient = NotionClient()

        // Check if Notion is configured
        guard notionClient.isConfigured else {
            onError?("Notion nicht konfiguriert. Bitte API Key und Database ID in den Einstellungen eingeben.")
            return
        }

        do {
            // Get screenshot count for this meeting
            let screenshotCount = try await DatabaseManager.shared.getScreenshotCountForMeeting(meetingId: meetingId)

            // Create Notion page
            let notionPage = try await notionClient.createMeetingPage(
                meeting: meeting,
                summary: summary.content,
                screenshotCount: screenshotCount
            )

            // Update meeting in database with Notion link
            try await DatabaseManager.shared.updateMeetingNotionLink(
                meetingId: meetingId,
                pageId: notionPage.id,
                pageUrl: notionPage.url
            )

            print("Meeting successfully synced to Notion: \(notionPage.url)")
        } catch {
            onError?("Notion Sync fehlgeschlagen: \(error.localizedDescription)")
        }
    }

    /// Manually sync a meeting to Notion
    func syncCurrentMeetingToNotion() async {
        guard let meeting = currentMeeting, let summary = lastSummary else {
            onError?("Kein Meeting oder Zusammenfassung verfuegbar")
            return
        }

        await syncMeetingToNotion(meeting: meeting, summary: summary)
    }

    // MARK: - Summary Generation

    func generateSummary(from startTime: Date, to endTime: Date) async {
        guard !isGeneratingSummary else { return }

        isGeneratingSummary = true
        defer { isGeneratingSummary = false }

        do {
            let generator = SummaryGenerator()
            let summary = try await generator.generateSummary(from: startTime, to: endTime)
            lastSummary = summary
        } catch {
            onError?("Zusammenfassung konnte nicht erstellt werden: \(error.localizedDescription)")
        }
    }
}
