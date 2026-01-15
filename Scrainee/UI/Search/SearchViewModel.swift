import Foundation
import Combine

/// View model for search functionality
@MainActor
final class SearchViewModel: ObservableObject {
    @Published var results: [SearchResult] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private var searchTask: Task<Void, Never>?
    private var debounceTask: Task<Void, Never>?

    // MARK: - Search

    /// Performs a search with the given query
    func search(query: String) async {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            clearResults()
            return
        }

        // Cancel previous search
        searchTask?.cancel()

        isLoading = true
        errorMessage = nil

        searchTask = Task {
            do {
                let searchResults = try await DatabaseManager.shared.searchOCR(query: query, limit: 100)

                if !Task.isCancelled {
                    self.results = searchResults
                }
            } catch {
                if !Task.isCancelled {
                    self.errorMessage = error.localizedDescription
                    self.results = []
                }
            }

            if !Task.isCancelled {
                self.isLoading = false
            }
        }
    }

    /// Debounced search - waits 300ms after last keystroke
    func debounceSearch(query: String) {
        debounceTask?.cancel()

        guard !query.isEmpty else {
            clearResults()
            return
        }

        debounceTask = Task {
            do {
                try await Task.sleep(nanoseconds: 300_000_000) // 300ms

                if !Task.isCancelled {
                    await search(query: query)
                }
            } catch {
                // Task was cancelled
            }
        }
    }

    /// Clears search results
    func clearResults() {
        searchTask?.cancel()
        debounceTask?.cancel()
        results = []
        isLoading = false
        errorMessage = nil
    }

    // MARK: - Filtering

    /// Filters results by app bundle identifier
    func filterByApp(_ appBundleId: String) -> [SearchResult] {
        results.filter { $0.appBundleId == appBundleId }
    }

    /// Filters results by date range
    func filterByDateRange(from: Date, to: Date) -> [SearchResult] {
        results.filter { $0.timestamp >= from && $0.timestamp <= to }
    }
}
