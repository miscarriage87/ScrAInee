// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - 📋 DEPENDENCY DOCUMENTATION
// ═══════════════════════════════════════════════════════════════════════════════
//
// FILE: GalleryViewModel.swift | PURPOSE: Pagination und Filter-Logik | LAYER: UI/Gallery
//
// DEPENDENCIES:
//   - DatabaseManager (Actor): Screenshot-Abfragen mit Pagination
//   - StorageManager: Dateipfad-Aufloesung fuer Screenshots
//   - Screenshot (Model): Screenshot-Entitaet
//   - GRDB: Datenbank-Framework (Import)
//
// DEPENDENTS:
//   - ScreenshotGalleryView.swift: @StateObject Consumer
//   - ScreenshotThumbnailView: @ObservedObject fuer Actions
//   - ScreenshotDetailView: @ObservedObject fuer Actions
//
// CHANGE IMPACT:
//   - Page-Size hier definiert (50 Screenshots pro Seite)
//   - Debounce-Zeit fuer Suche (300ms)
//   - Filter-Properties beeinflussen alle Abfragen
//
// LAST UPDATED: 2026-01-20
// ═══════════════════════════════════════════════════════════════════════════════

import SwiftUI
import Combine
import GRDB

/// ViewModel for the Screenshot Gallery with pagination and filtering
@MainActor
final class GalleryViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var screenshots: [Screenshot] = []
    @Published var selectedScreenshot: Screenshot?
    @Published var isLoading = false
    @Published var hasMorePages = true

    // Filters
    @Published var filterApp: String?
    @Published var filterDateFrom: Date?
    @Published var filterDateTo: Date?
    @Published var searchText: String = ""

    // MARK: - Private Properties

    private let pageSize = 50
    private var currentPage = 0
    private var cancellables = Set<AnyCancellable>()
    private let databaseManager = DatabaseManager.shared
    private let storageManager = StorageManager.shared

    // MARK: - Initialization

    init() {
        setupSearchDebounce()
    }

    // MARK: - Public Methods

    /// Loads the first page of screenshots
    func loadInitial() async {
        currentPage = 0
        screenshots = []
        hasMorePages = true
        await loadMore()
    }

    /// Loads the next page of screenshots
    func loadMore() async {
        guard !isLoading && hasMorePages else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            let offset = currentPage * pageSize
            let newScreenshots = try await fetchScreenshots(offset: offset, limit: pageSize)

            if newScreenshots.count < pageSize {
                hasMorePages = false
            }

            screenshots.append(contentsOf: newScreenshots)
            currentPage += 1
        } catch {
            FileLogger.shared.error("Failed to load screenshots: \(error)", context: "GalleryViewModel")
        }
    }

    /// Refreshes the gallery with current filters
    func refresh() async {
        await loadInitial()
    }

    /// Deletes a screenshot
    func deleteScreenshot(_ screenshot: Screenshot) async {
        guard let id = screenshot.id else { return }

        do {
            // Delete from database
            try await databaseManager.deleteScreenshot(id: id)

            // Delete file
            let fileURL = storageManager.screenshotsDirectory.appendingPathComponent(screenshot.filepath)
            try? FileManager.default.removeItem(at: fileURL)

            // Remove from list
            screenshots.removeAll { $0.id == id }

            // Deselect if selected
            if selectedScreenshot?.id == id {
                selectedScreenshot = nil
            }
        } catch {
            FileLogger.shared.error("Failed to delete screenshot: \(error)", context: "GalleryViewModel")
        }
    }

    /// Opens screenshot in Finder
    func showInFinder(_ screenshot: Screenshot) {
        let fileURL = storageManager.screenshotsDirectory.appendingPathComponent(screenshot.filepath)
        // Use activateFileViewerSelecting to ensure Finder opens (not third-party file managers)
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    }

    /// Opens screenshot with Quick Look
    func openWithQuickLook(_ screenshot: Screenshot) {
        let fileURL = storageManager.screenshotsDirectory.appendingPathComponent(screenshot.filepath)
        NSWorkspace.shared.open(fileURL)
    }

    /// Gets the file URL for a screenshot
    func fileURL(for screenshot: Screenshot) -> URL {
        storageManager.screenshotsDirectory.appendingPathComponent(screenshot.filepath)
    }

    /// Gets unique app names for filtering
    func getUniqueApps() async -> [String] {
        do {
            return try await databaseManager.getUniqueAppNames()
        } catch {
            return []
        }
    }

    // MARK: - Private Methods

    private func setupSearchDebounce() {
        $searchText
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                Task {
                    await self?.loadInitial()
                }
            }
            .store(in: &cancellables)
    }

    private func fetchScreenshots(offset: Int, limit: Int) async throws -> [Screenshot] {
        try await databaseManager.getScreenshots(
            offset: offset,
            limit: limit,
            appFilter: filterApp,
            dateFrom: filterDateFrom,
            dateTo: filterDateTo,
            searchText: searchText.isEmpty ? nil : searchText
        )
    }
}
