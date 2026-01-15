import XCTest
@testable import Scrainee

/// Tests for the HashTracker actor (thread-safe hash tracking per display)
final class HashTrackerTests: XCTestCase {

    var sut: HashTracker!

    override func setUp() async throws {
        sut = HashTracker()
    }

    override func tearDown() async throws {
        await sut.reset()
        sut = nil
    }

    // MARK: - Basic Functionality Tests

    func testSetAndGetHash() async throws {
        // Given
        let displayId: UInt32 = 1
        let hash = "abc123def456"

        // When
        await sut.setLastHash(hash, for: displayId)
        let retrievedHash = await sut.getLastHash(for: displayId)

        // Then
        XCTAssertEqual(retrievedHash, hash)
    }

    func testGetHashForNonExistentDisplay() async throws {
        // Given
        let displayId: UInt32 = 999

        // When
        let hash = await sut.getLastHash(for: displayId)

        // Then
        XCTAssertNil(hash)
    }

    func testIsDuplicate_withSameHash_returnsTrue() async throws {
        // Given
        let displayId: UInt32 = 1
        let hash = "abc123"
        await sut.setLastHash(hash, for: displayId)

        // When
        let isDuplicate = await sut.isDuplicate(hash, for: displayId)

        // Then
        XCTAssertTrue(isDuplicate)
    }

    func testIsDuplicate_withDifferentHash_returnsFalse() async throws {
        // Given
        let displayId: UInt32 = 1
        await sut.setLastHash("abc123", for: displayId)

        // When
        let isDuplicate = await sut.isDuplicate("xyz789", for: displayId)

        // Then
        XCTAssertFalse(isDuplicate)
    }

    func testIsDuplicate_withNoStoredHash_returnsFalse() async throws {
        // Given
        let displayId: UInt32 = 1

        // When
        let isDuplicate = await sut.isDuplicate("abc123", for: displayId)

        // Then
        XCTAssertFalse(isDuplicate)
    }

    // MARK: - Multi-Display Tests

    func testSameHashDifferentDisplays_notDuplicate() async throws {
        // Given
        let hash = "same_hash"
        await sut.setLastHash(hash, for: 1)

        // When - check same hash on different display
        let isDuplicate = await sut.isDuplicate(hash, for: 2)

        // Then - should not be duplicate (different display)
        XCTAssertFalse(isDuplicate)
    }

    func testMultipleDisplaysIndependentTracking() async throws {
        // Given
        await sut.setLastHash("hash_display_1", for: 1)
        await sut.setLastHash("hash_display_2", for: 2)
        await sut.setLastHash("hash_display_3", for: 3)

        // When
        let hash1 = await sut.getLastHash(for: 1)
        let hash2 = await sut.getLastHash(for: 2)
        let hash3 = await sut.getLastHash(for: 3)

        // Then
        XCTAssertEqual(hash1, "hash_display_1")
        XCTAssertEqual(hash2, "hash_display_2")
        XCTAssertEqual(hash3, "hash_display_3")
    }

    // MARK: - Reset Tests

    func testReset_clearsAllHashes() async throws {
        // Given
        await sut.setLastHash("hash1", for: 1)
        await sut.setLastHash("hash2", for: 2)

        // When
        await sut.reset()

        // Then
        let hash1 = await sut.getLastHash(for: 1)
        let hash2 = await sut.getLastHash(for: 2)
        XCTAssertNil(hash1)
        XCTAssertNil(hash2)
    }

    func testRemoveHash_removesSpecificDisplay() async throws {
        // Given
        await sut.setLastHash("hash1", for: 1)
        await sut.setLastHash("hash2", for: 2)

        // When
        await sut.removeHash(for: 1)

        // Then
        let hash1 = await sut.getLastHash(for: 1)
        let hash2 = await sut.getLastHash(for: 2)
        XCTAssertNil(hash1)
        XCTAssertEqual(hash2, "hash2")
    }

    // MARK: - Thread Safety Tests

    func testConcurrentAccess_isThreadSafe() async throws {
        // Given
        let iterations = 1000
        let displayCount: UInt32 = 5
        let hashTracker = sut!

        // When - concurrent writes and reads from multiple tasks
        await withTaskGroup(of: Void.self) { group in
            // Writers
            for i in 0..<iterations {
                let idx = i
                group.addTask {
                    let displayId = UInt32(idx) % displayCount
                    await hashTracker.setLastHash("hash_\(idx)", for: displayId)
                }
            }

            // Readers
            for i in 0..<iterations {
                let idx = i
                group.addTask {
                    let displayId = UInt32(idx) % displayCount
                    _ = await hashTracker.getLastHash(for: displayId)
                }
            }

            // Duplicate checkers
            for i in 0..<iterations {
                let idx = i
                group.addTask {
                    let displayId = UInt32(idx) % displayCount
                    _ = await hashTracker.isDuplicate("hash_\(idx)", for: displayId)
                }
            }
        }

        // Then - no crashes means thread safety is working
        // Verify we have tracked displays
        let trackedIds = await sut.trackedDisplayIds()
        XCTAssertFalse(trackedIds.isEmpty)
    }

    // MARK: - Stats Tests

    func testGetStats() async throws {
        // Given
        await sut.setLastHash("hash1", for: 1)
        await sut.setLastHash("hash2", for: 2)
        await sut.setLastHash("hash3", for: 3)

        // When
        let stats = await sut.getStats()

        // Then
        XCTAssertEqual(stats.displayCount, 3)
        XCTAssertEqual(stats.totalCaptures, 3)
    }

    func testTrackedDisplayIds() async throws {
        // Given
        await sut.setLastHash("hash1", for: 1)
        await sut.setLastHash("hash2", for: 5)
        await sut.setLastHash("hash3", for: 10)

        // When
        let trackedIds = await sut.trackedDisplayIds()

        // Then
        XCTAssertEqual(trackedIds, Set([1, 5, 10]))
    }
}
