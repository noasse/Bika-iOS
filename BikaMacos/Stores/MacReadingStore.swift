import Foundation
import SwiftUI

@Observable
final class MacReadingStore {
    private let keyValueStore: any KeyValueStore
    private let historyKey = "macReadingHistory"
    private let progressPrefix = "macReadProgress_"
    private let maxHistoryItems = 300

    private(set) var history: [MacHistoryItem] = []

    init(keyValueStore: any KeyValueStore = AppDependencies.shared.keyValueStore) {
        self.keyValueStore = keyValueStore
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
    }

    func removeHistory(comicId: String) {
        history.removeAll { $0.comicId == comicId }
        keyValueStore.removeObject(forKey: progressKey(for: comicId))
        saveHistory()
    }

    func clearHistory() {
        for item in history {
            keyValueStore.removeObject(forKey: progressKey(for: item.comicId))
        }
        history = []
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
}
