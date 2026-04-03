import XCTest
@testable import bika

@MainActor
final class ComicResultsViewModelTests: XCTestCase {
    override func setUp() {
        super.setUp()
        NavigationStateStore.shared.clearComicListState(for: ComicResultsQuery.favourites.restorationKey)
    }

    override func tearDown() {
        NavigationStateStore.shared.clearComicListState(for: ComicResultsQuery.favourites.restorationKey)
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

private func comic(id: String, title: String) -> [String: Any] {
    [
        "_id": id,
        "title": title,
        "author": "作者",
        "totalViews": 1,
        "totalLikes": 1,
        "pagesCount": 1,
        "epsCount": 1,
        "finished": false,
        "categories": [],
        "thumb": [
            "originalName": "cover.jpg",
            "path": "static/\(id).jpg",
            "fileServer": "https://example.com",
        ],
        "likesCount": 1,
    ]
}
