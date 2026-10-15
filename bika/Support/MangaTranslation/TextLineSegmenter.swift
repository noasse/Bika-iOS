import Foundation

/// A line of text inside a bubble, in analysis-bitmap pixels.
nonisolated struct SegmentedLine: Hashable, Sendable {
    let bounds: PixelRect
}

nonisolated struct SegmentedText: Sendable {
    let orientation: MangaTextOrientation
    /// In reading order: right to left for vertical text, top to bottom for horizontal.
    let lines: [SegmentedLine]
    /// Estimated size of one character cell, in pixels.
    let emSize: Int
}

/// Splits the ink inside a bubble into lines.
///
/// Uses projection profiles: for vertical text, counting ink per pixel column across the bubble
/// leaves blank gaps between text columns. The awkward cases are glyphs with blank gaps of their
/// own (川, 小) that look like extra columns, and furigana — small reading aids beside kanji —
/// that look like thin columns. Both are handled relative to the estimated character size.
nonisolated struct TextLineSegmenter: Sendable {
    nonisolated struct Configuration: Sendable {
        /// Runs separated by less than this fraction of an em are parts of one glyph.
        var glyphGapFraction: Double = 0.35
        /// Merging never produces a line wider than this many ems.
        var maximumLineWidthEms: Double = 1.3
        /// Lines narrower than this fraction of an em are furigana and are dropped.
        var furiganaWidthFraction: Double = 0.6
        /// A single line this much more elongated horizontally than vertically is read as
        /// horizontal first.
        var horizontalElongationAdvantage: Double = 1.5
        /// Horizontal text is only plausible when the ink is at least this many lines' heights wide.
        var minimumHorizontalAspect: Double = 2
        /// Readings whose characters are smaller than this many analysis pixels are not text —
        /// typically a run of dots or screentone caught inside a bubble.
        var minimumEmPixels = 10
        /// A bubble does not hold more lines than this; more means noise was split into lines.
        var maximumLines = 12

        init() {}
    }

    var configuration = Configuration()

    /// The most likely reading of the bubble.
    func segment(_ bubble: DetectedBubble) -> SegmentedText? {
        candidates(bubble).first
    }

    /// Plausible readings of the bubble, most likely first.
    ///
    /// Orientation is not decided from geometry alone. Run counts cannot do it (a horizontal
    /// line has gaps between its characters; a vertical column with 川 has gaps inside a glyph),
    /// and comparing line spacing to character spacing breaks whenever a letterer sets columns
    /// about as far apart as characters — a fixture with equal pitch both ways was enough to
    /// read `おい / 待てよ` across the columns as `待およてい`. So when both readings are
    /// plausible, both are returned and the recogniser's confidence decides. Manga is
    /// overwhelmingly vertical, so vertical comes first unless horizontal is clear-cut.
    func candidates(_ bubble: DetectedBubble) -> [SegmentedText] {
        let ink = bubble.inkBounds
        guard ink.width > 0, ink.height > 0 else { return [] }

        let columns = mergeGlyphPieces(runs(of: columnProfile(bubble, in: ink), offset: ink.minX))
        let rows = mergeGlyphPieces(runs(of: rowProfile(bubble, in: ink), offset: ink.minY))
        guard !columns.isEmpty, !rows.isEmpty else { return [] }

        let vertical = segmentVertical(bubble, ink: ink, columns: columns)
        let lineHeight = rows.map(\.count).sorted()[rows.count / 2]
        let horizontalIsPlausible = Double(ink.width) >= Double(lineHeight) * configuration.minimumHorizontalAspect
        let horizontal = horizontalIsPlausible ? segmentHorizontal(bubble, ink: ink, rows: rows) : nil

        let columnElongation = Double(ink.height) / Double(max(1, columns.map(\.count).max() ?? 1))
        let rowElongation = Double(ink.width) / Double(max(1, rows.map(\.count).max() ?? 1))
        let horizontalIsClear = rows.count == 1
            && rowElongation >= columnElongation * configuration.horizontalElongationAdvantage

        let ordered = horizontalIsClear ? [horizontal, vertical] : [vertical, horizontal]
        // Rejected here, before any OCR, so noise never costs a Vision call.
        return ordered.compactMap { $0 }.filter(isPlausibleText)
    }

    private func isPlausibleText(_ text: SegmentedText) -> Bool {
        text.emSize >= configuration.minimumEmPixels && text.lines.count <= configuration.maximumLines
    }

    /// Re-joins pieces of one glyph: adjacent runs with a small gap whose union is still about
    /// one character across. Furigana are left alone here and dropped later by width.
    ///
    /// The em is taken from the widest run, which assumes a line contains at least one glyph
    /// without an internal gap (の, さ, 本). Real text always does; a line made only of 川 and
    /// 小 would be mis-split.
    private func mergeGlyphPieces(_ initial: [ClosedRange<Int>]) -> [ClosedRange<Int>] {
        guard var em = initial.map(\.count).max(), em > 0 else { return [] }
        var merged = initial
        var didMerge = true
        while didMerge {
            didMerge = false
            em = merged.map(\.count).max() ?? em
            for index in stride(from: merged.count - 1, to: 0, by: -1) {
                let left = merged[index - 1]
                let right = merged[index]
                let gap = right.lowerBound - left.upperBound - 1
                let unionWidth = right.upperBound - left.lowerBound + 1
                if Double(gap) < Double(em) * configuration.glyphGapFraction,
                   Double(unionWidth) <= Double(em) * configuration.maximumLineWidthEms {
                    merged[index - 1] = left.lowerBound...right.upperBound
                    merged.remove(at: index)
                    didMerge = true
                }
            }
        }
        return merged
    }

    // MARK: - Vertical

    private func segmentVertical(_ bubble: DetectedBubble, ink: PixelRect, columns merged: [ClosedRange<Int>]) -> SegmentedText? {
        guard let em = merged.map(\.count).max(), em > 0 else { return nil }
        let columns = merged
            .filter { Double($0.count) >= Double(em) * configuration.furiganaWidthFraction }
            .compactMap { range -> SegmentedLine? in
                let xRange = PixelRect(minX: range.lowerBound, minY: ink.minY, maxX: range.upperBound + 1, maxY: ink.maxY)
                let rows = runs(of: rowProfile(bubble, in: xRange), offset: ink.minY)
                guard let top = rows.first?.lowerBound, let bottom = rows.last?.upperBound else {
                    return nil
                }
                return SegmentedLine(bounds: PixelRect(minX: range.lowerBound, minY: top, maxX: range.upperBound + 1, maxY: bottom + 1))
            }
            // Japanese vertical text reads right to left.
            .sorted { $0.bounds.minX > $1.bounds.minX }

        guard !columns.isEmpty else { return nil }
        return SegmentedText(orientation: .vertical, lines: columns, emSize: em)
    }

    // MARK: - Horizontal

    private func segmentHorizontal(_ bubble: DetectedBubble, ink: PixelRect, rows rowRuns: [ClosedRange<Int>]) -> SegmentedText? {
        guard let em = rowRuns.map(\.count).max(), em > 0 else { return nil }
        let lines = rowRuns
            .filter { Double($0.count) >= Double(em) * configuration.furiganaWidthFraction }
            .map { SegmentedLine(bounds: PixelRect(minX: ink.minX, minY: $0.lowerBound, maxX: ink.maxX, maxY: $0.upperBound + 1)) }
        guard !lines.isEmpty else { return nil }
        return SegmentedText(orientation: .horizontal, lines: lines, emSize: em)
    }

    // MARK: - Profiles

    private func columnProfile(_ bubble: DetectedBubble, in area: PixelRect) -> [Int] {
        bubble.columnInk(in: area)
    }

    private func rowProfile(_ bubble: DetectedBubble, in area: PixelRect) -> [Int] {
        bubble.rowInk(in: area)
    }

    /// Maximal runs of non-zero entries, shifted into page coordinates by `offset`.
    private func runs(of profile: [Int], offset: Int) -> [ClosedRange<Int>] {
        var result: [ClosedRange<Int>] = []
        var start: Int?
        for (index, value) in profile.enumerated() {
            if value > 0 {
                if start == nil { start = index }
            } else if let runStart = start {
                result.append((runStart + offset)...(index - 1 + offset))
                start = nil
            }
        }
        if let runStart = start {
            result.append((runStart + offset)...(profile.count - 1 + offset))
        }
        return result
    }
}
