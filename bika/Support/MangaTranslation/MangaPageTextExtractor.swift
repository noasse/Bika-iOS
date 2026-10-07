import CoreGraphics
import Foundation

/// Finds and reads the Japanese text on one manga page.
///
/// Pipeline: speech bubbles → lines inside each bubble → vertical lines reflowed into a
/// horizontal strip → Vision OCR. Text outside bubbles (sound effects, narration boxes drawn
/// over art) is out of scope for this experiment.
nonisolated struct MangaPageTextExtractor: Sendable {
    nonisolated struct Configuration: Sendable {
        /// Analysis happens on a copy whose long side is at most this many pixels.
        var analysisMaxDimension = 2000
        /// Blocks Vision is less sure of than this are dropped rather than translated wrongly.
        var minimumConfidence = 0.3
        /// A later (less likely) reading of a bubble replaces the first only if Vision is this
        /// much more confident in it.
        var alternativeReadingMargin = 0.15

        init() {}
    }

    var configuration = Configuration()
    var bubbleDetector = SpeechBubbleDetector()
    var segmenter = TextLineSegmenter()
    var reflow = TextReflow()
    var recognizer = JapaneseTextRecognizer()

    func extract(from image: CGImage) throws -> [MangaTextBlock] {
        guard let bitmap = GrayscaleBitmap(image: image, maxDimension: configuration.analysisMaxDimension) else {
            return []
        }
        let size = CGSize(width: bitmap.width, height: bitmap.height)

        var blocks: [MangaTextBlock] = []
        for bubble in bubbleDetector.detect(in: bitmap) {
            try Task.checkCancellation()
            guard let (text, result) = try bestReading(of: bubble),
                  result.confidence >= configuration.minimumConfidence else { continue }

            let textBounds = text.lines.map(\.bounds).reduce(text.lines[0].bounds) { $0.union($1) }
            blocks.append(MangaTextBlock(
                bubble: NormalizedRect(pixelRect: bubble.bounds.cgRect, in: size),
                textBounds: NormalizedRect(pixelRect: textBounds.cgRect, in: size),
                lines: text.lines.map { NormalizedRect(pixelRect: $0.bounds.cgRect, in: size) },
                orientation: text.orientation,
                sourceText: result.text
            ))
        }
        return Self.readingOrder(blocks)
    }

    /// Reads every plausible arrangement of the bubble and keeps the one Vision is most sure
    /// of. The segmenter lists the likelier arrangement first; a later one has to beat it by a
    /// margin, so a near-tie never flips a vertical bubble to horizontal.
    private func bestReading(of bubble: DetectedBubble) throws -> (SegmentedText, JapaneseTextRecognizer.Result)? {
        var best: (SegmentedText, JapaneseTextRecognizer.Result)?
        for candidate in segmenter.candidates(bubble) {
            guard let strip = reflow.strip(for: candidate, in: bubble) else { continue }
            let result = try recognizer.recognize(strip)
            guard !result.text.isEmpty else { continue }
            if let current = best {
                if result.confidence > current.1.confidence + configuration.alternativeReadingMargin {
                    best = (candidate, result)
                }
            } else {
                best = (candidate, result)
            }
        }
        return best
    }

    /// Manga pages read top to bottom, and right to left within a row. Bubbles whose tops are
    /// within `rowTolerance` of the row's first bubble share a row. Grouping first keeps the
    /// ordering well defined; a tolerance inside a sort comparator would not be transitive.
    static func readingOrder(_ blocks: [MangaTextBlock], rowTolerance: Double = 0.05) -> [MangaTextBlock] {
        var rows: [[MangaTextBlock]] = []
        for block in blocks.sorted(by: { $0.bubble.y < $1.bubble.y }) {
            if let rowTop = rows.last?.first?.bubble.y, block.bubble.y - rowTop <= rowTolerance {
                rows[rows.count - 1].append(block)
            } else {
                rows.append([block])
            }
        }
        return rows.flatMap { $0.sorted { $0.bubble.x > $1.bubble.x } }
    }
}
