import SwiftUI
import XCTest
@testable import BikaMacos

@MainActor
final class MacArchitectureBoundaryTests: XCTestCase {
    override func tearDown() {
        MacTestSupport.restoreLiveDependencies()
        super.tearDown()
    }

    func testSettingsUsesInjectedClientAndStore() async throws {
        let store = InMemoryKeyValueStore()
        let requestedPaths = LockedValue<[String]>([])
        let (client, _) = MacTestSupport.makeAPIClient(store: store) { request in
            var paths = requestedPaths.value
            paths.append(request.url?.path ?? "")
            requestedPaths.value = paths
            return MacTestSupport.jsonResponse(data: [
                "categories": [
                    ["_id": "category-1", "title": "首个分类"],
                    ["_id": "category-1", "title": "重复后端 ID"],
                ],
            ])
        }
        let imageCacheManager = SpyImageCacheManager()
        let view = MacSettingsView(
            themeModeRawValue: .constant(MacThemeMode.system.rawValue),
            blockedCategoriesStore: MacBlockedCategoriesStore(keyValueStore: store),
            client: client,
            keyValueStore: store,
            imageCacheManager: imageCacheManager
        )

        view.persistImageQuality(.high)
        let categories = try await view.fetchCategories()

        XCTAssertEqual(store.string(forKey: APIConfig.imageQualityKey), ImageQuality.high.rawValue)
        XCTAssertEqual(requestedPaths.value, ["/categories"])
        XCTAssertEqual(categories.map(\.title), ["首个分类"])
    }

    func testChangingImageQualityDropsCachedImages() async throws {
        let store = InMemoryKeyValueStore()
        let imageCacheManager = SpyImageCacheManager(
            usage: MacImageCacheUsage(memoryBytes: 1_024, diskBytes: 2_048)
        )
        let view = MacSettingsView(
            themeModeRawValue: .constant(MacThemeMode.system.rawValue),
            blockedCategoriesStore: MacBlockedCategoriesStore(keyValueStore: store),
            client: APIClient(tokenStore: TokenStore(store: store)),
            keyValueStore: store,
            imageCacheManager: imageCacheManager
        )

        XCTAssertEqual(imageCacheManager.clearCount, 0)

        view.persistImageQuality(.low)

        // The clear is kicked off from a detached task, so let the main actor drain it.
        try await waitUntil { imageCacheManager.clearCount == 1 }
        XCTAssertEqual(store.string(forKey: APIConfig.imageQualityKey), ImageQuality.low.rawValue)
    }

    private func waitUntil(
        timeout: Duration = .seconds(2),
        _ condition: @MainActor () -> Bool
    ) async throws {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("等待条件超时")
    }

    func testInstallForTestingPublishesOneDependencySnapshot() {
        let store = InMemoryKeyValueStore()
        let loader = FixtureImageDataLoader()
        let client = APIClient(tokenStore: TokenStore(store: store))

        AppDependencies.shared.installForTesting(
            apiClient: client,
            keyValueStore: store,
            imageDataLoader: loader
        )
        let snapshot = AppDependencies.shared.snapshot

        XCTAssertTrue(snapshot.apiClient === client)
        XCTAssertTrue(snapshot.keyValueStore === store)
        XCTAssertTrue((snapshot.imageDataLoader as? FixtureImageDataLoader) === loader)
        XCTAssertTrue(APIClient.shared === client)
    }
}
