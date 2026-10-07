import CoreGraphics
import Foundation

/// A rectangle expressed as fractions of the page image, origin top-left.
///
/// Everything the translation pipeline produces is stored this way rather than in view or pixel
/// coordinates. The reader decodes the same page at different sizes (orientation, zoom, decode
/// buckets), and an overlay tied to any one of those sizes drifts as soon as another is used.
nonisolated struct NormalizedRect: Codable, Hashable, Sendable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    /// - Parameters:
    ///   - pixelRect: a rectangle in pixel coordinates, origin top-left.
    ///   - imageSize: the pixel size of the image the rectangle was measured in.
    init(pixelRect: CGRect, in imageSize: CGSize) {
        let width = max(imageSize.width, 1)
        let height = max(imageSize.height, 1)
        self.init(
            x: Double(pixelRect.minX / width),
            y: Double(pixelRect.minY / height),
            width: Double(pixelRect.width / width),
            height: Double(pixelRect.height / height)
        )
    }

    /// The rectangle in pixel or point coordinates of a box of `size`, origin top-left.
    func rect(in size: CGSize) -> CGRect {
        CGRect(
            x: x * size.width,
            y: y * size.height,
            width: width * size.width,
            height: height * size.height
        )
    }
}

nonisolated enum MangaTextOrientation: String, Codable, Sendable {
    /// Columns top to bottom, read right to left — the norm in Japanese manga.
    case vertical
    case horizontal
}

nonisolated enum MangaTextKind: String, Codable, Sendable {
    /// Text inside a speech bubble, on a flat fill an overlay can paint over.
    case bubble
    /// Text set straight onto the page — afterwords, notes, horizontal narration — where an
    /// overlay must not simply paint over the art behind it.
    case caption
}

/// One run of source text found on a page: a speech bubble's contents, or a paragraph of
/// free text.
nonisolated struct MangaTextBlock: Codable, Hashable, Sendable {
    var kind: MangaTextKind = .bubble
    /// The area of the page an overlay may paint over: the bubble's interior, or for a caption
    /// the paragraph's bounds with a small margin.
    var bubble: NormalizedRect
    /// The bounding box of the text itself inside the bubble.
    var textBounds: NormalizedRect
    /// Text lines in reading order. For vertical text: right to left.
    var lines: [NormalizedRect]
    var orientation: MangaTextOrientation
    /// Recognised source text with lines joined in reading order.
    var sourceText: String
}
