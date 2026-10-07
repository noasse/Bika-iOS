import CoreGraphics
import Foundation

/// An 8-bit grayscale copy of a page, row-major, origin top-left. 0 is black, 255 is white.
///
/// Speech bubble and column detection only need luminance, and working on a plain byte buffer
/// keeps the flood fills and projection profiles cheap and easy to test.
nonisolated struct GrayscaleBitmap: Sendable {
    let width: Int
    let height: Int
    private(set) var pixels: [UInt8]

    init(width: Int, height: Int, pixels: [UInt8]) {
        precondition(width > 0 && height > 0 && pixels.count == width * height)
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    init(width: Int, height: Int, fill: UInt8 = 255) {
        self.init(width: width, height: height, pixels: Array(repeating: fill, count: width * height))
    }

    /// Draws `image` into a grayscale buffer whose long side is at most `maxDimension` pixels.
    /// Smaller images are kept at their own size rather than upscaled.
    init?(image: CGImage, maxDimension: Int) {
        let scale = min(1, Double(maxDimension) / Double(max(image.width, image.height)))
        let width = max(1, Int((Double(image.width) * scale).rounded()))
        let height = max(1, Int((Double(image.height) * scale).rounded()))
        var pixels = [UInt8](repeating: 255, count: width * height)
        let drew = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else {
                return false
            }
            // Transparent areas would otherwise read as black ink.
            context.setFillColor(gray: 1, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drew else { return nil }
        // CGContext memory is laid out top row first, so no flip is needed.
        self.init(width: width, height: height, pixels: pixels)
    }

    subscript(x: Int, y: Int) -> UInt8 {
        get { pixels[y * width + x] }
        set { pixels[y * width + x] = newValue }
    }

    func makeImage() -> CGImage? {
        let data = Data(pixels) as CFData
        guard let provider = CGDataProvider(data: data) else { return nil }
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }
}

/// An integer pixel rectangle, origin top-left, `maxX` / `maxY` exclusive.
nonisolated struct PixelRect: Hashable, Sendable {
    var minX: Int
    var minY: Int
    var maxX: Int
    var maxY: Int

    var width: Int { maxX - minX }
    var height: Int { maxY - minY }
    var area: Int { width * height }

    var cgRect: CGRect {
        CGRect(x: minX, y: minY, width: width, height: height)
    }

    func contains(_ other: PixelRect) -> Bool {
        other.minX >= minX && other.maxX <= maxX && other.minY >= minY && other.maxY <= maxY
    }

    func union(_ other: PixelRect) -> PixelRect {
        PixelRect(
            minX: min(minX, other.minX),
            minY: min(minY, other.minY),
            maxX: max(maxX, other.maxX),
            maxY: max(maxY, other.maxY)
        )
    }
}
