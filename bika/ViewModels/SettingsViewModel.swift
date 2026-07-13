import SwiftUI

@Observable
final class SettingsViewModel {
    let themeManager: ThemeManager

    var imageQuality: ImageQuality
    var lastRecordedImageQuality = "未记录"
    let isUITesting: Bool
    let appVersion: String
    var cloudHistoryEnabled = false
    var cloudHistoryBaseURL = ""
    var cloudHistoryBearerToken = ""
    var cloudHistoryCertificatePins = ""
    var cloudHistorySettingsMessage: String?
    var isTestingCloudHistoryConnection = false
    var imageCacheSizeDescription = "计算中..."
    var imageCacheMessage: String?
    var isRefreshingImageCache = false
    var isClearingImageCache = false

    private let blockedCategoriesManager: BlockedCategoriesManager
    private let keyValueStore: any KeyValueStore
    private let imageCacheManager: any ImageCacheManaging

    init(
        themeManager: ThemeManager = .shared,
        blockedCategoriesManager: BlockedCategoriesManager = .shared,
        keyValueStore: any KeyValueStore = AppDependencies.shared.keyValueStore,
        imageCacheManager: any ImageCacheManaging = ImageCacheController.shared,
        isUITesting: Bool = AppDependencies.shared.isUITesting,
        appVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "未知版本"
    ) {
        self.themeManager = themeManager
        self.blockedCategoriesManager = blockedCategoriesManager
        self.keyValueStore = keyValueStore
        self.imageCacheManager = imageCacheManager
        self.isUITesting = isUITesting
        self.appVersion = appVersion
        let savedImageQuality = keyValueStore.string(forKey: APIConfig.imageQualityKey) ?? APIConfig.imageQualityDefault
        imageQuality = ImageQuality(rawValue: savedImageQuality) ?? .original
        loadCloudHistorySettings()
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

    func refreshImageCacheUsage() async {
        guard !isRefreshingImageCache else { return }
        isRefreshingImageCache = true
        defer { isRefreshingImageCache = false }

        let usage = await imageCacheManager.usage()
        imageCacheSizeDescription = Self.formatByteCount(usage.totalBytes)
    }

    func clearImageCache() async {
        guard !isClearingImageCache else { return }
        isClearingImageCache = true
        imageCacheMessage = nil
        defer { isClearingImageCache = false }

        await imageCacheManager.clear()
        let usage = await imageCacheManager.usage()
        imageCacheSizeDescription = Self.formatByteCount(usage.totalBytes)
        imageCacheMessage = "图片缓存已清理"
    }

    func saveCloudHistorySettings() {
        let pins = parsedCloudHistoryPins()
        let trimmedURL = cloudHistoryBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedToken = cloudHistoryBearerToken.trimmingCharacters(in: .whitespacesAndNewlines)

        guard cloudHistoryEnabled else {
            persistCloudHistoryRawSettings(isEnabled: false, pins: pins)
            cloudHistorySettingsMessage = "云端历史同步已关闭"
            return
        }

        guard let config = validatedCloudHistoryConfig(
            pins: pins,
            trimmedURL: trimmedURL,
            trimmedToken: trimmedToken
        ) else { return }
        keyValueStore.setCloudHistoryConfig(config)
        cloudHistoryBaseURL = trimmedURL
        cloudHistoryBearerToken = trimmedToken
        cloudHistoryCertificatePins = pins.joined(separator: "\n")
        cloudHistorySettingsMessage = "云端历史同步已保存"
    }

    func testCloudHistoryConnection() async {
        guard cloudHistoryEnabled else {
            cloudHistorySettingsMessage = "请先启用云端历史同步"
            return
        }

        let pins = parsedCloudHistoryPins()
        let trimmedURL = cloudHistoryBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedToken = cloudHistoryBearerToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let config = validatedCloudHistoryConfig(
            pins: pins,
            trimmedURL: trimmedURL,
            trimmedToken: trimmedToken
        ) else { return }

        isTestingCloudHistoryConnection = true
        cloudHistorySettingsMessage = "正在测试云端连接..."
        defer { isTestingCloudHistoryConnection = false }

        do {
            try await CloudHistoryClient(config: config).testConnection()
            cloudHistorySettingsMessage = "云端连接成功"
        } catch {
            cloudHistorySettingsMessage = "云端连接失败：\(cloudHistoryErrorDescription(error))"
        }
    }

    private func loadCloudHistorySettings() {
        cloudHistoryEnabled = keyValueStore.string(forKey: CloudHistoryConfig.StorageKeys.isEnabled) == "1"
        cloudHistoryBaseURL = keyValueStore.string(forKey: CloudHistoryConfig.StorageKeys.baseURL) ?? ""
        cloudHistoryBearerToken = keyValueStore.string(forKey: CloudHistoryConfig.StorageKeys.bearerToken) ?? ""
        cloudHistoryCertificatePins = (keyValueStore.stringArray(forKey: CloudHistoryConfig.StorageKeys.certificateSHA256Pins) ?? [])
            .joined(separator: "\n")
    }

    private func persistCloudHistoryRawSettings(isEnabled: Bool, pins: [String]) {
        keyValueStore.setCloudHistoryEnabled(isEnabled)
        keyValueStore.set(cloudHistoryBaseURL.trimmingCharacters(in: .whitespacesAndNewlines), forKey: CloudHistoryConfig.StorageKeys.baseURL)
        keyValueStore.set(cloudHistoryBearerToken.trimmingCharacters(in: .whitespacesAndNewlines), forKey: CloudHistoryConfig.StorageKeys.bearerToken)
        keyValueStore.set(pins, forKey: CloudHistoryConfig.StorageKeys.certificateSHA256Pins)
    }

    private func validatedCloudHistoryConfig(
        pins: [String],
        trimmedURL: String,
        trimmedToken: String
    ) -> CloudHistoryConfig? {
        guard let baseURL = URL(string: trimmedURL), baseURL.scheme?.lowercased() == "https" else {
            cloudHistorySettingsMessage = "服务地址必须是 https:// 开头"
            return nil
        }

        guard !trimmedToken.isEmpty else {
            cloudHistorySettingsMessage = "同步 Token 不能为空"
            return nil
        }

        return CloudHistoryConfig(
            baseURL: baseURL,
            bearerToken: trimmedToken,
            certificateSHA256Pins: pins
        )
    }

    private func parsedCloudHistoryPins() -> [String] {
        cloudHistoryCertificatePins
            .components(separatedBy: CharacterSet(charactersIn: ",\n "))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func cloudHistoryErrorDescription(_ error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription {
            return description
        }
        return error.localizedDescription
    }

    private static func formatByteCount(_ bytes: Int) -> String {
        guard bytes > 0 else { return "0 KB" }
        return ByteCountFormatter.string(
            fromByteCount: Int64(bytes),
            countStyle: .file
        )
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
