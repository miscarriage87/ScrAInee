import Foundation
import AppKit
import CoreGraphics
import UniformTypeIdentifiers
@testable import Scrainee

/// Generiert Test-Bilder mit bekanntem Inhalt für E2E-Tests
struct ImageGenerator {

    // MARK: - Text Images for OCR Testing

    /// Erstellt ein Bild mit gerendertem Text für OCR-Tests
    static func createImageWithText(
        _ text: String,
        size: CGSize = CGSize(width: 800, height: 600),
        fontSize: CGFloat = 24,
        backgroundColor: NSColor = .white,
        textColor: NSColor = .black
    ) -> CGImage? {
        let image = NSImage(size: size)
        image.lockFocus()

        // Hintergrund
        backgroundColor.setFill()
        NSRect(origin: .zero, size: size).fill()

        // Text-Attribute
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .left
        paragraphStyle.lineBreakMode = .byWordWrapping

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .regular),
            .foregroundColor: textColor,
            .paragraphStyle: paragraphStyle
        ]

        // Text zeichnen mit Padding
        let textRect = NSRect(
            x: 40,
            y: size.height - 100 - fontSize,
            width: size.width - 80,
            height: fontSize * 4
        )
        text.draw(in: textRect, withAttributes: attributes)

        image.unlockFocus()

        var imageRect = NSRect(origin: .zero, size: size)
        return image.cgImage(forProposedRect: &imageRect, context: nil, hints: nil)
    }

    /// Erstellt ein Bild mit mehreren Textzeilen
    static func createImageWithMultilineText(
        lines: [String],
        size: CGSize = CGSize(width: 800, height: 600),
        fontSize: CGFloat = 20
    ) -> CGImage? {
        let text = lines.joined(separator: "\n")
        return createImageWithText(text, size: size, fontSize: fontSize)
    }

    // MARK: - Solid Color Images

    /// Erstellt ein einfarbiges Bild
    static func createSolidColorImage(
        color: NSColor,
        size: CGSize = CGSize(width: 100, height: 100)
    ) -> CGImage? {
        let image = NSImage(size: size)
        image.lockFocus()
        color.setFill()
        NSRect(origin: .zero, size: size).fill()
        image.unlockFocus()

        var imageRect = NSRect(origin: .zero, size: size)
        return image.cgImage(forProposedRect: &imageRect, context: nil, hints: nil)
    }

    // MARK: - Gradient Images for Hash Tests

    /// Erstellt ein Bild mit Gradient für Hash-Tests (einfarbige Bilder haben alle den gleichen Hash!)
    static func createGradientImage(
        startColor: NSColor,
        endColor: NSColor,
        size: CGSize = CGSize(width: 100, height: 100)
    ) -> CGImage? {
        let image = NSImage(size: size)
        image.lockFocus()

        let gradient = NSGradient(colors: [startColor, endColor])
        gradient?.draw(in: NSRect(origin: .zero, size: size), angle: 45)

        image.unlockFocus()

        var imageRect = NSRect(origin: .zero, size: size)
        return image.cgImage(forProposedRect: &imageRect, context: nil, hints: nil)
    }

    // MARK: - Mock Screenshots

    /// Erstellt ein Bild das einem Screenshot ähnelt (Gradient + UI-Elemente)
    static func createMockScreenshot(
        width: Int = 1920,
        height: Int = 1080
    ) -> CGImage? {
        let size = CGSize(width: width, height: height)
        let image = NSImage(size: size)
        image.lockFocus()

        // Gradient-Hintergrund
        let gradient = NSGradient(colors: [
            NSColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1.0),
            NSColor(red: 0.6, green: 0.3, blue: 0.7, alpha: 1.0)
        ])
        gradient?.draw(in: NSRect(origin: .zero, size: size), angle: 45)

        // "Menu Bar" simulieren
        NSColor.white.withAlphaComponent(0.95).setFill()
        NSRect(x: 0, y: size.height - 28, width: size.width, height: 28).fill()

        // "Dock" simulieren
        NSColor.gray.withAlphaComponent(0.5).setFill()
        let dockWidth: CGFloat = 600
        let dockX = (size.width - dockWidth) / 2
        NSRect(x: dockX, y: 8, width: dockWidth, height: 60).fill()

        // "Fenster" simulieren
        NSColor.white.setFill()
        let windowRect = NSRect(
            x: size.width * 0.15,
            y: size.height * 0.15,
            width: size.width * 0.7,
            height: size.height * 0.65
        )
        windowRect.fill()

        // Fenster-Titelleiste
        NSColor(white: 0.95, alpha: 1.0).setFill()
        NSRect(x: windowRect.minX, y: windowRect.maxY - 28, width: windowRect.width, height: 28).fill()

        image.unlockFocus()

        var imageRect = NSRect(origin: .zero, size: size)
        return image.cgImage(forProposedRect: &imageRect, context: nil, hints: nil)
    }

    /// Erstellt einen Screenshot mit sichtbarem Text (für OCR-Verifizierung)
    static func createMockScreenshotWithText(
        text: String,
        width: Int = 1920,
        height: Int = 1080
    ) -> CGImage? {
        let size = CGSize(width: width, height: height)
        let image = NSImage(size: size)
        image.lockFocus()

        // Weißer Hintergrund (besser für OCR)
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()

        // Text
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .left

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 32, weight: .regular),
            .foregroundColor: NSColor.black,
            .paragraphStyle: paragraphStyle
        ]

        let textRect = NSRect(
            x: 100,
            y: size.height - 200,
            width: size.width - 200,
            height: 150
        )
        text.draw(in: textRect, withAttributes: attributes)

        image.unlockFocus()

        var imageRect = NSRect(origin: .zero, size: size)
        return image.cgImage(forProposedRect: &imageRect, context: nil, hints: nil)
    }

    // MARK: - HEIC Save/Load Helpers

    /// Speichert ein CGImage als HEIC-Datei
    static func saveAsHEIC(
        _ image: CGImage,
        to url: URL,
        quality: Double = 0.6
    ) throws {
        // Verzeichnis erstellen falls nötig
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.heic.identifier as CFString,
            1,
            nil
        ) else {
            throw ImageGeneratorError.destinationCreationFailed
        }

        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: quality,
            kCGImagePropertyHasAlpha as CFString: false
        ]

        CGImageDestinationAddImage(destination, image, options as CFDictionary)

        guard CGImageDestinationFinalize(destination) else {
            throw ImageGeneratorError.finalizationFailed
        }
    }

    /// Lädt ein CGImage aus einer HEIC-Datei
    static func loadHEIC(from url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// Prüft ob eine Datei ein valides HEIC ist
    static func isValidHEIC(at url: URL) -> Bool {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return false
        }
        let uti = CGImageSourceGetType(source) as? String
        return uti == UTType.heic.identifier
    }
}

// MARK: - Errors

enum ImageGeneratorError: LocalizedError {
    case destinationCreationFailed
    case finalizationFailed

    var errorDescription: String? {
        switch self {
        case .destinationCreationFailed:
            return "Konnte HEIC-Ziel nicht erstellen"
        case .finalizationFailed:
            return "Konnte HEIC nicht finalisieren"
        }
    }
}
