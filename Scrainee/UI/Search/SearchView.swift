import SwiftUI

struct SearchView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel = SearchViewModel()
    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Search header
            searchHeader

            Divider()

            // Content
            if viewModel.isLoading {
                loadingView
            } else if viewModel.results.isEmpty {
                emptyStateView
            } else {
                resultsView
            }
        }
        .frame(minWidth: 500, minHeight: 400)
        .onAppear {
            isSearchFocused = true
        }
    }

    // MARK: - Search Header

    private var searchHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
                .font(.title3)

            if #available(macOS 14.0, *) {
                TextField("In Screenshots suchen...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($isSearchFocused)
                    .onSubmit {
                        performSearch()
                    }
                    .onChange(of: searchText) { _, newValue in
                        // Debounced search
                        viewModel.debounceSearch(query: newValue)
                    }
            } else {
                // Fallback on earlier versions
            }

            if !searchText.isEmpty {
                Button(action: clearSearch) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }

            if viewModel.isLoading {
                ProgressView()
                    .scaleEffect(0.8)
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Results View

    private var resultsView: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                // Results count
                HStack {
                    Text("\(viewModel.results.count) Ergebnisse")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top, 8)

                ForEach(viewModel.results) { result in
                    SearchResultRow(result: result)
                        .onTapGesture {
                            openScreenshot(result)
                        }
                }
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()

            if searchText.isEmpty {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 48))
                    .foregroundColor(.secondary)

                Text("Nach Text in Screenshots suchen")
                    .font(.headline)
                    .foregroundColor(.secondary)

                Text("Gib einen Suchbegriff ein, um in allen aufgenommenen Screenshots zu suchen.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            } else {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 48))
                    .foregroundColor(.secondary)

                Text("Keine Ergebnisse")
                    .font(.headline)
                    .foregroundColor(.secondary)

                Text("Keine Screenshots mit \"\(searchText)\" gefunden.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
            Text("Suche...")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
        }
    }

    // MARK: - Actions

    private func performSearch() {
        Task {
            await viewModel.search(query: searchText)
        }
    }

    private func clearSearch() {
        searchText = ""
        viewModel.clearResults()
    }

    private func openScreenshot(_ result: SearchResult) {
        // Open screenshot in Preview or Quick Look
        NSWorkspace.shared.open(result.fileURL)
    }
}

// MARK: - Search Result Row

struct SearchResultRow: View {
    let result: SearchResult

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Thumbnail
            AsyncThumbnailView(url: result.fileURL)
                .frame(width: 100, height: 60)
                .cornerRadius(6)
                .shadow(radius: 1)

            // Content
            VStack(alignment: .leading, spacing: 4) {
                // App name and time
                HStack {
                    if let appName = result.appName {
                        Text(appName)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                    }

                    Spacer()

                    Text(result.timestamp, style: .relative)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                // Window title
                if let windowTitle = result.windowTitle, !windowTitle.isEmpty {
                    Text(windowTitle)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                // Matched text
                Text(highlightedText)
                    .font(.caption)
                    .lineLimit(2)
                    .foregroundColor(.primary)
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
        .contentShape(Rectangle())
    }

    private var highlightedText: AttributedString {
        guard let highlighted = result.highlightedText else {
            return AttributedString(result.text.prefix(150) + (result.text.count > 150 ? "..." : ""))
        }

        // Convert <mark> tags to attributed string highlights
        var text = highlighted
            .replacingOccurrences(of: "<mark>", with: "")
            .replacingOccurrences(of: "</mark>", with: "")

        if text.count > 150 {
            text = String(text.prefix(150)) + "..."
        }

        return AttributedString(text)
    }
}

// MARK: - Async Thumbnail View

struct AsyncThumbnailView: View {
    let url: URL
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image = image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle()
                    .fill(Color.secondary.opacity(0.2))
                    .overlay {
                        ProgressView()
                            .scaleEffect(0.5)
                    }
            }
        }
        .task {
            await loadThumbnail()
        }
    }

    private func loadThumbnail() async {
        // Load thumbnail in background
        let cgImage = await Task.detached(priority: .background) { () -> CGImage? in
            let compressor = ImageCompressor()
            return compressor.createThumbnail(from: url, maxSize: 200)
        }.value

        await MainActor.run {
            if let cgImage = cgImage {
                self.image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            }
        }
    }
}

// MARK: - Preview

#Preview {
    SearchView()
        .environmentObject(AppState.shared)
        .frame(width: 600, height: 500)
}
