import XCTest
@testable import bika

@MainActor
final class ComicResultsViewModelTests: XCTestCase {
    override func tearDown() {
        TestSupport.restoreLiveDependencies()
        super.tearDown()
    }

    func testNewNavigationStateStoreDoesNotInheritAnotherInstancesState() {
        let firstStore = NavigationStateStore()
        firstStore.saveComicListState(
            ComicListNavigationState(
                currentPage: 3,
                sortModeRawValue: SortMode.views.rawValue,
                anchorComicID: "comic-3"
            ),
            for: ComicResultsQuery.favourites.restorationKey
        )

        let secondStore = NavigationStateStore()

        XCTAssertNil(secondStore.comicListState(for: ComicResultsQuery.favourites.restorationKey))
    }

    func testLoadFirstPageRestoresSavedPageSortAndAnchor() async throws {
        let navigationStateStore = NavigationStateStore()
        navigationStateStore.saveComicListState(
            ComicListNavigationState(
                currentPage: 2,
                sortModeRawValue: SortMode.liked.rawValue,
                anchorComicID: "comic-2"
            ),
            for: ComicResultsQuery.favourites.restorationKey
        )

        let (client, store) = TestSupport.makeAPIClient { request in
            XCTAssertEqual(request.url?.path, "/users/favourite")
            XCTAssertEqual(TestSupport.queryValue(named: "page", from: request), "2")
            XCTAssertEqual(TestSupport.queryValue(named: "s", from: request), SortMode.liked.rawValue)
            return TestSupport.jsonResponse(data: [
                "comics": comicsPage(page: 2, pages: 3, docs: [
                    comic(id: "comic-2", title: "收藏第二页"),
                ]),
            ])
        }

        let viewModel = ComicResultsViewModel(
            query: .favourites,
            client: client,
            keyValueStore: store,
            navigationStateStore: navigationStateStore
        )
        await viewModel.loadFirstPage()

        XCTAssertEqual(viewModel.sortMode, .liked)
        XCTAssertEqual(viewModel.currentPage, 2)
        XCTAssertEqual(viewModel.totalPages, 3)
        XCTAssertEqual(viewModel.pendingRestoreComicID, "comic-2")
        XCTAssertEqual(viewModel.comics.map(\.id), ["comic-2"])
    }

    func testPersistPageRestoresLastVisitedPageForNewViewModel() async {
        let navigationStateStore = NavigationStateStore()

        let (client, store) = TestSupport.makeAPIClient { request in
            let page = Int(TestSupport.queryValue(named: "page", from: request) ?? "1") ?? 1
            return TestSupport.jsonResponse(data: [
                "comics": comicsPage(page: page, pages: 3, docs: [
                    comic(id: "comic-\(page)", title: "Page \(page)"),
                ]),
            ])
        }

        let viewModel = ComicResultsViewModel(
            query: .favourites,
            client: client,
            keyValueStore: store,
            navigationStateStore: navigationStateStore
        )
        await viewModel.loadPage(2)
        viewModel.rememberNavigationAnchor(comicID: "comic-2")
        viewModel.persistPage()

        XCTAssertEqual(store.integer(forKey: ComicResultsQuery.favourites.pageStorageKey), 2)

        let restored = ComicResultsViewModel(
            query: .favourites,
            client: client,
            keyValueStore: store,
            navigationStateStore: navigationStateStore
        )
        await restored.loadFirstPage()

        XCTAssertEqual(restored.currentPage, 2)
        XCTAssertEqual(restored.pendingRestoreComicID, "comic-2")
        XCTAssertEqual(restored.comics.map(\.id), ["comic-2"])
    }

    func testChangeSortClearsAnchorAndLoadsFirstPage() async {
        let requestedSorts = LockedValue<[String]>([])
        let navigationStateStore = NavigationStateStore()

        let (client, store) = TestSupport.makeAPIClient { request in
            var values = requestedSorts.value
            values.append(TestSupport.queryValue(named: "s", from: request) ?? "")
            requestedSorts.value = values

            let page = Int(TestSupport.queryValue(named: "page", from: request) ?? "1") ?? 1
            return TestSupport.jsonResponse(data: [
                "comics": comicsPage(page: page, pages: 2, docs: [
                    comic(id: "comic-\(page)", title: "Page \(page)"),
                ]),
            ])
        }

        let viewModel = ComicResultsViewModel(
            query: .favourites,
            client: client,
            keyValueStore: store,
            navigationStateStore: navigationStateStore
        )
        await viewModel.loadPage(2)
        viewModel.rememberNavigationAnchor(comicID: "comic-2")

        await viewModel.changeSort(.views)

        XCTAssertEqual(viewModel.sortMode, .views)
        XCTAssertEqual(viewModel.currentPage, 1)
        XCTAssertNil(viewModel.pendingRestoreComicID)
        XCTAssertEqual(requestedSorts.value, [SortMode.defaultSort.rawValue, SortMode.views.rawValue])
        XCTAssertNil(navigationStateStore.comicListState(for: ComicResultsQuery.favourites.restorationKey)?.anchorComicID)
    }

    func testAuthorQueryHydratesCanonicalMetricsFromComicDetail() async {
        let navigationStateStore = NavigationStateStore()
        let authorQuery = ComicResultsQuery.author("作者A")

        let requestedPaths = LockedValue<[String]>([])
        let (client, store) = TestSupport.makeAPIClient { request in
            let path = request.url?.path ?? ""
            var paths = requestedPaths.value
            paths.append(path)
            requestedPaths.value = paths

            switch (request.httpMethod ?? "", path) {
            case ("POST", "/comics/advanced-search"):
                return TestSupport.jsonResponse(data: [
                    "comics": comicsPage(page: 1, pages: 1, docs: [
                        comic(
                            id: "comic-author-1",
                            title: "作者作品",
                            author: "作者A",
                            totalViews: nil,
                            totalLikes: nil,
                            likesCount: 7
                        ),
                    ]),
                ])
            case ("GET", "/comics/comic-author-1"):
                return TestSupport.jsonResponse(data: [
                    "comic": comicDetailPayload(
                        id: "comic-author-1",
                        title: "作者作品",
                        author: "作者A",
                        totalViews: 321,
                        totalLikes: 654,
                        likesCount: 7
                    ),
                ])
            default:
                return TestSupport.jsonResponse(data: [:])
            }
        }

        let viewModel = ComicResultsViewModel(
            query: authorQuery,
            client: client,
            keyValueStore: store,
            navigationStateStore: navigationStateStore
        )

        await viewModel.loadPage(1)

        XCTAssertEqual(requestedPaths.value, ["/comics/advanced-search", "/comics/comic-author-1"])
        XCTAssertEqual(viewModel.comics.map(\.id), ["comic-author-1"])
        XCTAssertEqual(viewModel.comics.first?.displayViews, 321)
        XCTAssertEqual(viewModel.comics.first?.displayLikes, 654)
        XCTAssertEqual(viewModel.comics.first?.likesCount, 7)
    }

    func testAuthorCanonicalMetricsHydrationNeverExceedsFourConcurrentRequests() async {
        let probe = CanonicalMetricsConcurrencyProbe()
        let docs = LockedValue((1...10).map {
            comic(
                id: "comic-author-\($0)",
                title: "作者作品 \($0)",
                author: "作者A"
            )
        })
        let (client, store) = TestSupport.makeAPIClient { request in
            let path = request.url?.path ?? ""
            if request.httpMethod == "POST" {
                return TestSupport.jsonResponse(data: [
                    "comics": comicsPage(page: 1, pages: 1, docs: docs.value),
                ])
            }

            let comicID = path.components(separatedBy: "/").last ?? "missing"
            probe.begin()
            do {
                try await Task.sleep(for: .milliseconds(100))
                probe.finish(cancelled: false)
                return TestSupport.jsonResponse(data: [
                    "comic": comicDetailPayload(
                        id: comicID,
                        title: comicID,
                        author: "作者A",
                        totalViews: 100,
                        totalLikes: 200,
                        likesCount: 7
                    ),
                ])
            } catch {
                probe.finish(cancelled: error is CancellationError)
                throw error
            }
        }
        let viewModel = ComicResultsViewModel(
            query: .author("作者A"),
            client: client,
            keyValueStore: store,
            navigationStateStore: .shared
        )

        await viewModel.loadPage(1)

        XCTAssertEqual(probe.startedCount, 10)
        XCTAssertLessThanOrEqual(probe.maximumConcurrentCount, 4)
        XCTAssertEqual(probe.activeCount, 0)
    }

    func testLoadingNewAuthorPageCancelsOldCanonicalMetricsHydration() async {
        let probe = CanonicalMetricsConcurrencyProbe()
        let oldDocs = LockedValue((1...8).map {
            comic(
                id: "old-comic-\($0)",
                title: "旧作品 \($0)",
                author: "作者A"
            )
        })
        let (client, store) = TestSupport.makeAPIClient { request in
            let path = request.url?.path ?? ""
            if request.httpMethod == "POST" {
                let page = TestSupport.page(from: request)
                let docs = page == 1
                    ? oldDocs.value
                    : [comic(id: "new-comic", title: "新作品", author: "作者A")]
                return TestSupport.jsonResponse(data: [
                    "comics": comicsPage(page: page, pages: 2, docs: docs),
                ])
            }

            let comicID = path.components(separatedBy: "/").last ?? "missing"
            if comicID.hasPrefix("old-comic-") {
                probe.begin()
                do {
                    try await Task.sleep(for: .seconds(30))
                    probe.finish(cancelled: false)
                } catch {
                    probe.finish(cancelled: error is CancellationError)
                    throw error
                }
            }

            return TestSupport.jsonResponse(data: [
                "comic": comicDetailPayload(
                    id: comicID,
                    title: comicID,
                    author: "作者A",
                    totalViews: 999,
                    totalLikes: 888,
                    likesCount: 7
                ),
            ])
        }
        let viewModel = ComicResultsViewModel(
            query: .author("作者A"),
            client: client,
            keyValueStore: store,
            navigationStateStore: .shared
        )

        let firstPageLoad = Task { await viewModel.loadPage(1) }
        await waitUntil { probe.startedCount >= 4 }

        await viewModel.loadPage(2)
        await waitUntil { probe.cancelledCount >= 4 }
        await firstPageLoad.value

        XCTAssertEqual(probe.startedCount, 4)
        XCTAssertEqual(viewModel.currentPage, 2)
        XCTAssertEqual(viewModel.comics.map(\.id), ["new-comic"])
        XCTAssertEqual(viewModel.comics.first?.displayViews, 999)
        XCTAssertEqual(viewModel.comics.first?.displayLikes, 888)
    }
}

nonisolated private func comicsPage(page: Int, pages: Int, docs: [[String: Any]]) -> [String: Any] {
    [
        "docs": docs,
        "total": docs.count,
        "limit": max(docs.count, 1),
        "page": page,
        "pages": pages,
    ]
}

nonisolated private func comic(
    id: String,
    title: String,
    author: String = "作者",
    totalViews: Int? = 1,
    totalLikes: Int? = 1,
    likesCount: Int? = 1
) -> [String: Any] {
    var payload: [String: Any] = [
        "_id": id,
        "title": title,
        "author": author,
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

    if let totalViews {
        payload["totalViews"] = totalViews
    }

    if let totalLikes {
        payload["totalLikes"] = totalLikes
    }

    if let likesCount {
        payload["likesCount"] = likesCount
    }

    return payload
}

nonisolated private func comicDetailPayload(
    id: String,
    title: String,
    author: String,
    totalViews: Int,
    totalLikes: Int,
    likesCount: Int
) -> [String: Any] {
    [
        "_id": id,
        "title": title,
        "author": author,
        "description": "详情",
        "chineseTeam": "汉化组",
        "categories": [],
        "tags": [],
        "pagesCount": 1,
        "epsCount": 1,
        "finished": false,
        "updated_at": "2026-04-07T00:00:00.000Z",
        "created_at": "2026-04-07T00:00:00.000Z",
        "thumb": [
            "originalName": "cover.jpg",
            "path": "static/\(id).jpg",
            "fileServer": "https://example.com",
        ],
        "creator": [
            "_id": "creator-1",
            "name": "作者A",
            "avatar": [
                "originalName": "avatar.jpg",
                "path": "static/avatar.jpg",
                "fileServer": "https://example.com",
            ],
        ],
        "totalViews": totalViews,
        "totalLikes": totalLikes,
        "totalComments": 0,
        "viewsCount": totalViews,
        "likesCount": likesCount,
        "commentsCount": 0,
        "isFavourite": false,
        "isLiked": false,
        "allowDownload": true,
        "allowComment": true,
    ]
}

private final class CanonicalMetricsConcurrencyProbe: @unchecked Sendable {
    private struct State {
        var activeCount = 0
        var maximumConcurrentCount = 0
        var startedCount = 0
        var cancelledCount = 0
    }

    private let lock = NSLock()
    private var state = State()

    var activeCount: Int { lock.withLock { state.activeCount } }
    var maximumConcurrentCount: Int { lock.withLock { state.maximumConcurrentCount } }
    var startedCount: Int { lock.withLock { state.startedCount } }
    var cancelledCount: Int { lock.withLock { state.cancelledCount } }

    func begin() {
        lock.withLock {
            state.activeCount += 1
            state.startedCount += 1
            state.maximumConcurrentCount = max(
                state.maximumConcurrentCount,
                state.activeCount
            )
        }
    }

    func finish(cancelled: Bool) {
        lock.withLock {
            state.activeCount = max(0, state.activeCount - 1)
            if cancelled {
                state.cancelledCount += 1
            }
        }
    }
}
