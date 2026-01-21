// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - 📋 DEPENDENCY DOCUMENTATION
// ═══════════════════════════════════════════════════════════════════════════════
//
// FILE: TimelineThumbnailStrip.swift | PURPOSE: Horizontale Thumbnail-Navigation | LAYER: UI/Timeline
//
// DEPENDENCIES:
//   - TimelineViewModel: @ObservedObject fuer Screenshots und Navigation
//   - ThumbnailCache (Actor): Async Thumbnail-Loading
//   - Screenshot (Model): Screenshot-Daten und fileURL
//
// DEPENDENTS:
//   - TimelineView.swift: Eingebettet zwischen Preview und Footer
//
// CHANGE IMPACT:
//   - Thumbnail-Groesse hier definiert (120x75 / 50x50 compact)
//   - ScrollView auto-scrollt zu currentIndex
//
// ENTHALTENE SUB-VIEWS:
//   - ThumbnailItem (private): Einzelnes Thumbnail mit Zeit-Label
//   - CompactThumbnailStrip: Alternative kompakte Darstellung
//   - SmallThumbnail (private): Kleines Thumbnail fuer Compact-Strip
//
// LAST UPDATED: 2026-01-21
// ═══════════════════════════════════════════════════════════════════════════════

import SwiftUI

/// A horizontal strip of thumbnails showing screenshots around the current position
struct TimelineThumbnailStrip: View {
    @ObservedObject var viewModel: TimelineViewModel
    let visibleCount: Int

    @State private var scrollOffset: CGFloat = 0

    private let thumbnailWidth: CGFloat = 120
    private let thumbnailHeight: CGFloat = 75
    private let spacing: CGFloat = 8

    init(viewModel: TimelineViewModel, visibleCount: Int = 9) {
        self.viewModel = viewModel
        self.visibleCount = visibleCount
    }

    var body: some View {
        GeometryReader { geometry in
            let totalWidth = geometry.size.width

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: spacing) {
                        ForEach(Array(viewModel.screenshots.enumerated()), id: \.element.id) { index, screenshot in
                            ThumbnailItem(
                                screenshot: screenshot,
                                isSelected: index == viewModel.currentIndex,
                                width: thumbnailWidth,
                                height: thumbnailHeight
                            )
                            .id(index)
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    viewModel.goToIndex(index)
                                }
                            }
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(thumbnailAccessibilityLabel(for: screenshot, at: index))
                            .accessibilityHint(index == viewModel.currentIndex ? "Aktuell ausgewählt" : "Doppeltippen um auszuwählen")
                            .accessibilityAddTraits(index == viewModel.currentIndex ? [.isButton, .isSelected] : .isButton)
                        }
                    }
                    .padding(.horizontal, (totalWidth - thumbnailWidth) / 2)
                }
                .onChange(of: viewModel.currentIndex) { _, newIndex in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo(newIndex, anchor: .center)
                    }
                }
                .onAppear {
                    // Initial scroll to current position
                    proxy.scrollTo(viewModel.currentIndex, anchor: .center)
                }
            }
        }
        .frame(height: thumbnailHeight + 16)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Thumbnail-Leiste mit \(viewModel.screenshots.count) Screenshots")
    }

    private func thumbnailAccessibilityLabel(for screenshot: Screenshot, at index: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        var label = "Screenshot \(index + 1), \(formatter.string(from: screenshot.timestamp))"
        if let appName = screenshot.appName {
            label += ", \(appName)"
        }
        return label
    }
}

// MARK: - Thumbnail Item

private struct ThumbnailItem: View {
    let screenshot: Screenshot
    let isSelected: Bool
    let width: CGFloat
    let height: CGFloat

    @State private var image: NSImage?
    @State private var isLoading = true

    var body: some View {
        ZStack {
            // Thumbnail image
            if let image = image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: width, height: height)
                    .clipped()
            } else if isLoading {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: width, height: height)
                    .overlay(
                        ProgressView()
                            .scaleEffect(0.5)
                    )
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: width, height: height)
                    .overlay(
                        Image(systemName: "photo")
                            .foregroundColor(.gray)
                    )
            }

            // Time label
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Text(timeString)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(3)
                        .padding(4)
                }
            }
        }
        .frame(width: width, height: height)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 3)
        )
        .shadow(color: isSelected ? Color.accentColor.opacity(0.3) : .clear, radius: 4)
        .scaleEffect(isSelected ? 1.05 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
        .task {
            await loadThumbnail()
        }
    }

    private var timeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: screenshot.timestamp)
    }

    private func loadThumbnail() async {
        guard let id = screenshot.id else {
            isLoading = false
            return
        }

        image = await ThumbnailCache.shared.thumbnail(for: id, url: screenshot.fileURL)
        isLoading = false
    }
}

// MARK: - Compact Thumbnail Strip

/// A more compact version showing fewer thumbnails
struct CompactThumbnailStrip: View {
    @ObservedObject var viewModel: TimelineViewModel

    private let thumbnailSize: CGFloat = 50

    var body: some View {
        HStack(spacing: 4) {
            ForEach(visibleScreenshots, id: \.offset) { item in
                SmallThumbnail(
                    screenshot: item.element,
                    isSelected: item.offset == viewModel.currentIndex
                )
                .frame(width: thumbnailSize, height: thumbnailSize)
                .onTapGesture {
                    viewModel.goToIndex(item.offset)
                }
            }
        }
    }

    private var visibleScreenshots: [EnumeratedSequence<[Screenshot]>.Element] {
        let range = 3 // Show 3 before and 3 after
        let start = max(0, viewModel.currentIndex - range)
        let end = min(viewModel.screenshots.count - 1, viewModel.currentIndex + range)

        guard start <= end else { return [] }

        return Array(viewModel.screenshots.enumerated()).filter { $0.offset >= start && $0.offset <= end }
    }
}

private struct SmallThumbnail: View {
    let screenshot: Screenshot
    let isSelected: Bool

    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image = image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(isSelected ? Color.accentColor : Color.gray.opacity(0.3), lineWidth: isSelected ? 2 : 1)
        )
        .task {
            guard let id = screenshot.id else { return }
            image = await ThumbnailCache.shared.thumbnail(for: id, url: screenshot.fileURL)
        }
    }
}

// MARK: - Preview

#Preview {
    VStack {
        Text("Thumbnail Strip")
        TimelineThumbnailStrip(viewModel: TimelineViewModel())
            .frame(height: 100)
    }
    .frame(width: 800, height: 150)
    .padding()
}
