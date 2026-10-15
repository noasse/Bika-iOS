// Renders Japanese text samples for verifying the converted manga-ocr models.
//
// Vertical samples use the OpenType `vert` feature: upright glyphs with their vertical forms
// (ー as a vertical stroke, 、 at the top right), as on a real page.
//
// Usage: swift tools/models/render_samples.swift <output-directory>

import AppKit
import CoreText

let output = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func font(_ size: CGFloat, vertical: Bool) -> CTFont {
    let base = CTFontCreateWithName("HiraginoSans-W6" as CFString, size, nil)
    guard vertical else { return base }
    let feature: [CFString: Any] = [kCTFontOpenTypeFeatureTag: "vert", kCTFontOpenTypeFeatureValue: 1]
    let descriptor = CTFontDescriptorCreateWithAttributes([kCTFontFeatureSettingsAttribute: [feature]] as CFDictionary)
    return CTFontCreateCopyWithAttributes(base, size, nil, descriptor)
}

/// columns: for vertical text, right to left; for horizontal, top to bottom lines.
func render(_ name: String, _ lines: [String], vertical: Bool, size: CGFloat = 40) throws {
    let cell = Int(size * 1.15), pad = 24
    let longest = lines.map(\.count).max() ?? 0
    let width = vertical ? lines.count * cell + 2 * pad : longest * cell + 2 * pad
    let height = vertical ? longest * cell + 2 * pad : lines.count * cell + 2 * pad
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(gray: 1, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let ctFont = font(size, vertical: vertical)
    for (lineIndex, line) in lines.enumerated() {
        for (index, character) in line.enumerated() {
            // Cell origin, top-left coordinates.
            let x = vertical ? width - pad - (lineIndex + 1) * cell : pad + index * cell
            let y = vertical ? pad + index * cell : pad + lineIndex * cell
            let ctLine = CTLineCreateWithAttributedString(NSAttributedString(string: String(character), attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): ctFont,
            ]))
            let bounds = CTLineGetBoundsWithOptions(ctLine, .useGlyphPathBounds)
            context.textPosition = CGPoint(
                x: CGFloat(x) + (CGFloat(cell) - bounds.width) / 2 - bounds.minX,
                y: CGFloat(height - y - cell) + (CGFloat(cell) - bounds.height) / 2 - bounds.minY
            )
            CTLineDraw(ctLine, context)
        }
    }
    let rep = NSBitmapImageRep(cgImage: context.makeImage()!)
    try rep.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name + ".png"))
    print(name, lines.joined(separator: "|"), vertical ? "vertical" : "horizontal")
}

try render("horizontal", ["ちょっと待って"], vertical: false)
try render("vertical-3col", ["本当に", "それで", "いいの？"], vertical: true)
try render("vertical-longvowel", ["ラーメン", "食べたい"], vertical: true)
try render("vertical-long", ["俺はまだ諦めて", "ないからな"], vertical: true)
