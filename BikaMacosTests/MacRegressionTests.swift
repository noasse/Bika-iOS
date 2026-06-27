import XCTest
@testable import BikaMacos

@MainActor
final class MacRegressionTests: XCTestCase {
    override func tearDown() {
        MacTestSupport.restoreLiveDependencies()
        super.tearDown()
    }

    func testCheckTokenClearsInvalidStoredTokenOnProfileFailure() async {
        let (client, store) = MacTestSupport.makeAPIClient { request in
            XCTAssertEqual(request.url?.path, "/users/profile")
            XCTAssertEqual(request.value(forHTTPHeaderField: "authorization"), "stale-token")
            return MacTestSupport.emptyHTTPResponse(statusCode: 401)
        }
        await client.tokenStore.setToken("stale-token")

        let model = MacLibraryModel(
            client: client,
            readingStore: MacReadingStore(keyValueStore: store),
            blockedCategoriesStore: MacBlockedCategoriesStore(keyValueStore: store)
        )

        await model.checkTokenIfNeeded()

        XCTAssertFalse(model.isAuthenticated)
        XCTAssertFalse(model.isCheckingToken)
        XCTAssertNil(model.userProfile)
        XCTAssertNotNil(model.authError)
        let storedToken = await client.tokenStore.getToken()
        XCTAssertNil(storedToken)
        XCTAssertNil(store.string(forKey: TokenStore.tokenKey))
    }

    func testEndpointEscapesQueryAndPathSeparatorsForMacTarget() {
        let comicsEndpoint: APIEndpoint<APIResponse<ComicsData>> = .comics(category: "A&B= C", page: 2)
        XCTAssertTrue(comicsEndpoint.path.contains("page=2"))
        XCTAssertTrue(comicsEndpoint.path.contains("c=A%26B%3D%20C"))
        XCTAssertFalse(comicsEndpoint.path.contains("&B="))

        let detailEndpoint: APIEndpoint<APIResponse<ComicDetailData>> = .comicDetail(id: "comic/with?special&chars")
        XCTAssertEqual(detailEndpoint.path, "comics/comic%2Fwith%3Fspecial%26chars")
    }

    func testMacReaderImagePrefetchWindowSkipsCurrentPageAndStaysWithinBounds() {
        XCTAssertEqual(
            MacReaderImagePrefetchPlan.indices(
                currentIndex: 5,
                pageCount: 10,
                lookBehind: 1,
                lookAhead: 3
            ),
            [6, 7, 8, 4]
        )

        XCTAssertEqual(
            MacReaderImagePrefetchPlan.indices(
                currentIndex: 0,
                pageCount: 3,
                lookBehind: 2,
                lookAhead: 4
            ),
            [1, 2]
        )

        XCTAssertEqual(
            MacReaderImagePrefetchPlan.indices(
                currentIndex: 4,
                pageCount: 5,
                lookBehind: 2,
                lookAhead: 3
            ),
            [3, 2]
        )
    }

    func testMacReaderWindowSizePersistenceStoresAndClampsContentSize() {
        let store = InMemoryKeyValueStore()

        XCTAssertNil(MacReaderWindowSizePersistence.restoredContentSize(from: store))

        MacReaderWindowSizePersistence.saveContentSize(
            CGSize(width: 980, height: 720),
            to: store
        )
        XCTAssertEqual(
            MacReaderWindowSizePersistence.restoredContentSize(from: store),
            CGSize(width: 980, height: 720)
        )

        MacReaderWindowSizePersistence.saveContentSize(
            CGSize(width: 200, height: 120),
            to: store
        )
        XCTAssertEqual(
            MacReaderWindowSizePersistence.restoredContentSize(from: store),
            MacReaderWindowSizePersistence.minimumContentSize
        )

        XCTAssertEqual(
            MacReaderWindowSizePersistence.fittedContentSize(
                CGSize(width: 1_200, height: 900),
                visibleFrame: CGRect(x: 0, y: 0, width: 800, height: 600)
            ),
            CGSize(width: 800, height: 600)
        )
    }

    func testClearHistoryClearsReadingStoreListAndSelectedDetail() {
        let store = InMemoryKeyValueStore()
        let (client, _) = MacTestSupport.makeAPIClient(store: store) { _ in
            throw MockURLProtocolError.unsupportedScenario
        }
        let readingStore = MacReadingStore(keyValueStore: store)
        let episode = Episode(id: "ep-1", title: "第一话", order: 1, updated_at: nil)
        let readerEpisode = MacReaderEpisode(episode: episode)
        let request = MacReaderLaunchRequest(
            comicId: "comic-1",
            comicTitle: "测试漫画",
            author: "作者",
            thumbPath: nil,
            thumbServer: nil,
            episodes: [readerEpisode],
            startEpisodeIndex: 0,
            startPageIndex: 0,
            restoreSavedProgress: false
        )
        readingStore.record(request: request, episode: readerEpisode, pageIndex: 3)

        let model = MacLibraryModel(
            client: client,
            readingStore: readingStore,
            blockedCategoriesStore: MacBlockedCategoriesStore(keyValueStore: store)
        )
        model.sidebarSelection = .history
        model.selectedComicID = "comic-1"
        model.detail = makeComicDetail(id: "comic-1")
        model.episodes = [episode]
        model.loadHistory()

        XCTAssertEqual(model.listItems.map(\.id), ["comic-1"])
        XCTAssertEqual(readingStore.progress(for: "comic-1")?.pageIndex, 3)

        model.clearHistory()

        XCTAssertTrue(readingStore.history.isEmpty)
        XCTAssertNil(readingStore.progress(for: "comic-1"))
        XCTAssertTrue(model.listItems.isEmpty)
        XCTAssertEqual(model.currentPage, 0)
        XCTAssertNil(model.selectedComicID)
        XCTAssertNil(model.detail)
        XCTAssertTrue(model.episodes.isEmpty)
    }

    private func makeComicDetail(id: String) -> ComicDetail {
        ComicDetail(
            id: id,
            title: "测试漫画",
            author: nil,
            description: nil,
            chineseTeam: nil,
            categories: nil,
            tags: nil,
            pagesCount: nil,
            epsCount: nil,
            finished: nil,
            updated_at: nil,
            created_at: nil,
            thumb: nil,
            creator: nil,
            totalViews: nil,
            totalLikes: nil,
            totalComments: nil,
            viewsCount: nil,
            likesCount: nil,
            commentsCount: nil,
            isFavourite: nil,
            isLiked: nil,
            allowDownload: nil,
            allowComment: nil
        )
    }
}
