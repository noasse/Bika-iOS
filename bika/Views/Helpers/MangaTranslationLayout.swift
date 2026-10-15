import UIKit

/// Where and how each translation is drawn over its page.
///
/// A bubble's original text is painted over with the bubble's own ground (white, gray or
/// black, sampled from the page) and the translation set inside, as large as fits. Free text
/// on the art gets a plate behind it instead: there is no flat ground to match.
///
/// Translations are set horizontally: Chinese reads either way, and English only this way.
nonisolated enum MangaTranslationLayout {
    nonisolated struct Item: Equatable {
        /// Painted first, over the original text.
        let cover: CGRect
        let cornerRadius: CGFloat
        /// Gray level of the cover, 0 black ... 1 white, and its opacity.
        let coverLevel: CGFloat
        let coverAlpha: CGFloat
        let text: String
        /// Inside `cover`.
        let textRect: CGRect
        let fontSize: CGFloat
        /// Black or white, whichever stands out on the cover.
        let textLevel: CGFloat
    }

    /// Text is never set larger than the original lettering, nor smaller than this fraction
    /// of it — below that a translation is better cut off than unreadable.
    static let smallestFraction: CGFloat = 0.45
    /// A long translation may exceed the original size by this much when the bubble has room.
    static let largestFraction: CGFloat = 1.0

    /// - Parameters:
    ///   - imageRect: where the page is drawn, in the view's coordinates.
    ///   - grounds: per block, the gray level around its text (see `MangaPageGround`).
    static func items(
        blocks: [MangaTextBlock],
        translations: [String],
        grounds: [Double],
        in imageRect: CGRect
    ) -> [Item] {
        zip(blocks.indices, zip(blocks, translations)).compactMap { index, pair in
            let (block, translation) = pair
            let text = translation.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            let ground = grounds.indices.contains(index) ? CGFloat(grounds[index]) : 1
            return item(block, text: text, ground: ground, in: imageRect)
        }
    }

    static func item(_ block: MangaTextBlock, text: String, ground: CGFloat, in imageRect: CGRect) -> Item? {
        func onScreen(_ rect: NormalizedRect) -> CGRect {
            rect.rect(in: imageRect.size).offsetBy(dx: imageRect.minX, dy: imageRect.minY)
        }
        let textBounds = onScreen(block.textBounds)
        guard textBounds.width > 1, textBounds.height > 1 else { return nil }
        let em = originalCharacterSize(block, in: imageRect) ?? min(textBounds.width, textBounds.height)
        let pad = max(2, em * 0.25)

        // Candidate areas, smallest first: the original text with a margin; then, for a
        // bubble, as much of its interior as is safely clear of the outline — an ellipse's
        // inscribed rectangle is about 71% of its box each way.
        var areas = [textBounds.insetBy(dx: -pad, dy: -pad)]
        let isBubble = block.kind == .bubble
        if isBubble {
            let bubble = onScreen(block.bubble)
            let inscribed = bubble.insetBy(dx: bubble.width * 0.146, dy: bubble.height * 0.146)
            areas = areas.map { $0.intersection(bubble.insetBy(dx: bubble.width * 0.04, dy: bubble.height * 0.04)) }
            areas.append(areas[0].union(inscribed).intersection(bubble.insetBy(dx: bubble.width * 0.08, dy: bubble.height * 0.08)))
        }
        areas = areas.filter { !$0.isNull && $0.width > 1 && $0.height > 1 }
        guard let first = areas.first else { return nil }

        let largest = em * largestFraction
        let smallest = em * smallestFraction
        var chosen = (area: areas.last!, size: smallest)
        for area in areas {
            let inner = area.insetBy(dx: pad * 0.5, dy: pad * 0.5)
            if let size = largestFittingSize(text, in: inner.size, from: smallest, to: largest) {
                chosen = (area, size)
                break
            }
        }
        // The cover must hide the original text even when the translation needed less room.
        let cover = chosen.area.union(first)
        let textRect = chosen.area.insetBy(dx: pad * 0.5, dy: pad * 0.5)
        return Item(
            cover: cover,
            cornerRadius: min(cover.width, cover.height) * (isBubble ? 0.3 : 0.15),
            coverLevel: ground,
            coverAlpha: isBubble ? 1 : 0.88,
            text: text,
            textRect: textRect,
            fontSize: chosen.size,
            textLevel: ground < 0.5 ? 1 : 0
        )
    }

    /// The original lettering's character size: the median line width for vertical text, the
    /// median line height for horizontal.
    static func originalCharacterSize(_ block: MangaTextBlock, in imageRect: CGRect) -> CGFloat? {
        let sizes = block.lines.map { line -> CGFloat in
            let rect = line.rect(in: imageRect.size)
            return block.orientation == .vertical ? rect.width : rect.height
        }.filter { $0 > 0 }.sorted()
        guard !sizes.isEmpty else { return nil }
        return sizes[sizes.count / 2]
    }

    static func attributed(_ text: String, size: CGFloat, level: CGFloat = 0) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.lineHeightMultiple = 0.95
        return NSAttributedString(string: text, attributes: [
            .font: UIFont.systemFont(ofSize: size, weight: .semibold),
            .foregroundColor: UIColor(white: level, alpha: 1),
            .paragraphStyle: paragraph,
        ])
    }

    /// The height `text` takes set at `size` within `width`.
    static func measuredSize(_ text: String, size: CGFloat, width: CGFloat) -> CGSize {
        let bounds = attributed(text, size: size).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        return CGSize(width: ceil(bounds.width), height: ceil(bounds.height))
    }

    /// The largest size in `smallest...largest` at which `text` fits `box`, or nil.
    static func largestFittingSize(_ text: String, in box: CGSize, from smallest: CGFloat, to largest: CGFloat) -> CGFloat? {
        func fits(_ size: CGFloat) -> Bool {
            let measured = measuredSize(text, size: size, width: box.width)
            return measured.height <= box.height && measured.width <= box.width + 0.5
        }
        guard smallest > 0, largest >= smallest, fits(smallest) else { return nil }
        var low = smallest, high = largest
        if fits(high) { return high }
        for _ in 0..<12 {
            let middle = (low + high) / 2
            if fits(middle) { low = middle } else { high = middle }
        }
        return low
    }
}

/// The gray level of a page around its text, to paint over the text in the same tone.
nonisolated struct MangaPageGround {
    private let bitmap: GrayscaleBitmap

    /// A small grayscale copy is enough: only flat areas around text are sampled.
    init?(image: CGImage) {
        guard let bitmap = GrayscaleBitmap(image: image, maxDimension: 600) else { return nil }
        self.bitmap = bitmap
    }

    /// The median level, 0...1, of a ring just outside `rect`'s text — inside a bubble, the
    /// bubble's fill.
    func level(around rect: NormalizedRect) -> Double {
        let width = Double(bitmap.width), height = Double(bitmap.height)
        let margin = max(2, min(rect.width * width, rect.height * height) * 0.08)
        let minX = rect.x * width - margin, maxX = (rect.x + rect.width) * width + margin
        let minY = rect.y * height - margin, maxY = (rect.y + rect.height) * height + margin
        var samples: [UInt8] = []
        let steps = 24
        for step in 0...steps {
            let t = Double(step) / Double(steps)
            for (x, y) in [(minX + (maxX - minX) * t, minY), (minX + (maxX - minX) * t, maxY),
                           (minX, minY + (maxY - minY) * t), (maxX, minY + (maxY - minY) * t)] {
                let px = Int(x.rounded()), py = Int(y.rounded())
                guard px >= 0, py >= 0, px < bitmap.width, py < bitmap.height else { continue }
                samples.append(bitmap[px, py])
            }
        }
        guard !samples.isEmpty else { return 1 }
        samples.sort()
        return Double(samples[samples.count / 2]) / 255
    }
}
