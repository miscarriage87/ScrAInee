import SwiftUI

/// Main gallery view for browsing screenshots
struct ScreenshotGalleryView: View {
    @StateObject private var viewModel = GalleryViewModel()
    @State private var showFilters = false
    @State private var availableApps: [String] = []

    private let columns = [
        GridItem(.adaptive(minimum: 200, maximum: 300), spacing: 12)
    ]

    var body: some View {
        HSplitView {
            // Main content - Screenshot grid
            VStack(spacing: 0) {
                // Toolbar
                toolbar

                Divider()

                // Grid or empty state
                if viewModel.screenshots.isEmpty && !viewModel.isLoading {
                    emptyState
                } else {
                    screenshotGrid
                }
            }
            .frame(minWidth: 400)

            // Detail panel
            if let screenshot = viewModel.selectedScreenshot {
                ScreenshotDetailView(
                    screenshot: screenshot,
                    viewModel: viewModel
                )
                .frame(minWidth: 300, maxWidth: 400)
            }
        }
        .frame(minWidth: 800, minHeight: 600)
        .task {
            availableApps = await viewModel.getUniqueApps()
            await viewModel.loadInitial()
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            // Search field
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Suchen...", text: $viewModel.searchText)
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
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
            .frame(maxWidth: 300)

            Spacer()

            // Filter button
            Button(action: { showFilters.toggle() }) {
                Label("Filter", systemImage: showFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
            }
            .popover(isPresented: $showFilters) {
                filterPopover
            }

            // Refresh button
            Button(action: {
                Task { await viewModel.refresh() }
            }) {
                Image(systemName: "arrow.clockwise")
            }
            .disabled(viewModel.isLoading)

            // Screenshot count
            Text("\(viewModel.screenshots.count) Screenshots")
                .foregroundColor(.secondary)
                .font(.caption)
        }
        .padding()
    }

    // MARK: - Filter Popover

    private var filterPopover: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Filter")
                .font(.headline)

            // App filter
            VStack(alignment: .leading, spacing: 4) {
                Text("App")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Picker("App", selection: $viewModel.filterApp) {
                    Text("Alle Apps").tag(nil as String?)
                    ForEach(availableApps, id: \.self) { app in
                        Text(app).tag(app as String?)
                    }
                }
                .labelsHidden()
            }

            // Date range
            VStack(alignment: .leading, spacing: 4) {
                Text("Zeitraum")
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack {
                    DatePicker("Von", selection: Binding(
                        get: { viewModel.filterDateFrom ?? Date().addingTimeInterval(-86400 * 7) },
                        set: { viewModel.filterDateFrom = $0 }
                    ), displayedComponents: .date)
                    .labelsHidden()

                    Text("bis")

                    DatePicker("Bis", selection: Binding(
                        get: { viewModel.filterDateTo ?? Date() },
                        set: { viewModel.filterDateTo = $0 }
                    ), displayedComponents: .date)
                    .labelsHidden()
                }
            }

            Divider()

            HStack {
                Button("Zuruecksetzen") {
                    viewModel.filterApp = nil
                    viewModel.filterDateFrom = nil
                    viewModel.filterDateTo = nil
                    Task { await viewModel.refresh() }
                }

                Spacer()

                Button("Anwenden") {
                    showFilters = false
                    Task { await viewModel.refresh() }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 300)
    }

    // MARK: - Screenshot Grid

    private var screenshotGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(viewModel.screenshots) { screenshot in
                    ScreenshotThumbnailView(
                        screenshot: screenshot,
                        isSelected: viewModel.selectedScreenshot?.id == screenshot.id,
                        viewModel: viewModel
                    )
                    .onTapGesture {
                        viewModel.selectedScreenshot = screenshot
                    }
                    .onAppear {
                        // Load more when reaching end
                        if screenshot.id == viewModel.screenshots.last?.id {
                            Task { await viewModel.loadMore() }
                        }
                    }
                }
            }
            .padding()

            if viewModel.isLoading {
                ProgressView()
                    .padding()
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 64))
                .foregroundColor(.secondary)

            Text("Keine Screenshots gefunden")
                .font(.title2)
                .foregroundColor(.secondary)

            if viewModel.filterApp != nil || viewModel.filterDateFrom != nil || !viewModel.searchText.isEmpty {
                Text("Versuche andere Filtereinstellungen")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Button("Filter zuruecksetzen") {
                    viewModel.filterApp = nil
                    viewModel.filterDateFrom = nil
                    viewModel.filterDateTo = nil
                    viewModel.searchText = ""
                    Task { await viewModel.refresh() }
                }
            } else {
                Text("Screenshots werden automatisch aufgenommen")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Thumbnail View

struct ScreenshotThumbnailView: View {
    let screenshot: Screenshot
    let isSelected: Bool
    @ObservedObject var viewModel: GalleryViewModel

    @State private var thumbnail: NSImage?
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Thumbnail
            ZStack {
                if let image = thumbnail {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 150)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 150)
                        .overlay {
                            ProgressView()
                        }
                }

                // Hover overlay
                if isHovering {
                    Color.black.opacity(0.3)
                    HStack(spacing: 16) {
                        Button(action: { viewModel.openWithQuickLook(screenshot) }) {
                            Image(systemName: "eye")
                                .font(.title2)
                        }
                        .buttonStyle(.plain)

                        Button(action: { viewModel.showInFinder(screenshot) }) {
                            Image(systemName: "folder")
                                .font(.title2)
                        }
                        .buttonStyle(.plain)
                    }
                    .foregroundColor(.white)
                }
            }
            .cornerRadius(8)

            // Info
            VStack(alignment: .leading, spacing: 2) {
                Text(screenshot.appName ?? "Unbekannt")
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)

                Text(screenshot.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(8)
        .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .onHover { hovering in
            isHovering = hovering
        }
        .contextMenu {
            Button("Im Finder zeigen") {
                viewModel.showInFinder(screenshot)
            }
            Button("Mit Quick Look oeffnen") {
                viewModel.openWithQuickLook(screenshot)
            }
            Divider()
            Button("Loeschen", role: .destructive) {
                Task { await viewModel.deleteScreenshot(screenshot) }
            }
        }
        .task {
            await loadThumbnail()
        }
    }

    private func loadThumbnail() async {
        let url = viewModel.fileURL(for: screenshot)
        if let image = NSImage(contentsOf: url) {
            // Create thumbnail
            let size = NSSize(width: 300, height: 200)
            let thumbnailImage = NSImage(size: size)
            thumbnailImage.lockFocus()
            image.draw(in: NSRect(origin: .zero, size: size),
                      from: NSRect(origin: .zero, size: image.size),
                      operation: .copy,
                      fraction: 1.0)
            thumbnailImage.unlockFocus()
            thumbnail = thumbnailImage
        }
    }
}

// MARK: - Detail View

struct ScreenshotDetailView: View {
    let screenshot: Screenshot
    @ObservedObject var viewModel: GalleryViewModel

    @State private var fullImage: NSImage?
    @State private var ocrText: String?

    var body: some View {
        if #available(macOS 14.0, *) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Full size preview
                    if let image = fullImage {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .cornerRadius(8)
                            .onTapGesture(count: 2) {
                                viewModel.openWithQuickLook(screenshot)
                            }
                    } else {
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .aspectRatio(16/9, contentMode: .fit)
                            .cornerRadius(8)
                            .overlay { ProgressView() }
                    }
                    
                    // Metadata
                    GroupBox("Details") {
                        VStack(alignment: .leading, spacing: 8) {
                            MetadataRow(label: "App", value: screenshot.appName ?? "Unbekannt")
                            MetadataRow(label: "Fenster", value: screenshot.windowTitle ?? "-")
                            MetadataRow(label: "Zeitpunkt", value: formatDate(screenshot.timestamp))
                            MetadataRow(label: "Aufloesung", value: "\(screenshot.width) x \(screenshot.height)")
                            MetadataRow(label: "Groesse", value: formatFileSize(screenshot.fileSize))
                            MetadataRow(label: "Hash", value: String(screenshot.hash?.prefix(16) ?? "-"))
                        }
                    }
                    
                    // OCR Text
                    if let text = ocrText, !text.isEmpty {
                        GroupBox("Erkannter Text") {
                            Text(text)
                                .font(.caption)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    
                    // Actions
                    HStack {
                        Button(action: { viewModel.showInFinder(screenshot) }) {
                            Label("Im Finder", systemImage: "folder")
                        }
                        
                        Button(action: { viewModel.openWithQuickLook(screenshot) }) {
                            Label("Quick Look", systemImage: "eye")
                        }
                        
                        Spacer()
                        
                        Button(role: .destructive) {
                            Task { await viewModel.deleteScreenshot(screenshot) }
                        } label: {
                            Label("Loeschen", systemImage: "trash")
                        }
                    }
                }
                .padding()
            }
            .task {
                await loadFullImage()
                await loadOCRText()
            }
            .onChange(of: screenshot.id) { _, _ in
                fullImage = nil
                ocrText = nil
                Task {
                    await loadFullImage()
                    await loadOCRText()
                }
            }
        } else {
            // Fallback on earlier versions
        }
    }

    private func loadFullImage() async {
        let url = viewModel.fileURL(for: screenshot)
        fullImage = NSImage(contentsOf: url)
    }

    private func loadOCRText() async {
        guard let id = screenshot.id else { return }
        do {
            ocrText = try await DatabaseManager.shared.getOCRText(for: id)
        } catch {
            ocrText = nil
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }

    private func formatFileSize(_ size: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }
}

// MARK: - Metadata Row

struct MetadataRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .leading)
            Text(value)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
        }
        .font(.caption)
    }
}
