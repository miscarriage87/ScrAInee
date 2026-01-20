// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - DEPENDENCY DOCUMENTATION
// ═══════════════════════════════════════════════════════════════════════════════
//
// FILE: ThumbnailCache | PURPOSE: LRU-Cache fuer Screenshot-Thumbnails | LAYER: Core/Cache
//
// DEPENDENCIES: AppKit (NSImage), CoreGraphics (CGImageSource)
// DEPENDENTS: TimelineThumbnailStrip, TimelineViewModel, E2E-Tests
// CHANGE IMPACT: Aenderungen betreffen Timeline-Performance und Speicherverbrauch
//
// LAST UPDATED: 2026-01-20
// ═══════════════════════════════════════════════════════════════════════════════

import AppKit
import Foundation

/// Thread-safe cache for screenshot thumbnails with LRU eviction
actor ThumbnailCache {
    static let shared = ThumbnailCache()

    // MARK: - Configuration

    private let maxCacheSize = 500
    private let thumbnailSize = CGSize(width: 200, height: 120)

    // MARK: - Cache Storage

    private var cache: [Int64: NSImage] = [:]
    private var accessOrder: [Int64] = []  // LRU tracking

    private init() {}

    // MARK: - Public API

    /// Gets a thumbnail from cache or loads it from disk
    func thumbnail(for screenshotId: Int64, url: URL) async -> NSImage? {
        // Check cache first
        if let cached = cache[screenshotId] {
            updateAccessOrder(screenshotId)
            return cached
        }

        // Load from disk
        guard let image = await loadThumbnail(from: url) else {
            return nil
        }

        // Store in cache
        store(image, for: screenshotId)
        return image
    }

    /// Preloads thumbnails for a list of screenshots
    func preload(_ screenshots: [Screenshot]) async {
        for screenshot in screenshots {
            guard let id = screenshot.id else { continue }
            // Skip if already cached
            if cache[id] != nil { continue }

            if let image = await loadThumbnail(from: screenshot.fileURL) {
                store(image, for: id)
            }
        }
    }

    /// Preloads thumbnails around a specific index
    func preloadAround(screenshots: [Screenshot], currentIndex: Int, range: Int = 50) async {
        let startIndex = max(0, currentIndex - range)
        let endIndex = min(screenshots.count - 1, currentIndex + range)

        guard startIndex <= endIndex else { return }

        let toPreload = Array(screenshots[startIndex...endIndex])
        await preload(toPreload)
    }

    /// Removes a specific thumbnail from cache
    func remove(_ screenshotId: Int64) {
        cache.removeValue(forKey: screenshotId)
        accessOrder.removeAll { $0 == screenshotId }
    }

    /// Clears the entire cache
    func clearAll() {
        cache.removeAll()
        accessOrder.removeAll()
    }

    /// Returns current cache size
    var cacheSize: Int {
        cache.count
    }

    // MARK: - Private Methods

    private func loadThumbnail(from url: URL) async -> NSImage? {
        // Run on background thread
        return await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
                return nil
            }

            let options: [CFString: Any] = [
                kCGImageSourceThumbnailMaxPixelSize: max(self.thumbnailSize.width, self.thumbnailSize.height),
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true
            ]

            guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                return nil
            }

            return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        }.value
    }

    private func store(_ image: NSImage, for screenshotId: Int64) {
        // Evict if at capacity
        while cache.count >= maxCacheSize {
            evictOldest()
        }

        cache[screenshotId] = image
        accessOrder.append(screenshotId)
    }

    private func updateAccessOrder(_ screenshotId: Int64) {
        // Move to end (most recently used)
        accessOrder.removeAll { $0 == screenshotId }
        accessOrder.append(screenshotId)
    }

    private func evictOldest() {
        guard let oldest = accessOrder.first else { return }
        accessOrder.removeFirst()
        cache.removeValue(forKey: oldest)
    }
}

// MARK: - ThumbnailView Helper

/// A view that loads and displays a thumbnail asynchronously
import SwiftUI

struct AsyncThumbnail: View {
    let screenshot: Screenshot
    @State private var image: NSImage?
    @State private var isLoading = true

    var body: some View {
        Group {
            if let image = image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if isLoading {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .overlay(
                        ProgressView()
                            .scaleEffect(0.5)
                    )
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .overlay(
                        Image(systemName: "photo")
                            .foregroundColor(.gray)
                    )
            }
        }
        .task {
            await loadThumbnail()
        }
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
