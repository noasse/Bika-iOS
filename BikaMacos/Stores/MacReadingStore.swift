import Foundation
import SwiftUI

@Observable
final class MacReadingStore {
    private let keyValueStore: any KeyValueStore
    private let cloudHistorySync: CloudHistorySyncService
    private let historyKey = "macReadingHistory"
    private let progressPrefix = "macReadProgress_"
    private let maxHistoryItems = 300
    private let cloudHistoryLimit = 200

    private(set) var history: [MacHistoryItem] = []

    init(
        keyValueStore: any KeyValueStore = AppDependencies.shared.keyValueStore,
        cloudHistorySync: CloudHistorySyncService? = nil
    ) {
        self.keyValueStore = keyValueStore
        self.cloudHistorySync = cloudHistorySync ?? CloudHistorySyncService(keyValueStore: keyValueStore)
        loadHistory()
    }

    func progress(for comicId: String) -> MacReadingProgress? {
        guard let data = keyValueStore.data(forKey: progressKey(for: comicId)) else { return nil }
        return try? JSONDecoder().decode(MacReadingProgress.self, from: data)
    }

    func record(
        request: MacReaderLaunchRequest,
        episode: MacReaderEpisode,
        pageIndex: Int
    ) {
        let progress = MacReadingProgress(
            episodeOrder: episode.order,
            episodeTitle: episode.title,
            pageIndex: max(pageIndex, 0)
        )
        if let data = try? JSONEncoder().encode(progress) {
            keyValueStore.set(data, forKey: progressKey(for: request.comicId))
        }

        history.removeAll { $0.comicId == request.comicId }
        history.insert(
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
        if history.count > maxHistoryItems {
            history = Array(history.prefix(maxHistoryItems))
        }
        saveHistory()
        cloudHistorySync.upload(history[0].cloudHistoryItem)
    }

    func removeHistory(comicId: String) {
        history.removeAll { $0.comicId == comicId }
        keyValueStore.removeObject(forKey: progressKey(for: comicId))
        saveHistory()
        cloudHistorySync.delete(comicID: comicId)
    }

    func clearHistory() {
        for item in history {
            keyValueStore.removeObject(forKey: progressKey(for: item.comicId))
        }
        history = []
        saveHistory()
        cloudHistorySync.clear()
    }

    func syncFromCloud() async {
        let cloudItems = await cloudHistorySync.fetchHistory(limit: cloudHistoryLimit)
        guard !cloudItems.isEmpty else { return }

        var itemsByComicID = Dictionary(uniqueKeysWithValues: history.map { ($0.comicId, $0) })
        for cloudItem in cloudItems {
            let localItem = itemsByComicID[cloudItem.comicID]
            guard localItem == nil || localItem!.updatedAt < cloudItem.lastReadAt else { continue }

            let mergedItem = MacHistoryItem(cloudHistoryItem: cloudItem, fallback: localItem)
            itemsByComicID[cloudItem.comicID] = mergedItem
            if let progress = cloudItem.macReadingProgress {
                saveProgress(progress, for: cloudItem.comicID)
            }
        }

        history = Array(itemsByComicID.values)
            .sorted { $0.updatedAt > $1.updatedAt }
        if history.count > maxHistoryItems {
            history = Array(history.prefix(maxHistoryItems))
        }
        saveHistory()
    }

    private func progressKey(for comicId: String) -> String {
        "\(progressPrefix)\(comicId)"
    }

    private func loadHistory() {
        guard let data = keyValueStore.data(forKey: historyKey) else { return }
        history = (try? JSONDecoder().decode([MacHistoryItem].self, from: data)) ?? []
    }

    private func saveHistory() {
        guard let data = try? JSONEncoder().encode(history) else { return }
        keyValueStore.set(data, forKey: historyKey)
    }

    private func saveProgress(_ progress: MacReadingProgress, for comicId: String) {
        guard let data = try? JSONEncoder().encode(progress) else { return }
        keyValueStore.set(data, forKey: progressKey(for: comicId))
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
