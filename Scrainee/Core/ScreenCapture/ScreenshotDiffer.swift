import Foundation
import CoreGraphics
import Accelerate

/// Intelligently compares screenshots to detect significant changes
/// Uses perceptual hashing and adaptive sampling for performance
final class ScreenshotDiffer {
    private var lastImageHash: UInt64 = 0
    private var lastSamplePixels: [UInt8] = []

    // Threshold for considering images different (0-100)
    // Higher = more sensitive to changes
    private let differenceThreshold: Double = 5.0

    // Grid size for sampling (smaller = faster but less accurate)
    private let sampleGridSize = 16

    // MARK: - Public API

    /// Checks if a new image is significantly different from the last one
    /// Returns true if the image should be captured
    func shouldCapture(_ image: CGImage) -> Bool {
        // Calculate perceptual hash
        let newHash = calculatePerceptualHash(image)

        // Calculate hamming distance
        let distance = hammingDistance(lastImageHash, newHash)
        let percentDifferent = Double(distance) / 64.0 * 100.0

        // Also check sample pixels for subtle changes
        let newSamples = samplePixels(from: image)
        let pixelDifference = calculatePixelDifference(lastSamplePixels, newSamples)

        // Update state
        lastImageHash = newHash
        lastSamplePixels = newSamples

        // Consider different if either metric exceeds threshold
        return percentDifferent > differenceThreshold || pixelDifference > differenceThreshold
    }

    /// Resets the differ state (use when capture context changes)
    func reset() {
        lastImageHash = 0
        lastSamplePixels = []
    }

    // MARK: - Perceptual Hash (pHash)

    /// Calculates a 64-bit perceptual hash using DCT
    private func calculatePerceptualHash(_ image: CGImage) -> UInt64 {
        // Resize to 32x32 grayscale
        guard let grayImage = toGrayscale32x32(image) else { return 0 }

        // Apply DCT (using simplified 8x8 block from top-left)
        let dctValues = applyDCT(grayImage)

        // Calculate median of DCT coefficients (excluding DC component)
        let coefficients = Array(dctValues[1..<64])
        let sorted = coefficients.sorted()
        let median = sorted[31]

        // Generate hash based on which values are above median
        var hash: UInt64 = 0
        for i in 0..<64 {
            if dctValues[i] > median {
                hash |= (1 << i)
            }
        }

        return hash
    }

    /// Converts image to 32x32 grayscale
    private func toGrayscale32x32(_ image: CGImage) -> [Float]? {
        let size = 32

        guard let context = CGContext(
            data: nil,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: size,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }

        context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))

        guard let data = context.data else { return nil }
        let pixels = data.bindMemory(to: UInt8.self, capacity: size * size)

        return (0..<(size * size)).map { Float(pixels[$0]) }
    }

    /// Simplified DCT implementation for 8x8 block
    private func applyDCT(_ pixels: [Float]) -> [Float] {
        // Use top-left 8x8 block
        var block = [Float](repeating: 0, count: 64)

        for y in 0..<8 {
            for x in 0..<8 {
                block[y * 8 + x] = pixels[y * 32 + x]
            }
        }

        // Apply 2D DCT
        var result = [Float](repeating: 0, count: 64)

        for v in 0..<8 {
            for u in 0..<8 {
                var sum: Float = 0
                for y in 0..<8 {
                    for x in 0..<8 {
                        sum += block[y * 8 + x] *
                            cos(Float.pi * Float(2 * x + 1) * Float(u) / 16.0) *
                            cos(Float.pi * Float(2 * y + 1) * Float(v) / 16.0)
                    }
                }
                let cu: Float = (u == 0) ? 1.0 / sqrt(2.0) : 1.0
                let cv: Float = (v == 0) ? 1.0 / sqrt(2.0) : 1.0
                result[v * 8 + u] = 0.25 * cu * cv * sum
            }
        }

        return result
    }

    /// Calculates hamming distance between two hashes
    private func hammingDistance(_ a: UInt64, _ b: UInt64) -> Int {
        (a ^ b).nonzeroBitCount
    }

    // MARK: - Pixel Sampling

    /// Samples pixels from a grid across the image
    private func samplePixels(from image: CGImage) -> [UInt8] {
        let width = image.width
        let height = image.height
        let stepX = width / sampleGridSize
        let stepY = height / sampleGridSize

        guard let data = image.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data) else {
            return []
        }

        let bytesPerPixel = image.bitsPerPixel / 8
        let bytesPerRow = image.bytesPerRow

        var samples: [UInt8] = []
        samples.reserveCapacity(sampleGridSize * sampleGridSize)

        for y in 0..<sampleGridSize {
            for x in 0..<sampleGridSize {
                let pixelX = x * stepX
                let pixelY = y * stepY
                let offset = pixelY * bytesPerRow + pixelX * bytesPerPixel

                // Get grayscale average of RGB
                if bytesPerPixel >= 3 {
                    let r = UInt16(bytes[offset])
                    let g = UInt16(bytes[offset + 1])
                    let b = UInt16(bytes[offset + 2])
                    samples.append(UInt8((r + g + b) / 3))
                } else if bytesPerPixel >= 1 {
                    samples.append(bytes[offset])
                }
            }
        }

        return samples
    }

    /// Calculates percentage difference between two pixel samples
    private func calculatePixelDifference(_ old: [UInt8], _ new: [UInt8]) -> Double {
        guard !old.isEmpty, old.count == new.count else { return 100.0 }

        var totalDiff: Int = 0
        for i in 0..<old.count {
            totalDiff += abs(Int(new[i]) - Int(old[i]))
        }

        let maxDiff = old.count * 255
        return Double(totalDiff) / Double(maxDiff) * 100.0
    }
}

// MARK: - Quick Hash Extension

extension ScreenshotDiffer {
    /// Generates a quick hash string for database storage
    static func quickHash(_ image: CGImage) -> String {
        // Use a simple average hash
        let size = 8

        guard let context = CGContext(
            data: nil,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: size,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return "" }

        context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))

        guard let data = context.data else { return "" }
        let pixels = data.bindMemory(to: UInt8.self, capacity: size * size)

        // Calculate average
        var sum: Int = 0
        for i in 0..<(size * size) {
            sum += Int(pixels[i])
        }
        let average = sum / (size * size)

        // Generate hash string
        var hash: UInt64 = 0
        for i in 0..<(size * size) {
            if pixels[i] > average {
                hash |= (1 << i)
            }
        }

        return String(format: "%016llx", hash)
    }
}
