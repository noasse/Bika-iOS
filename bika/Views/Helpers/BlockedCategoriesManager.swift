import SwiftUI

@Observable
final class BlockedCategoriesManager {
    static let shared = BlockedCategoriesManager()

    var blockedCategories: Set<String> {
        didSet { save() }
    }

    private init() {
        let saved = UserDefaults.standard.stringArray(forKey: "blockedCategories") ?? []
        blockedCategories = Set(saved)
    }

    private func save() {
        UserDefaults.standard.set(Array(blockedCategories), forKey: "blockedCategories")
    }

    func isBlocked(_ category: String) -> Bool {
        blockedCategories.contains(category)
    }

    func toggle(_ category: String) {
        if blockedCategories.contains(category) {
            blockedCategories.remove(category)
        } else {
            blockedCategories.insert(category)
        }
    }

    func filterComics(_ comics: [Comic]) -> [Comic] {
        guard !blockedCategories.isEmpty else { return comics }
        return comics.filter { comic in
            guard let categories = comic.categories else { return true }
            return !categories.contains(where: { blockedCategories.contains($0) })
        }
    }
}
