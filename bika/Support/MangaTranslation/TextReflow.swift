import CoreGraphics
import Foundation

/// Rearranges a bubble's text into one horizontal strip that Vision can read.
///
/// Vision recognises horizontal Japanese reliably but returns nothing for vertical Japanese —
/// not after rotating the image either. Glyphs themselves are upright in vertical text; only
/// their arrangement differs. So each column is cut into character cells, and the cells are
/// laid out left to right, columns in reading order. Measured on synthetic columns: 0 of 7
/// read directly or rotated, 7 of 7 read after reflow.
nonisolated struct TextReflow: Sendable {
    nonisolated struct Configuration: Sendable {
        /// Where to look for a cut, as a fraction of an em either side of the expected boundary.
        var cutSearchFraction: Double = 0.4
        /// Space between cells and between lines in the strip, in ems.
        var cellSpacing: Double = 0.15
        var lineSpacing: Double = 0.6
        /// Strips are scaled so one em is about this many pixels; Vision reads small text poorly.
        var targetEmPixels: Int = 48

        init() {}
    }

    var configuration = Configuration()

    /// Character cells of one vertical line, top to bottom, as row ranges.
    func cells(of line: SegmentedLine, emSize: Int, inkRows: (Int) -> Int) -> [Range<Int>] {
        let top = line.bounds.minY
        let bottom = line.bounds.maxY
        let em = max(emSize, 1)
        let window = max(1, Int(Double(em) * configuration.cutSearchFraction))

        var result: [Range<Int>] = []
        var start = top
        while start < bottom {
            let expected = start + em
            // Close enough to the end: the rest is the last character.
            if expected >= bottom - window {
                result.append(start..<bottom)
                break
            }
            // Cut at the emptiest row near the expected boundary, preferring the one closest
            // to it, but never so early that a cell is under half an em.
            let lower = max(start + em / 2, expected - window)
            let upper = min(bottom - 1, expected + window)
            var cut = expected
            var best = Int.max
            for row in lower...upper {
                let ink = inkRows(row)
                if ink < best || (ink == best && abs(row - expected) < abs(cut - expected)) {
                    best = ink
                    cut = row
                }
            }
            result.append(start..<cut)
            start = cut
        }
        return result
    }

    /// The bubble's text as a single horizontal strip of black ink on white.
    func strip(for text: SegmentedText, in bubble: DetectedBubble) -> CGImage? {
        let em = max(text.emSize, 1)

        switch text.orientation {
        case .horizontal:
            // Already left to right; just lift the ink out cleanly.
            let area = text.lines.map(\.bounds).reduce(text.lines[0].bounds) { $0.union($1) }
            var canvas = GrayscaleBitmap(width: area.width + 2 * em / 2, height: area.height + 2 * em / 2)
            copyInk(of: bubble, from: area, into: &canvas, atX: em / 2, y: em / 2)
            return scaled(canvas, em: em)

        case .vertical:
            let cellSpacing = Int(Double(em) * configuration.cellSpacing)
            let lineSpacing = Int(Double(em) * configuration.lineSpacing)
            let margin = em / 2

            var placements: [(source: PixelRect, x: Int)] = []
            var x = margin
            var tallest = 0
            for (lineIndex, line) in text.lines.enumerated() {
                if lineIndex > 0 { x += lineSpacing }
                // Computed once per line rather than once per candidate cut row.
                let inkPerRow = bubble.rowInk(in: line.bounds)
                let rows = cells(of: line, emSize: em) { row in
                    let index = row - line.bounds.minY
                    return inkPerRow.indices.contains(index) ? inkPerRow[index] : 0
                }
                for (cellIndex, rowRange) in rows.enumerated() {
                    if cellIndex > 0 { x += cellSpacing }
                    let source = PixelRect(minX: line.bounds.minX, minY: rowRange.lowerBound, maxX: line.bounds.maxX, maxY: rowRange.upperBound)
                    placements.append((source, x))
                    x += source.width
                    tallest = max(tallest, source.height)
                }
            }
            guard !placements.isEmpty else { return nil }

            var canvas = GrayscaleBitmap(width: x + margin, height: tallest + 2 * margin)
            for placement in placements {
                // Centre each cell vertically so a short glyph (、っ) sits on the line.
                let y = margin + (tallest - placement.source.height) / 2
                copyInk(of: bubble, from: placement.source, into: &canvas, atX: placement.x, y: y)
            }
            return scaled(canvas, em: em)
        }
    }

    /// Copies `area` of the bubble as pure black ink on white. Binarising drops anything that is
    /// not the bubble's own text — panel art bleeding in, screentone — which helps OCR more than
    /// keeping anti-aliased edges does.
    private func copyInk(of bubble: DetectedBubble, from area: PixelRect, into canvas: inout GrayscaleBitmap, atX originX: Int, y originY: Int) {
        for y in area.minY..<area.maxY {
            for x in area.minX..<area.maxX where bubble.isInk(x: x, y: y) {
                let targetX = originX + x - area.minX
                let targetY = originY + y - area.minY
                guard targetX >= 0, targetX < canvas.width, targetY >= 0, targetY < canvas.height else { continue }
                canvas[targetX, targetY] = 0
            }
        }
    }

    private func scaled(_ canvas: GrayscaleBitmap, em: Int) -> CGImage? {
        guard let image = canvas.makeImage() else { return nil }
        let factor = Double(configuration.targetEmPixels) / Double(max(em, 1))
        guard factor > 1.05 else { return image }

        let width = Int((Double(canvas.width) * factor).rounded())
        let height = Int((Double(canvas.height) * factor).rounded())
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return image
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}
