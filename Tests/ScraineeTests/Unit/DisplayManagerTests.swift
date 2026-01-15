import XCTest
@testable import Scrainee

/// Tests for DisplayInfo model and DisplayManager functionality
final class DisplayManagerTests: XCTestCase {

    // MARK: - DisplayInfo Model Tests

    func testDisplayInfo_initialization() {
        // Given/When
        let display = DisplayInfo(
            id: 12345,
            width: 2560,
            height: 1440,
            isMain: true,
            displayName: "Test Display"
        )

        // Then
        XCTAssertEqual(display.id, 12345)
        XCTAssertEqual(display.displayId, 12345)
        XCTAssertEqual(display.width, 2560)
        XCTAssertEqual(display.height, 1440)
        XCTAssertTrue(display.isMain)
        XCTAssertEqual(display.displayName, "Test Display")
    }

    func testDisplayInfo_resolution() {
        // Given
        let display = DisplayInfo(
            id: 1,
            width: 1920,
            height: 1080,
            isMain: false,
            displayName: "HD Display"
        )

        // When
        let resolution = display.resolution

        // Then
        XCTAssertEqual(resolution, "1920 x 1080")
    }

    func testDisplayInfo_equatable() {
        // Given
        let display1 = DisplayInfo(id: 1, width: 1920, height: 1080, isMain: true, displayName: "Display 1")
        let display2 = DisplayInfo(id: 1, width: 1920, height: 1080, isMain: true, displayName: "Display 1")
        let display3 = DisplayInfo(id: 2, width: 1920, height: 1080, isMain: false, displayName: "Display 2")

        // Then
        XCTAssertEqual(display1, display2)
        XCTAssertNotEqual(display1, display3)
    }

    func testDisplayInfo_identifiable() {
        // Given
        let displays = [
            DisplayInfo(id: 1, width: 1920, height: 1080, isMain: true, displayName: "Display 1"),
            DisplayInfo(id: 2, width: 2560, height: 1440, isMain: false, displayName: "Display 2")
        ]

        // Then - can be used in SwiftUI ForEach
        XCTAssertEqual(displays.map { $0.id }, [1, 2])
    }

    // MARK: - MockDisplayManager Tests

    func testMockDisplayManager_singleDisplay() async throws {
        // Given
        let mock = MockDisplayManager.singleDisplay()

        // When
        let displays = try await mock.getAvailableDisplays()

        // Then
        XCTAssertEqual(displays.count, 1)
        XCTAssertTrue(displays[0].isMain)
        XCTAssertEqual(displays[0].displayName, "Built-in Display")
    }

    func testMockDisplayManager_dualDisplay() async throws {
        // Given
        let mock = MockDisplayManager.dualDisplay()

        // When
        let displays = try await mock.getAvailableDisplays()

        // Then
        XCTAssertEqual(displays.count, 2)
        XCTAssertTrue(displays.contains { $0.isMain })
        XCTAssertTrue(displays.contains { !$0.isMain })
    }

    func testMockDisplayManager_tripleDisplay() async throws {
        // Given
        let mock = MockDisplayManager.tripleDisplay()

        // When
        let displays = try await mock.getAvailableDisplays()

        // Then
        XCTAssertEqual(displays.count, 3)
        let mainDisplays = displays.filter { $0.isMain }
        XCTAssertEqual(mainDisplays.count, 1)
    }

    func testMockDisplayManager_noDisplays() async throws {
        // Given
        let mock = MockDisplayManager.noDisplays()

        // When
        let displays = try await mock.getAvailableDisplays()

        // Then
        XCTAssertTrue(displays.isEmpty)
    }

    func testMockDisplayManager_throwsError() async throws {
        // Given
        let mock = MockDisplayManager.withError(CaptureError.noDisplay)

        // When/Then
        do {
            _ = try await mock.getAvailableDisplays()
            XCTFail("Expected error to be thrown")
        } catch {
            XCTAssertTrue(error is CaptureError)
        }
    }

    func testMockDisplayManager_simulateDisplayChange() async throws {
        // Given
        let mock = MockDisplayManager.singleDisplay()
        var receivedDisplays: [DisplayInfo] = []

        let cancellable = mock.displaysChangedPublisher.sink { displays in
            receivedDisplays = displays
        }
        defer { cancellable.cancel() }

        // When - simulate adding a display
        let newDisplays = [
            DisplayInfo(id: 1, width: 1920, height: 1080, isMain: true, displayName: "Built-in"),
            DisplayInfo(id: 2, width: 3840, height: 2160, isMain: false, displayName: "4K External")
        ]
        mock.simulateDisplayChange(newDisplays)

        // Then
        XCTAssertEqual(mock.mockDisplays.count, 2)
        XCTAssertEqual(receivedDisplays.count, 2)
    }

    // MARK: - Display Variations

    func testCommonDisplayResolutions() {
        // Given - common resolutions
        let displays = [
            DisplayInfo(id: 1, width: 1920, height: 1080, isMain: false, displayName: "Full HD"),
            DisplayInfo(id: 2, width: 2560, height: 1440, isMain: false, displayName: "QHD"),
            DisplayInfo(id: 3, width: 3840, height: 2160, isMain: false, displayName: "4K UHD"),
            DisplayInfo(id: 4, width: 2880, height: 1800, isMain: true, displayName: "MacBook Pro 15\""),
            DisplayInfo(id: 5, width: 3024, height: 1964, isMain: true, displayName: "MacBook Pro 14\""),
            DisplayInfo(id: 6, width: 6016, height: 3384, isMain: false, displayName: "Pro Display XDR")
        ]

        // Then
        XCTAssertEqual(displays[0].resolution, "1920 x 1080")
        XCTAssertEqual(displays[1].resolution, "2560 x 1440")
        XCTAssertEqual(displays[2].resolution, "3840 x 2160")
        XCTAssertEqual(displays[3].resolution, "2880 x 1800")
        XCTAssertEqual(displays[4].resolution, "3024 x 1964")
        XCTAssertEqual(displays[5].resolution, "6016 x 3384")
    }
}
