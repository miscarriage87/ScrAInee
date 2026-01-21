// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - 📋 DEPENDENCY DOCUMENTATION
// ═══════════════════════════════════════════════════════════════════════════════
//
// FILE: ScreenshotGalleryView.swift | PURPOSE: Screenshot-Grid mit Filterung | LAYER: UI/Gallery
//
// DEPENDENCIES:
//   - GalleryViewModel: @StateObject fuer Pagination und Filter
//   - Screenshot (Model): Screenshot-Entitaet
//   - DatabaseManager (Actor): OCR-Text Abfrage fuer Detail-View
//
// DEPENDENTS:
//   - ScraineeApp.swift: Window-Registration ("gallery-window")
//   - MenuBarView.swift: Galerie-Button oeffnet dieses Fenster
//   - HotkeyManager: Cmd+Shift+G oeffnet Galerie
//
// CHANGE IMPACT:
//   - Window-ID Aenderung erfordert Update in ScraineeApp.swift
//   - HSplitView: Grid links, Detail rechts
//   - Filter-Popover fuer App/Datum-Filter
//
// ENTHALTENE SUB-VIEWS:
//   - ScreenshotThumbnailView: Grid-Item mit Hover-Actions
//   - ScreenshotDetailView: Rechte Detail-Ansicht mit OCR-Text
//   - MetadataRow: Key-Value Anzeige fuer Details
//
// LAST UPDATED: 2026-01-21
// ═══════════════════════════════════════════════════════════════════════════════

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
                    .accessibilityHidden(true)
                TextField("Suchen...", text: $viewModel.searchText)
                    .textFieldStyle(.plain)
                    .accessibilityLabel("Suchfeld")
                    .accessibilityHint("Suche in Screenshot-Texten")

                if !viewModel.searchText.isEmpty {
                    Button(action: { viewModel.searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Suche löschen")
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
            .accessibilityLabel("Filter")
            .accessibilityHint(showFilters ? "Filter-Popover schließen" : "Filter-Optionen öffnen")
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
            .accessibilityLabel("Aktualisieren")
            .accessibilityHint("Lädt die Screenshots neu")

            // Screenshot count
            Text("\(viewModel.screenshots.count) Screenshots")
                .foregroundColor(.secondary)
                .font(.caption)
                .accessibilityLabel("\(viewModel.screenshots.count) Screenshots geladen")
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
                .accessibilityLabel("App-Filter")
                .accessibilityHint("Wähle eine App um nur deren Screenshots anzuzeigen")
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
                    .accessibilityLabel("Startdatum")

                    Text("bis")
                        .accessibilityHidden(true)

                    DatePicker("Bis", selection: Binding(
                        get: { viewModel.filterDateTo ?? Date() },
                        set: { viewModel.filterDateTo = $0 }
                    ), displayedComponents: .date)
                    .labelsHidden()
                    .accessibilityLabel("Enddatum")
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
                .accessibilityHint("Setzt alle Filter zurück")

                Spacer()

                Button("Anwenden") {
                    showFilters = false
                    Task { await viewModel.refresh() }
                }
                .buttonStyle(.borderedProminent)
                .accessibilityHint("Wendet die Filter an und schließt das Popover")
            }
        }
        .padding()
        .frame(width: 300)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Filter-Optionen")
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
                .accessibilityHidden(true)

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
                .accessibilityHint("Setzt alle Filter zurück und lädt alle Screenshots")
            } else {
                Text("Screenshots werden automatisch aufgenommen")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Keine Screenshots gefunden")
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(thumbnailAccessibilityLabel)
        .accessibilityHint(isSelected ? "Ausgewählt. Doppeltippen für Kontextmenü" : "Doppeltippen zum Auswählen")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var thumbnailAccessibilityLabel: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        let appName = screenshot.appName ?? "Unbekannte App"
        return "Screenshot von \(appName), \(formatter.string(from: screenshot.timestamp))"
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
                            .accessibilityLabel("Screenshot-Vorschau von \(screenshot.appName ?? "Unbekannt")")
                            .accessibilityHint("Doppeltippen für Quick Look")
                    } else {
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .aspectRatio(16/9, contentMode: .fit)
                            .cornerRadius(8)
                            .overlay { ProgressView() }
                            .accessibilityLabel("Screenshot wird geladen")
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
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Screenshot-Details")

                    // OCR Text
                    if let text = ocrText, !text.isEmpty {
                        GroupBox("Erkannter Text") {
                            Text(text)
                                .font(.caption)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .accessibilityElement(children: .contain)
                        .accessibilityLabel("Erkannter Text: \(String(text.prefix(200)))")
                    }

                    // Actions
                    HStack {
                        Button(action: { viewModel.showInFinder(screenshot) }) {
                            Label("Im Finder", systemImage: "folder")
                        }
                        .accessibilityHint("Öffnet den Ordner mit dem Screenshot im Finder")

                        Button(action: { viewModel.openWithQuickLook(screenshot) }) {
                            Label("Quick Look", systemImage: "eye")
                        }
                        .accessibilityHint("Zeigt den Screenshot in Quick Look an")

                        Spacer()

                        Button(role: .destructive) {
                            Task { await viewModel.deleteScreenshot(screenshot) }
                        } label: {
                            Label("Loeschen", systemImage: "trash")
                        }
                        .accessibilityHint("Löscht den Screenshot unwiderruflich")
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}
