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

    // MARK: - Helpers

    private func onlyBubble(_ bubble: Bubble) throws -> DetectedBubble {
        let page = MangaPageFixtures.page(bubbles: [bubble])
        let bitmap = try XCTUnwrap(GrayscaleBitmap(image: page, maxDimension: 2000))
        let detected = SpeechBubbleDetector().detect(in: bitmap)
        XCTAssertEqual(detected.count, 1)
        return try XCTUnwrap(detected.first)
    }
}
