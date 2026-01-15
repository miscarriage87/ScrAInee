import SwiftUI
import Charts

/// Admin Dashboard for viewing app statistics and analytics
struct AdminDashboardView: View {
    @StateObject private var viewModel = AdminViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header
                headerSection

                // Stats Grid
                statsGridSection

                // Charts Section
                chartsSection

                // Recent Meetings
                recentMeetingsSection

                // Quick Actions
                quickActionsSection
            }
            .padding()
        }
        .frame(minWidth: 700, minHeight: 600)
        .background(Color(.windowBackgroundColor))
        .task {
            await viewModel.loadAllStats()
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Admin Dashboard")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Letzte Aktualisierung: \(viewModel.lastUpdate, style: .relative)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: {
                Task { await viewModel.loadAllStats() }
            }) {
                Label("Aktualisieren", systemImage: "arrow.clockwise")
            }
            .disabled(viewModel.isLoading)
        }
    }

    // MARK: - Stats Grid Section

    private var statsGridSection: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 16) {
            StatCard(
                title: "Screenshots",
                value: "\(viewModel.stats.totalScreenshots)",
                icon: "camera.fill",
                color: .blue
            )

            StatCard(
                title: "Meetings",
                value: "\(viewModel.stats.totalMeetings)",
                icon: "video.fill",
                color: .green
            )

            StatCard(
                title: "Speicher",
                value: viewModel.stats.formattedStorage,
                icon: "externaldrive.fill",
                color: .orange
            )

            StatCard(
                title: "OCR Texte",
                value: "\(viewModel.stats.ocrProcessed)",
                icon: "doc.text.fill",
                color: .purple
            )

            StatCard(
                title: "KI Summaries",
                value: "\(viewModel.stats.aiSummariesGenerated)",
                icon: "sparkles",
                color: .pink
            )

            StatCard(
                title: "Notion Seiten",
                value: "\(viewModel.stats.notionPagesCreated)",
                icon: "doc.richtext",
                color: .indigo
            )

            StatCard(
                title: "API Kosten",
                value: CostEstimator.formatCost(viewModel.stats.estimatedAPICost),
                icon: "dollarsign.circle.fill",
                color: .yellow
            )

            StatCard(
                title: "Taeglich",
                value: "\(viewModel.stats.averageDailyScreenshots)/Tag",
                icon: "calendar",
                color: .teal
            )
        }
    }

    // MARK: - Charts Section

    private var chartsSection: some View {
        HStack(spacing: 16) {
            // Screenshots per Day Chart
            VStack(alignment: .leading, spacing: 8) {
                Text("Screenshots pro Tag")
                    .font(.headline)

                if #available(macOS 14.0, *) {
                    Chart(viewModel.dailyStats) { stat in
                        BarMark(
                            x: .value("Tag", stat.date, unit: .day),
                            y: .value("Screenshots", stat.count)
                        )
                        .foregroundStyle(Color.blue.gradient)
                    }
                    .frame(height: 200)
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                            AxisGridLine()
                            AxisValueLabel(format: .dateTime.day())
                        }
                    }
                } else {
                    // Fallback for older macOS
                    Text("Charts erfordern macOS 14+")
                        .foregroundColor(.secondary)
                        .frame(height: 200)
                }
            }
            .padding()
            .background(Color(.controlBackgroundColor))
            .cornerRadius(12)

            // Storage Breakdown Chart
            VStack(alignment: .leading, spacing: 8) {
                Text("Speicherverbrauch")
                    .font(.headline)

                if #available(macOS 14.0, *) {
                    Chart(viewModel.storageBreakdown) { item in
                        SectorMark(
                            angle: .value("Groesse", item.size),
                            innerRadius: .ratio(0.5),
                            angularInset: 1.5
                        )
                        .foregroundStyle(by: .value("Kategorie", item.category))
                    }
                    .frame(height: 200)
                } else {
                    Text("Charts erfordern macOS 14+")
                        .foregroundColor(.secondary)
                        .frame(height: 200)
                }
            }
            .padding()
            .background(Color(.controlBackgroundColor))
            .cornerRadius(12)
        }
    }

    // MARK: - Recent Meetings Section

    private var recentMeetingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Letzte Meetings")
                    .font(.headline)

                Spacer()

                Text("\(viewModel.recentMeetings.count) Meetings")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if viewModel.recentMeetings.isEmpty {
                Text("Noch keine Meetings aufgezeichnet")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                ForEach(viewModel.recentMeetings) { meeting in
                    MeetingRow(meeting: meeting)
                }
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
    }

    // MARK: - Quick Actions Section

    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Schnellaktionen")
                .font(.headline)

            HStack(spacing: 12) {
                ActionButton(
                    title: "Datenbank optimieren",
                    icon: "gearshape.fill",
                    action: { Task { await viewModel.vacuumDatabase() } }
                )

                ActionButton(
                    title: "Alte Daten bereinigen",
                    icon: "trash.fill",
                    action: { Task { await viewModel.cleanupOldData() } }
                )

                ActionButton(
                    title: "Stats exportieren",
                    icon: "square.and.arrow.up.fill",
                    action: { Task { await viewModel.exportStats() } }
                )

                ActionButton(
                    title: "Logs anzeigen",
                    icon: "doc.text.magnifyingglass",
                    action: { viewModel.showLogs() }
                )
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
    }
}

// MARK: - Stat Card Component

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.title2)

                Spacer()
            }

            Text(value)
                .font(.title)
                .fontWeight(.bold)

            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
    }
}

// MARK: - Meeting Row Component

struct MeetingRow: View {
    let meeting: Meeting

    var body: some View {
        HStack {
            Image(systemName: appIcon(for: meeting.appName))
                .foregroundColor(.blue)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(meeting.appName)
                    .fontWeight(.medium)

                Text(meeting.startTime, style: .date)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Text(meeting.formattedDuration)
                .font(.caption)
                .foregroundColor(.secondary)

            if meeting.notionPageUrl != nil {
                Image(systemName: "link")
                    .foregroundColor(.green)
            }

            statusBadge(for: meeting.status)
        }
        .padding(.vertical, 4)
    }

    private func appIcon(for appName: String) -> String {
        switch appName.lowercased() {
        case let name where name.contains("zoom"):
            return "video.fill"
        case let name where name.contains("teams"):
            return "person.3.fill"
        case let name where name.contains("meet"):
            return "video.badge.checkmark"
        case let name where name.contains("webex"):
            return "video.circle.fill"
        default:
            return "app.fill"
        }
    }

    @ViewBuilder
    private func statusBadge(for status: MeetingStatus) -> some View {
        let (text, color): (String, Color) = {
            switch status {
            case .active:
                return ("Aktiv", .green)
            case .completed:
                return ("Beendet", .blue)
            case .exported:
                return ("Exportiert", .purple)
            }
        }()

        Text(text)
            .font(.caption2)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(color.opacity(0.2))
            .foregroundColor(color)
            .cornerRadius(4)
    }
}

// MARK: - Action Button Component

struct ActionButton: View {
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)

                Text(title)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity)
            .padding()
        }
        .buttonStyle(.bordered)
    }
}

// MARK: - Preview

#Preview {
    AdminDashboardView()
}
