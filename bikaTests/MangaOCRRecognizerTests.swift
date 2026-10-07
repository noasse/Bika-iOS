import CoreGraphics
import CoreML
import XCTest
@testable import bika

/// The manga-ocr path. Model tests skip when bika/MangaModels was not converted locally
/// (tools/models/README.md), as on CI; the pure steps are tested regardless.
final class MangaOCRRecognizerTests: XCTestCase {
    private typealias Bubble = MangaPageFixtures.Bubble

    private func modelExtractor() throws -> MangaPageTextExtractor {
        let recognizer = try XCTUnwrap(
            MangaOCRRecognizer.bundled,
            "manga-ocr is not bundled; convert it with tools/models/convert_manga_ocr.py"
        )
        var extractor = MangaPageTextExtractor()
        extractor.textRecognizer = recognizer
        return extractor
    }

    private func requireModel() throws {
        try XCTSkipIf(MangaOCRRecognizer.bundled == nil, "manga-ocr not bundled")
    }

    // MARK: - Pure steps

    func testRepeatedTrigramIsBanned() {
        // ... 7 8 9 ... 7 8 → 9 would repeat the trigram 7 8 9.
        XCTAssertEqual(MangaOCRRecognizer.bannedTokens(after: [2, 7, 8, 9, 5, 7, 8], ngram: 3), [9])
        XCTAssertEqual(MangaOCRRecognizer.bannedTokens(after: [2, 7], ngram: 3), [])
        XCTAssertEqual(MangaOCRRecognizer.bannedTokens(after: [2, 7, 8, 9], ngram: 0), [])
    }

    func testDetokeniseSkipsSpecialTokensAndContinuationMarks() {
        let vocabulary = ["[PAD]", "[UNK]", "[CLS]", "[SEP]", "[MASK]", "本", "##当", "に", " "]
        XCTAssertEqual(MangaOCRRecognizer.detokenise([2, 5, 6, 7, 8, 3], vocabulary: vocabulary), "本当に")
    }

    func testOutputIsNormalisedLikeUpstream() {
        // Half-width ASCII to full width, as upstream manga-ocr does; dot runs to one ellipsis.
        XCTAssertEqual(MangaOCRRecognizer.normalised("いいの?"), "いいの？")
        XCTAssertEqual(MangaOCRRecognizer.normalised("あと10分!"), "あと１０分！")
        XCTAssertEqual(MangaOCRRecognizer.normalised("そうか..."), "そうか…")
    }

    func testPixelValuesAreScaledToMinusOneOne() throws {
        let context = CGContext(data: nil, width: 10, height: 10, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 10, height: 10))
        let values = try MangaOCRRecognizer.pixelValues(try XCTUnwrap(context.makeImage()))

        XCTAssertEqual(values.shape, [1, 3, 224, 224])
        XCTAssertEqual(values[[0, 0, 100, 100]].floatValue, 1, accuracy: 0.01)
        XCTAssertEqual(values[[0, 2, 100, 100]].floatValue, 1, accuracy: 0.01)
    }

    // MARK: - Model

    func testBundledModelLoads() throws {
        try requireModel()
        XCTAssertTrue(try XCTUnwrap(MangaOCRRecognizer.bundled).identifier.hasPrefix("manga-ocr@"))
        XCTAssertTrue(MangaPageTextExtractor().recognizerIdentifier.hasPrefix("manga-ocr@"))
        XCTAssertEqual(MangaPageTextExtractor.vision().recognizerIdentifier, "vision")
    }

    func testReadsMultiColumnVerticalBubbleWithoutReflow() throws {
        try requireModel()
        let page = MangaPageFixtures.page(bubbles: [
            Bubble(frame: CGRect(x: 650, y: 120, width: 340, height: 520), columns: ["本当に", "それで", "いいの？"]),
        ])

        let blocks = try modelExtractor().extract(from: page)

        XCTAssertEqual(blocks.map(\.sourceText), ["本当にそれでいいの？"])
        XCTAssertEqual(blocks.first?.orientation, .vertical)
        XCTAssertGreaterThan(blocks.first?.confidence ?? 0, 0.8)
    }

    func testReadsLongVowelMarkInVerticalText() throws {
        try requireModel()
        let page = MangaPageFixtures.page(bubbles: [
            Bubble(frame: CGRect(x: 650, y: 120, width: 300, height: 520), columns: ["ラーメン", "食べたい"]),
        ])

        XCTAssertEqual(try modelExtractor().extract(from: page).map(\.sourceText), ["ラーメン食べたい"])
    }

    func testReadsGrayBubbleAndSeveralBubblesInOrder() throws {
        try requireModel()
        let page = MangaPageFixtures.page(bubbles: [
            Bubble(frame: CGRect(x: 150, y: 140, width: 300, height: 440), columns: ["話を", "聞いて"], fill: 0.6),
            Bubble(frame: CGRect(x: 720, y: 120, width: 300, height: 440), columns: ["おい", "待てよ"]),
        ])

        XCTAssertEqual(try modelExtractor().extract(from: page).map(\.sourceText), ["おい待てよ", "話を聞いて"])
    }

    func testFuriganaDoesNotEndUpInTheText() throws {
        try requireModel()
        let page = MangaPageFixtures.page(bubbles: [
            Bubble(frame: CGRect(x: 600, y: 120, width: 360, height: 460), columns: ["諦めて", "ない"], furigana: "あきら"),
        ])

        XCTAssertEqual(try modelExtractor().extract(from: page).map(\.sourceText), ["諦めてない"])
    }

    func testCaptionsStillReadAlongsideModelBubbles() throws {
        try requireModel()
        let page = MangaPageFixtures.page(
            bubbles: [Bubble(frame: CGRect(x: 700, y: 120, width: 300, height: 440), columns: ["おい", "待てよ"])],
            captions: [.init(origin: CGPoint(x: 140, y: 720), lines: ["ここから本編です"], background: nil)]
        )

        let blocks = try modelExtractor().extract(from: page)

        XCTAssertEqual(Set(blocks.map(\.sourceText)), ["おい待てよ", "ここから本編です"])
    }

    func testModelPathTiming() throws {
        try requireModel()
        let page = MangaPageFixtures.page(bubbles: [
            Bubble(frame: CGRect(x: 760, y: 90, width: 300, height: 420), columns: ["本当に", "それで", "いいの？"]),
            Bubble(frame: CGRect(x: 420, y: 100, width: 280, height: 380), columns: ["話を", "聞いて"], fill: 0.6),
            Bubble(frame: CGRect(x: 90, y: 110, width: 280, height: 400), columns: ["おい", "待てよ"]),
            Bubble(frame: CGRect(x: 760, y: 560, width: 300, height: 420), columns: ["ラーメン", "食べたい"], fill: 0.85),
        ], screentone: true)
        let model = try modelExtractor()
        _ = try model.extract(from: page) // first run loads and specialises the models

        let modelTime = try model.timedExtract(from: page).milliseconds
        let visionTime = try MangaPageTextExtractor.vision().timedExtract(from: page).milliseconds
        // Informational: simulator timings say little about a device's Neural Engine.
        print("TIMING manga-ocr \(modelTime) ms, vision \(visionTime) ms")
    }
}

/// Rules calibrated on the first device run, tested with a stand-in recogniser so they hold
/// whether or not the model is bundled.
final class MangaModelPathRulesTests: XCTestCase {
    private struct FixedRecognizer: MangaTextRecognizing {
        let text: String
        let confidence: Double
        var identifier: String { "fixed" }
        func recognize(_ crop: CGImage) throws -> JapaneseTextRecognizer.Result {
            .init(text: text, confidence: confidence, steps: text.count + 1)
        }
    }

    private let page = MangaPageFixtures.page(bubbles: [
        .init(frame: CGRect(x: 650, y: 120, width: 340, height: 520), columns: ["本当に", "それで", "いいの？"]),
    ])

    private func extractor(confidence: Double) -> MangaPageTextExtractor {
        var extractor = MangaPageTextExtractor()
        extractor.textRecognizer = FixedRecognizer(text: "本当にそれでいいの？", confidence: confidence)
        extractor.configuration.readsCaptions = false
        return extractor
    }

    func testModelReadingsBelowTheCalibratedThresholdAreDropped() throws {
        // On the device run, readings under 0.8 were three-character fragments read off art.
        XCTAssertTrue(try extractor(confidence: 0.75).extract(from: page).isEmpty)
        XCTAssertEqual(try extractor(confidence: 0.85).extract(from: page).map(\.sourceText), ["本当にそれでいいの？"])
    }

    func testStageTimingsAccountForTheModelPath() throws {
        let result = try extractor(confidence: 0.9).timedExtract(from: page)

        XCTAssertEqual(result.stages.regionsRead, 1)
        XCTAssertEqual(result.stages.decoderSteps, "本当にそれでいいの？".count + 1)
        let parts = result.stages.preparation + result.stages.detection + result.stages.bubbleReading + result.stages.captions
        XCTAssertLessThanOrEqual(parts, result.milliseconds + 1)
    }

    func testOverlappingReadingsOfOneBubbleKeepTheMoreConfident() {
        func block(_ text: String, x: Double, confidence: Double) -> MangaTextBlock {
            let rect = NormalizedRect(x: x, y: 0.1, width: 0.2, height: 0.3)
            return MangaTextBlock(bubble: rect, textBounds: rect, lines: [rect], orientation: .vertical,
                                  sourceText: text, confidence: confidence)
        }
        let kept = MangaPageTextExtractor.removingDuplicates([
            block("weaker", x: 0.10, confidence: 0.82),
            block("stronger", x: 0.14, confidence: 0.99),  // overlaps the first by 80%
            block("elsewhere", x: 0.60, confidence: 0.90),
        ], overlap: 0.3)

        XCTAssertEqual(Set(kept.map(\.sourceText)), ["stronger", "elsewhere"])
    }

    func testRectsAreClippedToThePage() {
        // A caption padded at the left edge came back from a device with a negative x.
        let rect = NormalizedRect(pixelRect: CGRect(x: -60, y: 1700, width: 300, height: 200), in: CGSize(width: 1200, height: 1800))
        XCTAssertEqual(rect.x, 0)
        XCTAssertEqual(rect.x + rect.width, 240.0 / 1200, accuracy: 1e-9)
        XCTAssertEqual(rect.y + rect.height, 1, accuracy: 1e-9)
    }
}
