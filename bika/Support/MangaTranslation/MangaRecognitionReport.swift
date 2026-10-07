#if DEBUG
import Foundation

/// What recognition found on every page of a chapter, for evaluating the pipeline.
///
/// Judging recognition from device screenshots gave only an impression, could not compare one
/// round with the next, and meant passing page images around. This report holds text and
/// numbers only — no images and no image URLs — so it can be shared freely and two runs over
/// the same chapter can be compared line by line.
nonisolated struct MangaRecognitionReport: Codable, Sendable {
    nonisolated struct Page: Codable, Sendable {
        /// Zero-based position in the chapter.
        let index: Int
        /// Pixel size of the image recognition ran on.
        let pixelWidth: Int?
        let pixelHeight: Int?
        /// Recognition time alone, excluding download and waiting for a turn.
        let milliseconds: Int?
        /// Set when the page could not be loaded or recognised.
        let error: String?
        let blocks: [MangaTextBlock]
        /// Where the page's time went, by stage.
        var stages: MangaPageTextExtractor.StageTimings? = nil
    }

    nonisolated struct Summary: Codable, Sendable, Equatable {
        let pages: Int
        let failedPages: Int
        let bubbles: Int
        let captions: Int
        let verticalBubbles: Int
        let horizontalBubbles: Int
        let medianMilliseconds: Int?
        let slowestMilliseconds: Int?
        let totalMilliseconds: Int
    }

    let exportedAt: Date
    let pipelineVersion: Int
    /// What read the bubbles: `manga-ocr@<revision>`, or `vision` when the model is not bundled.
    let textRecognizer: String
    /// Loading and warming up the recogniser, which happens once per app launch before the
    /// first page is read; nil on the Vision path.
    let recognizerLoadMilliseconds: Int?
    /// Why a bundled model did not load, leaving the Vision path to read the chapter.
    let recognizerLoadFailure: String?
    let appVersion: String
    let buildNumber: String
    let deviceModel: String
    let systemVersion: String
    let comicID: String
    let episodeOrder: Int
    let episodeTitle: String
    let pages: [Page]
    let summary: Summary

    init(
        exportedAt: Date = Date(),
        pipelineVersion: Int = MangaPageTextExtractor.pipelineVersion,
        textRecognizer: String,
        recognizerLoadMilliseconds: Int? = nil,
        recognizerLoadFailure: String? = nil,
        appVersion: String,
        buildNumber: String,
        deviceModel: String,
        systemVersion: String,
        comicID: String,
        episodeOrder: Int,
        episodeTitle: String,
        pages: [Page]
    ) {
        self.exportedAt = exportedAt
        self.pipelineVersion = pipelineVersion
        self.textRecognizer = textRecognizer
        self.recognizerLoadMilliseconds = recognizerLoadMilliseconds
        self.recognizerLoadFailure = recognizerLoadFailure
        self.appVersion = appVersion
        self.buildNumber = buildNumber
        self.deviceModel = deviceModel
        self.systemVersion = systemVersion
        self.comicID = comicID
        self.episodeOrder = episodeOrder
        self.episodeTitle = episodeTitle
        self.pages = pages.sorted { $0.index < $1.index }
        self.summary = Self.summarise(pages)
    }

    static func summarise(_ pages: [Page]) -> Summary {
        let blocks = pages.flatMap(\.blocks)
        let bubbles = blocks.filter { $0.kind == .bubble }
        let timings = pages.compactMap(\.milliseconds).sorted()
        return Summary(
            pages: pages.count,
            failedPages: pages.filter { $0.error != nil }.count,
            bubbles: bubbles.count,
            captions: blocks.filter { $0.kind == .caption }.count,
            verticalBubbles: bubbles.filter { $0.orientation == .vertical }.count,
            horizontalBubbles: bubbles.filter { $0.orientation == .horizontal }.count,
            medianMilliseconds: timings.isEmpty ? nil : timings[timings.count / 2],
            slowestMilliseconds: timings.last,
            totalMilliseconds: timings.reduce(0, +)
        )
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    /// Writes the report to a temporary file named after the chapter and returns its URL.
    func write(to directory: URL = FileManager.default.temporaryDirectory) throws -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let safeComic = comicID.filter { $0.isLetter || $0.isNumber }
        let engine = textRecognizer.hasPrefix("manga-ocr") ? "mocr" : "vision"
        let name = "bika-recognition-\(safeComic)-ep\(episodeOrder)-v\(pipelineVersion)-\(engine)-\(formatter.string(from: exportedAt)).json"
        let url = directory.appendingPathComponent(name)
        try encoded().write(to: url, options: .atomic)
        return url
    }
}
#endif
