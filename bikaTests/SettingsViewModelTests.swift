import XCTest
@testable import bika

final class SettingsViewModelTests: XCTestCase {
    override func tearDown() {
        TestSupport.restoreLiveDependencies()
        super.tearDown()
    }

    func testSetImageQualityPersistsToInjectedStore() {
        let store = InMemoryKeyValueStore()
        AppDependencies.shared.installForTesting(keyValueStore: store)

        let themeManager = ThemeManager(keyValueStore: store)
        let blockedManager = BlockedCategoriesManager(keyValueStore: store)
        let viewModel = SettingsViewModel(
            themeManager: themeManager,
            blockedCategoriesManager: blockedManager,
            keyValueStore: store,
            isUITesting: true,
            appVersion: "1.0"
        )

        viewModel.setImageQuality(.high)

        XCTAssertEqual(viewModel.imageQuality, .high)
        XCTAssertEqual(store.string(forKey: APIConfig.imageQualityKey), ImageQuality.high.rawValue)
    }

    func testRefreshDiagnosticsUsesInjectedStore() {
        let store = InMemoryKeyValueStore()
        store.set(ImageQuality.medium.rawValue, forKey: MockURLProtocol.lastImageQualityHeaderKey)
        AppDependencies.shared.installForTesting(keyValueStore: store)

        let viewModel = SettingsViewModel(
            themeManager: ThemeManager(keyValueStore: store),
            blockedCategoriesManager: BlockedCategoriesManager(keyValueStore: store),
            keyValueStore: store,
            isUITesting: true,
            appVersion: "1.0"
        )
        viewModel.refreshDiagnostics()

        XCTAssertEqual(viewModel.lastRecordedImageQuality, ImageQuality.medium.rawValue)
    }

    func testSetThemeModePersistsToInjectedStore() {
        let store = InMemoryKeyValueStore()
        AppDependencies.shared.installForTesting(keyValueStore: store)

        let themeManager = ThemeManager(keyValueStore: store)
        let viewModel = SettingsViewModel(
            themeManager: themeManager,
            blockedCategoriesManager: BlockedCategoriesManager(keyValueStore: store),
            keyValueStore: store,
            isUITesting: false,
            appVersion: "1.0"
        )

        viewModel.setThemeMode(.light)

        XCTAssertEqual(viewModel.themeManager.themeMode, .light)
        XCTAssertEqual(store.string(forKey: "themeMode"), ThemeMode.light.rawValue)
    }

    func testSaveCloudHistorySettingsAllowsEmptyCertificatePins() {
        let store = InMemoryKeyValueStore()
        AppDependencies.shared.installForTesting(keyValueStore: store)

        let viewModel = SettingsViewModel(
            themeManager: ThemeManager(keyValueStore: store),
            blockedCategoriesManager: BlockedCategoriesManager(keyValueStore: store),
            keyValueStore: store,
            isUITesting: false,
            appVersion: "1.0"
        )
        viewModel.cloudHistoryEnabled = true
        viewModel.cloudHistoryBaseURL = "https://history-sync.invalid"
        viewModel.cloudHistoryBearerToken = "unit-test-token"
        viewModel.cloudHistoryCertificatePins = ""

        viewModel.saveCloudHistorySettings()

        XCTAssertEqual(viewModel.cloudHistorySettingsMessage, "云端历史同步已保存")
        XCTAssertEqual(store.cloudHistoryConfig()?.certificateSHA256Pins, [])
    }
}
