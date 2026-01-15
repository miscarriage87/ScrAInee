import SwiftUI

/// Floating overlay that shows relevant context during meetings
struct ContextOverlayView: View {
    @StateObject private var viewModel = ContextOverlayViewModel()
    @State private var isExpanded = false
    @State private var dragOffset = CGSize.zero

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Compact header (always visible)
            compactHeader

            // Expanded content
            if isExpanded {
                Divider()
                expandedContent
            }
        }
        .frame(width: isExpanded ? 320 : 200)
        .background(
            VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)
        )
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.2), radius: 10)
        .offset(dragOffset)
        .gesture(
            DragGesture()
                .onChanged { value in
                    dragOffset = value.translation
                }
                .onEnded { value in
                    dragOffset = CGSize(
                        width: dragOffset.width + value.translation.width,
                        height: dragOffset.height + value.translation.height
                    )
                }
        )
        .onAppear {
            viewModel.startMonitoring()
        }
        .onDisappear {
            viewModel.stopMonitoring()
        }
    }

    // MARK: - Compact Header

    private var compactHeader: some View {
        HStack(spacing: 8) {
            // Status indicator
            Circle()
                .fill(viewModel.isRecording ? Color.red : Color.gray)
                .frame(width: 8, height: 8)

            // Meeting info
            if let meeting = viewModel.currentMeeting {
                Image(systemName: meetingIcon(for: meeting.appName))
                    .foregroundColor(.blue)

                VStack(alignment: .leading, spacing: 2) {
                    Text(meeting.appName)
                        .font(.caption)
                        .fontWeight(.medium)

                    Text(viewModel.meetingDuration)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            } else {
                Text(viewModel.isRecording ? "Aufnahme" : "Bereit")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Expand/collapse button
            Button(action: { withAnimation { isExpanded.toggle() } }) {
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
    }

    // MARK: - Expanded Content

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Recent keywords
            if !viewModel.recentKeywords.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Haeufige Begriffe")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    FlowLayout(spacing: 4) {
                        ForEach(viewModel.recentKeywords.prefix(8), id: \.self) { keyword in
                            Text(keyword)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.2))
                                .cornerRadius(4)
                        }
                    }
                }
            }

            // Quick stats
            VStack(alignment: .leading, spacing: 4) {
                StatRowSmall(label: "Screenshots", value: "\(viewModel.screenshotCount)")
                StatRowSmall(label: "Erkannter Text", value: viewModel.ocrWordCount)
            }

            // Quick actions
            HStack(spacing: 8) {
                Button(action: { viewModel.toggleRecording() }) {
                    Image(systemName: viewModel.isRecording ? "pause.fill" : "play.fill")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button(action: { viewModel.requestSummary() }) {
                    Image(systemName: "doc.text")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button(action: { viewModel.openQuickAsk() }) {
                    Image(systemName: "sparkles")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(10)
    }

    // MARK: - Helpers

    private func meetingIcon(for appName: String) -> String {
        switch appName.lowercased() {
        case _ where appName.contains("Teams"):
            return "person.3.fill"
        case _ where appName.contains("Zoom"):
            return "video.fill"
        case _ where appName.contains("Meet"):
            return "video.circle.fill"
        case _ where appName.contains("Webex"):
            return "phone.fill"
        default:
            return "video.fill"
        }
    }
}

// MARK: - Small Stat Row

struct StatRowSmall: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.caption2)
                .fontWeight(.medium)
        }
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(
            in: proposal.width ?? 0,
            spacing: spacing,
            subviews: subviews
        )
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(
            in: bounds.width,
            spacing: spacing,
            subviews: subviews
        )
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x,
                                      y: bounds.minY + result.positions[index].y),
                         proposal: .unspecified)
        }
    }

    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []

        init(in width: CGFloat, spacing: CGFloat, subviews: Subviews) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var rowHeight: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)

                if x + size.width > width, x > 0 {
                    x = 0
                    y += rowHeight + spacing
                    rowHeight = 0
                }

                positions.append(CGPoint(x: x, y: y))
                rowHeight = max(rowHeight, size.height)
                x += size.width + spacing
            }

            self.size = CGSize(width: width, height: y + rowHeight)
        }
    }
}

// MARK: - Visual Effect Blur

struct VisualEffectBlur: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

// MARK: - View Model

@MainActor
final class ContextOverlayViewModel: ObservableObject {
    @Published var isRecording = false
    @Published var currentMeeting: MeetingSession?
    @Published var meetingDuration = "00:00"
    @Published var screenshotCount = 0
    @Published var ocrWordCount = "0 Woerter"
    @Published var recentKeywords: [String] = []

    private var timer: Timer?
    private var meetingStartTime: Date?

    func startMonitoring() {
        // Sync with AppState
        isRecording = AppState.shared.isCapturing
        currentMeeting = MeetingDetector.shared.activeMeeting

        if currentMeeting != nil {
            meetingStartTime = currentMeeting?.startTime
        }

        // Update timer
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateStats()
            }
        }

        Task {
            await loadKeywords()
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    func toggleRecording() {
        AppState.shared.toggleCapture()
        isRecording = AppState.shared.isCapturing
    }

    func requestSummary() {
        NotificationCenter.default.post(name: .showSummary, object: nil)
    }

    func openQuickAsk() {
        NotificationCenter.default.post(name: .showQuickAsk, object: nil)
    }

    private func updateStats() {
        isRecording = AppState.shared.isCapturing
        screenshotCount = AppState.shared.screenshotCount

        // Update meeting duration
        if let start = meetingStartTime ?? currentMeeting?.startTime {
            let duration = Int(Date().timeIntervalSince(start))
            let minutes = duration / 60
            let seconds = duration % 60
            meetingDuration = String(format: "%02d:%02d", minutes, seconds)
        }
    }

    private func loadKeywords() async {
        let lastHour = Calendar.current.date(byAdding: .hour, value: -1, to: Date())!

        do {
            let ocrTexts = try await DatabaseManager.shared.getOCRTexts(from: lastHour, to: Date())
            let allText = ocrTexts.map { $0.text }.joined(separator: " ")

            // Extract keywords (simple word frequency)
            let words = allText.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count > 4 }

            var wordCounts: [String: Int] = [:]
            for word in words {
                wordCounts[word, default: 0] += 1
            }

            recentKeywords = wordCounts
                .sorted { $0.value > $1.value }
                .prefix(10)
                .map { $0.key.capitalized }

            ocrWordCount = "\(words.count) Woerter"
        } catch {
            print("Failed to load keywords: \(error)")
        }
    }
}

// MARK: - Preview

#Preview {
    ContextOverlayView()
        .frame(width: 350, height: 250)
}
