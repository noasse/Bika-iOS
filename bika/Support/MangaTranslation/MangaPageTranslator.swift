import CoreGraphics
import Foundation

/// A page's text with its translation.
nonisolated struct MangaPageTranslation: Sendable {
    let target: MangaTranslationLanguage
    let blocks: [MangaTextBlock]
    /// One per block, in the same order.
    let translations: [String]
    let recognizedFromCache: Bool
    let translatedFromCache: Bool
    /// Time spent recognising and translating, excluding cache hits and waiting for a turn.
    var recognitionMilliseconds = 0
    var translationMilliseconds = 0
}

/// Recognises a page and translates its text, each step only when the cache has no answer.
nonisolated struct MangaPageTranslator: Sendable {
    /// Recognition, and what identifies its output in the cache.
    nonisolated struct Recognition: Sendable {
        /// The pipeline version and the detector and recogniser in use.
        let pipelineVersion: Int
        let detector: String
        let recognizer: String
        let recognize: @Sendable (CGImage, MangaTextRecognitionQueue.Urgency) async throws
            -> (blocks: [MangaTextBlock], milliseconds: Int)

        /// The page pipeline with the bundled models, one page at a time through the shared
        /// queue. Which models are in use is only known once they have loaded — seconds each —
        /// so this loads them, off the caller's thread.
        static func bundled() async -> Recognition {
            let (detector, recognizer) = await Task.detached(priority: .utility) {
                let extractor = MangaPageTextExtractor()
                return (extractor.detectorIdentifier, extractor.recognizerIdentifier)
            }.value
            return Recognition(
                pipelineVersion: MangaPageTextExtractor.pipelineVersion,
                detector: detector,
                recognizer: recognizer
            ) { image, urgency in
                try await MangaTextRecognitionQueue.shared.run(urgency: urgency) {
                    let result = try MangaPageTextExtractor().timedExtract(from: image)
                    return (result.blocks, result.milliseconds)
                }
            }
        }
    }

    let recognition: Recognition
    let engine: any MangaTranslationEngine
    let cache: MangaTranslationCache
    /// Pages being recognised and translated right now, shared by everyone who asks.
    private let recognizing = SharedWork<(blocks: [MangaTextBlock], milliseconds: Int, fromCache: Bool)>()
    private let translating = SharedWork<(translations: [String], milliseconds: Int, fromCache: Bool)>()

    init(recognition: Recognition, engine: any MangaTranslationEngine, cache: MangaTranslationCache) {
        self.recognition = recognition
        self.engine = engine
        self.cache = cache
    }

    func recognitionKey(for pageURL: URL) -> MangaTranslationCache.RecognitionKey {
        .init(pageURL: pageURL, pipelineVersion: recognition.pipelineVersion,
              detector: recognition.detector, recognizer: recognition.recognizer)
    }

    /// The page's text, from the cache, from a recognition already running, or recognised now.
    ///
    /// - Parameters:
    ///   - image: the decoded page, asked for only when the page has to be recognised.
    ///   - urgency: `.prefetch` for a page the reader has not reached, which waits behind
    ///     pages on screen.
    func recognize(
        pageURL: URL,
        image: @escaping @Sendable () async throws -> CGImage,
        urgency: MangaTextRecognitionQueue.Urgency = .visible
    ) async throws -> (blocks: [MangaTextBlock], milliseconds: Int, fromCache: Bool) {
        let key = recognitionKey(for: pageURL)
        let recognition = recognition
        let cache = cache
        return try await recognizing.value(for: key.value) {
            if let cached = await cache.recognition(for: key) { return (cached, 0, true) }
            let result = try await recognition.recognize(try await image(), urgency)
            await cache.store(result.blocks, for: key)
            return (result.blocks, result.milliseconds, false)
        }
    }

    /// - Parameters:
    ///   - image: the decoded page, asked for only when the page has not been recognised
    ///     before.
    ///   - urgency: `.prefetch` for a page the reader has not reached, which waits behind
    ///     pages on screen.
    func translate(
        pageURL: URL,
        image: @escaping @Sendable () async throws -> CGImage,
        to target: MangaTranslationLanguage,
        urgency: MangaTextRecognitionQueue.Urgency = .visible
    ) async throws -> MangaPageTranslation {
        let recognized = try await recognize(pageURL: pageURL, image: image, urgency: urgency)
        try Task.checkCancellation()

        let blocks = recognized.blocks
        let key = MangaTranslationCache.TranslationKey(recognition: recognitionKey(for: pageURL), engine: engine.identifier, target: target)
        let engine = engine
        let cache = cache
        let translated = try await translating.value(for: key.value) {
            if let cached = await cache.translations(for: key), cached.count == blocks.count { return (cached, 0, true) }
            let clock = ContinuousClock()
            let start = clock.now
            let translations = blocks.isEmpty ? [] : try await engine.translate(blocks.map(\.sourceText), to: target)
            guard translations.count == blocks.count else {
                throw MangaTranslationError.incompleteResponse(expected: blocks.count, received: translations.count)
            }
            await cache.store(translations, for: key)
            return (translations, Int(start.duration(to: clock.now) / .milliseconds(1)), false)
        }
        return MangaPageTranslation(
            target: target, blocks: blocks, translations: translated.translations,
            recognizedFromCache: recognized.fromCache, translatedFromCache: translated.fromCache,
            recognitionMilliseconds: recognized.milliseconds,
            translationMilliseconds: translated.milliseconds
        )
    }
}
