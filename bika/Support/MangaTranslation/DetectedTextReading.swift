import CoreGraphics
import Foundation

/// The page pipeline when the text detector is bundled: detector → read each text region with
/// the recogniser model. Bubble finding, the Vision paths and the caption pass are not used.
extension MangaPageTextExtractor {
    /// One text region the detector found, prepared for reading.
    nonisolated struct TextRegion: Sendable {
        let detection: ComicTextDetection
        /// The detected box in analysis-bitmap pixels.
        let bounds: PixelRect
        /// The text's ink with a margin, clipped to the page: what the recogniser sees.
        let crop: PixelRect
        /// Light text on a dark ground; the crop is inverted before reading.
        let isInverted: Bool
        let orientation: MangaTextOrientation
        /// In reading order, in analysis-bitmap pixels.
        let lines: [PixelRect]
    }

    /// Text regions worth reading: confident enough, and not the same text found twice (as a
    /// region inside a bubble and as free text, say), keeping the more confident.
    static func textRegions(
        _ detections: [ComicTextDetection],
        minimumScore: Double,
        overlap: Double
    ) -> [ComicTextDetection] {
        var kept: [ComicTextDetection] = []
        for detection in detections.sorted(by: { $0.score > $1.score })
        where detection.label != .bubble && detection.score >= minimumScore {
            if !kept.contains(where: { $0.rect.overlap(with: detection.rect) > overlap }) {
                kept.append(detection)
            }
        }
        return kept
    }

    /// The bubble a text region sits in: the most confident bubble covering nearly all of it.
    static func enclosingBubble(
        of text: NormalizedRect,
        in bubbles: [ComicTextDetection],
        minimumCover: Double = 0.8
    ) -> ComicTextDetection? {
        bubbles
            .filter { $0.rect.overlap(with: text) >= minimumCover && $0.rect.area >= text.area }
            .max { $0.score < $1.score }
    }

    /// Ink, orientation and lines for one detected region.
    ///
    /// The detector only gives a box. The lines matter for layout later, and the orientation
    /// for both, so the region's ink is separated from its ground — dark text on a light ground,
    /// or light on dark — and handed to the same line segmenter the rule-based path uses.
    func prepare(_ detection: ComicTextDetection, in bitmap: GrayscaleBitmap) -> TextRegion? {
        let size = CGSize(width: bitmap.width, height: bitmap.height)
        let rect = detection.rect.rect(in: size)
        let bounds = PixelRect(
            minX: max(0, Int(rect.minX.rounded(.down))), minY: max(0, Int(rect.minY.rounded(.down))),
            maxX: min(bitmap.width, Int(rect.maxX.rounded(.up))), maxY: min(bitmap.height, Int(rect.maxY.rounded(.up)))
        )
        guard bounds.width >= 4, bounds.height >= 4 else { return nil }

        // The ground is the region's typical brightness; text is what differs from it strongly.
        var histogram = [Int](repeating: 0, count: 256)
        for y in bounds.minY..<bounds.maxY {
            for x in bounds.minX..<bounds.maxX { histogram[Int(bitmap[x, y])] += 1 }
        }
        let ground = Self.median(histogram, count: bounds.area)
        let isInverted = ground < 128
        let contrast = configuration.detectedInkContrast
        var mask = [Bool](repeating: false, count: bounds.area)
        var inkBounds: PixelRect?
        for y in bounds.minY..<bounds.maxY {
            for x in bounds.minX..<bounds.maxX {
                let value = Int(bitmap[x, y])
                guard isInverted ? value >= ground + contrast : value <= ground - contrast else { continue }
                mask[(y - bounds.minY) * bounds.width + (x - bounds.minX)] = true
                let pixel = PixelRect(minX: x, minY: y, maxX: x + 1, maxY: y + 1)
                inkBounds = inkBounds?.union(pixel) ?? pixel
            }
        }

        let segmented = inkBounds.flatMap {
            segmenter.segment(DetectedBubble(bounds: bounds, inkBounds: $0, inkMask: mask))
        }
        // Without a segmentation (sparse or stylised ink, text on busy art), the box's shape
        // decides; Japanese is vertical unless clearly wider than tall.
        let orientation = segmented?.orientation ?? (bounds.width > bounds.height * 2 ? .horizontal : .vertical)

        // The recogniser stretches every crop to a square, and was trained on crops that hug
        // the text. The detector's box is looser — on a test page a two-column bubble's box was
        // nearly twice as wide as its text — and read off that box the columns came back
        // interleaved (`食べーメン` for `ラーメン食べたい`). So the crop follows the ink, with the
        // same margin as on the rule-based path.
        let text = inkBounds ?? bounds
        let margin = segmented.map { max(4, Int(Double($0.emSize) * configuration.detectedCropMarginEms)) }
            ?? max(4, Int(Double(min(bounds.width, bounds.height)) * 0.08))
        let crop = PixelRect(
            minX: max(0, text.minX - margin), minY: max(0, text.minY - margin),
            maxX: min(bitmap.width, text.maxX + margin), maxY: min(bitmap.height, text.maxY + margin)
        )
        return TextRegion(
            detection: detection,
            bounds: bounds,
            crop: crop,
            isInverted: isInverted,
            orientation: orientation,
            lines: segmented?.lines.map(\.bounds) ?? [bounds]
        )
    }

    /// The crop the recogniser reads: dark text on a light ground, as it was trained on.
    static func cropImage(_ region: TextRegion, from bitmap: GrayscaleBitmap) -> CGImage? {
        let area = region.crop
        var pixels = [UInt8](repeating: 255, count: area.area)
        for y in area.minY..<area.maxY {
            for x in area.minX..<area.maxX {
                let value = bitmap[x, y]
                pixels[(y - area.minY) * area.width + (x - area.minX)] = region.isInverted ? 255 - value : value
            }
        }
        return GrayscaleBitmap(width: area.width, height: area.height, pixels: pixels).makeImage()
    }

    /// Detects, then reads every text region with the recogniser model.
    func readDetectedText(
        page image: CGImage,
        bitmap: GrayscaleBitmap,
        detector: any ComicTextDetecting,
        recognizer: any MangaTextRecognizing,
        stages: inout StageTimings,
        lap: () -> Int
    ) throws -> [MangaTextBlock] {
        let detections = try detector.detect(image)
        let bubbles = detections.filter { $0.label == .bubble && $0.score >= configuration.minimumBubbleScore }
        let regions = Self.textRegions(
            detections, minimumScore: configuration.minimumTextScore, overlap: configuration.duplicateOverlap
        ).compactMap { prepare($0, in: bitmap) }
        try Task.checkCancellation()
        stages.detection = lap()

        let size = CGSize(width: bitmap.width, height: bitmap.height)
        var blocks: [MangaTextBlock] = []
        for region in regions {
            try Task.checkCancellation()
            guard let crop = Self.cropImage(region, from: bitmap) else { continue }
            let result = try recognizer.recognize(crop)
            stages.regionsRead += 1
            stages.decoderSteps += result.steps
            guard result.confidence >= configuration.minimumModelConfidence,
                  JapaneseTextRecognizer.looksLikeJapanese(result.text) else { continue }

            let textBounds = region.detection.rect
            let isFree = region.detection.label == .freeText
            let bubble = isFree ? nil : Self.enclosingBubble(of: textBounds, in: bubbles)
            blocks.append(MangaTextBlock(
                kind: isFree ? .caption : .bubble,
                // Free text and text with no bubble found around it get their own box with a
                // margin, as captions on the rule-based path do.
                bubble: bubble?.rect ?? NormalizedRect(pixelRect: region.crop.cgRect, in: size),
                textBounds: textBounds,
                lines: region.lines.map { NormalizedRect(pixelRect: $0.cgRect, in: size) },
                orientation: region.orientation,
                sourceText: result.text,
                confidence: result.confidence
            ))
        }
        stages.bubbleReading = lap()
        // Not removingDuplicates: that compares bubbles, and two texts in one bubble share it.
        // Regions found twice were already merged before reading.
        return Self.readingOrder(blocks)
    }

    private static func median(_ histogram: [Int], count: Int) -> Int {
        var seen = 0
        for (value, n) in histogram.enumerated() {
            seen += n
            if seen * 2 >= count { return value }
        }
        return 255
    }
}
