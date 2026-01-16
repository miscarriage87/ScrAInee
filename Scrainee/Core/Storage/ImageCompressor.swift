import Foundation
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers

/// Handles compression and storage of screenshots as HEIC files
final class ImageCompressor: Sendable {
    private let storageManager = StorageManager.shared

    // MARK: - Save as HEIC

    /// Saves a CGImage as HEIC file with the specified quality
    /// - Parameters:
    ///   - image: The image to save
    ///   - quality: Compression quality (0.0 - 1.0, default 0.6)
    /// - Returns: Relative file path from screenshots directory
    func saveAsHEIC(_ image: CGImage, quality: Double = 0.6) async throws -> String {
        let filename = generateFilename()
        let url = storageManager.screenshotsDirectory.appendingPathComponent(filename)

        // Ensure directory exists
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        // Create HEIC destination
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.heic.identifier as CFString,
            1,
            nil
        ) else {
            throw CompressionError.destinationCreationFailed
        }

        // Set compression options - explicitly set no alpha for opaque screenshots
        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: quality,
            kCGImagePropertyHasAlpha: false
        ]

        CGImageDestinationAddImage(destination, image, options as CFDictionary)

        // Finalize
        guard CGImageDestinationFinalize(destination) else {
            throw CompressionError.finalizationFailed
        }

        return filename
    }

    // MARK: - Generate Thumbnail

    /// Creates a thumbnail from an image
    func createThumbnail(from imageURL: URL, maxSize: CGFloat = 200) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxSize,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]

        guard let source = CGImageSourceCreateWithURL(imageURL as CFURL, nil) else {
            return nil
        }

        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// Creates a thumbnail from a CGImage
    func createThumbnail(from image: CGImage, maxSize: CGFloat = 200) -> CGImage? {
        let scale = min(maxSize / CGFloat(image.width), maxSize / CGFloat(image.height))
        let newWidth = Int(CGFloat(image.width) * scale)
        let newHeight = Int(CGFloat(image.height) * scale)

        guard let context = CGContext(
            data: nil,
            width: newWidth,
            height: newHeight,
            bitsPerComponent: image.bitsPerComponent,
            bytesPerRow: 0,
            space: image.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: image.bitmapInfo.rawValue
        ) else {
            return nil
        }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))

        return context.makeImage()
    }

    // MARK: - Load Image

    /// Loads an image from disk
    func loadImage(at relativePath: String) -> CGImage? {
        let url = storageManager.screenshotsDirectory.appendingPathComponent(relativePath)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// Loads image data from disk
    func loadImageData(at relativePath: String) -> Data? {
        let url = storageManager.screenshotsDirectory.appendingPathComponent(relativePath)
        return try? Data(contentsOf: url)
    }

    /// Loads image data and converts HEIC to JPEG for API compatibility
    /// Claude API only supports: JPEG, PNG, GIF, WebP (NOT HEIC)
    func loadImageDataForAPI(at relativePath: String, quality: CGFloat = 0.8) -> Data? {
        let url = storageManager.screenshotsDirectory.appendingPathComponent(relativePath)

        // Load the image
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }

        // Check if it's HEIC - if so, convert to JPEG
        if let uti = CGImageSourceGetType(source) as String?,
           uti.contains("heic") || uti.contains("heif") {
            return convertToJPEG(cgImage, quality: quality)
        }

        // For other formats (PNG, JPEG, etc.), return original data
        return try? Data(contentsOf: url)
    }

    /// Converts a CGImage to JPEG data
    func convertToJPEG(_ image: CGImage, quality: CGFloat = 0.8) -> Data? {
        let mutableData = NSMutableData()

        guard let destination = CGImageDestinationCreateWithData(
            mutableData,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: quality
        ]

        CGImageDestinationAddImage(destination, image, options as CFDictionary)

        guard CGImageDestinationFinalize(destination) else {
            return nil
        }

        return mutableData as Data
    }

    // MARK: - Helpers

    private func generateFilename() -> String {
        let timestamp = Int(Date().timeIntervalSince1970)
        let uuid = UUID().uuidString.prefix(8)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy/MM/dd"
        let datePath = dateFormatter.string(from: Date())
        return "\(datePath)/screenshot_\(timestamp)_\(uuid).heic"
    }
}

// MARK: - Errors

enum CompressionError: LocalizedError {
    case destinationCreationFailed
    case finalizationFailed
    case loadFailed

    var errorDescription: String? {
        switch self {
        case .destinationCreationFailed:
            return "Konnte Zieldatei nicht erstellen"
        case .finalizationFailed:
            return "Konnte Bild nicht speichern"
        case .loadFailed:
            return "Konnte Bild nicht laden"
        }
    }
}
