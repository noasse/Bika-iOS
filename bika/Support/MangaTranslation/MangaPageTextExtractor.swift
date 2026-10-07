import CoreGraphics
import Foundation

/// Finds and reads the Japanese text on one manga page.
///
/// Pipeline: speech bubbles → lines inside each bubble → vertical lines reflowed into a
/// horizontal strip → Vision OCR. Text outside bubbles (sound effects, narration boxes drawn
/// over art) is out of scope for this experiment.
nonisolated struct MangaPageTextExtractor: Sendable {
    /// Bumped whenever a change can alter what is recognised on a page. Reports record it so
    /// two evaluation runs can be compared, and cached results from another version are not
    /// reused.
    ///
    /// 1 bubbles and vertical reflow · 2 batched OCR · 3 line-art and garbage filters ·
    /// 4 flat-fill bubbles, free horizontal text, across-column misread filter ·
    /// 5 bubbles read by manga-ocr when bundled.
    static let pipelineVersion = 5

    nonisolated struct Configuration: Sendable {
        /// Analysis happens on a copy whose long side is at most this many pixels.
        var analysisMaxDimension = 2000
        /// Blocks Vision is less sure of than this are dropped rather than translated wrongly.
        var minimumConfidence = 0.3
        /// The same for the text recogniser model, whose confidence is the mean probability of
        /// the characters it chose. It always produces something, even for a crop with no text
        /// in it, so this is what keeps a face mistaken for a bubble from becoming dialogue.
        /// Provisional: to be calibrated from device reports, which record every confidence.
        var minimumModelConfidence = 0.5
        /// A later (less likely) reading of a bubble replaces the first only if Vision is this
        /// much more confident in it.
        var alternativeReadingMargin = 0.15
        /// A first reading at least this confident is kept without trying alternatives.
        var confidentReading = 0.8
        /// Also read horizontal text set straight onto the page (afterwords, notes, narration).
        var readsCaptions = true

        init() {}
    }

    var configuration = Configuration()
    var bubbleDetector = SpeechBubbleDetector()
    var segmenter = TextLineSegmenter()
    var reflow = TextReflow()
    var recognizer = JapaneseTextRecognizer()
    var captionReader = CaptionTextReader()
    /// Reads bubble text when available; nil falls back to Vision with column reflow.
    var textRecognizer: (any MangaTextRecognizing)? = MangaOCRRecognizer.bundled

    /// The path bubbles are read with, as recorded in reports.
    var recognizerIdentifier: String { textRecognizer?.identifier ?? "vision" }

    /// Reads bubbles with Vision and column reflow even when a recogniser model is bundled.
    static func vision() -> MangaPageTextExtractor {
        var extractor = MangaPageTextExtractor()
        extractor.textRecognizer = nil
        return extractor
    }

    /// `extract(from:)` plus how long it took in milliseconds.
    func timedExtract(from image: CGImage) throws -> (blocks: [MangaTextBlock], milliseconds: Int) {
        let clock = ContinuousClock()
        let start = clock.now
        let blocks = try extract(from: image)
        let elapsed = start.duration(to: clock.now)
        let milliseconds = Int(elapsed.components.seconds * 1000)
            + Int(elapsed.components.attoseconds / 1_000_000_000_000_000)
        return (blocks, milliseconds)
    }

    func extract(from image: CGImage) throws -> [MangaTextBlock] {
        guard let bitmap = GrayscaleBitmap(image: image, maxDimension: configuration.analysisMaxDimension) else {
            return []
        }
        let size = CGSize(width: bitmap.width, height: bitmap.height)
        try Task.checkCancellation()

        // Each bubble's plausible arrangements, most likely first.
        let detected = bubbleDetector.detect(in: bitmap)
        let segmented = detected.compactMap { bubble -> (DetectedBubble, [SegmentedText])? in
            let candidates = segmenter.candidates(bubble)
            return candidates.isEmpty ? nil : (bubble, candidates)
        }
        try Task.checkCancellation()

        let best: [(text: SegmentedText, result: JapaneseTextRecognizer.Result)?]
        let threshold: Double
        if let textRecognizer, let page = bitmap.makeImage() {
            best = try readWithModel(segmented, page: page, recognizer: textRecognizer)
            threshold = configuration.minimumModelConfidence
        } else {
            best = try readWithVision(segmented)
            threshold = configuration.minimumConfidence
        }
        let bubbles = segmented.map(\.0)

        var blocks = zip(bubbles, best).compactMap { bubble, reading -> MangaTextBlock? in
            guard let reading,
                  reading.result.confidence >= threshold,
                  JapaneseTextRecognizer.looksLikeJapanese(reading.result.text) else { return nil }
            let lines = reading.text.lines
            let textBounds = lines.map(\.bounds).reduce(lines[0].bounds) { $0.union($1) }
            return MangaTextBlock(
                bubble: NormalizedRect(pixelRect: bubble.bounds.cgRect, in: size),
                textBounds: NormalizedRect(pixelRect: textBounds.cgRect, in: size),
                lines: lines.map { NormalizedRect(pixelRect: $0.bounds.cgRect, in: size) },
                orientation: reading.text.orientation,
                sourceText: reading.result.text,
                confidence: reading.result.confidence
            )
        }
        if configuration.readsCaptions {
            try Task.checkCancellation()
            // Only bubbles that were actually read are excluded. A rejected region produced no
            // text, so reading it again cannot duplicate anything — and large areas enclosed by
            // line art, which the bubble path rejects, can hold a whole paragraph of free text.
            let readBubbles = blocks.map { $0.bubble.rect(in: size) }
            let paragraphs = try captionReader.read(bitmap, excluding: readBubbles)
            for paragraph in paragraphs where paragraph.confidence >= configuration.minimumConfidence {
                let bounds = paragraph.bounds
                let lineHeight = paragraph.lines.map(\.height).max() ?? 0
                blocks.append(MangaTextBlock(
                    kind: .caption,
                    bubble: NormalizedRect(pixelRect: bounds.insetBy(dx: -lineHeight * 0.3, dy: -lineHeight * 0.3), in: size),
                    textBounds: NormalizedRect(pixelRect: bounds, in: size),
                    lines: paragraph.lines.map { NormalizedRect(pixelRect: $0, in: size) },
                    orientation: .horizontal,
                    sourceText: paragraph.text,
                    confidence: paragraph.confidence
                ))
            }
        }

        return Self.readingOrder(blocks)
    }

    /// Reads each bubble's text region with the recogniser model, which handles vertical text
    /// and multi-column bubbles itself: no reflow, no choosing between arrangements. The most
    /// likely arrangement is still used for the block's lines and orientation, which layout
    /// needs. The crop is the bubble's ink with a small margin, kept inside the bubble so its
    /// outline does not intrude.
    private func readWithModel(
        _ segmented: [(DetectedBubble, [SegmentedText])],
        page: CGImage,
        recognizer: any MangaTextRecognizing
    ) throws -> [(text: SegmentedText, result: JapaneseTextRecognizer.Result)?] {
        try segmented.map { bubble, candidates in
            try Task.checkCancellation()
            let margin = max(4, Int(Double(candidates[0].emSize) * 0.3))
            let ink = bubble.inkBounds
            let area = PixelRect(
                minX: max(bubble.bounds.minX, ink.minX - margin),
                minY: max(bubble.bounds.minY, ink.minY - margin),
                maxX: min(bubble.bounds.maxX, ink.maxX + margin),
                maxY: min(bubble.bounds.maxY, ink.maxY + margin)
            )
            guard let crop = page.cropping(to: area.cgRect) else { return nil }
            let result = try recognizer.recognize(crop)
            return result.text.isEmpty ? nil : (candidates[0], result)
        }
    }

    /// Reads bubbles with Vision. Vertical lines are reflowed into strips; every bubble's most
    /// likely arrangement is read in one call, and alternatives only for bubbles that call was
    /// unsure of, in a second.
    private func readWithVision(
        _ segmented: [(DetectedBubble, [SegmentedText])]
    ) throws -> [(text: SegmentedText, result: JapaneseTextRecognizer.Result)?] {
        let readings: [[(SegmentedText, CGImage)]] = segmented.map { bubble, candidates in
            candidates.compactMap { text in reflow.strip(for: text, in: bubble).map { (text, $0) } }
        }
        let readable = readings.indices.filter { !readings[$0].isEmpty }

        var best: [(text: SegmentedText, result: JapaneseTextRecognizer.Result)?] = Array(repeating: nil, count: segmented.count)
        let first = try recognizer.recognize(readable.map { readings[$0][0].1 })
        for (index, result) in zip(readable, first) where !result.text.isEmpty {
            best[index] = (readings[index][0].0, result)
        }
        try Task.checkCancellation()

        let unsure = readable.filter { index in
            readings[index].count > 1 && (best[index]?.result.confidence ?? 0) < configuration.confidentReading
        }
        if !unsure.isEmpty {
            let alternatives = try recognizer.recognize(unsure.map { readings[$0][1].1 })
            for (index, result) in zip(unsure, alternatives) where !result.text.isEmpty {
                if Self.alternativeWins(result, over: best[index]?.result, margin: configuration.alternativeReadingMargin) {
                    best[index] = (readings[index][1].0, result)
                }
            }
        }
        return best
    }

    /// Whether a less likely reading of a bubble should replace the first one.
    ///
    /// Confidence alone was not enough: on a device, two-column vertical bubbles were read as
    /// horizontal because the horizontal reading — which picks up only part of the text, a row
    /// across both columns — came back slightly more confident. The alternative now has to be
    /// clearly more confident *and* read at least as many kana and kanji.
    static func alternativeWins(
        _ alternative: JapaneseTextRecognizer.Result,
        over current: JapaneseTextRecognizer.Result?,
        margin: Double
    ) -> Bool {
        guard let current else { return true }
        return alternative.confidence > current.confidence + margin
            && JapaneseTextRecognizer.japaneseLetterCount(alternative.text)
                >= JapaneseTextRecognizer.japaneseLetterCount(current.text)
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
