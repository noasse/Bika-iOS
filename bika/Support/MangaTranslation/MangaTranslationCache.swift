import CryptoKit
import Foundation

/// Recognition results and translations, kept on disk so a page is recognised and translated
/// once.
///
/// The two are stored separately because they go stale for different reasons: recognition when
/// the pipeline or its models change, a translation also when the engine or the target
/// language does. Switching the target language reuses the page's recognition.
///
/// Entries are small JSON files (a few KB per page). Beyond `maximumEntries` the least recently
/// used are removed.
actor MangaTranslationCache {
    static let shared = MangaTranslationCache(
        directory: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MangaTranslation", isDirectory: true)
    )

    /// Identifies a page's recognition: the image, and everything that can change what is
    /// recognised in it.
    nonisolated struct RecognitionKey: Hashable, Sendable {
        let value: String

        /// - Parameter pageURL: only the path is used; the same image is served from several
        ///   hosts.
        init(pageURL: URL, pipelineVersion: Int, detector: String, recognizer: String) {
            value = "\(pageURL.path)|v\(pipelineVersion)|\(detector)|\(recognizer)"
        }
    }

    nonisolated struct TranslationKey: Hashable, Sendable {
        let value: String

        init(recognition: RecognitionKey, engine: String, target: MangaTranslationLanguage) {
            value = "\(recognition.value)|\(engine)|\(target.rawValue)"
        }
    }

    /// What is stored: the key travels with the value, so a hash collision reads as a miss.
    private nonisolated struct Entry<Value: Codable>: Codable {
        let key: String
        let value: Value
    }

    private let directory: URL
    private let maximumEntries: Int
    /// Stamps each entry when written or read, for eviction.
    private let now: @Sendable () -> Date

    init(directory: URL, maximumEntries: Int = 4000, now: @escaping @Sendable () -> Date = { Date() }) {
        self.directory = directory
        self.maximumEntries = maximumEntries
        self.now = now
    }

    func recognition(for key: RecognitionKey) -> [MangaTextBlock]? {
        read(kind: "r", key: key.value)
    }

    func store(_ blocks: [MangaTextBlock], for key: RecognitionKey) {
        write(blocks, kind: "r", key: key.value)
    }

    func translations(for key: TranslationKey) -> [String]? {
        read(kind: "t", key: key.value)
    }

    func store(_ translations: [String], for key: TranslationKey) {
        write(translations, kind: "t", key: key.value)
    }

    func removeAll() {
        try? FileManager.default.removeItem(at: directory)
    }

    var entryCount: Int { entries().count }

    // MARK: - Files

    private func url(kind: String, key: String) -> URL {
        let digest = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent("\(kind)-\(digest).json")
    }

    private func read<Value: Codable>(kind: String, key: String) -> Value? {
        let url = url(kind: kind, key: key)
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let entry = try? JSONDecoder().decode(Entry<Value>.self, from: data), entry.key == key else {
            // Unreadable — written by an older format, or damaged. Either way, start over.
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        // Reading counts as use for eviction.
        try? FileManager.default.setAttributes([.modificationDate: now()], ofItemAtPath: url.path)
        return entry.value
    }

    private func write<Value: Codable>(_ value: Value, kind: String, key: String) {
        guard let data = try? JSONEncoder().encode(Entry(key: key, value: value)) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = url(kind: kind, key: key)
        try? data.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.modificationDate: now()], ofItemAtPath: url.path)
        evictIfNeeded()
    }

    private func entries() -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey], options: .skipsHiddenFiles
        )) ?? []
    }

    /// Removes the least recently used tenth once over the limit, so not every write lists
    /// the directory and sorts it.
    private func evictIfNeeded() {
        let files = entries()
        guard files.count > maximumEntries else { return }
        func used(_ url: URL) -> Date {
            (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        }
        let excess = files.count - maximumEntries + max(1, maximumEntries / 10)
        for url in files.sorted(by: { used($0) < used($1) }).prefix(excess) {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
