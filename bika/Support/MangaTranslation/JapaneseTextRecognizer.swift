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
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["ja-JP"]
        request.usesLanguageCorrection = true

        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        // A strip is a single line, so reading order is left to right by box position.
        let ordered = (request.results ?? [])
            .compactMap { observation -> (minX: CGFloat, text: VNRecognizedText)? in
                guard let candidate = observation.topCandidates(1).first else { return nil }
                return (observation.boundingBox.minX, candidate)
            }
            .sorted { $0.minX < $1.minX }
            .map(\.text)
        guard !ordered.isEmpty else { return Result(text: "", confidence: 0) }
        let raw = ordered.map(\.string).joined()
        let confidence = ordered.map { Double($0.confidence) }.reduce(0, +) / Double(ordered.count)
        return Result(text: Self.repairReflowArtifacts(raw), confidence: confidence)
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
        return String(repaired)
    }

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
