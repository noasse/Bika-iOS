import XCTest
@testable import bika

@MainActor
final class ComicResultsViewModelTests: XCTestCase {
    override func setUp() {
        super.setUp()
        NavigationStateStore.shared.clearComicListState(for: ComicResultsQuery.favourites.restorationKey)
        NavigationStateStore.shared.clearComicListState(for: ComicResultsQuery.author("作者A").restorationKey)
    }

    override func tearDown() {
        NavigationStateStore.shared.clearComicListState(for: ComicResultsQuery.favourites.restorationKey)
        NavigationStateStore.shared.clearComicListState(for: ComicResultsQuery.author("作者A").restorationKey)
        TestSupport.restoreLiveDependencies()
        super.tearDown()
    }

    func testLoadFirstPageRestoresSavedPageSortAndAnchor() async throws {
        let navigationStateStore = NavigationStateStore.shared
        navigationStateStore.clearComicListState(for: ComicResultsQuery.favourites.restorationKey)
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
        let navigationStateStore = NavigationStateStore.shared
        navigationStateStore.clearComicListState(for: ComicResultsQuery.favourites.restorationKey)

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
        let navigationStateStore = NavigationStateStore.shared
        navigationStateStore.clearComicListState(for: ComicResultsQuery.favourites.restorationKey)

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
        let navigationStateStore = NavigationStateStore.shared
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
}

private func comicsPage(page: Int, pages: Int, docs: [[String: Any]]) -> [String: Any] {
    [
        "docs": docs,
        "total": docs.count,
        "limit": max(docs.count, 1),
        "page": page,
        "pages": pages,
    ]
}

private func comic(
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

private func comicDetailPayload(
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
