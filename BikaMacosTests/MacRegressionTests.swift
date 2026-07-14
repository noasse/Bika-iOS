import XCTest
@testable import BikaMacos

@MainActor
final class MacRegressionTests: XCTestCase {
    override func tearDown() {
        MacTestSupport.restoreLiveDependencies()
        super.tearDown()
    }

    func testCheckTokenClearsInvalidStoredTokenOnProfileFailure() async throws {
        let (client, store) = MacTestSupport.makeAPIClient { request in
            XCTAssertEqual(request.url?.path, "/users/profile")
            XCTAssertEqual(request.value(forHTTPHeaderField: "authorization"), "stale-token")
            return MacTestSupport.emptyHTTPResponse(statusCode: 401)
        }
        try await client.tokenStore.setToken("stale-token")
        let accountSession = AccountSessionStore(keyValueStore: store)
        _ = try accountSession.activate(userID: "mac-user")

        let model = MacLibraryModel(
            client: client,
            readingStore: MacReadingStore(
                keyValueStore: store,
                accountSessionStore: accountSession
            ),
            blockedCategoriesStore: MacBlockedCategoriesStore(keyValueStore: store),
            accountSessionStore: accountSession
        )

        await model.checkTokenIfNeeded()

        XCTAssertFalse(model.isAuthenticated)
        XCTAssertFalse(model.isCheckingToken)
        XCTAssertNil(accountSession.currentScope)
        XCTAssertNil(model.userProfile)
        XCTAssertNotNil(model.authError)
        let storedToken = try await client.tokenStore.getToken()
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

    func testMacReaderViewModelFlushesCurrentProgressForWindowClose() throws {
        let store = InMemoryKeyValueStore()
        let accountSession = AccountSessionStore(keyValueStore: store)
        _ = try accountSession.activate(userID: "mac-user")
        let readingStore = MacReadingStore(
            keyValueStore: store,
            accountSessionStore: accountSession
        )
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

    func testMacReaderWindowPlansInitialWaterfallScrollForRestoredProgress() throws {
        let store = InMemoryKeyValueStore()
        let accountSession = AccountSessionStore(keyValueStore: store)
        _ = try accountSession.activate(userID: "mac-user")
        let readingStore = MacReadingStore(
            keyValueStore: store,
            accountSessionStore: accountSession
        )
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

    func testMacPostCommentReplacesInFlightPaginationWithoutStaleWriteback() async {
        let pageTwoGate = TestAsyncGate()
        let replacementGate = TestAsyncGate()
        let firstPageRequestCount = LockedValue(0)
        let pageTwoStarted = LockedValue(false)
        let replacementStarted = LockedValue(false)

        let (client, _) = MacTestSupport.makeAPIClient { request in
            if request.httpMethod == "POST" {
                return MacTestSupport.jsonResponse(data: [:])
            }

            let page = MacTestSupport.page(from: request)
            if page == 2 {
                pageTwoStarted.value = true
                await pageTwoGate.wait()
                return MacTestSupport.jsonResponse(
                    data: macCommentsPage(
                        page: 2,
                        pages: 2,
                        docs: [macComment(id: "mac-stale-page-2", likesCount: 0, isLiked: false)]
                    )
                )
            }

            firstPageRequestCount.value += 1
            if firstPageRequestCount.value == 1 {
                return MacTestSupport.jsonResponse(
                    data: macCommentsPage(
                        page: 1,
                        pages: 2,
                        docs: [macComment(id: "mac-initial", likesCount: 0, isLiked: false)]
                    )
                )
            }

            replacementStarted.value = true
            await replacementGate.wait()
            return MacTestSupport.jsonResponse(
                data: macCommentsPage(
                    page: 1,
                    pages: 1,
                    docs: [macComment(id: "mac-fresh", likesCount: 0, isLiked: false)]
                )
            )
        }

        let model = MacCommentsModel(comicId: "comic-1", client: client)
        await model.loadFirstPage()

        let paginationTask = Task { await model.loadMore() }
        await waitUntil { pageTwoStarted.value }

        model.commentText = "新评论"
        let postTask = Task { await model.postComment() }
        await waitUntil(timeout: 0.5) { replacementStarted.value }

        guard replacementStarted.value else {
            await pageTwoGate.open()
            await replacementGate.open()
            await paginationTask.value
            await postTask.value
            return
        }

        await pageTwoGate.open()
        await paginationTask.value

        XCTAssertTrue(model.isLoading)
        XCTAssertFalse(model.comments.contains { $0.id == "mac-stale-page-2" })

        await replacementGate.open()
        await postTask.value

        XCTAssertEqual(model.comments.map(\.id), ["mac-fresh"])
        XCTAssertEqual(model.currentPage, 1)
        XCTAssertFalse(model.isLoading)
    }

    func testMacPostReplyReplacesInFlightPaginationWithoutStaleWriteback() async {
        let pageTwoGate = TestAsyncGate()
        let replacementGate = TestAsyncGate()
        let firstPageRequestCount = LockedValue(0)
        let pageTwoStarted = LockedValue(false)
        let replacementStarted = LockedValue(false)

        let (client, _) = MacTestSupport.makeAPIClient { request in
            if request.httpMethod == "POST" {
                return MacTestSupport.jsonResponse(data: [:])
            }

            let page = MacTestSupport.page(from: request)
            if page == 2 {
                pageTwoStarted.value = true
                await pageTwoGate.wait()
                return MacTestSupport.jsonResponse(
                    data: macChildCommentsPage(
                        page: 2,
                        pages: 2,
                        docs: [macComment(id: "mac-stale-child-page-2", likesCount: 0, isLiked: false)]
                    )
                )
            }

            firstPageRequestCount.value += 1
            if firstPageRequestCount.value == 1 {
                return MacTestSupport.jsonResponse(
                    data: macChildCommentsPage(
                        page: 1,
                        pages: 2,
                        docs: [macComment(id: "mac-initial-child", likesCount: 0, isLiked: false)]
                    )
                )
            }

            replacementStarted.value = true
            await replacementGate.wait()
            return MacTestSupport.jsonResponse(
                data: macChildCommentsPage(
                    page: 1,
                    pages: 1,
                    docs: [macComment(id: "mac-fresh-child", likesCount: 0, isLiked: false)]
                )
            )
        }

        let model = MacChildCommentsModel(commentId: "comment-1", client: client)
        await model.loadFirstPage()

        let paginationTask = Task { await model.loadMore() }
        await waitUntil { pageTwoStarted.value }

        model.replyText = "新回复"
        let postTask = Task { await model.postReply() }
        await waitUntil(timeout: 0.5) { replacementStarted.value }

        guard replacementStarted.value else {
            await pageTwoGate.open()
            await replacementGate.open()
            await paginationTask.value
            await postTask.value
            return
        }

        await pageTwoGate.open()
        await paginationTask.value

        XCTAssertTrue(model.isLoading)
        XCTAssertFalse(model.comments.contains { $0.id == "mac-stale-child-page-2" })

        await replacementGate.open()
        await postTask.value

        XCTAssertEqual(model.comments.map(\.id), ["mac-fresh-child"])
        XCTAssertEqual(model.currentPage, 1)
        XCTAssertFalse(model.isLoading)
    }

    func testMacRootLikeUsesServerUnlikeAndIgnoresDuplicateInFlightRequest() async {
        let likeGate = TestAsyncGate()
        let likeRequestCount = LockedValue(0)

        let (client, _) = MacTestSupport.makeAPIClient { request in
            if request.url?.path == "/comments/mac-root-like/like" {
                likeRequestCount.value += 1
                await likeGate.wait()
                return MacTestSupport.jsonResponse(data: ["action": "unlike"])
            }

            return MacTestSupport.jsonResponse(
                data: macCommentsPage(
                    page: 1,
                    pages: 1,
                    docs: [macComment(id: "mac-root-like", likesCount: 4, isLiked: true)]
                )
            )
        }

        let model = MacCommentsModel(comicId: "comic-1", client: client)
        await model.loadFirstPage()

        let firstLikeTask = Task { await model.likeComment(id: "mac-root-like") }
        await waitUntil { likeRequestCount.value == 1 }

        let duplicateFinished = LockedValue(false)
        let duplicateLikeTask = Task {
            await model.likeComment(id: "mac-root-like")
            duplicateFinished.value = true
        }
        await waitUntil { duplicateFinished.value || likeRequestCount.value > 1 }

        XCTAssertTrue(duplicateFinished.value)
        XCTAssertEqual(likeRequestCount.value, 1)

        await likeGate.open()
        await firstLikeTask.value
        await duplicateLikeTask.value

        XCTAssertEqual(model.comments.first?.isLiked, false)
        XCTAssertEqual(model.comments.first?.likesCount, 3)
    }

    func testMacChildLikeUsesServerLikeAndIgnoresDuplicateInFlightRequest() async {
        let likeGate = TestAsyncGate()
        let likeRequestCount = LockedValue(0)

        let (client, _) = MacTestSupport.makeAPIClient { request in
            if request.url?.path == "/comments/mac-child-like/like" {
                likeRequestCount.value += 1
                await likeGate.wait()
                return MacTestSupport.jsonResponse(data: ["action": "like"])
            }

            return MacTestSupport.jsonResponse(
                data: macChildCommentsPage(
                    page: 1,
                    pages: 1,
                    docs: [macComment(id: "mac-child-like", likesCount: 0, isLiked: false)]
                )
            )
        }

        let model = MacChildCommentsModel(commentId: "comment-1", client: client)
        await model.loadFirstPage()

        let firstLikeTask = Task { await model.likeComment(id: "mac-child-like") }
        await waitUntil { likeRequestCount.value == 1 }

        let duplicateFinished = LockedValue(false)
        let duplicateLikeTask = Task {
            await model.likeComment(id: "mac-child-like")
            duplicateFinished.value = true
        }
        await waitUntil { duplicateFinished.value || likeRequestCount.value > 1 }

        XCTAssertTrue(duplicateFinished.value)
        XCTAssertEqual(likeRequestCount.value, 1)

        await likeGate.open()
        await firstLikeTask.value
        await duplicateLikeTask.value

        XCTAssertEqual(model.comments.first?.isLiked, true)
        XCTAssertEqual(model.comments.first?.likesCount, 1)
    }

    func testClearHistoryClearsReadingStoreListAndSelectedDetail() throws {
        let store = InMemoryKeyValueStore()
        let (client, _) = MacTestSupport.makeAPIClient(store: store) { _ in
            throw MockURLProtocolError.unsupportedScenario
        }
        let accountSession = AccountSessionStore(keyValueStore: store)
        _ = try accountSession.activate(userID: "mac-user")
        let readingStore = MacReadingStore(
            keyValueStore: store,
            accountSessionStore: accountSession
        )
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

    func testMacReadingStoreIsolatesAccountsAndClearsOrphanProgressOnlyInCurrentScope() throws {
        let store = InMemoryKeyValueStore()
        let accountSession = AccountSessionStore(keyValueStore: store)
        let readingStore = MacReadingStore(
            keyValueStore: store,
            accountSessionStore: accountSession
        )
        let episode = Episode(id: "ep-1", title: "第一话", order: 1, updated_at: nil)
        let readerEpisode = MacReaderEpisode(episode: episode)
        let request = MacReaderLaunchRequest(
            comicId: "comic-a",
            comicTitle: "账号 A 漫画",
            author: nil,
            thumbPath: nil,
            thumbServer: nil,
            episodes: [readerEpisode],
            startEpisodeIndex: 0,
            startPageIndex: 0,
            restoreSavedProgress: false
        )

        let scopeA = try accountSession.activate(userID: "mac-user-a")
        readingStore.record(request: request, episode: readerEpisode, pageIndex: 7)
        let orphanAKey = "macReadProgress.account.\(scopeA.rawValue).orphan-a"
        store.set(
            try JSONEncoder().encode(
                PersistenceEnvelope(
                    payload: MacReadingProgress(
                        episodeOrder: 1,
                        episodeTitle: "孤儿 A",
                        pageIndex: 2
                    )
                )
            ),
            forKey: orphanAKey
        )

        _ = try accountSession.activate(userID: "mac-user-b")
        XCTAssertTrue(readingStore.history.isEmpty)
        XCTAssertNil(readingStore.progress(for: "comic-a"))

        _ = try accountSession.activate(userID: "mac-user-a")
        XCTAssertEqual(readingStore.progress(for: "comic-a")?.pageIndex, 7)
        readingStore.clearHistory()
        XCTAssertNil(store.data(forKey: orphanAKey))

        _ = try accountSession.activate(userID: "mac-user-b")
        XCTAssertTrue(readingStore.history.isEmpty)
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

nonisolated private func macSearchComicsPage(page: Int, pages: Int, docs: [[String: Any]]) -> [String: Any] {
    [
        "docs": docs,
        "total": docs.count,
        "limit": max(docs.count, 1),
        "page": page,
        "pages": pages,
    ]
}

nonisolated private func macSearchComic(id: String, title: String) -> [String: Any] {
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

nonisolated private func macComment(id: String, likesCount: Int, isLiked: Bool) -> [String: Any] {
    [
        "_id": id,
        "content": id,
        "_user": [
            "_id": "user-\(id)",
            "name": "评论用户",
        ],
        "totalComments": 0,
        "commentsCount": 0,
        "isTop": false,
        "hide": false,
        "created_at": "2024-01-01T00:00:00.000Z",
        "likesCount": likesCount,
        "isLiked": isLiked,
    ]
}

nonisolated private func macCommentsPage(page: Int, pages: Int, docs: [[String: Any]]) -> [String: Any] {
    [
        "comments": [
            "docs": docs,
            "total": docs.count,
            "limit": max(docs.count, 1),
            "page": page,
            "pages": pages,
        ],
        "topComments": [],
    ]
}

nonisolated private func macChildCommentsPage(page: Int, pages: Int, docs: [[String: Any]]) -> [String: Any] {
    [
        "comments": [
            "docs": docs,
            "total": docs.count,
            "limit": max(docs.count, 1),
            "page": page,
            "pages": pages,
        ],
    ]
}
