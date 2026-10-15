import CoreGraphics
import CoreML
import Foundation

/// A region of text, or a speech bubble, found on a page.
nonisolated struct ComicTextDetection: Equatable, Sendable {
    nonisolated enum Label: String, Sendable {
        case bubble
        /// Text inside a speech bubble.
        case textInBubble = "text_bubble"
        /// Text outside bubbles: narration and notes on the art.
        case freeText = "text_free"
    }

    let label: Label
    let score: Double
    /// Fractions of the page, origin top-left.
    let rect: NormalizedRect
}

/// Finds the text on a page.
nonisolated protocol ComicTextDetecting: Sendable {
    /// Short identifier recorded in reports, e.g. `ctd@16e8a622`.
    var identifier: String { get }
    func detect(_ page: CGImage) throws -> [ComicTextDetection]
}

/// ogkalu/comic-text-and-bubble-detector (Apache-2.0) on Core ML: an RT-DETR-v2 trained on
/// about 11k manga, webtoon, manhua and western comic pages.
///
/// It replaces rule-based bubble finding, which took any flat light area with dark marks in it
/// for a bubble — on a device run more than half the regions it read were not text — and could
/// not see text outside a light closed bubble at all: narration on the art, white-on-black
/// bubbles, bubbles cut by the page edge.
///
/// Converted by tools/models/convert_comic_detector.py into bika/MangaModels/, which is not
/// committed. When it is not bundled, `bundled` is nil and pages are read the old way.
nonisolated final class ComicTextDetector: ComicTextDetecting, @unchecked Sendable {
    static let loaded = Result { try ComicTextDetector(bundle: .main) }
    /// nil when the model is not in the app bundle or did not load.
    static var bundled: ComicTextDetector? { try? loaded.get() }

    /// Why a bundled model did not load; nil when it loaded or simply is not bundled.
    static var loadFailure: String? {
        guard case .failure(let error) = loaded else { return nil }
        if case LoadError.missing = error { return nil }
        return String(describing: error)
    }

    nonisolated struct Manifest: Decodable, Sendable {
        let format: Int
        let revision: String
        let image_size: Int
        let labels: [String]
    }

    /// The interface this code drives: pixel_values [1,3,N,N] RGB in 0...1, stretched to
    /// N×N; scores [1,Q,labels] after sigmoid; boxes [1,Q,4] as centre x, centre y, width,
    /// height in fractions of the image.
    static let supportedFormat = 1

    enum LoadError: Error {
        case missing(String)
        case unsupported(Manifest)
    }

    static func validate(_ manifest: Manifest) throws {
        guard manifest.format == supportedFormat,
              manifest.labels == [ComicTextDetection.Label.bubble, .textInBubble, .freeText].map(\.rawValue)
        else { throw LoadError.unsupported(manifest) }
    }

    let identifier: String
    /// Loading and warming up the model, once per launch.
    private(set) var loadMilliseconds = 0
    private let model: MLModel
    private let imageSize: Int
    private let lock = NSLock()

    init(bundle: Bundle) throws {
        func url(_ name: String, _ ext: String) throws -> URL {
            guard let url = bundle.url(forResource: name, withExtension: ext) else {
                throw LoadError.missing("\(name).\(ext)")
            }
            return url
        }
        let start = DispatchTime.now()
        let manifest = try JSONDecoder().decode(
            Manifest.self, from: Data(contentsOf: try url("ComicTextDetectorManifest", "json"))
        )
        try Self.validate(manifest)
        let configuration = MLModelConfiguration()
        // Not the Neural Engine: there, on the conversion's check page, a narration box moved
        // far past tolerance and a spurious one appeared. CPU and GPU match PyTorch.
        configuration.computeUnits = .cpuAndGPU
        model = try MLModel(contentsOf: try url("ComicTextDetectorModel", "mlmodelc"), configuration: configuration)
        imageSize = manifest.image_size
        identifier = "ctd@\(manifest.revision.prefix(8))"
        // The first prediction specialises the model; pay that here, not on the first page.
        _ = try predict(try MLMultiArray(shape: [1, 3, NSNumber(value: imageSize), NSNumber(value: imageSize)], dataType: .float32))
        loadMilliseconds = Int((DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000)
    }

    func detect(_ page: CGImage) throws -> [ComicTextDetection] {
        let output = try predict(try Self.pixelValues(page, size: imageSize))
        guard let scores = output.featureValue(for: "scores")?.multiArrayValue,
              let boxes = output.featureValue(for: "boxes")?.multiArrayValue else { return [] }
        return Self.detections(scores: scores, boxes: boxes)
    }

    private func predict(_ pixels: MLMultiArray) throws -> MLFeatureProvider {
        try lock.withLock {
            try model.prediction(from: MLDictionaryFeatureProvider(dictionary: ["pixel_values": MLFeatureValue(multiArray: pixels)]))
        }
    }

    // MARK: - Steps, exposed for tests

    /// As upstream's image processor: RGB, stretched to size×size, scaled to 0...1, no
    /// normalisation.
    static func pixelValues(_ image: CGImage, size: Int) throws -> MLMultiArray {
        var rgba = [UInt8](repeating: 255, count: size * size * 4)
        rgba.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            ) else { return }
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
        }
        let array = try MLMultiArray(shape: [1, 3, NSNumber(value: size), NSNumber(value: size)], dataType: .float32)
        let plane = size * size
        array.withUnsafeMutableBufferPointer(ofType: Float.self) { values, _ in
            for index in 0..<plane {
                values[index] = Float(rgba[index * 4]) / 255
                values[plane + index] = Float(rgba[index * 4 + 1]) / 255
                values[2 * plane + index] = Float(rgba[index * 4 + 2]) / 255
            }
        }
        return array
    }

    /// Each query's most likely label with its score, most confident first. Thresholds are the
    /// caller's: a detection is only a candidate until its text has been read.
    static func detections(scores: MLMultiArray, boxes: MLMultiArray, minimumScore: Double = 0.2) -> [ComicTextDetection] {
        let queries = scores.shape[1].intValue
        let labelCount = scores.shape[2].intValue
        let labels: [ComicTextDetection.Label] = [.bubble, .textInBubble, .freeText]
        guard labelCount == labels.count, boxes.shape[1].intValue == queries else { return [] }
        let score = { (q: Int, l: Int) in scores[[0, NSNumber(value: q), NSNumber(value: l)]].doubleValue }
        let box = { (q: Int, i: Int) in boxes[[0, NSNumber(value: q), NSNumber(value: i)]].doubleValue }

        var found: [ComicTextDetection] = []
        for query in 0..<queries {
            let best = (0..<labelCount).max { score(query, $0) < score(query, $1) }!
            let value = score(query, best)
            guard value >= minimumScore else { continue }
            let (cx, cy, w, h) = (box(query, 0), box(query, 1), box(query, 2), box(query, 3))
            // Clipped to the page, as every rect the pipeline stores is.
            let minX = max(0, cx - w / 2), minY = max(0, cy - h / 2)
            let maxX = min(1, cx + w / 2), maxY = min(1, cy + h / 2)
            guard maxX > minX, maxY > minY else { continue }
            found.append(ComicTextDetection(
                label: labels[best], score: value,
                rect: NormalizedRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
            ))
        }
        return found.sorted { $0.score > $1.score }
    }
}
