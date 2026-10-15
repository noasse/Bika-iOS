import Foundation
import Translation

/// The system's on-device translation (the Translation framework).
///
/// Only from iOS 26: before that a session can only be had inside a SwiftUI view through
/// `.translationTask`, which does not fit work started from the reader's page pipeline. From
/// iOS 26 a session can be created directly once the language pack is installed; downloading
/// the pack still needs a view, and happens from the settings screen.
nonisolated struct AppleTranslationEngine: MangaTranslationEngine {
    var identifier: String { "apple-translation" }

    /// Sessions kept per target language. Typed `Any` because a stored property cannot be
    /// limited to iOS 26 the way the type it holds is.
    private static let sessions: Any? = {
        if #available(iOS 26.0, *) { AppleTranslationSessions() } else { nil }
    }()

    static var isAvailableOnThisSystem: Bool {
        if #available(iOS 26.0, *) { true } else { false }
    }

    func availability(of target: MangaTranslationLanguage) async -> MangaTranslationAvailability {
        guard #available(iOS 26.0, *) else { return .unavailableOnThisSystem }
        switch await LanguageAvailability().status(from: MangaTranslationLanguage.source, to: target.language) {
        case .installed: return .installed
        case .supported: return .needsDownload
        case .unsupported: return .unsupported
        @unknown default: return .unsupported
        }
    }

    func translate(_ texts: [String], to target: MangaTranslationLanguage) async throws -> [String] {
        guard #available(iOS 26.0, *) else { throw MangaTranslationError.unavailableOnThisSystem }
        guard !texts.isEmpty else { return [] }
        switch await availability(of: target) {
        case .installed: break
        case .needsDownload: throw MangaTranslationError.languageNotInstalled(target)
        case .unsupported: throw MangaTranslationError.unsupported(target)
        case .unavailableOnThisSystem: throw MangaTranslationError.unavailableOnThisSystem
        }

        // One batch per page: the session translates them together, and each response is
        // matched back to its text by identifier rather than trusting the order.
        let requests = texts.enumerated().map { index, text in
            TranslationSession.Request(sourceText: text, clientIdentifier: String(index))
        }
        guard let sessions = Self.sessions as? AppleTranslationSessions else { throw MangaTranslationError.unavailableOnThisSystem }
        var translations = [String?](repeating: nil, count: texts.count)
        for response in try await sessions.translations(from: requests, to: target) {
            if let index = response.clientIdentifier.flatMap(Int.init), translations.indices.contains(index) {
                translations[index] = response.targetText
            }
        }
        let received = translations.compactMap { $0 }
        guard received.count == texts.count else {
            throw MangaTranslationError.incompleteResponse(expected: texts.count, received: received.count)
        }
        return received
    }
}

/// One session per target language, kept for every page after the first, and used by one
/// page at a time: whether a session takes overlapping batches is not documented.
@available(iOS 26.0, *)
actor AppleTranslationSessions {
    private var sessions: [MangaTranslationLanguage: TranslationSession] = [:]
    private var isBusy = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func translations(
        from requests: [TranslationSession.Request],
        to target: MangaTranslationLanguage
    ) async throws -> [TranslationSession.Response] {
        await acquire()
        defer { release() }
        let session = sessions[target] ?? TranslationSession(installedSource: MangaTranslationLanguage.source, target: target.language)
        sessions[target] = session
        do {
            return try await session.translations(from: requests)
        } catch {
            // A session that failed — its language pack removed, say — is not reused.
            sessions[target] = nil
            throw error
        }
    }

    private func acquire() async {
        guard isBusy else {
            isBusy = true
            return
        }
        await withCheckedContinuation { waiting.append($0) }
    }

    private func release() {
        if waiting.isEmpty {
            isBusy = false
        } else {
            waiting.removeFirst().resume()
        }
    }
}
