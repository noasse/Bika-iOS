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
        /// A first reading at least this confident is kept without trying alternatives.
        var confidentReading = 0.8

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
        try Task.checkCancellation()

        // Each bubble's plausible readings, most likely first, already turned into strips.
        let bubbles = bubbleDetector.detect(in: bitmap).compactMap { bubble -> (DetectedBubble, [(SegmentedText, CGImage)])? in
            let readings = segmenter.candidates(bubble).compactMap { text in
                reflow.strip(for: text, in: bubble).map { (text, $0) }
            }
            return readings.isEmpty ? nil : (bubble, readings)
        }
        try Task.checkCancellation()

        // Round one: every bubble's most likely reading, in a single Vision call.
        var best: [(text: SegmentedText, result: JapaneseTextRecognizer.Result)?] = zip(
            bubbles,
            try recognizer.recognize(bubbles.map { $0.1[0].1 })
        ).map { bubble, result in
            result.text.isEmpty ? nil : (bubble.1[0].0, result)
        }
        try Task.checkCancellation()

        // Round two: alternatives, only for bubbles round one was unsure of — again one call.
        let unsure = bubbles.indices.filter { index in
            bubbles[index].1.count > 1 && (best[index]?.result.confidence ?? 0) < configuration.confidentReading
        }
        if !unsure.isEmpty {
            let alternatives = try recognizer.recognize(unsure.map { bubbles[$0].1[1].1 })
            for (index, result) in zip(unsure, alternatives) where !result.text.isEmpty {
                // The likelier reading only loses by a clear margin, so a near-tie never flips
                // a vertical bubble to horizontal.
                let current = best[index]?.result.confidence ?? -1
                if best[index] == nil || result.confidence > current + configuration.alternativeReadingMargin {
                    best[index] = (bubbles[index].1[1].0, result)
                }
            }
        }

        let blocks = zip(bubbles, best).compactMap { bubble, reading -> MangaTextBlock? in
            guard let reading, reading.result.confidence >= configuration.minimumConfidence else { return nil }
            let lines = reading.text.lines
            let textBounds = lines.map(\.bounds).reduce(lines[0].bounds) { $0.union($1) }
            return MangaTextBlock(
                bubble: NormalizedRect(pixelRect: bubble.0.bounds.cgRect, in: size),
                textBounds: NormalizedRect(pixelRect: textBounds.cgRect, in: size),
                lines: lines.map { NormalizedRect(pixelRect: $0.bounds.cgRect, in: size) },
                orientation: reading.text.orientation,
                sourceText: reading.result.text
            )
        }
        return Self.readingOrder(blocks)
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
