// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - 📋 DEPENDENCY DOCUMENTATION
// ═══════════════════════════════════════════════════════════════════════════════
//
// FILE: MeetingMinutesViewModel.swift | PURPOSE: Datenlogik für Meeting-Protokoll-View | LAYER: UI/MeetingMinutes
//
// DEPENDENCIES: DatabaseManager, MeetingTranscriptionCoordinator, MeetingMinutesGenerator, NotionClient, Meeting, TranscriptSegment, ActionItem, MeetingMinutes
// DEPENDENTS: MeetingMinutesView
// LISTENS TO: coordinator.$currentSegments, coordinator.$currentMinutes, coordinator.$actionItems (Combine)
// CHANGE IMPACT: Beeinflusst Transkript-Laden, Minutes-Generierung, Notion-Export, Action-Items-CRUD
//
// LAST UPDATED: 2026-01-20
// ═══════════════════════════════════════════════════════════════════════════════

import Foundation
import Combine

/// ViewModel for Meeting Minutes view
@MainActor
final class MeetingMinutesViewModel: ObservableObject {
    // MARK: - Published State

    @Published var meeting: Meeting?
    @Published var segments: [TranscriptSegment] = []
    @Published var minutes: MeetingMinutes?
    @Published var actionItems: [ActionItem] = []
    @Published var isLoading = false
    @Published var error: String?

    @Published var selectedTab: MinutesTab = .summary
    @Published var searchText = ""

    // MARK: - Computed Properties

    var filteredSegments: [TranscriptSegment] {
        if searchText.isEmpty {
            return segments
        }
        return segments.filter { $0.text.localizedCaseInsensitiveContains(searchText) }
    }

    var summaryText: String {
        minutes?.summary ?? "Keine Zusammenfassung verfügbar"
    }

    var keyPoints: [String] {
        minutes?.keyPointsList ?? []
    }

    var decisions: [String] {
        minutes?.decisionsList ?? []
    }

    var hasTranscript: Bool {
        !segments.isEmpty
    }

    var transcriptWordCount: Int {
        segments.reduce(0) { $0 + $1.wordCount }
    }

    var transcriptDuration: TimeInterval {
        guard let last = segments.last else { return 0 }
        return last.endTime
    }

    // MARK: - Dependencies

    private let databaseManager = DatabaseManager.shared
    private let coordinator = MeetingTranscriptionCoordinator.shared
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init(meeting: Meeting? = nil) {
        self.meeting = meeting
        setupBindings()

        if let meeting = meeting {
            Task {
                await loadData(for: meeting)
            }
        } else {
            // Auto-load most recent meeting if none provided
            Task {
                await loadMostRecentMeeting()
            }
        }
    }

    /// Loads the most recent meeting (for when view is opened without specific meeting)
    func loadMostRecentMeeting() async {
        isLoading = true
        error = nil

        do {
            // First check if there's an active meeting
            if let activeMeeting = try await databaseManager.getActiveMeeting() {
                self.meeting = activeMeeting
                await loadData(for: activeMeeting)
            } else if let recentMeeting = try await databaseManager.getMostRecentMeeting() {
                // Otherwise load the most recent completed meeting
                self.meeting = recentMeeting
                await loadData(for: recentMeeting)
            } else {
                // No meetings found
                isLoading = false
            }
        } catch {
            self.error = "Laden fehlgeschlagen: \(error.localizedDescription)"
            isLoading = false
        }
    }

    /// Loads a specific meeting by ID
    func loadMeeting(id meetingId: Int64) async {
        isLoading = true
        error = nil

        do {
            if let meeting = try await databaseManager.getMeeting(id: meetingId) {
                self.meeting = meeting
                await loadData(for: meeting)
            } else {
                self.error = "Meeting nicht gefunden"
                isLoading = false
            }
        } catch {
            self.error = "Laden fehlgeschlagen: \(error.localizedDescription)"
            isLoading = false
        }
    }

    // MARK: - Data Loading

    func loadData(for meeting: Meeting) async {
        guard let meetingId = meeting.id else { return }

        isLoading = true
        error = nil

        do {
            // Load transcript segments
            segments = try await databaseManager.getTranscriptSegments(for: meetingId)

            // Load minutes
            minutes = try await databaseManager.getMeetingMinutes(for: meetingId)

            // Load action items
            actionItems = try await databaseManager.getActionItems(for: meetingId)

        } catch {
            self.error = "Laden fehlgeschlagen: \(error.localizedDescription)"
        }

        isLoading = false
    }

    func refresh() async {
        guard let meeting = meeting else { return }
        await loadData(for: meeting)
    }

    // MARK: - Action Items

    func toggleActionItemStatus(_ item: ActionItem) async {
        guard let id = item.id else { return }

        let newStatus: ActionItemStatus = item.status == .completed ? .pending : .completed

        do {
            try await databaseManager.updateActionItemStatus(id: id, status: newStatus)

            // Update local state
            if let index = actionItems.firstIndex(where: { $0.id == id }) {
                actionItems[index].status = newStatus
            }
        } catch {
            self.error = "Status-Update fehlgeschlagen: \(error.localizedDescription)"
        }
    }

    func deleteActionItem(_ item: ActionItem) async {
        guard let id = item.id else { return }

        do {
            try await databaseManager.deleteActionItem(id: id)
            actionItems.removeAll { $0.id == id }
        } catch {
            self.error = "Löschen fehlgeschlagen: \(error.localizedDescription)"
        }
    }

    func addActionItem(title: String, assignee: String?, priority: ActionItemPriority) async {
        guard let meetingId = meeting?.id else { return }

        let item = ActionItem(
            meetingId: meetingId,
            minutesId: minutes?.id,
            title: title,
            assignee: assignee,
            priority: priority,
            status: .pending
        )

        do {
            var newItem = item
            newItem.id = try await databaseManager.insert(item)
            actionItems.append(newItem)
        } catch {
            self.error = "Hinzufügen fehlgeschlagen: \(error.localizedDescription)"
        }
    }

    // MARK: - Minutes Regeneration

    func regenerateMinutes() async {
        guard let meetingId = meeting?.id, !segments.isEmpty else { return }

        isLoading = true

        do {
            minutes = try await MeetingMinutesGenerator.shared.generateMinutes(
                for: meetingId,
                segments: segments,
                existingMinutes: nil,
                isLiveUpdate: false
            )
        } catch {
            self.error = "Regenerierung fehlgeschlagen: \(error.localizedDescription)"
        }

        isLoading = false
    }

    // MARK: - Notion Export

    /// Exports meeting minutes to Notion and returns the page URL
    func exportToNotion() async -> String? {
        guard let meeting = meeting else {
            error = "Kein Meeting ausgewählt"
            return nil
        }

        let client = NotionClient()
        guard client.isConfigured else {
            error = "Notion nicht konfiguriert. Bitte API-Key und Database-ID in den Einstellungen eingeben."
            return nil
        }

        guard let mins = minutes else {
            error = "Keine Meeting-Minutes vorhanden. Bitte zuerst generieren."
            return nil
        }

        isLoading = true

        do {
            let page = try await client.exportMeetingWithMinutes(
                meeting: meeting,
                minutes: mins,
                segments: segments,
                actionItems: actionItems
            )

            // Update meeting record with Notion link
            if let meetingId = meeting.id {
                try await databaseManager.updateMeetingNotionLink(
                    meetingId: meetingId,
                    pageId: page.id,
                    pageUrl: page.url
                )
                // Update local meeting object
                self.meeting?.notionPageId = page.id
                self.meeting?.notionPageUrl = page.url
            }

            isLoading = false
            return page.url
        } catch {
            self.error = "Notion-Export fehlgeschlagen: \(error.localizedDescription)"
            isLoading = false
            return nil
        }
    }

    /// Checks if Notion is configured
    var isNotionConfigured: Bool {
        NotionClient().isConfigured
    }

    /// Returns the Notion page URL if already exported
    var notionPageUrl: String? {
        meeting?.notionPageUrl
    }

    // MARK: - Private Methods

    private func setupBindings() {
        // Observe coordinator for live updates
        coordinator.$currentSegments
            .receive(on: DispatchQueue.main)
            .sink { [weak self] segments in
                guard let self = self,
                      let meetingId = self.meeting?.id,
                      meetingId == self.coordinator.currentMeetingId else { return }
                self.segments = segments
            }
            .store(in: &cancellables)

        coordinator.$currentMinutes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] minutes in
                guard let self = self,
                      let meetingId = self.meeting?.id else { return }
                if minutes?.meetingId == meetingId {
                    self.minutes = minutes
                }
            }
            .store(in: &cancellables)

        coordinator.$actionItems
            .receive(on: DispatchQueue.main)
            .sink { [weak self] items in
                guard let self = self,
                      let meetingId = self.meeting?.id else { return }
                self.actionItems = items.filter { $0.meetingId == meetingId }
            }
            .store(in: &cancellables)
    }

    // Expose coordinator's current meeting ID
    var currentMeetingId: Int64? {
        coordinator.currentMeetingId
    }
}

// MARK: - Coordinator Extension removed
// currentMeetingId is now public in MeetingTranscriptionCoordinator

// MARK: - Tab Enum

enum MinutesTab: String, CaseIterable {
    case summary = "Zusammenfassung"
    case actionItems = "Action Items"
    case decisions = "Entscheidungen"
}
