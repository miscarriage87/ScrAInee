@preconcurrency import Vision
import CoreGraphics
import Foundation

/// Result of OCR text recognition
struct OCRResultData: @unchecked Sendable {
    let text: String?
    let confidence: Float
    let language: String?
    let observations: [VNRecognizedTextObservation]
}

/// Manages OCR text recognition using Apple's Vision framework
final class OCRManager: Sendable {
    // Supported languages (German and English)
    private let supportedLanguages = ["de-DE", "en-US"]

    // MARK: - Text Recognition

    /// Recognizes text in an image
    /// - Parameter image: The CGImage to process
    /// - Returns: OCR result with extracted text and confidence
    func recognizeText(in image: CGImage) async -> OCRResultData {
        await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                guard error == nil,
                      let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: OCRResultData(
                        text: nil,
                        confidence: 0,
                        language: nil,
                        observations: []
                    ))
                    return
                }

                var fullText = ""
                var totalConfidence: Float = 0
                _ = Set<String>()

                for observation in observations {
                    if let topCandidate = observation.topCandidates(1).first {
                        fullText += topCandidate.string + "\n"
                        totalConfidence += topCandidate.confidence
                    }
                }

                let avgConfidence = observations.isEmpty ? 0 : totalConfidence / Float(observations.count)

                // Determine primary language
                let primaryLanguage = self.detectPrimaryLanguage(from: fullText)

                continuation.resume(returning: OCRResultData(
                    text: fullText.trimmingCharacters(in: .whitespacesAndNewlines),
                    confidence: avgConfidence,
                    language: primaryLanguage,
                    observations: observations
                ))
            }

            // Configure request
            request.recognitionLevel = .accurate
            request.recognitionLanguages = supportedLanguages
            request.usesLanguageCorrection = true
            request.automaticallyDetectsLanguage = true

            // Create handler and perform
            let handler = VNImageRequestHandler(cgImage: image, options: [:])

            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: OCRResultData(
                    text: nil,
                    confidence: 0,
                    language: nil,
                    observations: []
                ))
            }
        }
    }

    // MARK: - Text with Bounding Boxes

    /// Recognizes text with bounding box information
    /// - Parameter image: The CGImage to process
    /// - Returns: Array of text items with their positions
    func recognizeTextWithPositions(in image: CGImage) async -> [TextItem] {
        await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                guard error == nil,
                      let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: [])
                    return
                }

                var items: [TextItem] = []

                for observation in observations {
                    if let topCandidate = observation.topCandidates(1).first {
                        let item = TextItem(
                            text: topCandidate.string,
                            confidence: topCandidate.confidence,
                            boundingBox: observation.boundingBox
                        )
                        items.append(item)
                    }
                }

                continuation.resume(returning: items)
            }

            request.recognitionLevel = .accurate
            request.recognitionLanguages = supportedLanguages
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: image, options: [:])

            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: [])
            }
        }
    }

    // MARK: - Fast Recognition (for preview/search)

    /// Performs fast text recognition (lower accuracy, faster)
    func recognizeTextFast(in image: CGImage) async -> String? {
        await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                guard error == nil,
                      let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: nil)
                    return
                }

                let text = observations
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n")

                continuation.resume(returning: text.isEmpty ? nil : text)
            }

            // Use fast recognition
            request.recognitionLevel = .fast
            request.recognitionLanguages = supportedLanguages

            let handler = VNImageRequestHandler(cgImage: image, options: [:])

            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: nil)
            }
        }
    }

    // MARK: - Language Detection

    private func detectPrimaryLanguage(from text: String) -> String? {
        guard !text.isEmpty else { return nil }

        // Use NLLanguageRecognizer for language detection
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)

        guard let language = recognizer.dominantLanguage else {
            return nil
        }

        switch language {
        case .german:
            return "de"
        case .english:
            return "en"
        default:
            return language.rawValue
        }
    }
}

// MARK: - Supporting Types

import NaturalLanguage

/// Represents a recognized text item with position
struct TextItem {
    let text: String
    let confidence: Float
    let boundingBox: CGRect

    /// Converts normalized bounding box to image coordinates
    func boundingBoxInImage(width: CGFloat, height: CGFloat) -> CGRect {
        CGRect(
            x: boundingBox.minX * width,
            y: (1 - boundingBox.maxY) * height,
            width: boundingBox.width * width,
            height: boundingBox.height * height
        )
    }
}
