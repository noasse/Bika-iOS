import UIKit
import XCTest
@testable import bika

final class MangaTranslationLayoutTests: XCTestCase {
    /// A vertical three-column bubble in the top right of a 300×420 page.
    private func bubbleBlock(kind: MangaTextKind = .bubble) -> MangaTextBlock {
        let bubble = NormalizedRect(x: 0.6, y: 0.05, width: 0.3, height: 0.3)
        let text = NormalizedRect(x: 0.68, y: 0.1, width: 0.14, height: 0.18)
        let lines = (0..<3).map { NormalizedRect(x: 0.775 - Double($0) * 0.045, y: 0.1, width: 0.045, height: 0.18) }
        return MangaTextBlock(kind: kind, bubble: bubble, textBounds: text, lines: lines, orientation: .vertical,
                              sourceText: "本当にそれでいいの？", confidence: 0.99)
    }

    private let page = CGRect(x: 0, y: 0, width: 300, height: 420)

    private func onScreen(_ rect: NormalizedRect, _ imageRect: CGRect) -> CGRect {
        rect.rect(in: imageRect.size).offsetBy(dx: imageRect.minX, dy: imageRect.minY)
    }

    private func assertFits(_ item: MangaTranslationLayout.Item, file: StaticString = #filePath, line: UInt = #line) {
        let measured = MangaTranslationLayout.measuredSize(item.text, size: item.fontSize, width: item.textRect.width)
        XCTAssertLessThanOrEqual(measured.height, item.textRect.height + 0.5, "text overflows its area", file: file, line: line)
        XCTAssertTrue(item.cover.insetBy(dx: -0.5, dy: -0.5).contains(item.textRect), "text outside its cover", file: file, line: line)
    }

    func testTheTranslationFitsAndTheCoverHidesTheOriginal() throws {
        let block = bubbleBlock()
        let item = try XCTUnwrap(MangaTranslationLayout.item(block, text: "你真的觉得这样就好吗？", ground: 1, in: page))

        assertFits(item)
        XCTAssertTrue(item.cover.contains(onScreen(block.textBounds, page)), "original text left showing")
        let em = try XCTUnwrap(MangaTranslationLayout.originalCharacterSize(block, in: page))
        XCTAssertLessThanOrEqual(item.fontSize, em * MangaTranslationLayout.largestFraction + 0.01)
        XCTAssertGreaterThanOrEqual(item.fontSize, em * MangaTranslationLayout.smallestFraction - 0.01)
        XCTAssertEqual(item.coverAlpha, 1, "a bubble is painted over in its own tone")
    }

    func testALongTranslationTakesMoreOfTheBubbleButStaysInIt() throws {
        let block = bubbleBlock()
        let short = try XCTUnwrap(MangaTranslationLayout.item(block, text: "真的？", ground: 1, in: page))
        let long = try XCTUnwrap(MangaTranslationLayout.item(
            block, text: "Are you really sure that this is what you want to do with your life?", ground: 1, in: page))

        assertFits(long)
        XCTAssertGreaterThan(long.textRect.width * long.textRect.height, short.textRect.width * short.textRect.height)
        XCTAssertTrue(onScreen(block.bubble, page).contains(long.cover), "cover spills out of the bubble")
    }

    func testTextThatCannotFitIsSetSmallestInsideTheBubble() throws {
        let block = bubbleBlock()
        let essay = String(repeating: "这是一段长得离谱、无论如何都放不进这个对话框的译文。", count: 12)
        let item = try XCTUnwrap(MangaTranslationLayout.item(block, text: essay, ground: 1, in: page))

        let em = try XCTUnwrap(MangaTranslationLayout.originalCharacterSize(block, in: page))
        XCTAssertEqual(item.fontSize, em * MangaTranslationLayout.smallestFraction, accuracy: 0.01)
        XCTAssertTrue(onScreen(block.bubble, page).contains(item.cover))
    }

    func testLayoutFollowsThePageSize() throws {
        let block = bubbleBlock()
        let text = "你真的觉得这样就好吗？"
        let small = try XCTUnwrap(MangaTranslationLayout.item(block, text: text, ground: 1, in: page))
        let large = try XCTUnwrap(MangaTranslationLayout.item(
            block, text: text, ground: 1, in: CGRect(x: 10, y: 20, width: 600, height: 840)))

        XCTAssertEqual(large.cover.width, small.cover.width * 2, accuracy: 2)
        XCTAssertEqual(large.cover.minX, small.cover.minX * 2 + 10, accuracy: 2)
        XCTAssertEqual(large.fontSize, small.fontSize * 2, accuracy: small.fontSize * 0.15)
    }

    func testTextStandsOutFromItsGround() throws {
        let block = bubbleBlock()
        let onBlack = try XCTUnwrap(MangaTranslationLayout.item(block, text: "等等", ground: 0.05, in: page))
        let onGray = try XCTUnwrap(MangaTranslationLayout.item(block, text: "等等", ground: 0.6, in: page))

        XCTAssertEqual(onBlack.coverLevel, 0.05)
        XCTAssertEqual(onBlack.textLevel, 1)
        XCTAssertEqual(onGray.textLevel, 0)
    }

    func testFreeTextGetsAPlateAroundTheTextOnly() throws {
        let block = bubbleBlock(kind: .caption)
        let item = try XCTUnwrap(MangaTranslationLayout.item(block, text: "那一天，我", ground: 0.4, in: page))

        assertFits(item)
        XCTAssertLessThan(item.coverAlpha, 1, "art behind free text shows through a little")
        let text = onScreen(block.textBounds, page)
        XCTAssertLessThan(item.cover.width, text.width * 1.6, "a caption does not borrow a bubble's interior")
    }

    func testBlocksWithoutATranslationAreSkipped() {
        let items = MangaTranslationLayout.items(
            blocks: [bubbleBlock(), bubbleBlock()], translations: ["  ", "等等"], grounds: [1, 1], in: page)
        XCTAssertEqual(items.map(\.text), ["等等"])
    }
}

final class MangaPageGroundTests: XCTestCase {
    func testSamplesTheBubbleFillAroundItsText() throws {
        typealias Bubble = MangaPageFixtures.Bubble
        let frames = [CGRect(x: 760, y: 100, width: 340, height: 460),
                      CGRect(x: 380, y: 120, width: 300, height: 400),
                      CGRect(x: 60, y: 120, width: 300, height: 400)]
        let page = MangaPageFixtures.page(bubbles: [
            Bubble(frame: frames[0], columns: ["本当に", "それで"]),
            Bubble(frame: frames[1], columns: ["話を", "聞いて"], fill: 0.6),
            Bubble(frame: frames[2], columns: ["おい", "待てよ"], fill: 0, ink: 1),
        ])
        let ground = try XCTUnwrap(MangaPageGround(image: page))
        let size = MangaPageFixtures.pageSize

        let levels = frames.map { frame in
            // The text block's area: the middle of the bubble.
            ground.level(around: NormalizedRect(pixelRect: frame.insetBy(dx: frame.width * 0.32, dy: frame.height * 0.3), in: size))
        }

        XCTAssertEqual(levels[0], 1, accuracy: 0.05)
        XCTAssertEqual(levels[1], 0.6, accuracy: 0.06)
        XCTAssertEqual(levels[2], 0, accuracy: 0.05)
    }
}

@MainActor
final class MangaTranslationOverlayViewTests: XCTestCase {
    private let block = MangaTextBlock(
        bubble: NormalizedRect(x: 0.5, y: 0.1, width: 0.4, height: 0.3),
        textBounds: NormalizedRect(x: 0.6, y: 0.15, width: 0.2, height: 0.2),
        lines: [NormalizedRect(x: 0.7, y: 0.15, width: 0.06, height: 0.2), NormalizedRect(x: 0.62, y: 0.15, width: 0.06, height: 0.2)],
        orientation: .vertical, sourceText: "待って", confidence: 0.99)

    func testEachTranslationIsACoverAndALabel() {
        let overlay = MangaTranslationOverlayView(frame: CGRect(x: 0, y: 0, width: 300, height: 420))
        overlay.imageSize = CGSize(width: 1200, height: 1680)
        overlay.state = .translated(blocks: [block, block], translations: ["等等", "等一下"], grounds: [1, 0])
        overlay.layoutIfNeeded()

        XCTAssertEqual(overlay.items.count, 2)
        XCTAssertEqual(overlay.subviews.count, 4)
        XCTAssertEqual(overlay.subviews.compactMap { ($0 as? UILabel)?.attributedText?.string }, ["等等", "等一下"])
    }

    func testLabelsRenderAtTheZoomScale() throws {
        let overlay = MangaTranslationOverlayView(frame: CGRect(x: 0, y: 0, width: 300, height: 420))
        overlay.imageSize = CGSize(width: 1200, height: 1680)
        overlay.state = .translated(blocks: [block], translations: ["等等"], grounds: [1])
        overlay.layoutIfNeeded()
        let label = try XCTUnwrap(overlay.subviews.compactMap { $0 as? UILabel }.first)
        let base = label.layer.contentsScale

        overlay.zoomScale = 3

        XCTAssertEqual(label.layer.contentsScale, base * 3, accuracy: 0.01)
    }

    func testTranslatingAndFailingShowABadgeOnly() {
        let overlay = MangaTranslationOverlayView(frame: CGRect(x: 0, y: 0, width: 300, height: 420))
        overlay.imageSize = CGSize(width: 1200, height: 1680)
        overlay.state = .translating
        overlay.layoutIfNeeded()
        XCTAssertEqual(overlay.subviews.compactMap { ($0 as? UILabel)?.text }, ["翻译中…"])

        overlay.state = .failed("需要先在设置里下载简体中文语言包")
        overlay.layoutIfNeeded()
        XCTAssertEqual(overlay.subviews.compactMap { ($0 as? UILabel)?.text }, ["需要先在设置里下载简体中文语言包"])
    }

    func testThePageShowsTheOriginalWhilePressed() throws {
        let scrollView = ZoomingImageScrollView(frame: CGRect(x: 0, y: 0, width: 300, height: 420))
        scrollView.setImage(UIImage(cgImage: MangaPageFixtures.page(bubbles: [])))
        scrollView.layoutIfNeeded()
        scrollView.setTranslationState(.translated(blocks: [block], translations: ["等等"], grounds: [1]))
        let overlay = try XCTUnwrap(scrollView.readerImageView.subviews.compactMap { $0 as? MangaTranslationOverlayView }.first)
        XCTAssertFalse(overlay.isHidden)

        scrollView.showsOriginalWhilePressed = true
        XCTAssertTrue(overlay.isHidden)
        scrollView.showsOriginalWhilePressed = false
        XCTAssertFalse(overlay.isHidden)
    }

    func testANewImageDropsTheOldTranslation() {
        let scrollView = ZoomingImageScrollView(frame: CGRect(x: 0, y: 0, width: 300, height: 420))
        scrollView.setImage(UIImage(cgImage: MangaPageFixtures.page(bubbles: [])))
        scrollView.setTranslationState(.translated(blocks: [block], translations: ["等等"], grounds: [1]))

        scrollView.setImage(UIImage(cgImage: MangaPageFixtures.page(bubbles: [], size: CGSize(width: 800, height: 1200))))

        XCTAssertTrue(scrollView.readerImageView.subviews.compactMap { $0 as? MangaTranslationOverlayView }.isEmpty)
    }
}
