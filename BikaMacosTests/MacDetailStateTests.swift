import XCTest
@testable import BikaMacos

@MainActor
final class MacDetailStateTests: XCTestCase {
    override func tearDown() {
        MacTestSupport.restoreLiveDependencies()
        super.tearDown()
    }

    func testDetailBecomesVisibleBeforeEpisodesFinish() async {
        let episodeRequestEntered = LockedValue(false)
        let episodeGate = MacAsyncGate()
        let model = makeModel { request in
            switch request.url?.path {
            case "/comics/comic-1":
                return detailResponse(id: "comic-1", title: "漫画一")
            case "/comics/comic-1/eps":
                episodeRequestEntered.value = true
                await episodeGate.wait()
                return episodesResponse(page: 1, pages: 1, docs: [episode(id: "ep-1", order: 1)])
            case "/comics/comic-1/recommendation":
                return MacTestSupport.jsonResponse(data: ["comics": []])
            default:
                return MacTestSupport.jsonResponse(data: [:])
            }
        }

        let loadTask = Task { await model.loadDetail(comicId: "comic-1") }
        await waitUntil {
            episodeRequestEntered.value && model.detail?.id == "comic-1"
        }

        XCTAssertEqual(model.detail?.title, "漫画一")
        XCTAssertFalse(model.isDetailLoading)
        XCTAssertTrue(model.isLoadingEpisodes)

        await episodeGate.open()
        await loadTask.value
        XCTAssertEqual(model.episodes.map(\.id), ["ep-1"])
    }

    func testEpisodeFailureDoesNotDiscardSuccessfulDetail() async {
        let model = makeModel { request in
            switch request.url?.path {
            case "/comics/comic-1":
                return detailResponse(id: "comic-1", title: "漫画一")
            case "/comics/comic-1/eps":
                return MacTestSupport.jsonResponse(code: 500, message: "章节失败", data: [:])
            case "/comics/comic-1/recommendation":
                return MacTestSupport.jsonResponse(data: ["comics": []])
            default:
                return MacTestSupport.jsonResponse(data: [:])
            }
        }

        await model.loadDetail(comicId: "comic-1")

        XCTAssertEqual(model.detail?.id, "comic-1")
        XCTAssertTrue(model.episodes.isEmpty)
        XCTAssertNotNil(model.episodesError)
        XCTAssertNil(model.detailError)
    }

    func testEpisodePaginationStopsWhenReturnedPageDoesNotAdvance() async {
        let episodeRequestCount = LockedValue(0)
        let model = makeModel { request in
            switch request.url?.path {
            case "/comics/comic-1":
                return detailResponse(id: "comic-1", title: "漫画一")
            case "/comics/comic-1/eps":
                episodeRequestCount.value += 1
                if episodeRequestCount.value == 1 {
                    return episodesResponse(page: 1, pages: 2, docs: [episode(id: "ep-1", order: 1)])
                }
                if episodeRequestCount.value == 2 {
                    return episodesResponse(page: 1, pages: 2, docs: [episode(id: "ep-repeat", order: 2)])
                }
                throw MockURLProtocolError.unsupportedScenario
            case "/comics/comic-1/recommendation":
                return MacTestSupport.jsonResponse(data: ["comics": []])
            default:
                return MacTestSupport.jsonResponse(data: [:])
            }
        }

        await model.loadDetail(comicId: "comic-1")

        XCTAssertEqual(episodeRequestCount.value, 2)
        XCTAssertEqual(model.episodes.map(\.id), ["ep-1"])
        XCTAssertNotNil(model.episodesError)
        XCTAssertEqual(model.detail?.id, "comic-1")
    }

    func testSwitchingComicRejectsLateEpisodesFromPreviousComic() async {
        let oldEpisodeRequestEntered = LockedValue(false)
        let oldEpisodeGate = MacAsyncGate()
        let model = makeModel { request in
            switch request.url?.path {
            case "/comics/comic-1":
                return detailResponse(id: "comic-1", title: "漫画一")
            case "/comics/comic-1/eps":
                oldEpisodeRequestEntered.value = true
                await oldEpisodeGate.wait()
                return episodesResponse(page: 1, pages: 1, docs: [episode(id: "old-ep", order: 1)])
            case "/comics/comic-2":
                return detailResponse(id: "comic-2", title: "漫画二")
            case "/comics/comic-2/eps":
                return episodesResponse(page: 1, pages: 1, docs: [episode(id: "new-ep", order: 1)])
            case "/comics/comic-1/recommendation", "/comics/comic-2/recommendation":
                return MacTestSupport.jsonResponse(data: ["comics": []])
            default:
                return MacTestSupport.jsonResponse(data: [:])
            }
        }

        let oldTask = Task { await model.loadDetail(comicId: "comic-1") }
        await waitUntil { oldEpisodeRequestEntered.value }

        await model.loadDetail(comicId: "comic-2")
        await oldEpisodeGate.open()
        await oldTask.value

        XCTAssertEqual(model.detail?.id, "comic-2")
        XCTAssertEqual(model.episodes.map(\.id), ["new-ep"])
    }

    func testFavouriteCannotOverlapLikeMutation() async {
        let likeRequestEntered = LockedValue(false)
        let favouriteRequestCount = LockedValue(0)
        let likeGate = MacAsyncGate()
        let model = makeModel { request in
            let method = request.httpMethod ?? "GET"
            switch (method, request.url?.path) {
            case ("POST", "/comics/comic-1/like"):
                likeRequestEntered.value = true
                await likeGate.wait()
                return MacTestSupport.jsonResponse(data: ["action": "like"])
            case ("POST", "/comics/comic-1/favourite"):
                favouriteRequestCount.value += 1
                return MacTestSupport.jsonResponse(data: [:])
            case ("GET", "/comics/comic-1"):
                return detailResponse(id: "comic-1", title: "刷新详情")
            default:
                return MacTestSupport.jsonResponse(data: [:])
            }
        }
        model.selectedComicID = "comic-1"
        model.detail = makeDetail(id: "comic-1", title: "原详情")

        let likeTask = Task { await model.toggleLike() }
        await waitUntil { likeRequestEntered.value }
        await model.toggleFavourite()

        XCTAssertEqual(favouriteRequestCount.value, 0)
        XCTAssertTrue(model.isTogglingLike)
        XCTAssertFalse(model.isTogglingFavourite)

        await likeGate.open()
        await likeTask.value
    }

    func testMutationRefreshWithMissingComicKeepsExistingDetail() async {
        let model = makeModel { request in
            let method = request.httpMethod ?? "GET"
            if method == "POST", request.url?.path == "/comics/comic-1/like" {
                return MacTestSupport.jsonResponse(data: ["action": "like"])
            }
            return MacTestSupport.jsonResponse(data: [:])
        }
        model.selectedComicID = "comic-1"
        model.detail = makeDetail(id: "comic-1", title: "原详情")

        await model.toggleLike()

        XCTAssertEqual(model.detail?.title, "原详情")
    }

    func testFailedMutationForPreviousComicDoesNotOverwriteCurrentDetailError() async {
        let mutationStarted = LockedValue(false)
        let mutationGate = MacAsyncGate()
        let model = makeModel { request in
            if request.httpMethod == "POST", request.url?.path == "/comics/comic-1/like" {
                mutationStarted.value = true
                await mutationGate.wait()
                throw URLError(.timedOut)
            }
            return MacTestSupport.jsonResponse(data: [:])
        }
        model.selectedComicID = "comic-1"
        model.detail = makeDetail(id: "comic-1", title: "漫画一")

        let mutationTask = Task { await model.toggleLike() }
        await waitUntil { mutationStarted.value }
        model.selectedComicID = "comic-2"
        model.detail = makeDetail(id: "comic-2", title: "漫画二")
        model.detailError = nil

        await mutationGate.open()
        await mutationTask.value

        XCTAssertNil(model.detailError)
        XCTAssertEqual(model.detail?.id, "comic-2")
    }

    private func makeModel(handler: @escaping MockURLProtocolHandler) -> MacLibraryModel {
        let (client, store) = MacTestSupport.makeAPIClient(handler: handler)
        return MacLibraryModel(
            client: client,
            readingStore: MacReadingStore(keyValueStore: store),
            blockedCategoriesStore: MacBlockedCategoriesStore(keyValueStore: store)
        )
    }
}

private actor MacAsyncGate {
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func open() {
        continuation?.resume()
        continuation = nil
    }
}

nonisolated private func detailResponse(id: String, title: String) -> MockHTTPResponse {
    MacTestSupport.jsonResponse(data: ["comic": detailJSON(id: id, title: title)])
}

nonisolated private func detailJSON(id: String, title: String) -> [String: Any] {
    [
        "_id": id,
        "title": title,
        "isLiked": false,
        "isFavourite": false,
    ]
}

nonisolated private func episodesResponse(page: Int, pages: Int, docs: [[String: Any]]) -> MockHTTPResponse {
    MacTestSupport.jsonResponse(data: [
        "eps": [
            "docs": docs,
            "total": docs.count,
            "limit": max(docs.count, 1),
            "page": page,
            "pages": pages,
        ],
    ])
}

nonisolated private func episode(id: String, order: Int) -> [String: Any] {
    [
        "_id": id,
        "title": "第\(order)话",
        "order": order,
    ]
}

nonisolated private func makeDetail(id: String, title: String) -> ComicDetail {
    ComicDetail(
        id: id,
        title: title,
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
