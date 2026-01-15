@preconcurrency import ScreenCaptureKit
import CoreGraphics
import AppKit
import Combine

// MARK: - Delegate Protocol

protocol ScreenCaptureManagerDelegate: AnyObject {
    func screenCaptureManager(_ manager: ScreenCaptureManager, didCaptureScreenshot screenshot: Screenshot)
    func screenCaptureManager(_ manager: ScreenCaptureManager, didFailWithError error: Error)
}

// MARK: - Screen Capture Manager

/// Manages periodic screen capture using ScreenCaptureKit
/// Supports multi-monitor capture with parallel processing
@MainActor
final class ScreenCaptureManager: ObservableObject {
    weak var delegate: ScreenCaptureManagerDelegate?

    @Published private(set) var isCapturing = false
    @Published private(set) var captureCount = 0
    @Published private(set) var activeDisplayCount = 0

    private var captureTimer: Timer?
    private var currentInterval: TimeInterval = 3.0

    // Thread-safe hash tracking per display (replaces lastImageHash)
    private let hashTracker = HashTracker()

    private let databaseManager = DatabaseManager.shared
    private let ocrManager = OCRManager()
    private let imageCompressor = ImageCompressor()
    private let storageManager = StorageManager.shared
    private let displayManager: DisplayProviding

    /// Adaptive capture manager for dynamic interval adjustment
    let adaptiveManager = AdaptiveCaptureManager()
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    // Designated initializer without default argument to avoid nonisolated default evaluation
    init(displayManager: DisplayProviding) {
        self.displayManager = displayManager
    }

    // Convenience initializer that safely accesses DisplayManager.shared on the main actor
    convenience init() {
        self.init(displayManager: DisplayManager.shared)
    }

    // MARK: - Capture Control

    /// Starts capturing screenshots at the specified interval
    func startCapturing(interval: TimeInterval = 3.0) async throws {
        guard !isCapturing else { return }

        // Verify permission - try to request if not available
        let permissionManager = PermissionManager.shared
        var hasPermission = await permissionManager.checkScreenCapturePermission()

        if !hasPermission {
            // Try to request permission
            hasPermission = await permissionManager.requestScreenCapturePermission()
        }

        guard hasPermission else {
            throw CaptureError.noPermission
        }

        // Configure adaptive manager with base interval
        adaptiveManager.setBaseInterval(interval)
        adaptiveManager.resetDuplicateDetection()
        currentInterval = interval
        isCapturing = true
        captureCount = 0

        // Set up interval change monitoring
        setupIntervalMonitoring()

        // Start timer on main thread
        startCaptureTimer()
    }

    private func startCaptureTimer() {
        captureTimer?.invalidate()

        // Get adaptive interval based on current state
        let interval = adaptiveManager.getInterval(isMeeting: AppState.shared.isMeetingActive)
        currentInterval = interval

        captureTimer = Timer.scheduledTimer(
            withTimeInterval: interval,
            repeats: true
        ) { [weak self] _ in
            Task {
                await self?.captureScreen()
                await self?.checkAndUpdateInterval()
            }
        }
        // Fire immediately for first capture
        captureTimer?.fire()
    }

    private func setupIntervalMonitoring() {
        // Listen for meeting state changes
        NotificationCenter.default.publisher(for: .meetingStarted)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.handleMeetingStateChanged()
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .meetingEnded)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.handleMeetingStateChanged()
                }
            }
            .store(in: &cancellables)

        // Listen for idle state changes
        NotificationCenter.default.publisher(for: .captureIdleStateChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.checkAndUpdateInterval()
                }
            }
            .store(in: &cancellables)
    }

    private func handleMeetingStateChanged() {
        guard isCapturing else { return }
        let newInterval = adaptiveManager.getInterval(isMeeting: AppState.shared.isMeetingActive)
        if abs(newInterval - currentInterval) > 0.1 {
            startCaptureTimer()
        }
    }

    private func checkAndUpdateInterval() {
        guard isCapturing else { return }
        let newInterval = adaptiveManager.getInterval(isMeeting: AppState.shared.isMeetingActive)
        if abs(newInterval - currentInterval) > 0.1 {
            startCaptureTimer()
        }
    }

    /// Stops capturing screenshots
    func stopCapturing() {
        captureTimer?.invalidate()
        captureTimer = nil
        isCapturing = false
        cancellables.removeAll()

        // Reset hash tracker
        Task {
            await hashTracker.reset()
        }
    }

    /// Updates the capture interval
    func updateInterval(_ interval: TimeInterval) async throws {
        guard isCapturing else {
            currentInterval = interval
            return
        }

        stopCapturing()
        try await startCapturing(interval: interval)
    }

    // MARK: - Screenshot Capture (Multi-Monitor)

    /// Captures all available displays in parallel
    private func captureScreen() async {
        do {
            // Get available content
            let content = try await SCShareableContent.current

            guard !content.displays.isEmpty else {
                throw CaptureError.noDisplay
            }

            // Update display count
            activeDisplayCount = content.displays.count

            // Create filter (exclude our own app)
            let excludedApps = content.applications.filter { app in
                app.bundleIdentifier == Bundle.main.bundleIdentifier
            }

            // Capture all displays sequentially (required for Swift 6 Sendable compliance)
            for display in content.displays {
                await captureSingleDisplay(display, excludingApps: excludedApps)
            }

        } catch {
            delegate?.screenCaptureManager(self, didFailWithError: error)
        }
    }

    /// Captures a single display
    private func captureSingleDisplay(_ display: SCDisplay, excludingApps: [SCRunningApplication]) async {
        print("[DEBUG] captureSingleDisplay aufgerufen für Display \(display.displayID)")
        do {
            let filter = SCContentFilter(
                display: display,
                excludingApplications: excludingApps,
                exceptingWindows: []
            )

            // Configure capture for this specific display
            let configuration = SCStreamConfiguration()
            configuration.width = display.width
            configuration.height = display.height
            configuration.pixelFormat = kCVPixelFormatType_32BGRA
            configuration.showsCursor = false
            if #available(macOS 14.0, *) {
                configuration.captureResolution = .best
            } else {
                // Fallback on earlier versions
            }
            configuration.scalesToFit = false

            // Hoist image outside the availability check
            var capturedImage: CGImage?

            // Capture screenshot using modern API (macOS 14+)
            if #available(macOS 14.0, *) {
                capturedImage = try await SCScreenshotManager.captureImage(
                    contentFilter: filter,
                    configuration: configuration
                )
            } else {
                // Fallback on earlier versions - not implemented, skip
                return
            }

            guard let image = capturedImage else {
                throw CaptureError.captureFailure
            }

            // Process the screenshot with display-specific hash tracking
            await processScreenshot(image, displayId: display.displayID)

        } catch {
            // Log error but don't stop other displays from capturing
            print("Fehler beim Erfassen von Display \(display.displayID): \(error.localizedDescription)")
        }
    }

    // MARK: - Screenshot Processing

    private func processScreenshot(_ cgImage: CGImage, displayId: UInt32) async {
        // 1. Calculate perceptual hash for deduplication
        let hash = calculatePerceptualHash(cgImage)

        // 2. Thread-safe duplicate check per display using HashTracker actor
        let isDuplicate = await hashTracker.isDuplicate(hash, for: displayId)
        if isDuplicate {
            print("[DEBUG] Screenshot als Duplikat erkannt, überspringe")
            adaptiveManager.reportDuplicate()
            return
        }
        print("[DEBUG] Screenshot ist einzigartig, verarbeite weiter...")

        // Update hash for this display
        await hashTracker.setLastHash(hash, for: displayId)
        adaptiveManager.reportUnique()

        // 3. Get active app info
        let activeApp = NSWorkspace.shared.frontmostApplication
        let appName = activeApp?.localizedName
        let bundleId = activeApp?.bundleIdentifier
        let windowTitle = getActiveWindowTitle()

        // 3. Save as HEIC
        guard let filepath = try? await imageCompressor.saveAsHEIC(
            cgImage,
            quality: AppState.shared.heicQuality
        ) else {
            return
        }

        // 4. Get file size
        let fullPath = storageManager.screenshotsDirectory.appendingPathComponent(filepath)
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: fullPath.path)[.size] as? Int) ?? 0

        // 5. Create screenshot record
        var screenshot = Screenshot(
            filepath: filepath,
            timestamp: Date(),
            appBundleId: bundleId,
            appName: appName,
            windowTitle: windowTitle,
            displayId: Int(displayId),
            width: cgImage.width,
            height: cgImage.height,
            fileSize: fileSize,
            isDuplicate: false,
            hash: hash
        )

        // 6. Save to database
        do {
            print("[DEBUG] Speichere Screenshot in Datenbank...")
            let id = try await databaseManager.insert(screenshot)
            screenshot.id = id
            captureCount += 1
            print("[DEBUG] Screenshot gespeichert mit ID: \(id)")

            // Notify delegate
            delegate?.screenCaptureManager(self, didCaptureScreenshot: screenshot)

            // 7. Perform OCR in background if enabled
            if AppState.shared.ocrEnabled {
                Task.detached(priority: .background) { [weak self] in
                    guard let self = self else { return }
                    await self.performOCR(on: cgImage, screenshotId: id)
                }
            }
        } catch {
            print("[ERROR] Screenshot speichern fehlgeschlagen: \(error)")
            delegate?.screenCaptureManager(self, didFailWithError: error)
        }
    }

    // MARK: - Perceptual Hash (dHash Algorithm)

    private func calculatePerceptualHash(_ image: CGImage) -> String {
        // Simple difference hash (dHash) algorithm
        // Resize to 9x8, convert to grayscale, compute horizontal differences

        let size = CGSize(width: 9, height: 8)

        guard let context = CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: Int(size.width),
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return UUID().uuidString
        }

        context.draw(image, in: CGRect(origin: .zero, size: size))

        guard let data = context.data else {
            return UUID().uuidString
        }

        let pixels = data.bindMemory(to: UInt8.self, capacity: Int(size.width * size.height))
        var hash: UInt64 = 0

        for y in 0..<8 {
            for x in 0..<8 {
                let left = pixels[y * 9 + x]
                let right = pixels[y * 9 + x + 1]
                if left > right {
                    hash |= 1 << (y * 8 + x)
                }
            }
        }

        return String(format: "%016llx", hash)
    }

    // MARK: - Window Title (via Accessibility API)

    private func getActiveWindowTitle() -> String? {
        guard PermissionManager.shared.checkAccessibilityPermission() else {
            return nil
        }

        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            return nil
        }

        let appElement = AXUIElementCreateApplication(frontApp.processIdentifier)

        var focusedWindow: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            &focusedWindow
        )

        guard result == .success, let windowElement = focusedWindow else {
            return nil
        }

        var title: CFTypeRef?
        let titleResult = AXUIElementCopyAttributeValue(
            windowElement as! AXUIElement,
            kAXTitleAttribute as CFString,
            &title
        )

        guard titleResult == .success, let windowTitle = title as? String else {
            return nil
        }

        return windowTitle
    }

    // MARK: - OCR Processing

    private func performOCR(on image: CGImage, screenshotId: Int64) async {
        let result = await ocrManager.recognizeText(in: image)

        guard let text = result.text, !text.isEmpty else {
            return
        }

        let ocrResult = OCRResult(
            screenshotId: screenshotId,
            text: text,
            confidence: result.confidence,
            language: result.language,
            wordCount: text.split(separator: " ").count
        )

        do {
            try await databaseManager.insert(ocrResult)
        } catch {
            // Log OCR insertion error but don't propagate since this is background processing
            print("Failed to insert OCR result: \(error)")
        }
    }
}

// MARK: - Errors

enum CaptureError: LocalizedError {
    case noPermission
    case noDisplay
    case captureFailure
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .noPermission:
            return "Keine Berechtigung fuer Bildschirmaufnahme"
        case .noDisplay:
            return "Kein Display gefunden"
        case .captureFailure:
            return "Screenshot konnte nicht erstellt werden"
        case .saveFailed:
            return "Screenshot konnte nicht gespeichert werden"
        }
    }
}
