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

    func recognitionKey(for pageURL: URL) -> MangaTranslationCache.RecognitionKey {
        .init(pageURL: pageURL, pipelineVersion: recognition.pipelineVersion,
              detector: recognition.detector, recognizer: recognition.recognizer)
    }

    /// - Parameters:
    ///   - image: the decoded page, asked for only when the page has not been recognised
    ///     before.
    ///   - urgency: `.prefetch` for a page the reader has not reached, which waits behind
    ///     pages on screen.
    func translate(
        pageURL: URL,
        image: @Sendable () async throws -> CGImage,
        to target: MangaTranslationLanguage,
        urgency: MangaTextRecognitionQueue.Urgency = .visible
    ) async throws -> MangaPageTranslation {
        let recognitionKey = recognitionKey(for: pageURL)
        let blocks: [MangaTextBlock]
        var recognitionMilliseconds = 0
        let recognizedFromCache: Bool
        if let cached = await cache.recognition(for: recognitionKey) {
            blocks = cached
            recognizedFromCache = true
        } else {
            let result = try await recognition.recognize(try await image(), urgency)
            blocks = result.blocks
            recognitionMilliseconds = result.milliseconds
            recognizedFromCache = false
            await cache.store(blocks, for: recognitionKey)
        }
        try Task.checkCancellation()

        let translationKey = MangaTranslationCache.TranslationKey(recognition: recognitionKey, engine: engine.identifier, target: target)
        if let cached = await cache.translations(for: translationKey), cached.count == blocks.count {
            return MangaPageTranslation(
                target: target, blocks: blocks, translations: cached,
                recognizedFromCache: recognizedFromCache, translatedFromCache: true,
                recognitionMilliseconds: recognitionMilliseconds
            )
        }

        let clock = ContinuousClock()
        let start = clock.now
        let translations = blocks.isEmpty ? [] : try await engine.translate(blocks.map(\.sourceText), to: target)
        guard translations.count == blocks.count else {
            throw MangaTranslationError.incompleteResponse(expected: blocks.count, received: translations.count)
        }
        let elapsed = start.duration(to: clock.now)
        await cache.store(translations, for: translationKey)
        return MangaPageTranslation(
            target: target, blocks: blocks, translations: translations,
            recognizedFromCache: recognizedFromCache, translatedFromCache: false,
            recognitionMilliseconds: recognitionMilliseconds,
            translationMilliseconds: Int(elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000_000)
        )
    }
}
