import Foundation

/// A language pages can be translated into. Translation is always from Japanese.
nonisolated enum MangaTranslationLanguage: String, CaseIterable, Codable, Sendable {
    case simplifiedChinese = "zh-Hans"
    case english = "en"

    var displayName: String {
        switch self {
        case .simplifiedChinese: "简体中文"
        case .english: "English"
        }
    }

    var language: Locale.Language { Locale.Language(identifier: rawValue) }

    static let source = Locale.Language(identifier: "ja")
}

/// Whether a target language can be translated into on this device right now.
nonisolated enum MangaTranslationAvailability: Equatable, Sendable {
    case installed
    /// Supported, but its language pack has to be downloaded first.
    case needsDownload
    case unsupported
    /// The system cannot translate outside a SwiftUI view before iOS 26.
    case unavailableOnThisSystem
}

nonisolated enum MangaTranslationError: LocalizedError, Equatable {
    case languageNotInstalled(MangaTranslationLanguage)
    case unsupported(MangaTranslationLanguage)
    case unavailableOnThisSystem
    /// The engine answered a different number of texts than it was asked.
    case incompleteResponse(expected: Int, received: Int)

    var errorDescription: String? {
        switch self {
        case .languageNotInstalled(let language):
            "需要先在设置里下载\(language.displayName)语言包"
        case .unsupported(let language):
            "此设备不支持日文翻译为\(language.displayName)"
        case .unavailableOnThisSystem:
            "漫画翻译需要 iOS 26 或更高版本"
        case .incompleteResponse(let expected, let received):
            "翻译结果不完整（\(received)/\(expected)）"
        }
    }
}

/// Translates Japanese text.
nonisolated protocol MangaTranslationEngine: Sendable {
    /// Recorded with cached translations, so a different engine does not reuse them.
    var identifier: String { get }
    func availability(of target: MangaTranslationLanguage) async -> MangaTranslationAvailability
    /// One translation per text, in order.
    func translate(_ texts: [String], to target: MangaTranslationLanguage) async throws -> [String]
}
