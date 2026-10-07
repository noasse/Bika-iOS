import CoreGraphics
import CoreText
import Foundation
@testable import bika

/// Draws synthetic manga pages for the translation pipeline tests.
///
/// Pages are rendered at 1x through a plain CGContext so pixel and point coordinates agree.
/// Vertical text uses CoreText's vertical glyph forms, so the long-vowel mark and punctuation
/// take the shapes they have in real vertical typesetting rather than their horizontal ones.
enum MangaPageFixtures {
    struct Bubble {
        /// Bubble ellipse in page pixels, origin top-left.
        var frame: CGRect
        /// Columns in reading order (right to left).
        var columns: [String]
        var fontSize: CGFloat = 36
        /// Optional reading aid drawn beside the first column, as real furigana is.
        var furigana: String? = nil
        var vertical = true
        /// Interior brightness, 0 black ... 1 white. Real bubbles are often gray or tinted.
        var fill: CGFloat = 1
        /// `false` draws only the text, straight onto the page — vertical narration over art.
        var outlined = true
    }

    /// Horizontal text set straight onto the page, as in an afterword.
    struct Caption {
        /// Top-left of the first line, in page pixels.
        var origin: CGPoint
        var lines: [String]
        var fontSize: CGFloat = 22
        /// Brightness of the block behind the text; `nil` leaves the page as it is.
        var background: CGFloat? = 0.93
    }

    static let pageSize = CGSize(width: 1200, height: 1700)

    /// - Parameter screentone: covers the art area with a dot pattern, as printed manga does.
    ///   Every white gap between dots is a tiny enclosed light region, which is what makes
    ///   real pages expensive for bubble detection.
    /// - Parameter decorations: extra line art drawn before the bubbles, in top-left page
    ///   coordinates — for shapes that only look like bubbles.
    static func page(
        bubbles: [Bubble],
        captions: [Caption] = [],
        size: CGSize = pageSize,
        screentone: Bool = false,
        decorations: (CGContext) -> Void = { _ in }
    ) -> CGImage {
        let width = Int(size.width), height = Int(size.height)
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        // Work in top-left coordinates like the pipeline does.
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1, y: -1)

        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(origin: .zero, size: size))

        // One big panel with some mid-gray "art" so bubbles are not the only shapes on the page.
        let panel = CGRect(x: 40, y: 40, width: size.width - 80, height: size.height - 80)
        context.setFillColor(gray: 0.55, alpha: 1)
        context.fill(CGRect(x: panel.minX, y: panel.maxY - 500, width: panel.width, height: 500))
        context.setStrokeColor(gray: 0.2, alpha: 1)
        context.setLineWidth(3)
        for i in 0..<30 {
            let x = panel.minX + CGFloat(i) * 37
            context.move(to: CGPoint(x: x, y: panel.maxY - 500))
            context.addLine(to: CGPoint(x: x + 120, y: panel.maxY))
        }
        context.strokePath()
        if screentone {
            context.setFillColor(gray: 0.15, alpha: 1)
            let pitch: CGFloat = 7
            var y = panel.minY
            while y < panel.maxY - 500 {
                var x = panel.minX + (Int(y / pitch) % 2 == 0 ? 0 : pitch / 2)
                while x < panel.maxX {
                    context.fillEllipse(in: CGRect(x: x, y: y, width: 4, height: 4))
                    x += pitch
                }
                y += pitch
            }
        }
        context.setLineWidth(6)
        context.stroke(panel)

        context.saveGState()
        decorations(context)
        context.restoreGState()
        for caption in captions { draw(caption, in: context) }
        for bubble in bubbles { draw(bubble, in: context) }
        return context.makeImage()!
    }

    private static func draw(_ caption: Caption, in context: CGContext) {
        let font = CTFontCreateWithName("HiraginoSans-W3" as CFString, caption.fontSize, nil)
        let lineHeight = caption.fontSize * 1.6
        let width = CGFloat(caption.lines.map(\.count).max() ?? 0) * caption.fontSize
        if let background = caption.background {
            context.setFillColor(gray: background, alpha: 1)
            context.fill(CGRect(x: caption.origin.x - 20, y: caption.origin.y - 20,
                                width: width + 40, height: CGFloat(caption.lines.count) * lineHeight + 40))
        }
        for (index, line) in caption.lines.enumerated() {
            for (column, character) in line.enumerated() {
                drawGlyph(character, font: font, vertical: false,
                          in: CGRect(x: caption.origin.x + CGFloat(column) * caption.fontSize,
                                     y: caption.origin.y + CGFloat(index) * lineHeight,
                                     width: caption.fontSize, height: caption.fontSize),
                          context: context)
            }
        }
    }

    private static func draw(_ bubble: Bubble, in context: CGContext) {
        if bubble.outlined {
            context.setFillColor(gray: bubble.fill, alpha: 1)
            context.fillEllipse(in: bubble.frame)
            context.setStrokeColor(gray: 0, alpha: 1)
            context.setLineWidth(4)
            context.strokeEllipse(in: bubble.frame)
        }

        let font = CTFontCreateWithName("HiraginoSans-W6" as CFString, bubble.fontSize, nil)
        let cell = bubble.fontSize * 1.15

        if bubble.vertical {
            let columnCount = CGFloat(bubble.columns.count)
            let longest = CGFloat(bubble.columns.map(\.count).max() ?? 0)
            let blockWidth = columnCount * cell
            let blockHeight = longest * cell
            let right = bubble.frame.midX + blockWidth / 2
            let top = bubble.frame.midY - blockHeight / 2
            for (columnIndex, column) in bubble.columns.enumerated() {
                let x = right - CGFloat(columnIndex + 1) * cell
                for (row, character) in column.enumerated() {
                    drawGlyph(character, font: font, vertical: true,
                              in: CGRect(x: x, y: top + CGFloat(row) * cell, width: cell, height: cell), context: context)
                }
                if columnIndex == 0, let furigana = bubble.furigana {
                    let small = CTFontCreateWithName("HiraginoSans-W6" as CFString, bubble.fontSize * 0.4, nil)
                    let smallCell = bubble.fontSize * 0.45
                    for (row, character) in furigana.enumerated() {
                        drawGlyph(character, font: small, vertical: true,
                                  in: CGRect(x: x + cell + 2, y: top + CGFloat(row) * smallCell, width: smallCell, height: smallCell),
                                  context: context)
                    }
                }
            }
        } else {
            let longest = CGFloat(bubble.columns.map(\.count).max() ?? 0)
            let left = bubble.frame.midX - longest * cell / 2
            let top = bubble.frame.midY - CGFloat(bubble.columns.count) * cell / 2
            for (lineIndex, line) in bubble.columns.enumerated() {
                for (index, character) in line.enumerated() {
                    drawGlyph(character, font: font, vertical: false,
                              in: CGRect(x: left + CGFloat(index) * cell, y: top + CGFloat(lineIndex) * cell, width: cell, height: cell),
                              context: context)
                }
            }
        }
    }

    /// Draws one glyph centred in `cell` (top-left coordinates, context already flipped).
    ///
    /// Vertical text uses the OpenType `vert` feature, which swaps in the vertical *shapes* of
    /// characters like ー and 、 while leaving every glyph upright — as on a real page.
    /// kCTVerticalFormsAttributeName is not a substitute: inside a horizontal line it also
    /// rotates each glyph 90°, producing sideways text no manga contains.
    private static func drawGlyph(_ character: Character, font: CTFont, vertical: Bool, in cell: CGRect, context: CGContext) {
        let drawingFont = vertical ? verticalAlternates(of: font) : font
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): drawingFont,
            NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true,
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: String(character), attributes: attributes))
        let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)

        context.saveGState()
        context.setFillColor(gray: 0, alpha: 1)
        // CoreText draws in a bottom-left space; undo the page flip locally around the cell.
        context.translateBy(x: 0, y: cell.midY * 2)
        context.scaleBy(x: 1, y: -1)
        context.textMatrix = .identity
        context.textPosition = CGPoint(
            x: cell.midX - bounds.width / 2 - bounds.minX,
            y: cell.midY - bounds.height / 2 - bounds.minY
        )
        CTLineDraw(line, context)
        context.restoreGState()
    }

    private static func verticalAlternates(of font: CTFont) -> CTFont {
        let feature: [CFString: Any] = [
            kCTFontOpenTypeFeatureTag: "vert",
            kCTFontOpenTypeFeatureValue: 1,
        ]
        let descriptor = CTFontDescriptorCreateWithAttributes([
            kCTFontFeatureSettingsAttribute: [feature],
        ] as CFDictionary)
        return CTFontCreateCopyWithAttributes(font, CTFontGetSize(font), nil, descriptor)
    }
}
