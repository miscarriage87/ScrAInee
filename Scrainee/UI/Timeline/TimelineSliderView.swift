import SwiftUI

/// A custom slider for timeline navigation with activity segment visualization
struct TimelineSliderView: View {
    @Binding var value: Double
    let segments: [ActivitySegment]
    let dayStart: Date?
    let dayEnd: Date?
    let onScrubbing: ((Bool) -> Void)?

    @State private var isDragging = false

    // App colors for segments
    private let segmentColors: [Color] = [
        .blue, .green, .orange, .purple, .pink,
        .cyan, .yellow, .red, .indigo, .mint,
        .teal, .brown
    ]

    init(
        value: Binding<Double>,
        segments: [ActivitySegment],
        dayStart: Date? = nil,
        dayEnd: Date? = nil,
        onScrubbing: ((Bool) -> Void)? = nil
    ) {
        self._value = value
        self.segments = segments
        self.dayStart = dayStart
        self.dayEnd = dayEnd
        self.onScrubbing = onScrubbing
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height: CGFloat = 40

            ZStack(alignment: .leading) {
                // Background track
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 8)
                    .offset(y: height / 2 - 4)

                // Segment bars
                segmentBars(width: width, height: height)

                // Progress track
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.accentColor.opacity(0.3))
                    .frame(width: max(0, width * value), height: 8)
                    .offset(y: height / 2 - 4)

                // Thumb
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 20, height: 20)
                    .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
                    .offset(x: max(0, min(width - 20, (width - 20) * value)))
                    .offset(y: height / 2 - 10)
            }
            .frame(height: height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        if !isDragging {
                            isDragging = true
                            onScrubbing?(true)
                        }
                        let newValue = max(0, min(1, gesture.location.x / width))
                        value = newValue
                    }
                    .onEnded { _ in
                        isDragging = false
                        onScrubbing?(false)
                    }
            )
        }
        .frame(height: 40)
    }

    // MARK: - Segment Visualization

    @ViewBuilder
    private func segmentBars(width: CGFloat, height: CGFloat) -> some View {
        if let start = dayStart, let end = dayEnd, !segments.isEmpty {
            let totalDuration = end.timeIntervalSince(start)
            if totalDuration > 0 {
                ForEach(segments) { segment in
                    let segmentStart = segment.startTime.timeIntervalSince(start) / totalDuration
                    let segmentEnd = segment.endTime.timeIntervalSince(start) / totalDuration
                    let segmentWidth = max(2, (segmentEnd - segmentStart) * width)
                    let xOffset = segmentStart * width

                    RoundedRectangle(cornerRadius: 2)
                        .fill(segmentColors[segment.colorIndex])
                        .opacity(0.6)
                        .frame(width: segmentWidth, height: 16)
                        .offset(x: xOffset, y: 0)
                }
            }
        }
    }
}

// MARK: - Time Labels

struct TimelineTimeLabels: View {
    let dayStart: Date?
    let dayEnd: Date?
    let currentTime: Date?

    private let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    var body: some View {
        HStack {
            // Start time
            Text(dayStart.map { timeFormatter.string(from: $0) } ?? "--:--")
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()

            // Current time
            if let current = currentTime {
                Text(timeFormatter.string(from: current))
                    .font(.caption)
                    .fontWeight(.medium)
            }

            Spacer()

            // End time
            Text(dayEnd.map { timeFormatter.string(from: $0) } ?? "--:--")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Navigation Buttons

struct TimelineNavigationButtons: View {
    @ObservedObject var viewModel: TimelineViewModel

    var body: some View {
        HStack(spacing: 16) {
            // Jump backward
            Button(action: { viewModel.jumpBackward() }) {
                Image(systemName: "backward.fill")
                    .font(.title2)
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.canGoPrevious)
            .help("10 Screenshots zurück (Shift+Links)")

            // Previous
            Button(action: { viewModel.goToPrevious() }) {
                Image(systemName: "chevron.left")
                    .font(.title2)
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.canGoPrevious)
            .help("Vorheriger Screenshot (Links)")

            // Position indicator
            Text(viewModel.positionText)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(minWidth: 80)

            // Next
            Button(action: { viewModel.goToNext() }) {
                Image(systemName: "chevron.right")
                    .font(.title2)
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.canGoNext)
            .help("Nächster Screenshot (Rechts)")

            // Jump forward
            Button(action: { viewModel.jumpForward() }) {
                Image(systemName: "forward.fill")
                    .font(.title2)
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.canGoNext)
            .help("10 Screenshots vor (Shift+Rechts)")
        }
    }
}

// MARK: - Date Navigation

struct TimelineDateNavigation: View {
    @ObservedObject var viewModel: TimelineViewModel
    @State private var showDatePicker = false

    var body: some View {
        HStack(spacing: 12) {
            // Previous day
            Button(action: { viewModel.goToPreviousDay() }) {
                Image(systemName: "chevron.left.circle")
                    .font(.title2)
            }
            .buttonStyle(.plain)
            .help("Vorheriger Tag")

            // Current date (clickable for date picker)
            Button(action: { showDatePicker.toggle() }) {
                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                    Text(viewModel.formattedDate)
                        .fontWeight(.medium)
                }
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showDatePicker) {
                DatePicker(
                    "Datum",
                    selection: $viewModel.selectedDate,
                    in: ...Date(),
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .padding()
                .frame(width: 300)
            }

            // Next day
            Button(action: { viewModel.goToNextDay() }) {
                Image(systemName: "chevron.right.circle")
                    .font(.title2)
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.canGoNextDay)
            .help("Nächster Tag")

            // Today button
            if !Calendar.current.isDateInToday(viewModel.selectedDate) {
                Button("Heute") {
                    viewModel.goToToday()
                }
                .buttonStyle(.bordered)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        TimelineSliderView(
            value: .constant(0.5),
            segments: [],
            dayStart: Date().addingTimeInterval(-3600 * 8),
            dayEnd: Date()
        )
        .padding()
    }
    .frame(width: 600, height: 100)
}
