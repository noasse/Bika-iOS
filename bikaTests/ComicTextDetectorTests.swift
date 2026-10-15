import CoreGraphics
import CoreML
import XCTest
@testable import bika

/// The detector path: the trained text detector finds the text, manga-ocr reads it. The path's
/// own logic is tested with stand-ins, so it runs on CI; model tests skip when bika/MangaModels
/// was not converted locally and fail when it was but did not load.
final class ComicTextDetectorTests: XCTestCase {
    private typealias Bubble = MangaPageFixtures.Bubble

    // MARK: - Decoding the model's output

    func testDetectionsAreDecodedFromCentreBoxesAndClippedToThePage() throws {
        let scores = try MLMultiArray(shape: [1, 3, 3], dataType: .float32)
        let boxes = try MLMultiArray(shape: [1, 3, 4], dataType: .float32)
        func set(_ array: MLMultiArray, _ query: Int, _ values: [Double]) {
            for (index, value) in values.enumerated() { array[[0, NSNumber(value: query), NSNumber(value: index)]] = NSNumber(value: value) }
        }
        set(scores, 0, [0.9, 0.1, 0.0]); set(boxes, 0, [0.5, 0.5, 0.2, 0.4])
        set(scores, 1, [0.0, 0.05, 0.1]); set(boxes, 1, [0.2, 0.2, 0.1, 0.1])    // too unsure to keep
        set(scores, 2, [0.1, 0.6, 0.2]); set(boxes, 2, [0.95, 0.5, 0.2, 0.1])    // runs off the right edge

        let found = ComicTextDetector.detections(scores: scores, boxes: boxes)

        XCTAssertEqual(found.map(\.label), [.bubble, .textInBubble])
        XCTAssertEqual(found[0].rect.x, 0.4, accuracy: 1e-6)
        XCTAssertEqual(found[0].rect.height, 0.4, accuracy: 1e-6)
        XCTAssertEqual(found[1].rect.x + found[1].rect.width, 1, accuracy: 1e-6)
        XCTAssertEqual(found[1].rect.width, 0.15, accuracy: 1e-6)
    }

    func testPixelValuesAreRGBInZeroToOne() throws {
        let context = CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(red: 1, green: 0, blue: 0.5, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))

        let values = try ComicTextDetector.pixelValues(try XCTUnwrap(context.makeImage()), size: 16)

        XCTAssertEqual(values.shape, [1, 3, 16, 16])
        XCTAssertEqual(values[[0, 0, 8, 8]].floatValue, 1, accuracy: 0.01)
        XCTAssertEqual(values[[0, 1, 8, 8]].floatValue, 0, accuracy: 0.01)
        XCTAssertEqual(values[[0, 2, 8, 8]].floatValue, 0.5, accuracy: 0.01)
    }

    // MARK: - Choosing and preparing regions

    private func detection(_ label: ComicTextDetection.Label, _ score: Double, x: Double, y: Double, w: Double, h: Double) -> ComicTextDetection {
        ComicTextDetection(label: label, score: score, rect: NormalizedRect(x: x, y: y, width: w, height: h))
    }

    func testTextFoundTwiceIsReadOnceAndBubblesAreNotRead() {
        let regions = MangaPageTextExtractor.textRegions([
            detection(.bubble, 0.98, x: 0.1, y: 0.1, w: 0.3, h: 0.3),
            detection(.textInBubble, 0.8, x: 0.15, y: 0.15, w: 0.2, h: 0.2),
            detection(.freeText, 0.5, x: 0.16, y: 0.15, w: 0.2, h: 0.2),   // the same text again
            detection(.freeText, 0.2, x: 0.6, y: 0.6, w: 0.1, h: 0.1),     // below the floor
            detection(.freeText, 0.6, x: 0.6, y: 0.1, w: 0.1, h: 0.3),
        ], minimumScore: 0.3, overlap: 0.3)

        XCTAssertEqual(regions.map(\.score), [0.8, 0.6])
    }

    func testTextIsFramedByTheBubbleAroundIt() {
        let text = NormalizedRect(x: 0.2, y: 0.2, width: 0.1, height: 0.2)
        let bubbles = [
            detection(.bubble, 0.9, x: 0.25, y: 0.1, w: 0.4, h: 0.4),   // covers only half the text
            detection(.bubble, 0.8, x: 0.15, y: 0.15, w: 0.2, h: 0.3),
        ]

        XCTAssertEqual(MangaPageTextExtractor.enclosingBubble(of: text, in: bubbles)?.score, 0.8)
        XCTAssertNil(MangaPageTextExtractor.enclosingBubble(of: text, in: [bubbles[0]]))
    }

    func testLightTextOnDarkGroundIsInvertedForReading() throws {
        // Two light vertical columns on black: a white-on-black bubble.
        var bitmap = GrayscaleBitmap(width: 200, height: 300, fill: 0)
        for x in 0..<200 where (60..<80).contains(x) || (120..<140).contains(x) {
            for y in 50..<250 where y % 30 < 24 { bitmap[x, y] = 250 }
        }
        let region = try XCTUnwrap(MangaPageTextExtractor().prepare(
            detection(.textInBubble, 0.9, x: 0.2, y: 0.1, w: 0.6, h: 0.8), in: bitmap
        ))

        XCTAssertTrue(region.isInverted)
        XCTAssertEqual(region.orientation, .vertical)
        XCTAssertEqual(region.lines.count, 2)
        XCTAssertGreaterThan(region.lines[0].minX, region.lines[1].minX, "vertical lines read right to left")
        let crop = try XCTUnwrap(MangaPageTextExtractor.cropImage(region, from: bitmap))
        let cropBitmap = try XCTUnwrap(GrayscaleBitmap(image: crop, maxDimension: 1000))
        XCTAssertEqual(cropBitmap[0, 0], 255, "the dark ground is light in what the recogniser sees")
    }

    // MARK: - The path, with stand-ins

    private struct FixedDetector: ComicTextDetecting {
        let detections: [ComicTextDetection]
        var identifier: String { "fixed-detector" }
        func detect(_ page: CGImage) throws -> [ComicTextDetection] { detections }
    }

    /// Reads every region as its own index, with fixed confidences in order.
    private final class CountingRecognizer: MangaTextRecognizing, @unchecked Sendable {
        let confidences: [Double]
        private var next = 0
        init(confidences: [Double]) { self.confidences = confidences }
        var identifier: String { "counting" }
        func recognize(_ crop: CGImage) throws -> JapaneseTextRecognizer.Result {
            defer { next += 1 }
            return .init(text: "台詞\(next)", confidence: confidences[next], steps: 4)
        }
    }

    private func extractor(_ detections: [ComicTextDetection], confidences: [Double]) -> MangaPageTextExtractor {
        var extractor = MangaPageTextExtractor()
        extractor.textDetector = FixedDetector(detections: detections)
        extractor.textRecognizer = CountingRecognizer(confidences: confidences)
        return extractor
    }

    func testFreeTextBecomesACaptionAndBubbleTextIsFramedByItsBubble() throws {
        let page = MangaPageFixtures.page(bubbles: [])
        let bubble = detection(.bubble, 0.95, x: 0.5, y: 0.05, w: 0.4, h: 0.3)
        let result = try extractor([
            bubble,
            detection(.textInBubble, 0.9, x: 0.72, y: 0.1, w: 0.1, h: 0.2),
            detection(.textInBubble, 0.9, x: 0.55, y: 0.1, w: 0.1, h: 0.2),  // a second text in the same bubble
            detection(.freeText, 0.6, x: 0.1, y: 0.6, w: 0.05, h: 0.2),
        ], confidences: [0.95, 0.95, 0.95]).timedExtract(from: page)

        XCTAssertEqual(result.blocks.map(\.kind), [.bubble, .bubble, .caption])
        XCTAssertEqual(result.blocks[0].bubble, bubble.rect)
        XCTAssertEqual(result.blocks[1].bubble, bubble.rect, "both texts in the bubble are kept")
        XCTAssertGreaterThan(result.blocks[0].textBounds.x, result.blocks[1].textBounds.x, "right to left")
        XCTAssertEqual(result.stages.regionsRead, 3)
        XCTAssertEqual(result.stages.decoderSteps, 12)
    }

    func testReadingsBelowTheModelThresholdAreDropped() throws {
        let page = MangaPageFixtures.page(bubbles: [])
        let blocks = try extractor([
            detection(.textInBubble, 0.9, x: 0.7, y: 0.1, w: 0.1, h: 0.2),
            detection(.freeText, 0.9, x: 0.1, y: 0.1, w: 0.1, h: 0.2),
        ], confidences: [0.95, 0.5]).extract(from: page)

        XCTAssertEqual(blocks.map(\.sourceText), ["台詞0"])
    }

    func testDetectorIsOnlyUsedWithTheRecogniserModel() {
        var extractor = MangaPageTextExtractor.vision()
        extractor.textDetector = FixedDetector(detections: [])
        XCTAssertEqual(extractor.detectorIdentifier, "rules", "Vision cannot read detected regions in any orientation")
        XCTAssertEqual(MangaPageTextExtractor.rules().detectorIdentifier, "rules")
    }

    // MARK: - Model

    private func modelExtractor() throws -> MangaPageTextExtractor {
        if let failure = ComicTextDetector.loadFailure { XCTFail("text detector failed to load: \(failure)") }
        if let failure = MangaOCRRecognizer.loadFailure { XCTFail("manga-ocr failed to load: \(failure)") }
        try XCTSkipIf(ComicTextDetector.bundled == nil || MangaOCRRecognizer.bundled == nil, "models not bundled")
        let extractor = MangaPageTextExtractor()
        XCTAssertTrue(extractor.detectorIdentifier.hasPrefix("ctd@"))
        return extractor
    }

    func testReadsTheTextRuleBasedFindingMissed() throws {
        let extractor = try modelExtractor()
        let page = MangaPageFixtures.page(bubbles: [
            Bubble(frame: CGRect(x: 760, y: 100, width: 340, height: 460), columns: ["本当に", "それで", "いいの？"]),
            Bubble(frame: CGRect(x: 380, y: 120, width: 300, height: 400), columns: ["話を", "聞いて"], fill: 0),
            Bubble(frame: CGRect(x: 940, y: 640, width: 360, height: 420), columns: ["ここだ", "よ"]),
            Bubble(frame: CGRect(x: 520, y: 1220, width: 120, height: 300), columns: ["その日"], outlined: false),
        ].map { var bubble = $0; if bubble.fill == 0 { bubble.ink = 1 }; return bubble })
        // White-on-black; cut by the page edge; narration straight on the art. The rule-based
        // path reads none of them right (of the edge bubble it gets a fragment).
        let byRule = try MangaPageTextExtractor.rules().extract(from: page).map(\.sourceText)
        XCTAssertTrue(Set(byRule).isDisjoint(with: ["話を聞いて", "ここだよ", "その日"]), "\(byRule)")

        let blocks = try extractor.extract(from: page)

        XCTAssertEqual(blocks.map(\.sourceText), ["本当にそれでいいの？", "話を聞いて", "ここだよ", "その日"])
        XCTAssertEqual(blocks.map(\.kind), [.bubble, .bubble, .bubble, .caption])
        XCTAssertEqual(blocks.map(\.orientation), [.vertical, .vertical, .vertical, .vertical])
    }

    func testScreentoneAndLineArtAreNotText() throws {
        let extractor = try modelExtractor()
        let page = MangaPageFixtures.page(
            bubbles: [Bubble(frame: CGRect(x: 700, y: 120, width: 300, height: 440), columns: ["おい", "待てよ"])],
            screentone: true
        ) { context in
            // Closed white shapes with marks inside: what the rule-based path mistook for bubbles.
            context.setStrokeColor(gray: 0, alpha: 1)
            context.setLineWidth(3)
            for index in 0..<4 {
                let frame = CGRect(x: 120 + index * 120, y: 700, width: 90, height: 140)
                context.setFillColor(gray: 1, alpha: 1)
                context.fillEllipse(in: frame)
                context.strokeEllipse(in: frame)
                context.stroke(CGRect(x: frame.midX - 10, y: frame.midY - 30, width: 20, height: 60))
            }
        }

        XCTAssertEqual(try extractor.extract(from: page).map(\.sourceText), ["おい待てよ"])
    }

    func testDetectorTiming() throws {
        let extractor = try modelExtractor()
        let page = MangaPageFixtures.page(bubbles: [
            Bubble(frame: CGRect(x: 760, y: 90, width: 300, height: 420), columns: ["本当に", "それで", "いいの？"]),
            Bubble(frame: CGRect(x: 420, y: 100, width: 280, height: 380), columns: ["話を", "聞いて"], fill: 0.6),
            Bubble(frame: CGRect(x: 90, y: 110, width: 280, height: 400), columns: ["おい", "待てよ"]),
        ], screentone: true)
        _ = try extractor.extract(from: page)

        let detected = try extractor.timedExtract(from: page)
        let rules = try MangaPageTextExtractor.rules().timedExtract(from: page)
        // Informational: simulator timings say little about a device's GPU.
        print("TIMING detector path \(detected.milliseconds) ms (finding \(detected.stages.detection)), "
              + "rules \(rules.milliseconds) ms (finding \(rules.stages.detection))")
    }
}
