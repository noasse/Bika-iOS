import Foundation

@Observable
final class ReadingProgressManager {
    static let shared = ReadingProgressManager()

    struct Progress: Codable {
        let episodeOrder: Int
        let episodeTitle: String
        let pageIndex: Int
    }

    private let defaults = UserDefaults.standard

    private init() {}

    func save(comicId: String, progress: Progress) {
        if let data = try? JSONEncoder().encode(progress) {
            defaults.set(data, forKey: key(for: comicId))
        }
    }

    func get(comicId: String) -> Progress? {
        guard let data = defaults.data(forKey: key(for: comicId)) else { return nil }
        return try? JSONDecoder().decode(Progress.self, from: data)
    }

    func remove(comicId: String) {
        defaults.removeObject(forKey: key(for: comicId))
    }

    private func key(for comicId: String) -> String {
        "readProgress_\(comicId)"
    }
}
