import Foundation
import SwiftUI

@MainActor
@Observable
final class MacReadingStore {
    private let keyValueStore: any KeyValueStore
    private let cloudHistorySync: CloudHistorySyncService
    private let accountSessionStore: AccountSessionStore
    private let requiredScope: AccountScope?
    private let enforcesRequiredScope: Bool
    private let legacyHistoryKey = "macReadingHistory"
    private let legacyProgressPrefix = "macReadProgress_"
    private let scopedHistoryPrefix = "macReadingHistory.account."
    private let scopedProgressPrefix = "macReadProgress.account."
    private let maxHistoryItems = 300
    private let cloudHistoryLimit = 200
    private var scopedHistory: [MacHistoryItem] = []
    private var loadedScope: AccountScope?

    var history: [MacHistoryItem] {
        ensureLoadedForCurrentScope()
        return scopedHistory
    }

    init(
        keyValueStore: any KeyValueStore = AppDependencies.shared.keyValueStore,
        cloudHistorySync: CloudHistorySyncService? = nil,
        accountSessionStore: AccountSessionStore? = nil,
        requiredScope: AccountScope? = nil,
        enforcesRequiredScope: Bool = false
    ) {
        self.keyValueStore = keyValueStore
        self.cloudHistorySync = cloudHistorySync ?? CloudHistorySyncService(keyValueStore: keyValueStore)
        self.accountSessionStore = accountSessionStore ?? .shared
        self.requiredScope = requiredScope
        self.enforcesRequiredScope = enforcesRequiredScope
        ensureLoadedForCurrentScope()
    }

    func scopedForReader() -> MacReadingStore {
        let originScope = prepareActiveScope()
        return MacReadingStore(
            keyValueStore: keyValueStore,
            cloudHistorySync: cloudHistorySync,
            accountSessionStore: accountSessionStore,
            requiredScope: originScope,
            enforcesRequiredScope: true
        )
    }

    func progress(for comicId: String) -> MacReadingProgress? {
        guard let scope = prepareActiveScope() else { return nil }
        return loadProgress(forKey: progressKey(for: comicId, scope: scope))
    }

    func record(
        request: MacReaderLaunchRequest,
        episode: MacReaderEpisode,
        pageIndex: Int
    ) {
        guard let scope = prepareActiveScope() else { return }
        guard !enforcesRequiredScope || scope == requiredScope else { return }
        let progress = MacReadingProgress(
            episodeOrder: episode.order,
            episodeTitle: episode.title,
            pageIndex: max(pageIndex, 0)
        )
        persistProgress(progress, forKey: progressKey(for: request.comicId, scope: scope))

        scopedHistory.removeAll { $0.comicId == request.comicId }
        scopedHistory.insert(
            MacHistoryItem(
                comicId: request.comicId,
                title: request.comicTitle,
                author: request.author,
                thumbPath: request.thumbPath,
                thumbServer: request.thumbServer,
                episodeOrder: episode.order,
                episodeTitle: episode.title,
                pageIndex: max(pageIndex, 0),
                updatedAt: Date()
            ),
            at: 0
        )
        if scopedHistory.count > maxHistoryItems {
            scopedHistory = Array(scopedHistory.prefix(maxHistoryItems))
        }
        saveHistory()
        cloudHistorySync.upload(scopedHistory[0].cloudHistoryItem)
    }

    func removeHistory(comicId: String) {
        guard let scope = prepareActiveScope() else { return }
        scopedHistory.removeAll { $0.comicId == comicId }
        keyValueStore.removeObject(forKey: progressKey(for: comicId, scope: scope))
        saveHistory()
        cloudHistorySync.delete(comicID: comicId)
    }

    func clearHistory() {
        guard let scope = prepareActiveScope() else { return }
        for key in keyValueStore.keys(withPrefix: progressPrefix(for: scope))
            where !key.hasSuffix(".corruptBackup") {
            keyValueStore.removeObject(forKey: key)
        }
        scopedHistory = []
        saveHistory()
        cloudHistorySync.clear()
    }

    func syncFromCloud() async {
        guard let scope = prepareActiveScope() else { return }
        let cloudItems = await cloudHistorySync.fetchHistory(limit: cloudHistoryLimit)
        guard !Task.isCancelled,
              accountSessionStore.currentScope == scope else { return }
        applyCloudHistoryItems(cloudItems, expectedScope: scope)
    }

    func applyCloudHistoryItems(
        _ cloudItems: [CloudHistoryItem],
        expectedScope: AccountScope
    ) {
        guard prepareActiveScope() == expectedScope else { return }
        guard !cloudItems.isEmpty else { return }

        var itemsByComicID = Dictionary(uniqueKeysWithValues: scopedHistory.map { ($0.comicId, $0) })
        for cloudItem in cloudItems {
            let localItem = itemsByComicID[cloudItem.comicID]
            guard localItem == nil || localItem!.updatedAt < cloudItem.lastReadAt else { continue }

            let mergedItem = MacHistoryItem(cloudHistoryItem: cloudItem, fallback: localItem)
            itemsByComicID[cloudItem.comicID] = mergedItem
            if let progress = cloudItem.macReadingProgress {
                persistProgress(
                    progress,
                    forKey: progressKey(for: cloudItem.comicID, scope: expectedScope)
                )
            }
        }

        scopedHistory = Array(itemsByComicID.values)
            .sorted { $0.updatedAt > $1.updatedAt }
        if scopedHistory.count > maxHistoryItems {
            scopedHistory = Array(scopedHistory.prefix(maxHistoryItems))
        }
        persistHistory(scopedHistory, forKey: historyKey(for: expectedScope))
    }

    @discardableResult
    private func prepareActiveScope() -> AccountScope? {
        ensureLoadedForCurrentScope()
        return accountSessionStore.currentScope
    }

    private func ensureLoadedForCurrentScope() {
        let scope = accountSessionStore.currentScope
        guard scope != loadedScope else { return }

        loadedScope = scope
        scopedHistory = []
        guard let scope else { return }

        migrateLegacyDataIfNeeded(to: scope)
        scopedHistory = loadHistory(forKey: historyKey(for: scope))
    }

    private func saveHistory() {
        guard let scope = accountSessionStore.currentScope else { return }
        persistHistory(scopedHistory, forKey: historyKey(for: scope))
    }

    private func saveProgress(_ progress: MacReadingProgress, for comicId: String) {
        guard let scope = prepareActiveScope() else { return }
        persistProgress(progress, forKey: progressKey(for: comicId, scope: scope))
    }

    private func migrateLegacyDataIfNeeded(to scope: AccountScope) {
        guard accountSessionStore.ownsLegacyData(scope) else { return }
        migrateLegacyHistory(to: scope)
        migrateLegacyProgress(to: scope)
    }

    private func migrateLegacyHistory(to scope: AccountScope) {
        guard let data = keyValueStore.data(forKey: legacyHistoryKey) else { return }
        guard let legacyItems = decodeHistory(data) else {
            preserveCorruptData(data, forKey: legacyHistoryKey)
            keyValueStore.removeObject(forKey: legacyHistoryKey)
            return
        }

        let destinationKey = historyKey(for: scope)
        let existingItems = keyValueStore.data(forKey: destinationKey)
            .flatMap(decodeHistory) ?? []
        var merged = Dictionary(uniqueKeysWithValues: existingItems.map { ($0.comicId, $0) })
        for item in legacyItems {
            if let existing = merged[item.comicId], existing.updatedAt >= item.updatedAt {
                continue
            }
            merged[item.comicId] = item
        }
        let mergedItems = Array(merged.values)
            .sorted { $0.updatedAt > $1.updatedAt }
        persistHistory(Array(mergedItems.prefix(maxHistoryItems)), forKey: destinationKey)
        keyValueStore.removeObject(forKey: legacyHistoryKey)
    }

    private func migrateLegacyProgress(to scope: AccountScope) {
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

            let destinationKey = progressKey(for: comicID, scope: scope)
            if keyValueStore.data(forKey: destinationKey) == nil {
                persistProgress(progress, forKey: destinationKey)
            }
            keyValueStore.removeObject(forKey: legacyKey)
        }
    }

    private func loadHistory(forKey key: String) -> [MacHistoryItem] {
        guard let data = keyValueStore.data(forKey: key) else { return [] }
        if let envelope = try? JSONDecoder().decode(PersistenceEnvelope<[MacHistoryItem]>.self, from: data),
           envelope.schemaVersion == PersistenceEnvelope<[MacHistoryItem]>.currentSchemaVersion {
            return envelope.payload
        }
        if let legacy = try? JSONDecoder().decode([MacHistoryItem].self, from: data) {
            persistHistory(legacy, forKey: key)
            return legacy
        }

        preserveCorruptData(data, forKey: key)
        keyValueStore.removeObject(forKey: key)
        persistHistory([], forKey: key)
        return []
    }

    private func loadProgress(forKey key: String) -> MacReadingProgress? {
        guard let data = keyValueStore.data(forKey: key) else { return nil }
        if let envelope = try? JSONDecoder().decode(PersistenceEnvelope<MacReadingProgress>.self, from: data),
           envelope.schemaVersion == PersistenceEnvelope<MacReadingProgress>.currentSchemaVersion {
            return envelope.payload
        }
        if let legacy = try? JSONDecoder().decode(MacReadingProgress.self, from: data) {
            persistProgress(legacy, forKey: key)
            return legacy
        }

        preserveCorruptData(data, forKey: key)
        keyValueStore.removeObject(forKey: key)
        return nil
    }

    private func decodeHistory(_ data: Data) -> [MacHistoryItem]? {
        if let envelope = try? JSONDecoder().decode(PersistenceEnvelope<[MacHistoryItem]>.self, from: data) {
            return envelope.payload
        }
        return try? JSONDecoder().decode([MacHistoryItem].self, from: data)
    }

    private func decodeProgress(_ data: Data) -> MacReadingProgress? {
        if let envelope = try? JSONDecoder().decode(PersistenceEnvelope<MacReadingProgress>.self, from: data) {
            return envelope.payload
        }
        return try? JSONDecoder().decode(MacReadingProgress.self, from: data)
    }

    private func persistHistory(_ history: [MacHistoryItem], forKey key: String) {
        guard let data = try? JSONEncoder().encode(PersistenceEnvelope(payload: history)) else { return }
        keyValueStore.set(data, forKey: key)
    }

    private func persistProgress(_ progress: MacReadingProgress, forKey key: String) {
        guard let data = try? JSONEncoder().encode(PersistenceEnvelope(payload: progress)) else { return }
        keyValueStore.set(data, forKey: key)
    }

    private func preserveCorruptData(_ data: Data, forKey key: String) {
        let backupKey = "\(key).corruptBackup"
        guard keyValueStore.data(forKey: backupKey) == nil else { return }
        keyValueStore.set(data, forKey: backupKey)
    }

    private func historyKey(for scope: AccountScope) -> String {
        "\(scopedHistoryPrefix)\(scope.rawValue)"
    }

    private func progressPrefix(for scope: AccountScope) -> String {
        "\(scopedProgressPrefix)\(scope.rawValue)."
    }

    private func progressKey(for comicId: String, scope: AccountScope) -> String {
        "\(progressPrefix(for: scope))\(comicId)"
    }
}

private extension MacHistoryItem {
    init(cloudHistoryItem: CloudHistoryItem, fallback: MacHistoryItem?) {
        self.init(
            comicId: cloudHistoryItem.comicID,
            title: cloudHistoryItem.title,
            author: cloudHistoryItem.author,
            thumbPath: cloudHistoryItem.thumbPath,
            thumbServer: cloudHistoryItem.thumbServer,
            episodeOrder: cloudHistoryItem.episodeOrder ?? fallback?.episodeOrder ?? 0,
            episodeTitle: cloudHistoryItem.episodeTitle ?? fallback?.episodeTitle ?? "未记录",
            pageIndex: cloudHistoryItem.pageIndex ?? fallback?.pageIndex ?? 0,
            updatedAt: cloudHistoryItem.lastReadAt
        )
    }

    var cloudHistoryItem: CloudHistoryItem {
        CloudHistoryItem(
            comicID: comicId,
            title: title,
            author: author,
            thumbPath: thumbPath,
            thumbServer: thumbServer,
            lastReadAt: updatedAt,
            episodeOrder: episodeOrder,
            episodeTitle: episodeTitle,
            pageIndex: pageIndex
        )
    }
}

private extension CloudHistoryItem {
    var macReadingProgress: MacReadingProgress? {
        guard let episodeOrder, let episodeTitle, let pageIndex else { return nil }
        return MacReadingProgress(
            episodeOrder: episodeOrder,
            episodeTitle: episodeTitle,
            pageIndex: pageIndex
        )
    }
}
