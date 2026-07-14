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
        let view = MacSettingsView(
            themeModeRawValue: .constant(MacThemeMode.system.rawValue),
            blockedCategoriesStore: MacBlockedCategoriesStore(keyValueStore: store),
            client: client,
            keyValueStore: store
        )

        view.persistImageQuality(.high)
        let categories = try await view.fetchCategories()

        XCTAssertEqual(store.string(forKey: APIConfig.imageQualityKey), ImageQuality.high.rawValue)
        XCTAssertEqual(requestedPaths.value, ["/categories"])
        XCTAssertEqual(categories.map(\.title), ["首个分类"])
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
