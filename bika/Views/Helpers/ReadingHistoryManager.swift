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

        var id: String { comicId }
    }

    var items: [HistoryItem] = []

    private let defaults = UserDefaults.standard
    private let storageKey = "readingHistory"
    private let maxItems = 200

    private init() {
        load()
    }

    func record(comicId: String, title: String, thumbPath: String, thumbServer: String?, author: String?) {
        // Remove existing entry for this comic
        items.removeAll { $0.comicId == comicId }

        // Insert at front
        let item = HistoryItem(
            comicId: comicId,
            title: title,
            thumbPath: thumbPath,
            thumbServer: thumbServer,
            author: author,
            lastReadDate: Date()
        )
        items.insert(item, at: 0)

        // Trim to max
        if items.count > maxItems {
            items = Array(items.prefix(maxItems))
        }

        save()
    }

    func remove(comicId: String) {
        items.removeAll { $0.comicId == comicId }
        save()
    }

    func clearAll() {
        items = []
        save()
    }

    private func load() {
        guard let data = defaults.data(forKey: storageKey) else { return }
        items = (try? JSONDecoder().decode([HistoryItem].self, from: data)) ?? []
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) {
            defaults.set(data, forKey: storageKey)
        }
    }
}
