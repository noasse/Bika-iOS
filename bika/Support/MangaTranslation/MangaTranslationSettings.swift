import Foundation

/// The user's manga translation choices. Experimental, so off unless switched on, and with no
/// target language until the user picks one.
nonisolated struct MangaTranslationSettings: Equatable, Sendable {
    var isEnabled = false
    var target: MangaTranslationLanguage?

    /// Enabled with a language chosen: pages can be translated.
    var activeTarget: MangaTranslationLanguage? { isEnabled ? target : nil }

    private enum Keys {
        static let enabled = "mangaTranslation.enabled"
        static let target = "mangaTranslation.target"
    }

    static func load(from store: any KeyValueStore) -> MangaTranslationSettings {
        MangaTranslationSettings(
            isEnabled: store.integer(forKey: Keys.enabled) == 1,
            target: store.string(forKey: Keys.target).flatMap(MangaTranslationLanguage.init(rawValue:))
        )
    }

    func save(to store: any KeyValueStore) {
        store.set(isEnabled ? 1 : 0, forKey: Keys.enabled)
        store.set(target?.rawValue, forKey: Keys.target)
    }
}
