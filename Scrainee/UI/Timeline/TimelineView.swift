// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - 📋 DEPENDENCY DOCUMENTATION
// ═══════════════════════════════════════════════════════════════════════════════
//
// FILE: TimelineView.swift | PURPOSE: Rewind-Style Timeline UI | LAYER: UI/Timeline
//
// DEPENDENCIES:
//   - TimelineViewModel: State-Management und Screenshot-Navigation
//   - TimelineThumbnailStrip: Horizontale Thumbnail-Leiste
//   - TimelineSliderView: Zeit-Slider mit Aktivitaets-Segmenten
//   - TimelineTimeLabels: Start/Ende/Aktuelle Zeit Anzeige
//   - TimelineNavigationButtons: Vor/Zurueck Navigation
//   - TimelineDateNavigation: Tages-Navigation mit DatePicker
//   - Screenshot (Model): Screenshot-Metadaten
//   - ActivitySegment (Model): App-Aktivitaets-Segmente
//
// DEPENDENTS:
//   - ScraineeApp.swift: Window-Registration ("timeline-window")
//   - MenuBarView.swift: Timeline-Button oeffnet dieses Fenster
//
// CHANGE IMPACT:
//   - Window-ID Aenderung erfordert Update in ScraineeApp.swift
//   - Keyboard-Shortcuts hier definiert (Pfeiltasten)
//
// LAST UPDATED: 2026-01-20
// ═══════════════════════════════════════════════════════════════════════════════

import SwiftUI

/// Main Timeline view for browsing through screenshots chronologically
struct ScreenshotTimelineView: View {
    @StateObject private var viewModel = TimelineViewModel()
    @State private var showingInfo = false

    var body: some View {
        VStack(spacing: 0) {
            // Header with date navigation
            headerView
                .padding(.horizontal)
                .padding(.vertical, 12)
                .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // Main content
            if viewModel.isLoading {
                loadingView
            } else if viewModel.screenshots.isEmpty {
                emptyStateView
            } else {
                contentView
            }

            Divider()

            // Footer with controls
            footerView
                .padding(.horizontal)
                .padding(.vertical, 12)
                .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 800, minHeight: 600)
        .onAppear {
            Task {
                await viewModel.loadScreenshotsForDay(Date())
            }
        }
        .focusable()
        .onKeyPress(phases: .down) { keyPress in
            let shift = keyPress.modifiers.contains(.shift)

            switch keyPress.key {
            case .leftArrow:
                if shift {
                    viewModel.jumpBackward()
                } else {
                    viewModel.goToPrevious()
                }
                return .handled
            case .rightArrow:
                if shift {
                    viewModel.jumpForward()
                } else {
                    viewModel.goToNext()
                }
                return .handled
            default:
                return .ignored
            }
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            TimelineDateNavigation(viewModel: viewModel)

            Spacer()

            // Current screenshot info
            if viewModel.currentScreenshot != nil {
                HStack(spacing: 8) {
                    // App icon placeholder
                    Image(systemName: "app.fill")
                        .foregroundColor(.secondary)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(viewModel.currentAppName)
                            .font(.headline)
                        if !viewModel.currentWindowTitle.isEmpty {
                            Text(viewModel.currentWindowTitle)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }

                    Text(viewModel.currentTimeText)
                        .font(.system(.title2, design: .monospaced))
                        .fontWeight(.medium)
                }
            }

            Spacer()

            // Info button
            Button(action: { showingInfo.toggle() }) {
                Image(systemName: "info.circle")
                    .font(.title2)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showingInfo) {
                infoPopover
            }
        }
    }

    // MARK: - Content

    private var contentView: some View {
        VStack(spacing: 0) {
            // Screenshot preview
            screenshotPreview
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // Thumbnail strip
            TimelineThumbnailStrip(viewModel: viewModel)
                .padding(.vertical, 8)
                .background(Color(nsColor: .controlBackgroundColor))
        }
    }

    private var screenshotPreview: some View {
        GeometryReader { geometry in
            if let screenshot = viewModel.currentScreenshot {
                ScreenshotPreviewView(screenshot: screenshot)
                    .frame(width: geometry.size.width, height: geometry.size.height)
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.1))
            }
        }
    }

    // MARK: - Footer

    private var footerView: some View {
        VStack(spacing: 12) {
            // Slider with time labels
            VStack(spacing: 4) {
                TimelineSliderView(
                    value: $viewModel.sliderValue,
                    segments: viewModel.segments,
                    dayStart: viewModel.dayStartTime,
                    dayEnd: viewModel.dayEndTime
                )

                TimelineTimeLabels(
                    dayStart: viewModel.dayStartTime,
                    dayEnd: viewModel.dayEndTime,
                    currentTime: viewModel.currentScreenshot?.timestamp
                )
            }

            // Navigation buttons
            TimelineNavigationButtons(viewModel: viewModel)
        }
    }

    // MARK: - States

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Lade Screenshots...")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 64))
                .foregroundColor(.secondary)

            Text("Keine Screenshots")
                .font(.title2)
                .fontWeight(.medium)

            Text("Für diesen Tag wurden keine Screenshots aufgezeichnet.")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            if !Calendar.current.isDateInToday(viewModel.selectedDate) {
                Button("Zu Heute wechseln") {
                    viewModel.goToToday()
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Info Popover

    private var infoPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tastenkürzel")
                .font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                GridRow {
                    Text("←")
                        .fontWeight(.medium)
                    Text("Vorheriger Screenshot")
                }
                GridRow {
                    Text("→")
                        .fontWeight(.medium)
                    Text("Nächster Screenshot")
                }
                GridRow {
                    Text("Shift + ←")
                        .fontWeight(.medium)
                    Text("10 Screenshots zurück")
                }
                GridRow {
                    Text("Shift + →")
                        .fontWeight(.medium)
                    Text("10 Screenshots vor")
                }
            }
            .font(.system(.body, design: .monospaced))

            Divider()

            if !viewModel.segments.isEmpty {
                Text("Aktivitäts-Segmente")
                    .font(.headline)

                Text("\(viewModel.segments.count) Apps heute aktiv")
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .frame(width: 280)
    }

}

// MARK: - Screenshot Preview View

private struct ScreenshotPreviewView: View {
    let screenshot: Screenshot
    @State private var image: NSImage?
    @State private var isLoading = true

    var body: some View {
        ZStack {
            if let image = image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else if isLoading {
                ProgressView()
            } else {
                VStack {
                    Image(systemName: "photo")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("Bild konnte nicht geladen werden")
                        .foregroundColor(.secondary)
                }
            }
        }
        .background(Color.black.opacity(0.05))
        .task(id: screenshot.id) {
            await loadImage()
        }
    }

    private func loadImage() async {
        isLoading = true
        image = nil

        // Load full image (not thumbnail)
        image = await Task.detached(priority: .userInitiated) {
            NSImage(contentsOf: screenshot.fileURL)
        }.value

        isLoading = false
    }
}

// MARK: - Preview

#Preview {
    ScreenshotTimelineView()
        .frame(width: 1000, height: 700)
}
