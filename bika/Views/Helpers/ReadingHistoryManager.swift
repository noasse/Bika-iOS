import Foundation

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

    var items: [HistoryItem] = []

    private let keyValueStore: any KeyValueStore
    private let cloudHistorySync: CloudHistorySyncService
    private let readingProgressManager: ReadingProgressManager
    private let storageKey = "readingHistory"
    private let maxItems = 200

    init(
        keyValueStore: any KeyValueStore = AppDependencies.shared.keyValueStore,
        cloudHistorySync: CloudHistorySyncService? = nil,
        readingProgressManager: ReadingProgressManager? = nil
    ) {
        self.keyValueStore = keyValueStore
        self.cloudHistorySync = cloudHistorySync ?? CloudHistorySyncService(keyValueStore: keyValueStore)
        self.readingProgressManager = readingProgressManager ?? ReadingProgressManager(keyValueStore: keyValueStore)
        load()
    }

    func record(comicId: String, title: String, thumbPath: String, thumbServer: String?, author: String?) {
        // Remove existing entry for this comic
        items.removeAll { $0.comicId == comicId }
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
        items.insert(item, at: 0)

        // Trim to max
        if items.count > maxItems {
            items = Array(items.prefix(maxItems))
        }

        save()
        cloudHistorySync.upload(item.cloudHistoryItem)
    }

    func remove(comicId: String) {
        items.removeAll { $0.comicId == comicId }
        save()
        cloudHistorySync.delete(comicID: comicId)
    }

    func clearAll() {
        items = []
        save()
        cloudHistorySync.clear()
    }

    func syncFromCloud() async {
        let cloudItems = await cloudHistorySync.fetchHistory(limit: maxItems)
        applyCloudHistoryItems(cloudItems)
    }

    func syncProgressFromCloud(for comicId: String) async {
        let cloudItems = await cloudHistorySync.fetchHistory(limit: maxItems)
        guard let cloudItem = cloudItems.first(where: { $0.comicID == comicId }) else { return }
        applyCloudHistoryItems([cloudItem])
    }

    func applyCloudHistoryItems(_ cloudItems: [CloudHistoryItem]) {
        guard !cloudItems.isEmpty else { return }
        var itemsByComicID = Dictionary(uniqueKeysWithValues: items.map { ($0.comicId, $0) })
        for cloudItem in cloudItems {
            let localItem = itemsByComicID[cloudItem.comicID]
            guard localItem == nil || localItem!.lastReadDate < cloudItem.lastReadAt else { continue }
            itemsByComicID[cloudItem.comicID] = HistoryItem(cloudHistoryItem: cloudItem, fallback: localItem)
            if let progress = cloudItem.readingProgress {
                readingProgressManager.save(comicId: cloudItem.comicID, progress: progress)
            }
        }

        items = Array(itemsByComicID.values)
            .sorted { $0.lastReadDate > $1.lastReadDate }
        if items.count > maxItems {
            items = Array(items.prefix(maxItems))
        }
        save()
    }

    private func load() {
        guard let data = keyValueStore.data(forKey: storageKey) else { return }
        items = (try? JSONDecoder().decode([HistoryItem].self, from: data)) ?? []
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) {
            keyValueStore.set(data, forKey: storageKey)
        }
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
