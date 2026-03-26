import Foundation

@Observable
final class ReadingProgressManager {
    static let shared = ReadingProgressManager()

    struct Progress: Codable {
        let episodeOrder: Int
        let episodeTitle: String
        let pageIndex: Int
    }

    private let keyValueStore: any KeyValueStore

    init(keyValueStore: any KeyValueStore = AppDependencies.shared.keyValueStore) {
        self.keyValueStore = keyValueStore
    }

    func save(comicId: String, progress: Progress) {
        if let data = try? JSONEncoder().encode(progress) {
            keyValueStore.set(data, forKey: key(for: comicId))
        }
    }

    func get(comicId: String) -> Progress? {
        guard let data = keyValueStore.data(forKey: key(for: comicId)) else { return nil }
        return try? JSONDecoder().decode(Progress.self, from: data)
    }

    func remove(comicId: String) {
        keyValueStore.removeObject(forKey: key(for: comicId))
    }

    private func key(for comicId: String) -> String {
        "readProgress_\(comicId)"
    }
}
