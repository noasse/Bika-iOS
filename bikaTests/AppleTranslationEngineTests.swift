import XCTest
@testable import bika

/// The system translation engine. What it can do depends on the device: language packs are
/// downloaded by the user, and the simulator may have none. Tests that need a pack skip
/// without it; the rest of the pipeline is tested with a stand-in engine.
final class AppleTranslationEngineTests: XCTestCase {
    private let engine = AppleTranslationEngine()

    func testReportsAvailabilityForEveryTarget() async throws {
        #if targetEnvironment(simulator)
        // The simulator reports every pair as unsupported: system translation is device-only.
        throw XCTSkip("system translation is not available in the simulator")
        #else
        for target in MangaTranslationLanguage.allCases {
            let availability = await engine.availability(of: target)
            print("TRANSLATION availability ja → \(target.rawValue): \(availability)")
            XCTAssertNotEqual(availability, .unsupported, "the system translates Japanese into \(target.displayName)")
        }
        #endif
    }

    func testTranslatesABatchInOrder() async throws {
        for target in MangaTranslationLanguage.allCases {
            guard await engine.availability(of: target) == .installed else {
                print("TRANSLATION \(target.rawValue) not installed here; skipped")
                continue
            }
            let texts = ["おはよう", "ありがとう", "本当にそれでいいの？"]
            let translations = try await engine.translate(texts, to: target)
            print("TRANSLATION \(target.rawValue): \(translations)")
            XCTAssertEqual(translations.count, texts.count)
            XCTAssertFalse(translations.contains(where: \.isEmpty))
        }
    }

    func testAPackThatIsNotInstalledIsReportedAsSuch() async throws {
        for target in MangaTranslationLanguage.allCases where await engine.availability(of: target) == .needsDownload {
            do {
                _ = try await engine.translate(["おはよう"], to: target)
                XCTFail("translating without the pack should fail")
            } catch let error as MangaTranslationError {
                XCTAssertEqual(error, .languageNotInstalled(target))
            }
        }
    }

    func testNothingToTranslateNeedsNoPack() async throws {
        let empty = try await engine.translate([], to: .english)
        XCTAssertEqual(empty, [])
    }
}
