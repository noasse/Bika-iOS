import CoreGraphics
import XCTest
@testable import bika

/// Stand-in engine: translates by tagging each text with the target, and counts calls.
private final class FakeTranslationEngine: MangaTranslationEngine, @unchecked Sendable {
    var availabilityResult: MangaTranslationAvailability = .installed
    /// Drops the last translation, as a broken engine might.
    var dropsOne = false
    private let lock = NSLock()
    private var _calls: [[String]] = []
    var calls: [[String]] { lock.withLock { _calls } }

    var identifier: String { "fake" }

    func availability(of target: MangaTranslationLanguage) async -> MangaTranslationAvailability {
        availabilityResult
    }

    func translate(_ texts: [String], to target: MangaTranslationLanguage) async throws -> [String] {
        lock.withLock { _calls.append(texts) }
        let translations = texts.map { "[\(target.rawValue)] \($0)" }
        return dropsOne ? Array(translations.dropLast()) : translations
    }
}

/// Stand-in recognition returning fixed blocks, counting calls.
private final class FakeRecognition: @unchecked Sendable {
    let blocks: [MangaTextBlock]
    private let lock = NSLock()
    private var _calls = 0
    var calls: Int { lock.withLock { _calls } }

    init(texts: [String]) {
        blocks = texts.enumerated().map { index, text in
            let rect = NormalizedRect(x: 0.1 + Double(index) * 0.2, y: 0.1, width: 0.1, height: 0.2)
            return MangaTextBlock(bubble: rect, textBounds: rect, lines: [rect], orientation: .vertical,
                                  sourceText: text, confidence: 0.99)
        }
    }

    /// - Parameter delay: how long recognising takes, so callers can overlap.
    func recognition(version: Int = 8, delay: Duration = .zero) -> MangaPageTranslator.Recognition {
        MangaPageTranslator.Recognition(pipelineVersion: version, detector: "ctd@test", recognizer: "mocr@test") { [self] _, _ in
            lock.withLock { _calls += 1 }
            if delay > .zero { try await Task.sleep(for: delay) }
            return (blocks, 5)
        }
    }
}

/// A clock that moves a minute on every reading, so use order is unambiguous.
private final class SteppingClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current = Date(timeIntervalSince1970: 1_000_000)
    func next() -> Date { lock.withLock { current += 60; return current } }
}

private func temporaryCache(maximumEntries: Int = 100) -> (MangaTranslationCache, URL) {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MangaTranslationTests-\(UUID().uuidString)")
    let clock = SteppingClock()
    return (MangaTranslationCache(directory: directory, maximumEntries: maximumEntries, now: { clock.next() }), directory)
}

private let page = MangaPageFixtures.page(bubbles: [])
private let pageURL = URL(string: "https://storage1.picacomic.com/static/abc/0001.jpg")!

final class MangaTranslationSettingsTests: XCTestCase {
    func testOffWithNoLanguageUntilChosen() {
        let settings = MangaTranslationSettings.load(from: InMemoryKeyValueStore())
        XCTAssertFalse(settings.isEnabled)
        XCTAssertNil(settings.target)
        XCTAssertNil(settings.activeTarget)
    }

    func testChoicesPersist() {
        let store = InMemoryKeyValueStore()
        MangaTranslationSettings(isEnabled: true, target: .english).save(to: store)
        XCTAssertEqual(MangaTranslationSettings.load(from: store), MangaTranslationSettings(isEnabled: true, target: .english))
        XCTAssertEqual(MangaTranslationSettings.load(from: store).activeTarget, .english)
    }

    func testALanguageChosenButSwitchedOffTranslatesNothing() {
        let settings = MangaTranslationSettings(isEnabled: false, target: .simplifiedChinese)
        XCTAssertNil(settings.activeTarget)
    }

    func testAnUnknownStoredLanguageReadsAsNoneChosen() {
        let store = InMemoryKeyValueStore()
        store.set("zh-Hant", forKey: "mangaTranslation.target")
        XCTAssertNil(MangaTranslationSettings.load(from: store).target)
    }
}

final class MangaTranslationCacheTests: XCTestCase {
    private func key(_ url: URL = pageURL, version: Int = 8, detector: String = "ctd@a") -> MangaTranslationCache.RecognitionKey {
        .init(pageURL: url, pipelineVersion: version, detector: detector, recognizer: "mocr@a")
    }

    func testRecognitionAndTranslationsRoundTrip() async {
        let (cache, directory) = temporaryCache()
        defer { try? FileManager.default.removeItem(at: directory) }
        let blocks = FakeRecognition(texts: ["おはよう"]).blocks
        let translationKey = MangaTranslationCache.TranslationKey(recognition: key(), engine: "fake", target: .english)

        await cache.store(blocks, for: key())
        await cache.store(["Good morning"], for: translationKey)

        let recognition = await cache.recognition(for: key())
        let translations = await cache.translations(for: translationKey)
        XCTAssertEqual(recognition, blocks)
        XCTAssertEqual(translations, ["Good morning"])
    }

    func testTheSameImageFromAnotherHostIsTheSamePage() async {
        let (cache, directory) = temporaryCache()
        defer { try? FileManager.default.removeItem(at: directory) }
        await cache.store(FakeRecognition(texts: ["あ"]).blocks, for: key())

        let mirrored = await cache.recognition(for: key(URL(string: "https://storage-b.picacomic.com/static/abc/0001.jpg")!))
        XCTAssertNotNil(mirrored)
    }

    func testChangesThatCanAlterTheResultMiss() async {
        let (cache, directory) = temporaryCache()
        defer { try? FileManager.default.removeItem(at: directory) }
        await cache.store(FakeRecognition(texts: ["あ"]).blocks, for: key())
        await cache.store(["A"], for: .init(recognition: key(), engine: "fake", target: .english))

        let newPipeline = await cache.recognition(for: key(version: 9))
        let newDetector = await cache.recognition(for: key(detector: "rules"))
        let otherTarget = await cache.translations(for: .init(recognition: key(), engine: "fake", target: .simplifiedChinese))
        let otherEngine = await cache.translations(for: .init(recognition: key(), engine: "other", target: .english))
        XCTAssertNil(newPipeline)
        XCTAssertNil(newDetector)
        XCTAssertNil(otherTarget)
        XCTAssertNil(otherEngine)
    }

    func testADamagedEntryIsAMissAndIsRemoved() async throws {
        let (cache, directory) = temporaryCache()
        defer { try? FileManager.default.removeItem(at: directory) }
        await cache.store(FakeRecognition(texts: ["あ"]).blocks, for: key())
        let file = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first)
        try Data("not json".utf8).write(to: file)

        let damaged = await cache.recognition(for: key())
        XCTAssertNil(damaged)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testLeastRecentlyUsedEntriesGoFirst() async throws {
        let (cache, directory) = temporaryCache(maximumEntries: 3)
        defer { try? FileManager.default.removeItem(at: directory) }
        func pageKey(_ n: Int) -> MangaTranslationCache.RecognitionKey {
            key(URL(string: "https://host/static/p\(n).jpg")!)
        }
        let blocks = FakeRecognition(texts: ["あ"]).blocks
        for n in 0..<3 { await cache.store(blocks, for: pageKey(n)) }
        _ = await cache.recognition(for: pageKey(0))   // page 0 is used again: now the most recent

        await cache.store(blocks, for: pageKey(3))      // over the limit

        let kept0 = await cache.recognition(for: pageKey(0))
        let kept1 = await cache.recognition(for: pageKey(1))
        let kept3 = await cache.recognition(for: pageKey(3))
        XCTAssertNotNil(kept0, "recently read")
        XCTAssertNil(kept1, "least recently used")
        XCTAssertNotNil(kept3, "just written")
    }
}

final class MangaPageTranslatorTests: XCTestCase {
    func testAPageIsRecognisedAndTranslatedOnce() async throws {
        let (cache, directory) = temporaryCache()
        defer { try? FileManager.default.removeItem(at: directory) }
        let recognition = FakeRecognition(texts: ["おはよう", "待って"])
        let engine = FakeTranslationEngine()
        let translator = MangaPageTranslator(recognition: recognition.recognition(), engine: engine, cache: cache)

        let first = try await translator.translate(pageURL: pageURL, image: { page }, to: .english)
        let second = try await translator.translate(pageURL: pageURL, image: {
            XCTFail("a cached page is not decoded again")
            return page
        }, to: .english)

        XCTAssertEqual(first.translations, ["[en] おはよう", "[en] 待って"])
        XCTAssertEqual(second.translations, first.translations)
        XCTAssertEqual(second.blocks, first.blocks)
        XCTAssertFalse(first.recognizedFromCache || first.translatedFromCache)
        XCTAssertTrue(second.recognizedFromCache && second.translatedFromCache)
        XCTAssertEqual(recognition.calls, 1)
        XCTAssertEqual(engine.calls, [["おはよう", "待って"]])
    }

    func testRequestsForAPageAlreadyInProgressShareItsWork() async throws {
        let (cache, directory) = temporaryCache()
        defer { try? FileManager.default.removeItem(at: directory) }
        let recognition = FakeRecognition(texts: ["おはよう"])
        let engine = FakeTranslationEngine()
        // The page on screen, the prefetcher and the debug overlay asking at once.
        let translator = MangaPageTranslator(recognition: recognition.recognition(delay: .milliseconds(200)), engine: engine, cache: cache)

        async let visible = translator.translate(pageURL: pageURL, image: { page }, to: .english)
        async let prefetched = translator.translate(pageURL: pageURL, image: { page }, to: .english, urgency: .prefetch)
        async let overlay = translator.recognize(pageURL: pageURL, image: { page })
        let results = try await (visible, prefetched, overlay)

        XCTAssertEqual(results.0.translations, results.1.translations)
        XCTAssertEqual(results.2.blocks, results.0.blocks)
        XCTAssertEqual(recognition.calls, 1)
        XCTAssertEqual(engine.calls.count, 1)
    }

    func testAnotherLanguageReusesTheRecognition() async throws {
        let (cache, directory) = temporaryCache()
        defer { try? FileManager.default.removeItem(at: directory) }
        let recognition = FakeRecognition(texts: ["おはよう"])
        let engine = FakeTranslationEngine()
        let translator = MangaPageTranslator(recognition: recognition.recognition(), engine: engine, cache: cache)

        _ = try await translator.translate(pageURL: pageURL, image: { page }, to: .english)
        let chinese = try await translator.translate(pageURL: pageURL, image: { page }, to: .simplifiedChinese)

        XCTAssertEqual(chinese.translations, ["[zh-Hans] おはよう"])
        XCTAssertTrue(chinese.recognizedFromCache)
        XCTAssertFalse(chinese.translatedFromCache)
        XCTAssertEqual(recognition.calls, 1)
        XCTAssertEqual(engine.calls.count, 2)
    }

    func testANewPipelineVersionRecognisesAgain() async throws {
        let (cache, directory) = temporaryCache()
        defer { try? FileManager.default.removeItem(at: directory) }
        let recognition = FakeRecognition(texts: ["おはよう"])
        let engine = FakeTranslationEngine()

        _ = try await MangaPageTranslator(recognition: recognition.recognition(version: 8), engine: engine, cache: cache)
            .translate(pageURL: pageURL, image: { page }, to: .english)
        _ = try await MangaPageTranslator(recognition: recognition.recognition(version: 9), engine: engine, cache: cache)
            .translate(pageURL: pageURL, image: { page }, to: .english)

        XCTAssertEqual(recognition.calls, 2)
        XCTAssertEqual(engine.calls.count, 2)
    }

    func testAnIncompleteTranslationIsAnErrorAndIsNotCached() async throws {
        let (cache, directory) = temporaryCache()
        defer { try? FileManager.default.removeItem(at: directory) }
        let recognition = FakeRecognition(texts: ["おはよう", "待って"])
        let engine = FakeTranslationEngine()
        engine.dropsOne = true
        let translator = MangaPageTranslator(recognition: recognition.recognition(), engine: engine, cache: cache)

        do {
            _ = try await translator.translate(pageURL: pageURL, image: { page }, to: .english)
            XCTFail("expected an error")
        } catch let error as MangaTranslationError {
            XCTAssertEqual(error, .incompleteResponse(expected: 2, received: 1))
        }
        engine.dropsOne = false
        let retried = try await translator.translate(pageURL: pageURL, image: { page }, to: .english)
        XCTAssertEqual(retried.translations.count, 2)
        XCTAssertEqual(engine.calls.count, 2, "the failed result was not cached")
        XCTAssertEqual(recognition.calls, 1, "the recognition was")
    }

    func testAPageWithoutTextNeedsNoTranslation() async throws {
        let (cache, directory) = temporaryCache()
        defer { try? FileManager.default.removeItem(at: directory) }
        let engine = FakeTranslationEngine()
        let translator = MangaPageTranslator(recognition: FakeRecognition(texts: []).recognition(), engine: engine, cache: cache)

        let result = try await translator.translate(pageURL: pageURL, image: { page }, to: .english)

        XCTAssertEqual(result.translations, [])
        XCTAssertEqual(engine.calls.count, 0)
    }
}

final class MangaTranslationSettingsViewModelTests: XCTestCase {
    @MainActor
    private func viewModel(store: InMemoryKeyValueStore, engine: FakeTranslationEngine) -> SettingsViewModel {
        SettingsViewModel(
            themeManager: ThemeManager(keyValueStore: store),
            blockedCategoriesManager: BlockedCategoriesManager(keyValueStore: store),
            keyValueStore: store,
            translationEngine: engine,
            isMangaTranslationSupported: true,
            isUITesting: false,
            appVersion: "1.0"
        )
    }

    @MainActor
    func testChoicesAreSavedAndPackStatusFollowsTheLanguage() async {
        let store = InMemoryKeyValueStore()
        let engine = FakeTranslationEngine()
        engine.availabilityResult = .needsDownload
        let model = viewModel(store: store, engine: engine)

        model.setMangaTranslationEnabled(true)
        model.setMangaTranslationTarget(.simplifiedChinese)
        await model.refreshMangaTranslationAvailability()

        XCTAssertEqual(MangaTranslationSettings.load(from: store).activeTarget, .simplifiedChinese)
        XCTAssertEqual(model.mangaTranslationAvailability, .needsDownload)

        model.setMangaTranslationTarget(nil)
        XCTAssertNil(model.mangaTranslationAvailability, "no language, no pack status")
        await model.refreshMangaTranslationAvailability()
        XCTAssertNil(model.mangaTranslationAvailability)
    }
}

final class SharedWorkTests: XCTestCase {
    /// Work that runs until cancelled, recording that it was.
    private final class Endless: @unchecked Sendable {
        private let lock = NSLock()
        private var _cancelled = false
        private var _starts = 0
        var cancelled: Bool { lock.withLock { _cancelled } }
        var starts: Int { lock.withLock { _starts } }

        func run() async throws -> Int {
            lock.withLock { _starts += 1 }
            do {
                while true { try await Task.sleep(for: .milliseconds(10)) }
            } catch {
                lock.withLock { _cancelled = true }
                throw error
            }
        }
    }

    private func waitUntil(_ condition: @escaping () async -> Bool) async throws {
        for _ in 0..<200 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("timed out")
    }

    func testWorkStopsOnlyWhenEveryoneWaitingHasLeft() async throws {
        let shared = SharedWork<Int>()
        let work = Endless()
        let first = Task { try await shared.value(for: "page") { try await work.run() } }
        try await waitUntil { work.starts == 1 }
        let second = Task { try await shared.value(for: "page") { try await work.run() } }
        try await Task.sleep(for: .milliseconds(50))

        first.cancel()                          // the page scrolled away; the prefetcher still wants it
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertFalse(work.cancelled)
        XCTAssertEqual(work.starts, 1, "the second caller joined, it did not start again")

        second.cancel()
        try await waitUntil { work.cancelled }
        let remaining = await shared.inProgressCount
        XCTAssertEqual(remaining, 0)
    }

    func testFinishedWorkIsNotReused() async throws {
        let shared = SharedWork<Int>()
        let counter = OSAllocatedCounter()
        let first = try await shared.value(for: "page") { counter.next() }
        let second = try await shared.value(for: "page") { counter.next() }
        XCTAssertEqual([first, second], [1, 2], "results are the cache's job, not this one's")
    }
}

private final class OSAllocatedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func next() -> Int { lock.withLock { value += 1; return value } }
}
