import SwiftUI

@Observable
final class SettingsViewModel {
    let themeManager: ThemeManager

    var imageQuality: ImageQuality
    var lastRecordedImageQuality = "未记录"
    let isUITesting: Bool
    let appVersion: String

    private let blockedCategoriesManager: BlockedCategoriesManager
    private let keyValueStore: any KeyValueStore

    init(
        themeManager: ThemeManager = .shared,
        blockedCategoriesManager: BlockedCategoriesManager = .shared,
        keyValueStore: any KeyValueStore = AppDependencies.shared.keyValueStore,
        isUITesting: Bool = AppDependencies.shared.isUITesting,
        appVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "未知版本"
    ) {
        self.themeManager = themeManager
        self.blockedCategoriesManager = blockedCategoriesManager
        self.keyValueStore = keyValueStore
        self.isUITesting = isUITesting
        self.appVersion = appVersion
        let savedImageQuality = keyValueStore.string(forKey: APIConfig.imageQualityKey) ?? APIConfig.imageQualityDefault
        imageQuality = ImageQuality(rawValue: savedImageQuality) ?? .original
    }

    var blockedCategoryCount: Int {
        blockedCategoriesManager.blockedCategories.count
    }

    func setThemeMode(_ mode: ThemeMode) {
        themeManager.themeMode = mode
    }

    func setImageQuality(_ quality: ImageQuality) {
        imageQuality = quality
        keyValueStore.set(quality.rawValue, forKey: APIConfig.imageQualityKey)
    }

    func refreshDiagnostics() {
        lastRecordedImageQuality = keyValueStore.string(forKey: MockURLProtocol.lastImageQualityHeaderKey) ?? "未记录"
    }
}

@Observable
final class BlockedCategoriesViewModel {
    var categories: [Category] = []
    var isLoading = false
    var errorMessage: String?

    private let client: any APIClientProtocol
    private let blockedManager: BlockedCategoriesManager

    init(
        client: any APIClientProtocol = APIClient.shared,
        blockedManager: BlockedCategoriesManager = .shared
    ) {
        self.client = client
        self.blockedManager = blockedManager
    }

    func loadCategories() async {
        guard categories.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let response: APIResponse<CategoriesData> = try await client.send(.categories())
            categories = response.data?.categories.filter { $0.isWeb != true } ?? []
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func toggleCategory(_ category: String) {
        blockedManager.toggle(category)
    }

    func isBlocked(_ category: String) -> Bool {
        blockedManager.isBlocked(category)
    }
}
