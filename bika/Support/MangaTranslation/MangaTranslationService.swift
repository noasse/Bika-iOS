import Foundation

/// The reader's one page translator, built once: building it loads the recognition models,
/// seconds of work that every page on screen would otherwise wait on separately.
@MainActor
final class MangaTranslationService {
    static let shared = MangaTranslationService()

    private var building: Task<MangaPageTranslator, Never>?

    func translator() async -> MangaPageTranslator {
        if let building { return await building.value }
        let task = Task {
            MangaPageTranslator(recognition: await .bundled(), engine: AppleTranslationEngine(), cache: .shared)
        }
        building = task
        return await task.value
    }

    /// Starts loading the models without waiting, when translation is about to be wanted.
    func prepare() {
        MangaPageTextExtractor.preloadModels()
        guard building == nil else { return }
        Task { _ = await translator() }
    }
}
