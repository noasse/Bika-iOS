import XCTest
@testable import bika

final class SettingsViewModelTests: XCTestCase {
    override func tearDown() {
        TestSupport.restoreLiveDependencies()
        super.tearDown()
    }

    @MainActor
    func testRefreshAndClearImageCacheUpdatesDisplayedSize() async {
        let store = InMemoryKeyValueStore()
        let cacheManager = StubImageCacheManager(initialBytes: 1_500_000)
        let viewModel = SettingsViewModel(
            themeManager: ThemeManager(keyValueStore: store),
            blockedCategoriesManager: BlockedCategoriesManager(keyValueStore: store),
            keyValueStore: store,
            imageCacheManager: cacheManager,
            isUITesting: false,
            appVersion: "1.0"
        )

        await viewModel.refreshImageCacheUsage()
        XCTAssertNotEqual(viewModel.imageCacheSizeDescription, "0 KB")

        await viewModel.clearImageCache()

        XCTAssertEqual(viewModel.imageCacheSizeDescription, "0 KB")
        XCTAssertEqual(viewModel.imageCacheMessage, "图片缓存已清理")
        let clearCallCount = await cacheManager.clearCallCount
        XCTAssertEqual(clearCallCount, 1)
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

    @MainActor
    func testRefreshAndClearImageDiagnosticsUpdatesDescriptions() async {
        let diagnostics = StubImageDiagnosticsManager(
            status: ImageDiagnosticsStatus(
                eventCount: 12,
                lastErrorAt: Date(timeIntervalSince1970: 1_700_000_000)
            )
        )
        let viewModel = makeSettingsViewModel(imageDiagnostics: diagnostics)

        await viewModel.refreshImageDiagnostics()
        XCTAssertEqual(viewModel.imageDiagnosticsCountDescription, "12 条")
        XCTAssertNotEqual(
            viewModel.imageDiagnosticsLastErrorDescription,
            "暂无错误"
        )

        await viewModel.clearImageDiagnostics()
        XCTAssertEqual(viewModel.imageDiagnosticsCountDescription, "0 条")
        XCTAssertEqual(viewModel.imageDiagnosticsMessage, "图片诊断日志已清空")
    }

    @MainActor
    func testExportImageDiagnosticsReturnsFileAndUsesAppMetadata() async throws {
        let diagnostics = StubImageDiagnosticsManager(
            status: ImageDiagnosticsStatus(eventCount: 1, lastErrorAt: nil)
        )
        let expectedURL = URL(fileURLWithPath: "/tmp/export.json")
        await diagnostics.setExportURL(expectedURL)
        let viewModel = makeSettingsViewModel(imageDiagnostics: diagnostics)

        let result = await viewModel.exportImageDiagnostics()

        XCTAssertEqual(result, expectedURL)
        let metadata = await diagnostics.lastMetadata
        XCTAssertEqual(metadata?.appVersion, "1.0")
        XCTAssertEqual(metadata?.buildNumber, "42")
        XCTAssertEqual(metadata?.deviceModel, "iPhone-Test")
        XCTAssertEqual(metadata?.imageQuality, ImageQuality.original.rawValue)
    }

    @MainActor
    func testClearFailureKeepsCountAndShowsMessage() async {
        let diagnostics = StubImageDiagnosticsManager(
            status: ImageDiagnosticsStatus(eventCount: 7, lastErrorAt: nil),
            clearError: URLError(.cannotWriteToFile)
        )
        let viewModel = makeSettingsViewModel(imageDiagnostics: diagnostics)

        await viewModel.refreshImageDiagnostics()
        await viewModel.clearImageDiagnostics()

        XCTAssertEqual(viewModel.imageDiagnosticsCountDescription, "7 条")
        XCTAssertTrue(
            viewModel.imageDiagnosticsMessage?
                .hasPrefix("清空图片诊断日志失败：") == true
        )
    }

    @MainActor
    func testExportFailureReturnsNilWithoutClearingLogs() async {
        let diagnostics = StubImageDiagnosticsManager(
            status: ImageDiagnosticsStatus(eventCount: 7, lastErrorAt: nil),
            exportError: URLError(.cannotCreateFile)
        )
        let viewModel = makeSettingsViewModel(imageDiagnostics: diagnostics)

        let result = await viewModel.exportImageDiagnostics()

        XCTAssertNil(result)
        let clearCallCount = await diagnostics.clearCallCount
        XCTAssertEqual(clearCallCount, 0)
        XCTAssertTrue(
            viewModel.imageDiagnosticsMessage?
                .hasPrefix("导出图片诊断日志失败：") == true
        )
    }

    @MainActor
    private func makeSettingsViewModel(
        imageDiagnostics: any ImageDiagnosticsManaging
    ) -> SettingsViewModel {
        let store = InMemoryKeyValueStore()
        return SettingsViewModel(
            themeManager: ThemeManager(keyValueStore: store),
            blockedCategoriesManager: BlockedCategoriesManager(
                keyValueStore: store
            ),
            keyValueStore: store,
            imageCacheManager: StubImageCacheManager(initialBytes: 0),
            imageDiagnostics: imageDiagnostics,
            isUITesting: false,
            appVersion: "1.0",
            buildNumber: "42",
            deviceInfo: ImageDiagnosticsDeviceInfo(
                model: "iPhone-Test",
                systemName: "iOS",
                systemVersion: "26.5"
            )
        )
    }
}

private actor StubImageCacheManager: ImageCacheManaging {
    private var bytes: Int
    private(set) var clearCallCount = 0

    init(initialBytes: Int) {
        bytes = initialBytes
    }

    func usage() -> ImageCacheUsage {
        ImageCacheUsage(memoryBytes: bytes, diskBytes: 0)
    }

    func clear() {
        clearCallCount += 1
        bytes = 0
    }
}

private actor StubImageDiagnosticsManager: ImageDiagnosticsManaging {
    private var currentStatus: ImageDiagnosticsStatus
    private var exportURL = URL(fileURLWithPath: "/tmp/image-diagnostics.json")
    private let clearError: URLError?
    private let exportError: URLError?
    private(set) var clearCallCount = 0
    private(set) var lastMetadata: ImageDiagnosticsMetadata?

    init(
        status: ImageDiagnosticsStatus,
        clearError: URLError? = nil,
        exportError: URLError? = nil
    ) {
        currentStatus = status
        self.clearError = clearError
        self.exportError = exportError
    }

    nonisolated func record(_ event: ImageDiagnosticEvent) {}

    func status() -> ImageDiagnosticsStatus {
        currentStatus
    }

    func snapshot() -> [ImageDiagnosticEvent] {
        []
    }

    func flush() {}

    func clear() throws {
        clearCallCount += 1
        if let clearError {
            throw clearError
        }
        currentStatus = ImageDiagnosticsStatus(
            eventCount: 0,
            lastErrorAt: nil
        )
    }

    func export(metadata: ImageDiagnosticsMetadata) throws -> URL {
        lastMetadata = metadata
        if let exportError {
            throw exportError
        }
        return exportURL
    }

    func setExportURL(_ url: URL) {
        exportURL = url
    }
}
