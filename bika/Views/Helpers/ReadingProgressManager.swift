import Foundation

@MainActor
@Observable
final class ReadingProgressManager {
    static let shared = ReadingProgressManager()

    struct Progress: Codable, Equatable {
        let episodeOrder: Int
        let episodeTitle: String
        let pageIndex: Int
    }

    private let keyValueStore: any KeyValueStore
    private let accountSessionStore: AccountSessionStore
    private let scopedProgressPrefix = "readProgress.account."
    private let legacyProgressPrefix = "readProgress_"

    init(
        keyValueStore: any KeyValueStore = AppDependencies.shared.keyValueStore,
        accountSessionStore: AccountSessionStore? = nil
    ) {
        self.keyValueStore = keyValueStore
        self.accountSessionStore = accountSessionStore ?? .shared
    }

    func save(comicId: String, progress: Progress) {
        guard let scope = prepareActiveScope() else { return }
        persist(progress, forKey: key(for: comicId, scope: scope))
    }

    func get(comicId: String) -> Progress? {
        guard let scope = prepareActiveScope() else { return nil }
        return loadProgress(forKey: key(for: comicId, scope: scope))
    }

    func remove(comicId: String) {
        guard let scope = prepareActiveScope() else { return }
        keyValueStore.removeObject(forKey: key(for: comicId, scope: scope))
    }

    func removeAllForCurrentAccount() {
        guard let scope = prepareActiveScope() else { return }
        let prefix = scopedPrefix(for: scope)
        for key in keyValueStore.keys(withPrefix: prefix) where !key.hasSuffix(".corruptBackup") {
            keyValueStore.removeObject(forKey: key)
        }
    }

    private func prepareActiveScope() -> AccountScope? {
        guard let scope = accountSessionStore.currentScope else { return nil }
        migrateLegacyProgressIfNeeded(to: scope)
        return scope
    }

    private func migrateLegacyProgressIfNeeded(to scope: AccountScope) {
        guard accountSessionStore.ownsLegacyData(scope) else { return }

        let legacyKeys = keyValueStore.keys(withPrefix: legacyProgressPrefix)
            .filter { !$0.hasSuffix(".corruptBackup") }
        for legacyKey in legacyKeys {
            guard let data = keyValueStore.data(forKey: legacyKey) else { continue }
            let comicID = String(legacyKey.dropFirst(legacyProgressPrefix.count))
            guard !comicID.isEmpty else { continue }

            guard let progress = decodeProgress(data) else {
                preserveCorruptData(data, forKey: legacyKey)
                keyValueStore.removeObject(forKey: legacyKey)
                continue
            }

            let destinationKey = key(for: comicID, scope: scope)
            if keyValueStore.data(forKey: destinationKey) == nil {
                persist(progress, forKey: destinationKey)
            }
            keyValueStore.removeObject(forKey: legacyKey)
        }
    }

    private func loadProgress(forKey key: String) -> Progress? {
        guard let data = keyValueStore.data(forKey: key) else { return nil }
        if let envelope = try? JSONDecoder().decode(PersistenceEnvelope<Progress>.self, from: data),
           envelope.schemaVersion == PersistenceEnvelope<Progress>.currentSchemaVersion {
            return envelope.payload
        }
        if let progress = try? JSONDecoder().decode(Progress.self, from: data) {
            persist(progress, forKey: key)
            return progress
        }

        preserveCorruptData(data, forKey: key)
        keyValueStore.removeObject(forKey: key)
        return nil
    }

    private func decodeProgress(_ data: Data) -> Progress? {
        if let envelope = try? JSONDecoder().decode(PersistenceEnvelope<Progress>.self, from: data) {
            return envelope.payload
        }
        return try? JSONDecoder().decode(Progress.self, from: data)
    }

    private func persist(_ progress: Progress, forKey key: String) {
        guard let data = try? JSONEncoder().encode(PersistenceEnvelope(payload: progress)) else { return }
        keyValueStore.set(data, forKey: key)
    }

    private func preserveCorruptData(_ data: Data, forKey key: String) {
        let backupKey = "\(key).corruptBackup"
        guard keyValueStore.data(forKey: backupKey) == nil else { return }
        keyValueStore.set(data, forKey: backupKey)
    }

    private func scopedPrefix(for scope: AccountScope) -> String {
        "\(scopedProgressPrefix)\(scope.rawValue)."
    }

    private func key(for comicId: String, scope: AccountScope) -> String {
        "\(scopedPrefix(for: scope))\(comicId)"
    }
}
