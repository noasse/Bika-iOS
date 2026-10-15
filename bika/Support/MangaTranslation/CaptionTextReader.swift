import CoreGraphics
import Foundation
import Vision

/// Reads horizontal Japanese set straight onto the page — afterwords, notes, horizontal
/// narration — and groups it into paragraphs.
///
/// Unlike vertical text, horizontal Japanese is something Vision both finds and reads on its
/// own, so this is one Vision pass over the whole page.
///
/// Vertical text is the hazard. Vision does not read it, but given a block of several columns it
/// may read *across* them, one row at a time, and return lines of genuine kana and kanji — a
/// two-column block came back as `い本`, `い当`, `のに`. Those lines are stacked with almost no
/// gap, because each "line" is one row of the columns, so the line just above or below is part
/// of the same characters. Real horizontal lines have line spacing above and below them.
/// Paragraphs whose lines mostly have ink pressed right against them are dropped.
nonisolated struct CaptionTextReader: Sendable {
    nonisolated struct Configuration: Sendable {
        /// Lines Vision is less sure of than this are left out of paragraphs.
        var minimumLineConfidence = 0.3
        /// A line joins a paragraph when its height is within this fraction of the paragraph's…
        var lineHeightTolerance = 0.4
        /// …the gap above it is at most this many line heights…
        var maximumLineGap = 1.2
        /// …and it overlaps the paragraph horizontally by at least this fraction of its width.
        var minimumHorizontalOverlap = 0.3
        /// The bands checked for neighbouring ink, as fractions of the line height away from it.
        var neighbourBand: ClosedRange<Double> = 0.08...0.4
        /// A band with at least this fraction of ink pixels means text pressed against the line.
        var neighbourInkFraction = 0.05
        /// Pixels darker than this count as ink for that check.
        var inkThreshold: UInt8 = 128

        init() {}
    }

    nonisolated struct Paragraph: Sendable {
        /// Line boxes in reading order, in the image's pixels, origin top-left.
        let lines: [CGRect]
        let text: String
        let confidence: Double

        var bounds: CGRect { lines.dropFirst().reduce(lines[0]) { $0.union($1) } }
    }

    var configuration = Configuration()

    /// - Parameter excluded: areas already read another way (bubbles), in the bitmap's pixels.
    ///   Horizontal text inside a bubble is found by this pass too and would be read twice.
    func read(_ bitmap: GrayscaleBitmap, excluding excluded: [CGRect]) throws -> [Paragraph] {
        guard let image = bitmap.makeImage() else { return [] }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["ja-JP"]
        request.usesLanguageCorrection = true
        // The default minimum is 1/32 of the image height; afterword-sized text on a page is
        // around a hundredth of it and would be dropped.
        request.minimumTextHeight = 0
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        try Task.checkCancellation()

        let size = CGSize(width: image.width, height: image.height)
        let lines: [(rect: CGRect, text: String, confidence: Double)] = (request.results ?? []).compactMap { observation in
            guard let candidate = observation.topCandidates(1).first,
                  Double(candidate.confidence) >= configuration.minimumLineConfidence else { return nil }
            // Vision boxes are normalised, origin bottom-left.
            let box = observation.boundingBox
            let rect = CGRect(
                x: box.minX * size.width,
                y: (1 - box.maxY) * size.height,
                width: box.width * size.width,
                height: box.height * size.height
            )
            let centre = CGPoint(x: rect.midX, y: rect.midY)
            guard !excluded.contains(where: { $0.contains(centre) }) else { return nil }
            return (rect, candidate.string, Double(candidate.confidence))
        }

        return group(lines.sorted { $0.rect.minY < $1.rect.minY }).compactMap { members in
            let pressed = members.filter { hasInkPressedAgainst($0.rect, in: bitmap) }.count
            // Most lines with text right against them: vertical text read across its columns.
            guard Double(pressed) <= Double(members.count) / 2 else { return nil }
            let text = JapaneseTextRecognizer.collapsingDotRuns(members.map(\.text).joined())
            guard JapaneseTextRecognizer.looksLikeJapanese(text) else { return nil }
            let confidence = members.map(\.confidence).reduce(0, +) / Double(members.count)
            return Paragraph(lines: members.map(\.rect), text: text, confidence: confidence)
        }
    }

    /// Whether ink sits right above or right below the line — closer than line spacing would
    /// put the next line.
    func hasInkPressedAgainst(_ line: CGRect, in bitmap: GrayscaleBitmap) -> Bool {
        let height = line.height
        guard height >= 1 else { return false }
        let minX = max(0, Int(line.minX.rounded())), maxX = min(bitmap.width, Int(line.maxX.rounded()))
        guard minX < maxX else { return false }
        let near = configuration.neighbourBand.lowerBound * height
        let far = configuration.neighbourBand.upperBound * height
        let above = (line.minY - far)..<(line.minY - near)
        let below = (line.maxY + near)..<(line.maxY + far)
        return [above, below].contains { band in
            let top = max(0, Int(band.lowerBound.rounded())), bottom = min(bitmap.height, Int(band.upperBound.rounded()))
            guard top < bottom else { return false }
            var ink = 0
            for y in top..<bottom {
                for x in minX..<maxX where bitmap[x, y] < configuration.inkThreshold { ink += 1 }
            }
            return Double(ink) / Double((bottom - top) * (maxX - minX)) >= configuration.neighbourInkFraction
        }
    }

    /// Lines in top-to-bottom order, grouped into paragraphs. A line joins the most recent
    /// paragraph it fits: similar height, normal spacing below its last line, overlapping it
    /// horizontally.
    private func group(
        _ lines: [(rect: CGRect, text: String, confidence: Double)]
    ) -> [[(rect: CGRect, text: String, confidence: Double)]] {
        var paragraphs: [[(rect: CGRect, text: String, confidence: Double)]] = []
        for line in lines {
            let height = line.rect.height
            let target = paragraphs.lastIndex { paragraph in
                guard let last = paragraph.last else { return false }
                let lineHeight = paragraph.map(\.rect.height).sorted()[paragraph.count / 2]
                let gap = line.rect.minY - last.rect.maxY
                let span = paragraph.dropFirst().reduce(paragraph[0].rect) { $0.union($1.rect) }
                let overlap = min(span.maxX, line.rect.maxX) - max(span.minX, line.rect.minX)
                return abs(height - lineHeight) <= lineHeight * configuration.lineHeightTolerance
                    && gap >= -lineHeight * 0.3
                    && gap <= lineHeight * configuration.maximumLineGap
                    && overlap >= line.rect.width * configuration.minimumHorizontalOverlap
            }
            if let target {
                paragraphs[target].append(line)
            } else {
                paragraphs.append([line])
            }
        }
        return paragraphs
    }
}
