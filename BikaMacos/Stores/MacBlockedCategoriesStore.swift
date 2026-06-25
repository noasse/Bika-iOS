import Foundation
import SwiftUI

@MainActor
@Observable
final class MacBlockedCategoriesStore {
    private let keyValueStore: any KeyValueStore
    private let storageKey = "blockedCategories"

    var blockedCategories: Set<String>

    init(keyValueStore: any KeyValueStore = AppDependencies.shared.keyValueStore) {
        self.keyValueStore = keyValueStore
        blockedCategories = Set(keyValueStore.stringArray(forKey: storageKey) ?? [])
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
        keyValueStore.set(Array(blockedCategories).sorted(), forKey: storageKey)
    }

    func filter(_ comics: [Comic]) -> [Comic] {
        guard !blockedCategories.isEmpty else { return comics }
        return comics.filter { comic in
            guard let categories = comic.categories else { return true }
            return !categories.contains { blockedCategories.contains($0) }
        }
    }
}
