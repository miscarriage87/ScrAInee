import Foundation
import SwiftUI
import Combine

/// ViewModel for the Timeline view - manages screenshot navigation and state
@MainActor
final class TimelineViewModel: ObservableObject {
    // MARK: - Published State

    @Published var selectedDate: Date = Date()
    @Published var currentScreenshot: Screenshot?
    @Published var currentIndex: Int = 0
    @Published var screenshots: [Screenshot] = []
    @Published var segments: [ActivitySegment] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    // Time bounds for the current day
    @Published var dayStartTime: Date?
    @Published var dayEndTime: Date?

    // For slider
    @Published var sliderValue: Double = 0

    // MARK: - Private

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init() {
        setupBindings()
    }

    private func setupBindings() {
        // When selected date changes, reload screenshots
        $selectedDate
            .removeDuplicates { Calendar.current.isDate($0, inSameDayAs: $1) }
            .sink { [weak self] date in
                Task {
                    await self?.loadScreenshotsForDay(date)
                }
            }
            .store(in: &cancellables)

        // When slider value changes, update current screenshot
        $sliderValue
            .debounce(for: .milliseconds(50), scheduler: RunLoop.main)
            .sink { [weak self] value in
                self?.updateScreenshotFromSlider(value)
            }
            .store(in: &cancellables)
    }

    // MARK: - Data Loading

    /// Loads screenshots for a specific day
    func loadScreenshotsForDay(_ date: Date) async {
        isLoading = true
        errorMessage = nil

        do {
            // Get screenshots for the day
            screenshots = try await DatabaseManager.shared.getScreenshotsForDay(date)

            // Build activity segments
            segments = ActivitySegment.buildSegments(from: screenshots)

            // Get time bounds
            if let bounds = try await DatabaseManager.shared.getTimeBoundsForDay(date) {
                dayStartTime = bounds.start
                dayEndTime = bounds.end
            } else {
                dayStartTime = nil
                dayEndTime = nil
            }

            // Set to most recent screenshot or first if navigating to past day
            if Calendar.current.isDateInToday(date) {
                // Today: go to most recent
                currentIndex = screenshots.count - 1
            } else {
                // Past day: go to first
                currentIndex = 0
            }

            updateCurrentScreenshot()

            // Preload thumbnails
            if !screenshots.isEmpty {
                Task.detached(priority: .background) { [screenshots, currentIndex] in
                    await ThumbnailCache.shared.preloadAround(
                        screenshots: screenshots,
                        currentIndex: currentIndex
                    )
                }
            }

        } catch {
            errorMessage = "Fehler beim Laden: \(error.localizedDescription)"
        }

        isLoading = false
    }

    /// Refreshes current day
    func refresh() async {
        await loadScreenshotsForDay(selectedDate)
    }

    // MARK: - Navigation

    /// Goes to the next screenshot
    func goToNext() {
        guard currentIndex < screenshots.count - 1 else { return }
        currentIndex += 1
        updateCurrentScreenshot()
        triggerPreload()
    }

    /// Goes to the previous screenshot
    func goToPrevious() {
        guard currentIndex > 0 else { return }
        currentIndex -= 1
        updateCurrentScreenshot()
        triggerPreload()
    }

    /// Jumps forward by a number of screenshots
    func jumpForward(_ count: Int = 10) {
        currentIndex = min(screenshots.count - 1, currentIndex + count)
        updateCurrentScreenshot()
        triggerPreload()
    }

    /// Jumps backward by a number of screenshots
    func jumpBackward(_ count: Int = 10) {
        currentIndex = max(0, currentIndex - count)
        updateCurrentScreenshot()
        triggerPreload()
    }

    /// Goes to a specific time
    func goToTime(_ time: Date) async {
        guard let screenshot = try? await DatabaseManager.shared.getScreenshotClosestTo(time: time) else {
            return
        }

        if let index = screenshots.firstIndex(where: { $0.id == screenshot.id }) {
            currentIndex = index
            updateCurrentScreenshot()
            triggerPreload()
        }
    }

    /// Goes to a specific screenshot by index
    func goToIndex(_ index: Int) {
        guard index >= 0 && index < screenshots.count else { return }
        currentIndex = index
        updateCurrentScreenshot()
        triggerPreload()
    }

    /// Goes to the previous day
    func goToPreviousDay() {
        guard let newDate = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate) else { return }
        selectedDate = newDate
    }

    /// Goes to the next day
    func goToNextDay() {
        guard let newDate = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate) else { return }
        // Don't go past today
        if newDate <= Date() {
            selectedDate = newDate
        }
    }

    /// Goes to today
    func goToToday() {
        selectedDate = Date()
    }

    // MARK: - Slider

    /// Updates slider value from current index
    private func updateSliderFromIndex() {
        guard !screenshots.isEmpty else {
            sliderValue = 0
            return
        }
        sliderValue = Double(currentIndex) / Double(screenshots.count - 1)
    }

    /// Updates current screenshot from slider value
    private func updateScreenshotFromSlider(_ value: Double) {
        guard !screenshots.isEmpty else { return }

        let newIndex = Int(round(value * Double(screenshots.count - 1)))
        guard newIndex != currentIndex else { return }

        currentIndex = max(0, min(screenshots.count - 1, newIndex))
        currentScreenshot = screenshots.isEmpty ? nil : screenshots[currentIndex]
        triggerPreload()
    }

    // MARK: - Private Helpers

    private func updateCurrentScreenshot() {
        currentScreenshot = screenshots.isEmpty ? nil : screenshots[currentIndex]
        updateSliderFromIndex()
    }

    private func triggerPreload() {
        Task.detached(priority: .background) { [screenshots, currentIndex] in
            await ThumbnailCache.shared.preloadAround(
                screenshots: screenshots,
                currentIndex: currentIndex
            )
        }
    }

    // MARK: - Computed Properties

    /// Whether we can go to next
    var canGoNext: Bool {
        currentIndex < screenshots.count - 1
    }

    /// Whether we can go to previous
    var canGoPrevious: Bool {
        currentIndex > 0
    }

    /// Whether we can go to next day
    var canGoNextDay: Bool {
        !Calendar.current.isDateInToday(selectedDate)
    }

    /// Current position text (e.g., "42 / 1234")
    var positionText: String {
        guard !screenshots.isEmpty else { return "0 / 0" }
        return "\(currentIndex + 1) / \(screenshots.count)"
    }

    /// Formatted date for display
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")

        if Calendar.current.isDateInToday(selectedDate) {
            return "Heute"
        } else if Calendar.current.isDateInYesterday(selectedDate) {
            return "Gestern"
        } else {
            formatter.dateFormat = "EEEE, d. MMMM"
            return formatter.string(from: selectedDate)
        }
    }

    /// Formatted time for current screenshot
    var currentTimeText: String {
        guard let screenshot = currentScreenshot else { return "--:--" }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: screenshot.timestamp)
    }

    /// App name for current screenshot
    var currentAppName: String {
        currentScreenshot?.appName ?? "Unbekannt"
    }

    /// Window title for current screenshot
    var currentWindowTitle: String {
        currentScreenshot?.windowTitle ?? ""
    }
}
