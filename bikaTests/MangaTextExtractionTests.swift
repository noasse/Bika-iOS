import CoreGraphics
import XCTest
@testable import bika

final class MangaTextExtractionTests: XCTestCase {
    private typealias Bubble = MangaPageFixtures.Bubble

    // MARK: - Bitmap

    func testBitmapKeepsTopRowFirst() throws {
        // A page whose top-left corner is black; CGContext buffers are easy to get upside down.
        let context = CGContext(data: nil, width: 20, height: 10, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 20, height: 10))
        context.setFillColor(gray: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 9, width: 1, height: 1)) // CG origin is bottom-left: this is the top row

        let bitmap = try XCTUnwrap(GrayscaleBitmap(image: try XCTUnwrap(context.makeImage()), maxDimension: 100))

        XCTAssertEqual(bitmap[0, 0], 0)
        XCTAssertEqual(bitmap[0, 9], 255)
    }

    func testBitmapDownscalesLongSideOnly() throws {
        let page = MangaPageFixtures.page(bubbles: [])
        let bitmap = try XCTUnwrap(GrayscaleBitmap(image: page, maxDimension: 850))
        XCTAssertEqual(bitmap.height, 850)
        XCTAssertEqual(bitmap.width, 600)
    }

    // MARK: - Bubbles

    func testDetectsEachEnclosedBubbleButNotThePageBackground() throws {
        let page = MangaPageFixtures.page(bubbles: [
            Bubble(frame: CGRect(x: 700, y: 120, width: 300, height: 420), columns: ["おい", "待てよ"]),
            Bubble(frame: CGRect(x: 150, y: 200, width: 280, height: 380), columns: ["本当に", "いいの"]),
        ])
        let bitmap = try XCTUnwrap(GrayscaleBitmap(image: page, maxDimension: 2000))

        let bubbles = SpeechBubbleDetector().detect(in: bitmap)

        XCTAssertEqual(bubbles.count, 2)
        for bubble in bubbles {
            XCTAssertLessThan(bubble.bounds.width, 320, "the page background must never be taken for a bubble")
        }
    }

    func testEmptyBubbleIsIgnored() throws {
        let page = MangaPageFixtures.page(bubbles: [
            Bubble(frame: CGRect(x: 700, y: 120, width: 300, height: 420), columns: []),
        ])
        let bitmap = try XCTUnwrap(GrayscaleBitmap(image: page, maxDimension: 2000))

        XCTAssertTrue(SpeechBubbleDetector().detect(in: bitmap).isEmpty)
    }

    // MARK: - Lines

    func testVerticalColumnsComeBackRightToLeft() throws {
        let bubble = try onlyBubble(Bubble(frame: CGRect(x: 600, y: 120, width: 380, height: 460),
                                           columns: ["俺は", "まだ", "諦めない"]))

        let text = try XCTUnwrap(TextLineSegmenter().segment(bubble))

        XCTAssertEqual(text.orientation, .vertical)
        XCTAssertEqual(text.lines.count, 3)
        XCTAssertEqual(text.lines.map(\.bounds.minX), text.lines.map(\.bounds.minX).sorted(by: >))
        // The third column is the longest.
        XCTAssertGreaterThan(text.lines[2].bounds.height, text.lines[0].bounds.height)
    }

    func testGlyphsWithTheirOwnGapsStayInOneColumn() throws {
        // 小 and 川 have blank vertical gaps inside the glyph; さ and ん do not, as in real text.
        let bubble = try onlyBubble(Bubble(frame: CGRect(x: 600, y: 120, width: 300, height: 460),
                                           columns: ["小川さん"]))

        let text = try XCTUnwrap(TextLineSegmenter().segment(bubble))

        XCTAssertEqual(text.lines.count, 1)
    }

    func testFuriganaIsDropped() throws {
        let bubble = try onlyBubble(Bubble(frame: CGRect(x: 600, y: 120, width: 360, height: 460),
                                           columns: ["諦めて", "ない"], furigana: "あきら"))

        let text = try XCTUnwrap(TextLineSegmenter().segment(bubble))

        XCTAssertEqual(text.lines.count, 2, "the reading aid beside 諦 must not become a column of its own")
    }

    func testWideSingleLineIsHorizontal() throws {
        let bubble = try onlyBubble(Bubble(frame: CGRect(x: 300, y: 200, width: 640, height: 200),
                                           columns: ["ちょっと待って"], vertical: false))

        let text = try XCTUnwrap(TextLineSegmenter().segment(bubble))

        XCTAssertEqual(text.orientation, .horizontal)
        XCTAssertEqual(text.lines.count, 1)
    }

    // MARK: - Reflow cuts

    func testCutsLandInTheGapsBetweenCharacters() {
        // Characters 40px tall with 8px gaps, so the true pitch is 48px; em is measured as 40.
        let rows = Set((0..<5).flatMap { index in (index * 48)..<(index * 48 + 40) })
        let line = SegmentedLine(bounds: PixelRect(minX: 0, minY: 0, maxX: 40, maxY: 4 * 48 + 40))

        let cells = TextReflow().cells(of: line, emSize: 40) { rows.contains($0) ? 30 : 0 }

        XCTAssertEqual(cells.count, 5)
        for cell in cells.dropLast() {
            XCTAssertFalse(rows.contains(cell.upperBound), "cut at \(cell.upperBound) falls inside a character")
        }
    }

    // MARK: - Repairs

    func testVerticalLongVowelMarkIsRestored() {
        XCTAssertEqual(JapaneseTextRecognizer.repairReflowArtifacts("ラ|メン"), "ラーメン")
        XCTAssertEqual(JapaneseTextRecognizer.repairReflowArtifacts("すご l い"), "すごーい")
        // Not after Japanese: left alone.
        XCTAssertEqual(JapaneseTextRecognizer.repairReflowArtifacts("1回"), "1回")
    }

    func testVerticalEllipsisIsRestored() {
        XCTAssertEqual(JapaneseTextRecognizer.repairReflowArtifacts("そう："), "そう…")
    }

    // MARK: - Reading order

    func testBubblesReadTopToBottomThenRightToLeft() {
        func block(x: Double, y: Double, _ text: String) -> MangaTextBlock {
            let rect = NormalizedRect(x: x, y: y, width: 0.1, height: 0.1)
            return MangaTextBlock(bubble: rect, textBounds: rect, lines: [rect], orientation: .vertical, sourceText: text)
        }
        let ordered = MangaPageTextExtractor.readingOrder([
            block(x: 0.1, y: 0.52, "lower-left"),
            block(x: 0.1, y: 0.10, "top-left"),
            block(x: 0.7, y: 0.13, "top-right"),
            block(x: 0.7, y: 0.50, "lower-right"),
        ])
        XCTAssertEqual(ordered.map(\.sourceText), ["top-right", "top-left", "lower-right", "lower-left"])
    }

    // MARK: - End to end

    func testReadsVerticalJapaneseFromABubble() throws {
        let page = MangaPageFixtures.page(bubbles: [
            Bubble(frame: CGRect(x: 650, y: 120, width: 340, height: 520), columns: ["本当に", "それで", "いいの？"]),
        ])

        let blocks = try MangaPageTextExtractor().extract(from: page)

        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks.first?.sourceText, "本当にそれでいいの？")
        XCTAssertEqual(blocks.first?.orientation, .vertical)
    }

    func testReadsLongVowelMarkInVerticalText() throws {
        let page = MangaPageFixtures.page(bubbles: [
            Bubble(frame: CGRect(x: 650, y: 120, width: 300, height: 520), columns: ["ラーメン", "食べたい"]),
        ])

        let blocks = try MangaPageTextExtractor().extract(from: page)

        XCTAssertEqual(blocks.first?.sourceText, "ラーメン食べたい")
    }

    func testReadsSeveralBubblesInReadingOrder() throws {
        let page = MangaPageFixtures.page(bubbles: [
            Bubble(frame: CGRect(x: 150, y: 140, width: 300, height: 440), columns: ["話を", "聞いて"]),
            Bubble(frame: CGRect(x: 720, y: 120, width: 300, height: 440), columns: ["おい", "待てよ"]),
        ])

        let blocks = try MangaPageTextExtractor().extract(from: page)

        XCTAssertEqual(blocks.map(\.sourceText), ["おい待てよ", "話を聞いて"])
    }

    // MARK: - Device findings (round 2)
    //
    // Each of these reproduces something seen on real line-art pages on a device.

    func testBubbleInsideAnEnclosedAreaIsReadOnce() throws {
        // A real bubble inside a larger area closed off by line art. The outer area's "ink" is
        // the bubble's outline and text, so it used to be read a second time.
        let page = MangaPageFixtures.page(bubbles: [
            Bubble(frame: CGRect(x: 520, y: 220, width: 260, height: 380), columns: ["待って", "くれ"]),
        ]) { context in
            context.setFillColor(gray: 1, alpha: 1)
            context.fill(CGRect(x: 360, y: 120, width: 560, height: 600))
            context.setStrokeColor(gray: 0, alpha: 1)
            context.setLineWidth(5)
            context.stroke(CGRect(x: 360, y: 120, width: 560, height: 600))
        }

        let blocks = try MangaPageTextExtractor().extract(from: page)

        XCTAssertEqual(blocks.map(\.sourceText), ["待ってくれ"])
    }

    func testVerticalEllipsisAtTheEndOfALineBecomesOneEllipsis() throws {
        // Reflow cuts a vertical double ellipsis into cells. Before collapsing dot runs it came
        // back as `そうか…・…•なるほど`, the same artefact seen on a device.
        let page = MangaPageFixtures.page(bubbles: [
            Bubble(frame: CGRect(x: 650, y: 120, width: 300, height: 560), columns: ["そうか……", "なるほど"]),
        ])

        let blocks = try MangaPageTextExtractor().extract(from: page)

        XCTAssertEqual(blocks.first?.sourceText, "そうか…なるほど")
    }

    // Strings below were returned on a device for line-art features (faces, hair, page
    // numbers) that the bubble detector took for bubbles. Synthetic faces could not reproduce
    // that — Vision returns nothing for them — so the filter is tested on the strings directly.
    func testRejectsTextThatIsNotJapanese() {
        for garbage in ["し?,", "•…", "12/", "1X", "0.", "6", "※", "、//はい)", "…", "ー"] {
            XCTAssertFalse(
                JapaneseTextRecognizer.looksLikeJapanese(JapaneseTextRecognizer.collapsingDotRuns(garbage)),
                "\(garbage) should be rejected"
            )
        }
    }

    func testKeepsShortAndPunctuatedJapanese() {
        for line in ["は?", "え!?", "本当に?", "そうか…", "…ハハ…", "あと10分", "待ってくれ"] {
            XCTAssertTrue(JapaneseTextRecognizer.looksLikeJapanese(line), "\(line) should be kept")
        }
    }

    func testDotRunsCollapseButANameSeparatorStays() {
        XCTAssertEqual(JapaneseTextRecognizer.collapsingDotRuns("そうか…・"), "そうか…")
        XCTAssertEqual(JapaneseTextRecognizer.collapsingDotRuns("待って・・・"), "待って…")
        XCTAssertEqual(JapaneseTextRecognizer.collapsingDotRuns("えっ..."), "えっ…")
        XCTAssertEqual(JapaneseTextRecognizer.collapsingDotRuns("…•"), "…")
        XCTAssertEqual(JapaneseTextRecognizer.collapsingDotRuns("そうか・・・⋯・・"), "そうか…")
        XCTAssertEqual(JapaneseTextRecognizer.collapsingDotRuns("ジョン・スミス"), "ジョン・スミス")
    }

    func testAlternativeReadingNeedsMoreConfidenceAndAsMuchText() {
        typealias R = JapaneseTextRecognizer.Result
        let vertical = R(text: "これはなんだろう", confidence: 0.6)

        // More confident but reads only part of the text: a row across two columns.
        XCTAssertFalse(MangaPageTextExtractor.alternativeWins(R(text: "これは", confidence: 0.95), over: vertical, margin: 0.15))
        // As long but not clearly more confident.
        XCTAssertFalse(MangaPageTextExtractor.alternativeWins(R(text: "これはなんだろう", confidence: 0.7), over: vertical, margin: 0.15))
        // Clearly better on both.
        XCTAssertTrue(MangaPageTextExtractor.alternativeWins(R(text: "これはなんだろうか", confidence: 0.9), over: vertical, margin: 0.15))
        // Nothing to beat.
        XCTAssertTrue(MangaPageTextExtractor.alternativeWins(R(text: "は", confidence: 0.4), over: nil, margin: 0.15))
    }

    // MARK: - Device findings (round 3)

    func testReadsAGrayBubble() throws {
        // A fixed "brightness at least 200" rule only ever found white bubbles.
        let page = MangaPageFixtures.page(bubbles: [
            Bubble(frame: CGRect(x: 650, y: 120, width: 320, height: 480), columns: ["本当に", "いいの？"], fill: 0.55),
        ])

        let blocks = try MangaPageTextExtractor().extract(from: page)

        XCTAssertEqual(blocks.map(\.sourceText), ["本当にいいの？"])
        XCTAssertEqual(blocks.first?.kind, .bubble)
    }

    func testReadsATintedBubble() throws {
        let page = MangaPageFixtures.page(bubbles: [
            Bubble(frame: CGRect(x: 650, y: 120, width: 320, height: 480), columns: ["話を", "聞いて"], fill: 0.82),
        ])

        XCTAssertEqual(try MangaPageTextExtractor().extract(from: page).map(\.sourceText), ["話を聞いて"])
    }

    func testReadsFreeHorizontalTextAsOneParagraph() throws {
        // Text straight on the page background, as in an afterword: no enclosing box.
        let page = MangaPageFixtures.page(bubbles: [], captions: [
            .init(origin: CGPoint(x: 140, y: 700), lines: ["今回は初めての", "合同誌になります", "最後までお楽しみください"], background: nil),
        ])

        let blocks = try MangaPageTextExtractor().extract(from: page)

        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks.first?.kind, .caption)
        XCTAssertEqual(blocks.first?.lines.count, 3)
        XCTAssertEqual(blocks.first?.sourceText, "今回は初めての合同誌になります最後までお楽しみください")
    }

    func testCaptionsAndBubblesAreReadTogether() throws {
        let page = MangaPageFixtures.page(
            bubbles: [Bubble(frame: CGRect(x: 700, y: 120, width: 300, height: 440), columns: ["おい", "待てよ"])],
            captions: [.init(origin: CGPoint(x: 140, y: 720), lines: ["ここから本編です"], background: nil)]
        )

        let blocks = try MangaPageTextExtractor().extract(from: page)

        XCTAssertEqual(Set(blocks.map(\.sourceText)), ["おい待てよ", "ここから本編です"])
        XCTAssertEqual(blocks.first { $0.sourceText == "ここから本編です" }?.kind, .caption)
    }

    func testHorizontalNarrationBoxReadsItsLinesInOrder() throws {
        // A tinted box enclosing horizontal lines is a narration box: read as a bubble. Its
        // lines all start at about the same x, and sorting by x alone read them bottom first.
        let page = MangaPageFixtures.page(bubbles: [], captions: [
            .init(origin: CGPoint(x: 140, y: 700), lines: ["今回は初めての", "合同誌になります", "最後までお楽しみください"], background: 0.9),
        ])

        let blocks = try MangaPageTextExtractor().extract(from: page)

        XCTAssertEqual(blocks.map(\.sourceText), ["今回は初めての合同誌になります最後までお楽しみください"])
    }

    func testPiecesAreOrderedByRowThenColumn() {
        // Vision boxes: bottom-left origin, so the top row has the highest y.
        let pieces: [(box: CGRect, text: String)] = [
            (CGRect(x: 0.1, y: 0.1, width: 0.5, height: 0.1), "third"),
            (CGRect(x: 0.6, y: 0.5, width: 0.3, height: 0.1), "second-right"),
            (CGRect(x: 0.1, y: 0.5, width: 0.4, height: 0.1), "second-left"),
            (CGRect(x: 0.1, y: 0.8, width: 0.5, height: 0.1), "first"),
        ]
        XCTAssertEqual(JapaneseTextRecognizer.readingOrder(pieces).map(\.text),
                       ["first", "second-left", "second-right", "third"])
    }

    func testVerticalTextOnTheArtIsNotMisreadAsAHorizontalCaption() throws {
        // Vertical narration with no bubble. Vision does not read it properly, but given several
        // columns it can read *across* them and return a line of real kana and kanji — with an
        // undetected gray bubble it produced `い本い当のに？`, which passes the Japanese check.
        let page = MangaPageFixtures.page(bubbles: [
            Bubble(frame: CGRect(x: 600, y: 160, width: 300, height: 440), columns: ["本当に", "いいの？"], outlined: false),
        ])

        let captions = try MangaPageTextExtractor().extract(from: page).filter { $0.kind == .caption }

        XCTAssertEqual(captions.map(\.sourceText), [])
    }

    func testHorizontalBubbleTextIsNotReadAgainAsACaption() throws {
        // The full-page pass finds horizontal text inside bubbles too.
        let page = MangaPageFixtures.page(bubbles: [
            Bubble(frame: CGRect(x: 300, y: 200, width: 640, height: 200), columns: ["ちょっと待って"], vertical: false),
        ])

        let blocks = try MangaPageTextExtractor().extract(from: page)

        XCTAssertEqual(blocks.map(\.sourceText), ["ちょっと待って"])
        XCTAssertEqual(blocks.first?.kind, .bubble)
    }

    // MARK: - Helpers

    private func onlyBubble(_ bubble: Bubble) throws -> DetectedBubble {
        let page = MangaPageFixtures.page(bubbles: [bubble])
        let bitmap = try XCTUnwrap(GrayscaleBitmap(image: page, maxDimension: 2000))
        let detected = SpeechBubbleDetector().detect(in: bitmap)
        XCTAssertEqual(detected.count, 1)
        return try XCTUnwrap(detected.first)
    }
}
