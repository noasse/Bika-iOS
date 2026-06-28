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

    func testMacZoomableImageLayoutFitsImageToViewportWidth() {
        let frame = MacZoomableImageLayout.fittedImageFrame(
            imageSize: CGSize(width: 800, height: 1_200),
            viewportSize: CGSize(width: 400, height: 700)
        )

        XCTAssertEqual(frame.origin.x, 0, accuracy: 0.01)
        XCTAssertEqual(frame.origin.y, 50, accuracy: 0.01)
        XCTAssertEqual(frame.size.width, 400, accuracy: 0.01)
        XCTAssertEqual(frame.size.height, 600, accuracy: 0.01)
    }

    func testMacZoomableImageLayoutUsesTapLocationAsZoomCenter() {
        let center = MacZoomableImageLayout.zoomCenter(
            tapLocation: CGPoint(x: 180, y: 240),
            imageFrame: CGRect(x: 40, y: 80, width: 360, height: 540)
        )

        XCTAssertEqual(center.x, 180, accuracy: 0.01)
        XCTAssertEqual(center.y, 240, accuracy: 0.01)
    }

    func testMacReaderViewModelFlushesCurrentProgressForWindowClose() {
        let store = InMemoryKeyValueStore()
        let readingStore = MacReadingStore(keyValueStore: store)
        let episode = Episode(id: "ep-1", title: "第一话", order: 1, updated_at: nil)
        let request = MacReaderLaunchRequest(
            comicId: "comic-progress",
            comicTitle: "进度漫画",
            author: "作者",
            thumbPath: nil,
            thumbServer: nil,
            episodes: [MacReaderEpisode(episode: episode)],
            startEpisodeIndex: 0,
            startPageIndex: 0,
            restoreSavedProgress: false
        )
        let viewModel = MacReaderViewModel(request: request, readingStore: readingStore)
        viewModel.currentPageIndex = 6

        viewModel.saveCurrentProgress()

        XCTAssertEqual(readingStore.progress(for: "comic-progress")?.pageIndex, 6)
    }

    func testMacReaderWindowPlansInitialWaterfallScrollForRestoredProgress() {
        let store = InMemoryKeyValueStore()
        let readingStore = MacReadingStore(keyValueStore: store)
        let episode = Episode(id: "ep-1", title: "第一话", order: 1, updated_at: nil)
        let request = MacReaderLaunchRequest(
            comicId: "comic-continue",
            comicTitle: "继续阅读漫画",
            author: "作者",
            thumbPath: nil,
            thumbServer: nil,
            episodes: [MacReaderEpisode(episode: episode)],
            startEpisodeIndex: 0,
            startPageIndex: 0,
            restoreSavedProgress: false
        )
        readingStore.record(
            request: request,
            episode: MacReaderEpisode(episode: episode),
            pageIndex: 5
        )

        let continueRequest = MacReaderLaunchRequest(
            comicId: "comic-continue",
            comicTitle: "继续阅读漫画",
            author: "作者",
            thumbPath: nil,
            thumbServer: nil,
            episodes: [MacReaderEpisode(episode: episode)],
            startEpisodeIndex: 0,
            startPageIndex: 0,
            restoreSavedProgress: true
        )
        let viewModel = MacReaderViewModel(
            request: continueRequest,
            readingStore: readingStore,
            keyValueStore: store
        )

        XCTAssertEqual(viewModel.currentPageIndex, 5)
        XCTAssertEqual(MacReaderWindowView.initialWaterfallScrollRequest(for: viewModel), 5)
    }

    func testMacSearchExpandsBracketedAliasesAndDeduplicatesResults() async throws {
        let requestKeywords = LockedValue<[String]>([])

        let (client, store) = MacTestSupport.makeAPIClient { request in
            let body = try XCTUnwrap(request.resolvedHTTPBodyData())
            let requestBody = try JSONDecoder().decode(MacSearchRequestBody.self, from: body)
            var keywords = requestKeywords.value
            keywords.append(requestBody.keyword)
            requestKeywords.value = keywords

            let docs: [[String: Any]]
            switch requestBody.keyword {
            case "生蚝（花生）":
                docs = [
                    macSearchComic(id: "comic-full", title: "完整作者名"),
                    macSearchComic(id: "comic-shared", title: "重复结果"),
                ]
            case "生蚝":
                docs = [
                    macSearchComic(id: "comic-main", title: "主名结果"),
                    macSearchComic(id: "comic-shared", title: "重复结果"),
                ]
            case "花生":
                docs = [
                    macSearchComic(id: "comic-alias", title: "括号名结果"),
                ]
            default:
                docs = []
            }

            return MacTestSupport.jsonResponse(data: [
                "comics": macSearchComicsPage(page: 1, pages: 1, docs: docs),
            ])
        }

        let model = MacLibraryModel(
            client: client,
            readingStore: MacReadingStore(keyValueStore: store),
            blockedCategoriesStore: MacBlockedCategoriesStore(keyValueStore: store)
        )
        model.searchText = "生蚝（花生）"

        await model.search(page: 1)

        XCTAssertEqual(requestKeywords.value, ["生蚝（花生）", "生蚝", "花生"])
        XCTAssertEqual(
            model.listItems.map(\.id),
            ["comic-full", "comic-shared", "comic-main", "comic-alias"]
        )
        XCTAssertEqual(model.currentPage, 1)
        XCTAssertEqual(model.totalPages, 1)
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

private nonisolated struct MacSearchRequestBody: Decodable {
    let keyword: String
    let sort: String?
    let categories: [String]?
}

private func macSearchComicsPage(page: Int, pages: Int, docs: [[String: Any]]) -> [String: Any] {
    [
        "docs": docs,
        "total": docs.count,
        "limit": max(docs.count, 1),
        "page": page,
        "pages": pages,
    ]
}

private func macSearchComic(id: String, title: String) -> [String: Any] {
    [
        "_id": id,
        "title": title,
        "author": "生蚝（花生）",
        "pagesCount": 1,
        "epsCount": 1,
        "finished": false,
        "categories": [],
        "thumb": [
            "originalName": "cover.jpg",
            "path": "static/\(id).jpg",
            "fileServer": "https://example.com",
        ],
    ]
}
