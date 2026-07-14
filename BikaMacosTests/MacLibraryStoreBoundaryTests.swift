import XCTest
@testable import BikaMacos

@MainActor
final class MacLibraryStoreBoundaryTests: XCTestCase {
    override func tearDown() {
        MacTestSupport.restoreLiveDependencies()
        super.tearDown()
    }

    func testFeatureStoreInstancesDoNotShareMutableState() {
        let (client, store) = MacTestSupport.makeAPIClient { _ in
            MacTestSupport.jsonResponse(data: [:])
        }
        let accountSession = AccountSessionStore(keyValueStore: store)
        let readingStore = MacReadingStore(
            keyValueStore: store,
            accountSessionStore: accountSession
        )
        let blockedStore = MacBlockedCategoriesStore(keyValueStore: store)

        let authenticationA = MacAuthenticationStore(
            client: client,
            accountSessionStore: accountSession
        )
        let authenticationB = MacAuthenticationStore(
            client: client,
            accountSessionStore: accountSession
        )
        authenticationA.authError = "A"
        XCTAssertNil(authenticationB.authError)

        let listA = MacLibraryListStore(
            client: client,
            readingStore: readingStore,
            blockedCategoriesStore: blockedStore
        )
        let listB = MacLibraryListStore(
            client: client,
            readingStore: readingStore,
            blockedCategoriesStore: blockedStore
        )
        listA.searchText = "A"
        XCTAssertEqual(listB.searchText, "")

        let detailA = MacComicDetailStore(
            client: client,
            readingStore: readingStore,
            blockedCategoriesStore: blockedStore
        )
        let detailB = MacComicDetailStore(
            client: client,
            readingStore: readingStore,
            blockedCategoriesStore: blockedStore
        )
        detailA.detailError = "A"
        XCTAssertNil(detailB.detailError)
    }

    func testFacadeForwardsMutableStateToOwningStores() {
        let (client, store) = MacTestSupport.makeAPIClient { _ in
            MacTestSupport.jsonResponse(data: [:])
        }
        let accountSession = AccountSessionStore(keyValueStore: store)
        let model = MacLibraryModel(
            client: client,
            readingStore: MacReadingStore(
                keyValueStore: store,
                accountSessionStore: accountSession
            ),
            blockedCategoriesStore: MacBlockedCategoriesStore(keyValueStore: store),
            accountSessionStore: accountSession
        )

        model.authError = "auth"
        model.searchText = "keyword"
        model.detailError = "detail"

        XCTAssertEqual(model.authenticationStore.authError, "auth")
        XCTAssertEqual(model.listStore.searchText, "keyword")
        XCTAssertEqual(model.detailStore.detailError, "detail")
    }
}
