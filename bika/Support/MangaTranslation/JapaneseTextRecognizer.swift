import CoreGraphics
import Foundation
import Vision

/// Reads a reflowed strip of Japanese with Vision, then repairs what reflow distorts.
nonisolated struct JapaneseTextRecognizer: Sendable {
    nonisolated struct Result: Sendable {
        let text: String
        /// Mean Vision confidence over the recognised lines, 0...1.
        let confidence: Double
    }

    func recognize(_ image: CGImage) throws -> Result {
        try recognize([image]).first ?? Result(text: "", confidence: 0)
    }

    /// Reads several strips with a single Vision request.
    ///
    /// Each Vision call carries a large fixed cost — on a page with seven bubbles, OCR was
    /// three to four seconds of a four-second total, at roughly 250 ms per call. So the strips
    /// are stacked into one sheet with wide gaps between them, recognised once, and every
    /// recognised line is assigned back to the strip whose band it falls in.
    func recognize(_ strips: [CGImage]) throws -> [Result] {
        guard !strips.isEmpty else { return [] }
        guard let sheet = Self.stack(strips) else {
            return strips.map { _ in Result(text: "", confidence: 0) }
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["ja-JP"]
        request.usesLanguageCorrection = true
        // The default minimum is a fraction of the *image* height. On a tall sheet of stacked
        // strips each line would fall under it and be dropped without a word.
        request.minimumTextHeight = 0

        try VNImageRequestHandler(cgImage: sheet.image, options: [:]).perform([request])

        var linesPerStrip = [[(minX: CGFloat, text: VNRecognizedText)]](repeating: [], count: strips.count)
        let sheetHeight = CGFloat(sheet.image.height)
        for observation in request.results ?? [] {
            guard let candidate = observation.topCandidates(1).first else { continue }
            // Vision boxes are normalised with a bottom-left origin; bands are top-down pixels.
            let midY = (1 - observation.boundingBox.midY) * sheetHeight
            guard let strip = sheet.bands.firstIndex(where: { $0.contains(midY) }) else { continue }
            linesPerStrip[strip].append((observation.boundingBox.minX, candidate))
        }

        return linesPerStrip.map { lines in
            // A strip is one line of text, so reading order is left to right by box position.
            let ordered = lines.sorted { $0.minX < $1.minX }.map(\.text)
            guard !ordered.isEmpty else { return Result(text: "", confidence: 0) }
            let raw = ordered.map(\.string).joined()
            let confidence = ordered.map { Double($0.confidence) }.reduce(0, +) / Double(ordered.count)
            return Result(text: Self.repairReflowArtifacts(raw), confidence: confidence)
        }
    }

    /// Stacks strips top to bottom on white with a gap as tall as the tallest strip, so Vision
    /// never joins lines from neighbouring strips. Returns each strip's band, widened by half a
    /// gap either side, in top-down pixel coordinates.
    private static func stack(_ strips: [CGImage]) -> (image: CGImage, bands: [Range<CGFloat>])? {
        let gap = strips.map(\.height).max() ?? 0
        let width = (strips.map(\.width).max() ?? 0) + gap
        let height = strips.reduce(gap) { $0 + $1.height + gap }
        guard width > 0, height > 0,
              let context = CGContext(
                  data: nil,
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: CGColorSpaceCreateDeviceGray(),
                  bitmapInfo: CGImageAlphaInfo.none.rawValue
              ) else {
            return nil
        }
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        var bands: [Range<CGFloat>] = []
        var top = gap
        for strip in strips {
            // CGContext draws bottom-up.
            context.draw(strip, in: CGRect(x: gap / 2, y: height - top - strip.height, width: strip.width, height: strip.height))
            let half = CGFloat(gap) / 2
            bands.append((CGFloat(top) - half)..<(CGFloat(top + strip.height) + half))
            top += strip.height + gap
        }
        guard let image = context.makeImage() else { return nil }
        return (image, bands)
    }

    /// Fixes characters that only look wrong because vertical glyphs were laid out horizontally.
    static func repairReflowArtifacts(_ text: String) -> String {
        // Vision may separate cells it reads as distinct words; Japanese has no spaces.
        let characters = Array(text.filter { !$0.isWhitespace })
        var repaired: [Character] = []
        repaired.reserveCapacity(characters.count)

        for (index, character) in characters.enumerated() {
            // In vertical text the long-vowel mark ー is a vertical stroke, which reads as one of
            // these once laid out horizontally. It only makes sense after a kana or kanji.
            if verticalBarLookalikes.contains(character),
               index > 0,
               isJapanese(characters[index - 1]) {
                repaired.append("ー")
                continue
            }
            // Vertical ellipsis ︙ reads as a colon.
            if character == ":" || character == "：" || character == "︙" {
                repaired.append("…")
                continue
            }
            repaired.append(character)
        }
        return collapsingDotRuns(String(repaired))
    }

    /// A vertical ellipsis is cut into cells like any other glyph, so it comes back as `…`
    /// plus a stray `・` or `•`. Any run of two or more dot-like characters becomes one `…`;
    /// a single `・` is left alone, as in names (アルカナ・シャドウ).
    static func collapsingDotRuns(_ text: String) -> String {
        var result = ""
        var run = 0
        var pendingDot: Character = "・"
        func flush() {
            if run >= 2 { result.append("…") } else if run == 1 { result.append(pendingDot) }
            run = 0
        }
        for character in text {
            if dotLike.contains(character) {
                if run == 0 { pendingDot = character }
                run += 1
            } else {
                flush()
                result.append(character)
            }
        }
        flush()
        return result
    }

    private static let dotLike: Set<Character> = ["…", "⋯", "・", "･", "•", "·", ".", "‥"]

    /// Whether recognised text is plausibly Japanese dialogue rather than something Vision made
    /// of an eye, a hair line or a page number.
    ///
    /// On line-art pages the white of a face enclosed by its outline is shaped exactly like a
    /// speech bubble, and Vision returns things like `し?,`, `•…`, `11/` or `111X` for the
    /// features inside it. Kana and kanji must be at least `minimumRatio` of the characters
    /// that count. Ordinary dialogue punctuation does not count either way — including the ASCII
    /// `?` and `!` Vision often returns for full-width ones — so a one-kana line like `は?`
    /// passes. Stray symbols count against; digits count half, since dialogue does use them.
    static func looksLikeJapanese(_ text: String, minimumRatio: Double = 0.6) -> Bool {
        let counts = characterCounts(text)
        guard counts.japanese >= 1 else { return false }
        return counts.japanese / (counts.japanese + counts.foreign) >= minimumRatio
    }

    /// Kana and kanji, excluding punctuation. Used to compare two readings of one bubble: the
    /// wrong orientation tends to read only part of the text.
    static func japaneseLetterCount(_ text: String) -> Int {
        Int(characterCounts(text).japanese)
    }

    private static func characterCounts(_ text: String) -> (japanese: Double, foreign: Double) {
        var japanese = 0.0
        var foreign = 0.0
        for character in text where !character.isWhitespace && !dialoguePunctuation.contains(character) {
            if isJapanese(character) {
                japanese += 1
            } else if character.isASCII, character.isNumber {
                foreign += 0.5
            } else {
                foreign += 1
            }
        }
        return (japanese, foreign)
    }

    /// Punctuation that real dialogue is full of. `・` and `ー` sit inside the katakana block,
    /// so they must be listed here or a line of dots would count as Japanese.
    private static let dialoguePunctuation: Set<Character> = [
        "…", "⋯", "‥", "・", "･", "ー", "〜", "~", "、", "。", "，", "．",
        "！", "？", "!", "?", "「", "」", "『", "』", "（", "）", "(", ")",
        "♡", "♥", "♪", "☆", "★", "―", "—",
    ]

    private static let verticalBarLookalikes: Set<Character> = ["|", "｜", "丨", "l", "I", "1", "︱"]

    private static func isJapanese(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { scalar in
            switch scalar.value {
            case 0x3040...0x309F, // hiragana
                 0x30A0...0x30FF, // katakana
                 0x4E00...0x9FFF, // CJK unified ideographs
                 0x3400...0x4DBF: // CJK extension A
                return true
            default:
                return false
            }
        }
    }
}
