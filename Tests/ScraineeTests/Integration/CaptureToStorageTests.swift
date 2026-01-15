import XCTest
@testable import Scrainee

/// Integration tests for the capture-to-storage pipeline
final class CaptureToStorageTests: XCTestCase {

    // MARK: - HashTracker Integration Tests

    func testHashTracker_multiDisplayWorkflow() async throws {
        // Given - simulate multi-monitor setup
        let hashTracker = HashTracker()
        let displays: [UInt32] = [1, 2, 3]
        let initialHashes = ["hash_d1_v1", "hash_d2_v1", "hash_d3_v1"]

        // When - set initial hashes for all displays
        for (index, displayId) in displays.enumerated() {
            await hashTracker.setLastHash(initialHashes[index], for: displayId)
        }

        // Then - verify all hashes are stored correctly
        for (index, displayId) in displays.enumerated() {
            let hash = await hashTracker.getLastHash(for: displayId)
            XCTAssertEqual(hash, initialHashes[index])
        }
    }

    func testHashTracker_duplicateDetectionPerDisplay() async throws {
        // Given
        let hashTracker = HashTracker()

        // Set different hashes for different displays
        await hashTracker.setLastHash("unique_hash_1", for: 1)
        await hashTracker.setLastHash("unique_hash_2", for: 2)

        // When - check same hash on display 1
        let isDuplicateOnDisplay1 = await hashTracker.isDuplicate("unique_hash_1", for: 1)
        // Check same hash on display 2 (should not be duplicate - different display)
        let isNotDuplicateOnDisplay2 = await hashTracker.isDuplicate("unique_hash_1", for: 2)

        // Then
        XCTAssertTrue(isDuplicateOnDisplay1)
        XCTAssertFalse(isNotDuplicateOnDisplay2)
    }

    func testHashTracker_parallelCaptureSimulation() async throws {
        // Given - simulate parallel capture from 3 displays
        let hashTracker = HashTracker()
        let captureCount = 100

        // When - simulate parallel captures
        await withTaskGroup(of: Void.self) { group in
            for captureNumber in 0..<captureCount {
                // Display 1
                group.addTask {
                    let hash = "capture_\(captureNumber)_display_1"
                    let isDupe = await hashTracker.isDuplicate(hash, for: 1)
                    if !isDupe {
                        await hashTracker.setLastHash(hash, for: 1)
                    }
                }

                // Display 2
                group.addTask {
                    let hash = "capture_\(captureNumber)_display_2"
                    let isDupe = await hashTracker.isDuplicate(hash, for: 2)
                    if !isDupe {
                        await hashTracker.setLastHash(hash, for: 2)
                    }
                }

                // Display 3
                group.addTask {
                    let hash = "capture_\(captureNumber)_display_3"
                    let isDupe = await hashTracker.isDuplicate(hash, for: 3)
                    if !isDupe {
                        await hashTracker.setLastHash(hash, for: 3)
                    }
                }
            }
        }

        // Then - verify no crashes and all displays are tracked
        let stats = await hashTracker.getStats()
        XCTAssertEqual(stats.displayCount, 3)
    }

    // MARK: - Display Management Integration Tests

    func testMockDisplayManager_hotPlugSimulation() async throws {
        // Given - start with single display
        let displayManager = MockDisplayManager.singleDisplay()
        var displayChanges: [[DisplayInfo]] = []

        let cancellable = displayManager.displaysChangedPublisher.sink { displays in
            displayChanges.append(displays)
        }
        defer { cancellable.cancel() }

        // When - simulate connecting second display
        let dualDisplays = [
            DisplayInfo(id: 1, width: 1920, height: 1080, isMain: true, displayName: "Built-in"),
            DisplayInfo(id: 2, width: 2560, height: 1440, isMain: false, displayName: "External")
        ]
        displayManager.simulateDisplayChange(dualDisplays)

        // Then - simulate disconnecting
        let singleDisplay = [
            DisplayInfo(id: 1, width: 1920, height: 1080, isMain: true, displayName: "Built-in")
        ]
        displayManager.simulateDisplayChange(singleDisplay)

        // Verify changes were received
        XCTAssertEqual(displayChanges.count, 2)
        XCTAssertEqual(displayChanges[0].count, 2) // Dual display
        XCTAssertEqual(displayChanges[1].count, 1) // Back to single
    }

    // MARK: - SearchResult Integration Tests

    func testSearchResult_filterByApp() {
        // Given
        let results = [
            SearchResult(
                id: 1,
                filepath: "test1.heic",
                timestamp: Date(),
                appName: "Safari",
                appBundleId: "com.apple.Safari",
                windowTitle: "Google",
                text: "search results",
                highlightedText: nil
            ),
            SearchResult(
                id: 2,
                filepath: "test2.heic",
                timestamp: Date(),
                appName: "Xcode",
                appBundleId: "com.apple.dt.Xcode",
                windowTitle: "Project",
                text: "code content",
                highlightedText: nil
            ),
            SearchResult(
                id: 3,
                filepath: "test3.heic",
                timestamp: Date(),
                appName: "Safari",
                appBundleId: "com.apple.Safari",
                windowTitle: "Apple",
                text: "apple website",
                highlightedText: nil
            )
        ]

        // When
        let safariResults = results.filter { $0.appBundleId == "com.apple.Safari" }
        let xcodeResults = results.filter { $0.appBundleId == "com.apple.dt.Xcode" }

        // Then
        XCTAssertEqual(safariResults.count, 2)
        XCTAssertEqual(xcodeResults.count, 1)
    }

    func testSearchResult_filterByDateRange() {
        // Given
        let now = Date()
        let oneHourAgo = now.addingTimeInterval(-3600)
        let twoHoursAgo = now.addingTimeInterval(-7200)
        let threeHoursAgo = now.addingTimeInterval(-10800)

        let results = [
            SearchResult(id: 1, filepath: "1.heic", timestamp: threeHoursAgo, appName: nil, appBundleId: nil, windowTitle: nil, text: "old", highlightedText: nil),
            SearchResult(id: 2, filepath: "2.heic", timestamp: twoHoursAgo, appName: nil, appBundleId: nil, windowTitle: nil, text: "middle", highlightedText: nil),
            SearchResult(id: 3, filepath: "3.heic", timestamp: oneHourAgo, appName: nil, appBundleId: nil, windowTitle: nil, text: "recent", highlightedText: nil),
            SearchResult(id: 4, filepath: "4.heic", timestamp: now, appName: nil, appBundleId: nil, windowTitle: nil, text: "now", highlightedText: nil)
        ]

        // When - filter last 2 hours
        let fromTime = now.addingTimeInterval(-7200)
        let filtered = results.filter { $0.timestamp >= fromTime && $0.timestamp <= now }

        // Then
        XCTAssertEqual(filtered.count, 3) // 2 hours ago, 1 hour ago, now
    }
}
