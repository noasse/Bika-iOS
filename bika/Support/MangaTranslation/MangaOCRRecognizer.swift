import CoreGraphics
import CoreML
import Foundation

/// Reads one block of Japanese text from an image crop, in any orientation.
nonisolated protocol MangaTextRecognizing: Sendable {
    /// Short identifier recorded in reports, e.g. `manga-ocr@aa6573bd`.
    var identifier: String { get }
    func recognize(_ crop: CGImage) throws -> JapaneseTextRecognizer.Result
}

/// manga-ocr (kha-white/manga-ocr-base, Apache-2.0) running on Core ML.
///
/// Trained on manga, it reads vertical text, multi-column bubbles, furigana and stylised
/// lettering directly — the cases the Vision path handles worst, since Vision cannot read
/// vertical Japanese at all and needs every column cut up and reflowed first.
///
/// The models are converted by tools/models/convert_manga_ocr.py into bika/MangaModels/, which
/// is not committed. When they are not bundled, `bundled` is nil and recognition falls back to
/// the Vision path.
nonisolated final class MangaOCRRecognizer: MangaTextRecognizing, @unchecked Sendable {
    /// Loaded on first use; nil when the models are not in the app bundle.
    static let bundled: MangaOCRRecognizer? = try? MangaOCRRecognizer(bundle: .main)

    nonisolated struct Manifest: Decodable, Sendable {
        /// Model interface version written by convert_manga_ocr.py.
        let format: Int?
        let revision: String
        let vocab_size: Int
        let decoder_start_token_id: Int
        let eos_token_id: Int
        let max_tokens: Int
        let no_repeat_ngram_size: Int
    }

    /// The interface this code drives: the encoder returns the decoder's cross-attention keys
    /// and values, and the decoder takes them with the prefix. Format 1 models took encoder
    /// states instead and recomputed the projection every step.
    static let supportedFormat = 2

    enum LoadError: Error {
        case missing(String)
        /// Converted for a different interface; reconvert with tools/models/convert_manga_ocr.py.
        case unsupportedFormat(Int?)
    }

    static func validate(_ manifest: Manifest) throws {
        guard manifest.format == supportedFormat else { throw LoadError.unsupportedFormat(manifest.format) }
    }

    let identifier: String
    private let encoder: MLModel
    private let decoder: MLModel
    private let vocabulary: [String]
    private let manifest: Manifest
    /// Predictions are serialised; the recognition queue already runs one page at a time.
    private let lock = NSLock()

    private static let imageSize = 224
    /// Ids below this are [PAD] [UNK] [CLS] [SEP] [MASK].
    private static let firstTextToken = 5

    init(bundle: Bundle) throws {
        func url(_ name: String, _ ext: String) throws -> URL {
            guard let url = bundle.url(forResource: name, withExtension: ext) else {
                throw LoadError.missing("\(name).\(ext)")
            }
            return url
        }
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all
        encoder = try MLModel(contentsOf: try url("MangaOCREncoder", "mlmodelc"), configuration: configuration)
        decoder = try MLModel(contentsOf: try url("MangaOCRDecoder", "mlmodelc"), configuration: configuration)
        vocabulary = try String(contentsOf: try url("MangaOCRVocab", "txt"), encoding: .utf8)
            .components(separatedBy: "\n")
        manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: try url("MangaOCRManifest", "json")))
        // A model converted for another interface would be driven with the wrong inputs; fall
        // back to Vision instead of misreading.
        try Self.validate(manifest)
        identifier = "manga-ocr@\(manifest.revision.prefix(8))/f\(Self.supportedFormat)"
    }

    func recognize(_ crop: CGImage) throws -> JapaneseTextRecognizer.Result {
        try lock.withLock {
            // Once per region: the image, and every decoder layer's cross-attention keys and
            // values, which would otherwise be recomputed on every step.
            let encoded = try encoder.prediction(from: MLDictionaryFeatureProvider(dictionary: [
                "pixel_values": MLFeatureValue(multiArray: try Self.pixelValues(crop)),
            ]))
            guard let keys = encoded.featureValue(for: "cross_keys"),
                  let values = encoded.featureValue(for: "cross_values") else {
                return JapaneseTextRecognizer.Result(text: "", confidence: 0)
            }

            var ids = [manifest.decoder_start_token_id]
            var probabilities: [Double] = []
            while ids.count < manifest.max_tokens {
                try Task.checkCancellation()
                let input = try MLMultiArray(shape: [1, NSNumber(value: ids.count)], dataType: .int32)
                for (index, id) in ids.enumerated() { input[[0, NSNumber(value: index)]] = NSNumber(value: id) }
                guard let logits = try decoder.prediction(from: MLDictionaryFeatureProvider(dictionary: [
                    "input_ids": MLFeatureValue(multiArray: input),
                    "cross_keys": keys,
                    "cross_values": values,
                ])).featureValue(for: "logits")?.multiArrayValue else { break }

                let (token, probability) = Self.nextToken(
                    logits,
                    count: manifest.vocab_size,
                    banned: Self.bannedTokens(after: ids, ngram: manifest.no_repeat_ngram_size)
                )
                ids.append(token)
                if token == manifest.eos_token_id { break }
                probabilities.append(probability)
            }

            let text = Self.normalised(Self.detokenise(ids, vocabulary: vocabulary))
            let confidence = probabilities.isEmpty ? 0 : probabilities.reduce(0, +) / Double(probabilities.count)
            return JapaneseTextRecognizer.Result(text: text, confidence: confidence, steps: ids.count - 1)
        }
    }

    // MARK: - Steps, exposed for tests

    /// As upstream manga-ocr: grayscale, stretched to 224×224, scaled to -1...1, repeated over
    /// three channels.
    static func pixelValues(_ image: CGImage) throws -> MLMultiArray {
        let size = imageSize
        var gray = [UInt8](repeating: 255, count: size * size)
        gray.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return }
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
        }
        let array = try MLMultiArray(shape: [1, 3, NSNumber(value: size), NSNumber(value: size)], dataType: .float32)
        let plane = size * size
        array.withUnsafeMutableBufferPointer(ofType: Float.self) { values, _ in
            for index in 0..<plane {
                let value = (Float(gray[index]) / 255 - 0.5) / 0.5
                values[index] = value
                values[plane + index] = value
                values[2 * plane + index] = value
            }
        }
        return array
    }

    /// Tokens that would repeat an n-gram already generated — transformers' no_repeat_ngram,
    /// which stops the decoder looping on a phrase.
    static func bannedTokens(after ids: [Int], ngram n: Int) -> Set<Int> {
        // An earlier n-gram can only exist once n tokens are out; with fewer the range below
        // would run backwards.
        guard n > 1, ids.count >= n else { return [] }
        let prefix = Array(ids.suffix(n - 1))
        var banned = Set<Int>()
        for start in 0...(ids.count - n) where Array(ids[start..<(start + n - 1)]) == prefix {
            banned.insert(ids[start + n - 1])
        }
        return banned
    }

    /// The most likely allowed token and its softmax probability.
    static func nextToken(_ logits: MLMultiArray, count: Int, banned: Set<Int>) -> (Int, Double) {
        logits.withUnsafeBufferPointer(ofType: Float.self) { values in
            var best = 0
            var bestValue = -Float.infinity
            var maximum = -Float.infinity
            for index in 0..<count {
                maximum = max(maximum, values[index])
                if values[index] > bestValue, !banned.contains(index) {
                    bestValue = values[index]
                    best = index
                }
            }
            var sum: Double = 0
            for index in 0..<count { sum += exp(Double(values[index] - maximum)) }
            return (best, exp(Double(bestValue - maximum)) / sum)
        }
    }

    static func detokenise(_ ids: [Int], vocabulary: [String]) -> String {
        ids.lazy
            .filter { $0 >= firstTextToken && $0 < vocabulary.count }
            .map { vocabulary[$0].hasPrefix("##") ? String(vocabulary[$0].dropFirst(2)) : vocabulary[$0] }
            .joined()
            .filter { !$0.isWhitespace }
    }

    /// Dot runs collapse to one ellipsis as on the Vision path; remaining ASCII becomes full
    /// width, as upstream manga-ocr does (`?` → `？`).
    static func normalised(_ text: String) -> String {
        let collapsed = JapaneseTextRecognizer.collapsingDotRuns(text)
        return String(String.UnicodeScalarView(collapsed.unicodeScalars.map { scalar in
            (0x21...0x7E).contains(scalar.value) ? Unicode.Scalar(scalar.value + 0xFEE0) ?? scalar : scalar
        }))
    }
}
