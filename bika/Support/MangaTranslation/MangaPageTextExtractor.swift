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
    /// 5 bubbles read by manga-ocr when bundled ·
    /// 6 model threshold calibrated on a device, overlapping duplicates removed, rects clipped.
    static let pipelineVersion = 6

    nonisolated struct Configuration: Sendable {
        /// Analysis happens on a copy whose long side is at most this many pixels.
        var analysisMaxDimension = 2000
        /// Blocks Vision is less sure of than this are dropped rather than translated wrongly.
        var minimumConfidence = 0.3
        /// The same for the text recogniser model, whose confidence is the mean probability of
        /// the characters it chose. It always produces something, even for a crop with no text
        /// in it, so this is what keeps a face mistaken for a bubble from becoming dialogue.
        /// Calibrated on a device run (33 pages, 210 bubbles): confidences split into readings
        /// at 0.97 and above with a median of 10 characters, and readings under 0.8 with a
        /// median of 3 — fragments read off art. Short real lines came back at 0.99.
        var minimumModelConfidence = 0.8
        /// Free horizontal text read by Vision. The one garbage caption in that run, a single
        /// character, sat at exactly the old floor of 0.3.
        var minimumCaptionConfidence = 0.5
        /// Two blocks whose boxes share more than this fraction of the smaller one are the same
        /// text read twice; the more confident reading is kept. On the device run such pairs
        /// overlapped by 31%–90%.
        var duplicateOverlap = 0.3
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

    /// Where a page's recognition time went. A device run measured about 1.1 s per page
    /// before any bubble was read and about 46 ms per character read, against about 5 ms per
    /// decoder step on a Mac; these split that up so the next run says which part is slow.
    nonisolated struct StageTimings: Codable, Sendable, Equatable {
        /// Grayscale copy of the page.
        var preparation = 0
        /// Bubble detection and line segmentation.
        var detection = 0
        /// Reading the bubbles, with the model or with Vision.
        var bubbleReading = 0
        /// The free-text pass.
        var captions = 0
        /// Regions handed to the bubble recogniser.
        var regionsRead = 0
        /// Decoder steps the model took in total; 0 on the Vision path.
        var decoderSteps = 0
    }

    /// `extract(from:)` plus how long it took in milliseconds, in total and by stage.
    func timedExtract(from image: CGImage) throws -> (blocks: [MangaTextBlock], milliseconds: Int, stages: StageTimings) {
        let clock = ContinuousClock()
        let start = clock.now
        let (blocks, stages) = try measuredExtract(from: image)
        return (blocks, Self.milliseconds(start.duration(to: clock.now)), stages)
    }

    func extract(from image: CGImage) throws -> [MangaTextBlock] {
        try measuredExtract(from: image).blocks
    }

    private static func milliseconds(_ duration: Duration) -> Int {
        Int(duration.components.seconds * 1000) + Int(duration.components.attoseconds / 1_000_000_000_000_000)
    }

    private func measuredExtract(from image: CGImage) throws -> (blocks: [MangaTextBlock], stages: StageTimings) {
        var stages = StageTimings()
        let clock = ContinuousClock()
        var mark = clock.now
        func lap() -> Int {
            let now = clock.now
            defer { mark = now }
            return Self.milliseconds(mark.duration(to: now))
        }

        guard let bitmap = GrayscaleBitmap(image: image, maxDimension: configuration.analysisMaxDimension) else {
            return ([], stages)
        }
        stages.preparation = lap()
        let size = CGSize(width: bitmap.width, height: bitmap.height)
        try Task.checkCancellation()

        // Each bubble's plausible arrangements, most likely first.
        let detected = bubbleDetector.detect(in: bitmap)
        let segmented = detected.compactMap { bubble -> (DetectedBubble, [SegmentedText])? in
            let candidates = segmenter.candidates(bubble)
            return candidates.isEmpty ? nil : (bubble, candidates)
        }
        try Task.checkCancellation()
        stages.detection = lap()

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
        stages.bubbleReading = lap()
        stages.regionsRead = segmented.count
        stages.decoderSteps = best.compactMap { $0?.result.steps }.reduce(0, +)

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
            for paragraph in paragraphs where paragraph.confidence >= configuration.minimumCaptionConfidence {
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

        stages.captions = lap()
        return (Self.readingOrder(Self.removingDuplicates(blocks, overlap: configuration.duplicateOverlap)), stages)
    }

    /// Keeps the most confident of any blocks whose boxes largely coincide. Bubble detection
    /// can return two overlapping regions for one bubble — neither inside the other, so the
    /// nesting rule does not catch it — and both get read.
    static func removingDuplicates(_ blocks: [MangaTextBlock], overlap threshold: Double) -> [MangaTextBlock] {
        var kept: [MangaTextBlock] = []
        for block in blocks.sorted(by: { $0.confidence > $1.confidence }) {
            if !kept.contains(where: { $0.bubble.overlap(with: block.bubble) > threshold }) {
                kept.append(block)
            }
        }
        return kept
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
