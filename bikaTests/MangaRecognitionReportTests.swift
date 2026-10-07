import CoreGraphics
import XCTest
@testable import bika

final class MangaRecognitionReportTests: XCTestCase {
    private func block(_ text: String, kind: MangaTextKind = .bubble, orientation: MangaTextOrientation = .vertical) -> MangaTextBlock {
        let rect = NormalizedRect(x: 0.1, y: 0.1, width: 0.2, height: 0.3)
        return MangaTextBlock(kind: kind, bubble: rect, textBounds: rect, lines: [rect],
                              orientation: orientation, sourceText: text, confidence: 0.9)
    }

    private func report(_ pages: [MangaRecognitionReport.Page]) -> MangaRecognitionReport {
        MangaRecognitionReport(
            exportedAt: Date(timeIntervalSince1970: 1_790_000_000),
            appVersion: "1.0", buildNumber: "7", deviceModel: "iPhone17,1", systemVersion: "18.4",
            comicID: "comic/../42", episodeOrder: 3, episodeTitle: "第3话", pages: pages
        )
    }

    func testSummaryCountsBlocksAndTimings() {
        let summary = report([
            .init(index: 1, pixelWidth: 1000, pixelHeight: 1400, milliseconds: 900, error: nil,
                  blocks: [block("おい"), block("待て", orientation: .horizontal), block("後書き", kind: .caption, orientation: .horizontal)]),
            .init(index: 0, pixelWidth: 1000, pixelHeight: 1400, milliseconds: 1500, error: nil, blocks: [block("本当に")]),
            .init(index: 2, pixelWidth: nil, pixelHeight: nil, milliseconds: nil, error: "下载失败", blocks: []),
            .init(index: 3, pixelWidth: 1000, pixelHeight: 1400, milliseconds: 600, error: nil, blocks: []),
        ]).summary

        XCTAssertEqual(summary, .init(
            pages: 4, failedPages: 1,
            bubbles: 3, captions: 1, verticalBubbles: 2, horizontalBubbles: 1,
            medianMilliseconds: 900, slowestMilliseconds: 1500, totalMilliseconds: 3000
        ))
    }

    func testPagesAreInChapterOrder() {
        let pages = report([
            .init(index: 2, pixelWidth: nil, pixelHeight: nil, milliseconds: nil, error: nil, blocks: []),
            .init(index: 0, pixelWidth: nil, pixelHeight: nil, milliseconds: nil, error: nil, blocks: []),
            .init(index: 1, pixelWidth: nil, pixelHeight: nil, milliseconds: nil, error: nil, blocks: []),
        ]).pages
        XCTAssertEqual(pages.map(\.index), [0, 1, 2])
    }

    func testReportHoldsTextAndNumbersOnly() throws {
        // The report is meant to be shared freely: no image data and no image URLs.
        let data = try report([
            .init(index: 0, pixelWidth: 1000, pixelHeight: 1400, milliseconds: 800, error: nil, blocks: [block("おい待てよ")]),
        ]).encoded()
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertTrue(json.contains("おい待てよ"))
        XCTAssertFalse(json.contains("http"))
        XCTAssertFalse(json.lowercased().contains("url"))
        XCTAssertLessThan(data.count, 4_000)

        let decoded = try JSONDecoder.reportDecoder.decode(MangaRecognitionReport.self, from: data)
        XCTAssertEqual(decoded.pipelineVersion, MangaPageTextExtractor.pipelineVersion)
        XCTAssertEqual(decoded.pages.first?.blocks.first?.sourceText, "おい待てよ")
        XCTAssertEqual(decoded.summary.bubbles, 1)
    }

    func testFileNameIsSafeAndNamesTheRun() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = try report([]).write(to: directory)

        // A comic id with path characters must not escape the directory.
        XCTAssertEqual(url.deletingLastPathComponent().standardizedFileURL, directory.standardizedFileURL)
        XCTAssertTrue(url.lastPathComponent.hasPrefix("bika-recognition-comic42-ep3-v\(MangaPageTextExtractor.pipelineVersion)-"))
        XCTAssertEqual(url.pathExtension, "json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testRecognisedBlocksCarryVisionConfidence() throws {
        let page = MangaPageFixtures.page(bubbles: [
            .init(frame: CGRect(x: 650, y: 120, width: 340, height: 520), columns: ["本当に", "それで", "いいの？"]),
        ])

        let block = try XCTUnwrap(try MangaPageTextExtractor().extract(from: page).first)

        XCTAssertGreaterThan(block.confidence, 0.3)
        XCTAssertLessThanOrEqual(block.confidence, 1)
    }
}

private extension JSONDecoder {
    static var reportDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
