import SwiftUI

/// Main view for displaying meeting minutes and transcript
struct MeetingMinutesView: View {
    @StateObject private var viewModel: MeetingMinutesViewModel
    @ObservedObject private var coordinator = MeetingTranscriptionCoordinator.shared

    init(meeting: Meeting? = nil) {
        _viewModel = StateObject(wrappedValue: MeetingMinutesViewModel(meeting: meeting))
    }

    var body: some View {
        HSplitView {
            // Left: Transcript
            transcriptPanel
                .frame(minWidth: 350, idealWidth: 450)

            // Right: Minutes & Action Items
            minutesPanel
                .frame(minWidth: 300, idealWidth: 400)
        }
        .frame(minWidth: 800, minHeight: 500)
        .toolbar {
            ToolbarItemGroup {
                if coordinator.isTranscribing {
                    LiveTranscriptionBadge()
                }

                Button(action: { Task { await viewModel.refresh() } }) {
                    Label("Aktualisieren", systemImage: "arrow.clockwise")
                }

                if viewModel.hasTranscript {
                    Button(action: { Task { await viewModel.regenerateMinutes() } }) {
                        Label("Regenerieren", systemImage: "arrow.triangle.2.circlepath")
                    }
                }

                Menu {
                    Button("Als Markdown exportieren") {
                        exportAsMarkdown()
                    }
                    Button("Zu Notion exportieren") {
                        exportToNotion()
                    }
                } label: {
                    Label("Exportieren", systemImage: "square.and.arrow.up")
                }
            }
        }
        .overlay {
            if viewModel.isLoading {
                ProgressView("Laden...")
                    .padding()
                    .background(.regularMaterial)
                    .cornerRadius(8)
            }
        }
        .alert("Fehler", isPresented: .constant(viewModel.error != nil)) {
            Button("OK") { viewModel.error = nil }
        } message: {
            Text(viewModel.error ?? "")
        }
    }

    // MARK: - Transcript Panel

    private var transcriptPanel: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Transkript")
                    .font(.headline)

                Spacer()

                if viewModel.hasTranscript {
                    Text("\(viewModel.segments.count) Segmente")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()

            Divider()

            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Transkript durchsuchen...", text: $viewModel.searchText)
                    .textFieldStyle(.plain)

                if !viewModel.searchText.isEmpty {
                    Button(action: { viewModel.searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // Transcript list
            if viewModel.hasTranscript {
                ScrollViewReader { proxy in
                    List(viewModel.filteredSegments) { segment in
                        TranscriptSegmentRow(segment: segment)
                            .id(segment.id)
                    }
                    .listStyle(.plain)
                }
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "text.bubble")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)

                    Text("Kein Transkript vorhanden")
                        .font(.headline)
                        .foregroundColor(.secondary)

                    if coordinator.isTranscribing {
                        Text("Transkription läuft...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // Footer with stats
            if viewModel.hasTranscript {
                Divider()

                HStack {
                    Text("\(viewModel.transcriptWordCount) Wörter")
                    Spacer()
                    Text(formatDuration(viewModel.transcriptDuration))
                }
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(8)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Minutes Panel

    private var minutesPanel: some View {
        VStack(spacing: 0) {
            // Tab picker
            Picker("", selection: $viewModel.selectedTab) {
                ForEach(MinutesTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            Divider()

            // Content
            ScrollView {
                switch viewModel.selectedTab {
                case .summary:
                    summaryContent
                case .actionItems:
                    actionItemsContent
                case .decisions:
                    decisionsContent
                }
            }
        }
    }

    // MARK: - Summary Content

    private var summaryContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Summary
            GroupBox("Zusammenfassung") {
                Text(viewModel.summaryText)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Key Points
            if !viewModel.keyPoints.isEmpty {
                GroupBox("Kernpunkte") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(viewModel.keyPoints, id: \.self) { point in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "circle.fill")
                                    .font(.system(size: 6))
                                    .foregroundColor(.accentColor)
                                    .padding(.top, 6)

                                Text(point)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            // Meeting info
            if let meeting = viewModel.meeting {
                GroupBox("Meeting-Info") {
                    VStack(alignment: .leading, spacing: 4) {
                        LabeledContent("App", value: meeting.appName)
                        LabeledContent("Datum", value: formatDate(meeting.startTime))
                        if let duration = meeting.durationSeconds {
                            LabeledContent("Dauer", value: formatDuration(TimeInterval(duration)))
                        }
                        LabeledContent("Transkript-Status", value: meeting.transcriptionStatus.displayName)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding()
    }

    // MARK: - Action Items Content

    private var actionItemsContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Add button
            HStack {
                Spacer()
                Button(action: showAddActionItemSheet) {
                    Label("Action Item hinzufügen", systemImage: "plus")
                }
            }
            .padding(.horizontal)

            // Items list
            if viewModel.actionItems.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "checklist")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)

                    Text("Keine Action Items")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, 40)
            } else {
                ForEach(viewModel.actionItems) { item in
                    ActionItemRow(
                        item: item,
                        onToggle: { Task { await viewModel.toggleActionItemStatus(item) } },
                        onDelete: { Task { await viewModel.deleteActionItem(item) } }
                    )
                }
                .padding(.horizontal)
            }
        }
        .padding(.vertical)
    }

    // MARK: - Decisions Content

    private var decisionsContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            if viewModel.decisions.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.seal")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)

                    Text("Keine Entscheidungen dokumentiert")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, 40)
            } else {
                ForEach(viewModel.decisions, id: \.self) { decision in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)

                        Text(decision)
                            .textSelection(.enabled)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(8)
                }
                .padding(.horizontal)
            }
        }
        .padding(.vertical)
    }

    // MARK: - Helper Methods

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, secs)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func showAddActionItemSheet() {
        // Would show a sheet to add action item
    }

    private func exportAsMarkdown() {
        // Export implementation
    }

    private func exportToNotion() {
        // Notion export implementation
    }
}

// MARK: - Transcript Segment Row

struct TranscriptSegmentRow: View {
    let segment: TranscriptSegment

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Timestamp
            Text(segment.formattedTimestamp)
                .font(.caption.monospacedDigit())
                .foregroundColor(.secondary)
                .frame(width: 45, alignment: .trailing)

            // Text
            Text(segment.text)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Action Item Row

struct ActionItemRow: View {
    let item: ActionItem
    let onToggle: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Checkbox
            Button(action: onToggle) {
                Image(systemName: item.status == .completed ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(item.status == .completed ? .green : .secondary)
                    .font(.title2)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .strikethrough(item.status == .completed)
                    .foregroundColor(item.status == .completed ? .secondary : .primary)

                HStack(spacing: 8) {
                    if let assignee = item.assignee {
                        Label(assignee, systemImage: "person")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    if let dueDate = item.formattedDueDate {
                        Label(dueDate, systemImage: "calendar")
                            .font(.caption)
                            .foregroundColor(item.isOverdue ? .red : .secondary)
                    }

                    PriorityBadge(priority: item.priority)
                }
            }

            Spacer()

            // Delete button
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
            .opacity(0.6)
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }
}

// MARK: - Priority Badge

struct PriorityBadge: View {
    let priority: ActionItemPriority

    var body: some View {
        Text(priority.displayName)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(backgroundColor)
            .foregroundColor(.white)
            .cornerRadius(4)
    }

    private var backgroundColor: Color {
        switch priority {
        case .low: return .gray
        case .medium: return .blue
        case .high: return .orange
        case .urgent: return .red
        }
    }
}

// MARK: - Live Transcription Badge

struct LiveTranscriptionBadge: View {
    @ObservedObject private var coordinator = MeetingTranscriptionCoordinator.shared
    @State private var isAnimating = false

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color.red)
                .frame(width: 8, height: 8)
                .scaleEffect(isAnimating ? 1.2 : 1.0)

            Text(coordinator.statusMessage.isEmpty ? "Aufnahme läuft" : coordinator.statusMessage)
                .font(.caption)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.red.opacity(0.1))
        .cornerRadius(12)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
        }
    }
}

// MARK: - Preview

#Preview {
    MeetingMinutesView()
        .frame(width: 900, height: 600)
}
