import Foundation

@MainActor
@Observable
final class ReadingHistoryManager {
    static let shared = ReadingHistoryManager()

    struct HistoryItem: Codable, Identifiable {
        let comicId: String
        let title: String
        let thumbPath: String
        let thumbServer: String?
        let author: String?
        var lastReadDate: Date
        var episodeOrder: Int?
        var episodeTitle: String?
        var pageIndex: Int?

        var id: String { comicId }
    }

    var items: [HistoryItem] {
        ensureLoadedForCurrentScope()
        return scopedItems
    }

    private let keyValueStore: any KeyValueStore
    private let cloudHistorySync: CloudHistorySyncService
    private let readingProgressManager: ReadingProgressManager
    private let accountSessionStore: AccountSessionStore
    private let legacyStorageKey = "readingHistory"
    private let scopedStoragePrefix = "readingHistory.account."
    private let maxItems = 200
    private var scopedItems: [HistoryItem] = []
    private var loadedScope: AccountScope?

    init(
        keyValueStore: any KeyValueStore = AppDependencies.shared.keyValueStore,
        cloudHistorySync: CloudHistorySyncService? = nil,
        readingProgressManager: ReadingProgressManager? = nil,
        accountSessionStore: AccountSessionStore? = nil
    ) {
        let resolvedAccountSessionStore = accountSessionStore ?? .shared
        self.keyValueStore = keyValueStore
        self.cloudHistorySync = cloudHistorySync ?? CloudHistorySyncService(keyValueStore: keyValueStore)
        self.accountSessionStore = resolvedAccountSessionStore
        self.readingProgressManager = readingProgressManager ?? ReadingProgressManager(
            keyValueStore: keyValueStore,
            accountSessionStore: resolvedAccountSessionStore
        )
        ensureLoadedForCurrentScope()
    }

    func record(comicId: String, title: String, thumbPath: String, thumbServer: String?, author: String?) {
        guard prepareActiveScope() != nil else { return }
        // Remove existing entry for this comic
        scopedItems.removeAll { $0.comicId == comicId }
        let progress = readingProgressManager.get(comicId: comicId)

        // Insert at front
        let item = HistoryItem(
            comicId: comicId,
            title: title,
            thumbPath: thumbPath,
            thumbServer: thumbServer,
            author: author,
            lastReadDate: Date(),
            episodeOrder: progress?.episodeOrder,
            episodeTitle: progress?.episodeTitle,
            pageIndex: progress?.pageIndex
        )
        scopedItems.insert(item, at: 0)

        // Trim to max
        if scopedItems.count > maxItems {
            scopedItems = Array(scopedItems.prefix(maxItems))
        }

        save()
        cloudHistorySync.upload(item.cloudHistoryItem)
    }

    func remove(comicId: String) {
        guard prepareActiveScope() != nil else { return }
        scopedItems.removeAll { $0.comicId == comicId }
        readingProgressManager.remove(comicId: comicId)
        save()
        cloudHistorySync.delete(comicID: comicId)
    }

    func clearAll() {
        guard prepareActiveScope() != nil else { return }
        scopedItems = []
        readingProgressManager.removeAllForCurrentAccount()
        save()
        cloudHistorySync.clear()
    }

    func syncFromCloud() async {
        guard let scope = prepareActiveScope() else { return }
        let cloudItems = await cloudHistorySync.fetchHistory(limit: maxItems)
        guard !Task.isCancelled,
              accountSessionStore.currentScope == scope else { return }
        applyCloudHistoryItems(cloudItems, expectedScope: scope)
    }

    func syncProgressFromCloud(for comicId: String) async {
        guard let scope = prepareActiveScope() else { return }
        let cloudItems = await cloudHistorySync.fetchHistory(limit: maxItems)
        guard !Task.isCancelled,
              accountSessionStore.currentScope == scope else { return }
        guard let cloudItem = cloudItems.first(where: { $0.comicID == comicId }) else { return }
        applyCloudHistoryItems([cloudItem], expectedScope: scope)
    }

    func applyCloudHistoryItems(_ cloudItems: [CloudHistoryItem]) {
        guard let scope = prepareActiveScope() else { return }
        applyCloudHistoryItems(cloudItems, expectedScope: scope)
    }

    func applyCloudHistoryItems(
        _ cloudItems: [CloudHistoryItem],
        expectedScope: AccountScope
    ) {
        guard prepareActiveScope() == expectedScope else { return }
        guard !cloudItems.isEmpty else { return }
        var itemsByComicID = Dictionary(uniqueKeysWithValues: scopedItems.map { ($0.comicId, $0) })
        for cloudItem in cloudItems {
            let localItem = itemsByComicID[cloudItem.comicID]
            guard localItem == nil || localItem!.lastReadDate < cloudItem.lastReadAt else { continue }
            itemsByComicID[cloudItem.comicID] = HistoryItem(cloudHistoryItem: cloudItem, fallback: localItem)
            if let progress = cloudItem.readingProgress {
                readingProgressManager.save(comicId: cloudItem.comicID, progress: progress)
            }
        }

        scopedItems = Array(itemsByComicID.values)
            .sorted { $0.lastReadDate > $1.lastReadDate }
        if scopedItems.count > maxItems {
            scopedItems = Array(scopedItems.prefix(maxItems))
        }
        save()
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
        scopedItems = []
        guard let scope else { return }

        migrateLegacyHistoryIfNeeded(to: scope)
        scopedItems = loadHistory(for: storageKey(for: scope))
    }

    private func migrateLegacyHistoryIfNeeded(to scope: AccountScope) {
        guard accountSessionStore.ownsLegacyData(scope),
              let legacyData = keyValueStore.data(forKey: legacyStorageKey) else { return }

        guard let legacyItems = decodeHistory(legacyData) else {
            preserveCorruptData(legacyData, forKey: legacyStorageKey)
            keyValueStore.removeObject(forKey: legacyStorageKey)
            return
        }

        let destinationKey = storageKey(for: scope)
        let existingItems = keyValueStore.data(forKey: destinationKey)
            .flatMap(decodeHistory) ?? []
        var merged = Dictionary(uniqueKeysWithValues: existingItems.map { ($0.comicId, $0) })
        for item in legacyItems {
            if let existing = merged[item.comicId], existing.lastReadDate >= item.lastReadDate {
                continue
            }
            merged[item.comicId] = item
        }

        let mergedItems = Array(merged.values)
            .sorted { $0.lastReadDate > $1.lastReadDate }
        persist(Array(mergedItems.prefix(maxItems)), forKey: destinationKey)
        keyValueStore.removeObject(forKey: legacyStorageKey)
    }

    private func loadHistory(for key: String) -> [HistoryItem] {
        guard let data = keyValueStore.data(forKey: key) else { return [] }
        if let envelope = try? JSONDecoder().decode(PersistenceEnvelope<[HistoryItem]>.self, from: data),
           envelope.schemaVersion == PersistenceEnvelope<[HistoryItem]>.currentSchemaVersion {
            return envelope.payload
        }
        if let legacyItems = try? JSONDecoder().decode([HistoryItem].self, from: data) {
            persist(legacyItems, forKey: key)
            return legacyItems
        }

        preserveCorruptData(data, forKey: key)
        keyValueStore.removeObject(forKey: key)
        persist([], forKey: key)
        return []
    }

    private func decodeHistory(_ data: Data) -> [HistoryItem]? {
        if let envelope = try? JSONDecoder().decode(PersistenceEnvelope<[HistoryItem]>.self, from: data) {
            return envelope.payload
        }
        return try? JSONDecoder().decode([HistoryItem].self, from: data)
    }

    private func save() {
        guard let scope = accountSessionStore.currentScope else { return }
        persist(scopedItems, forKey: storageKey(for: scope))
    }

    private func persist(_ items: [HistoryItem], forKey key: String) {
        if let data = try? JSONEncoder().encode(PersistenceEnvelope(payload: items)) {
            keyValueStore.set(data, forKey: key)
        }
    }

    private func preserveCorruptData(_ data: Data, forKey key: String) {
        let backupKey = "\(key).corruptBackup"
        guard keyValueStore.data(forKey: backupKey) == nil else { return }
        keyValueStore.set(data, forKey: backupKey)
    }

    private func storageKey(for scope: AccountScope) -> String {
        "\(scopedStoragePrefix)\(scope.rawValue)"
    }
}

private extension ReadingHistoryManager.HistoryItem {
    init(cloudHistoryItem: CloudHistoryItem, fallback: ReadingHistoryManager.HistoryItem?) {
        self.init(
            comicId: cloudHistoryItem.comicID,
            title: cloudHistoryItem.title,
            thumbPath: cloudHistoryItem.thumbPath ?? "",
            thumbServer: cloudHistoryItem.thumbServer,
            author: cloudHistoryItem.author,
            lastReadDate: cloudHistoryItem.lastReadAt,
            episodeOrder: cloudHistoryItem.episodeOrder ?? fallback?.episodeOrder,
            episodeTitle: cloudHistoryItem.episodeTitle ?? fallback?.episodeTitle,
            pageIndex: cloudHistoryItem.pageIndex ?? fallback?.pageIndex
        )
    }

    var cloudHistoryItem: CloudHistoryItem {
        CloudHistoryItem(
            comicID: comicId,
            title: title,
            author: author,
            thumbPath: thumbPath.isEmpty ? nil : thumbPath,
            thumbServer: thumbServer,
            lastReadAt: lastReadDate,
            episodeOrder: episodeOrder,
            episodeTitle: episodeTitle,
            pageIndex: pageIndex
        )
    }
}

private extension CloudHistoryItem {
    var readingProgress: ReadingProgressManager.Progress? {
        guard let episodeOrder, let episodeTitle, let pageIndex else { return nil }
        return ReadingProgressManager.Progress(
            episodeOrder: episodeOrder,
            episodeTitle: episodeTitle,
            pageIndex: pageIndex
        )
    }
}
