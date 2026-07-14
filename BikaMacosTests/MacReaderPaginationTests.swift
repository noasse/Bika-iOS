import XCTest
@testable import BikaMacos

@MainActor
final class MacReaderPaginationTests: XCTestCase {
    override func tearDown() {
        MacTestSupport.restoreLiveDependencies()
        super.tearDown()
    }

    func testSubsequentPageFailurePreservesLoadedPages() async throws {
        let (client, store) = MacTestSupport.makeAPIClient { request in
            if MacTestSupport.page(from: request) == 1 {
                return MacTestSupport.jsonResponse(data: [
                    "pages": macReaderPagePayload(
                        page: 1,
                        pages: 2,
                        docs: [macReaderPage(id: "page-1")]
                    ),
                ])
            }

            return MacTestSupport.emptyHTTPResponse(statusCode: 500)
        }
        let viewModel = try makeViewModel(client: client, store: store)

        await viewModel.startIfNeeded()

        XCTAssertEqual(viewModel.pages.compactMap(\.id), ["page-1"])
        XCTAssertNotNil(viewModel.partialErrorMessage)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isLoading)
    }

    func testRepeatedReturnedPageStopsWithVisiblePartialError() async throws {
        let requestCount = LockedValue(0)
        let (client, store) = MacTestSupport.makeAPIClient { request in
            requestCount.value += 1
            if MacTestSupport.page(from: request) == 1 {
                return MacTestSupport.jsonResponse(data: [
                    "pages": macReaderPagePayload(
                        page: 1,
                        pages: 2,
                        docs: [macReaderPage(id: "page-1")]
                    ),
                ])
            }

            return MacTestSupport.jsonResponse(data: [
                "pages": macReaderPagePayload(
                    page: 1,
                    pages: 2,
                    docs: [macReaderPage(id: "repeated-page")]
                ),
            ])
        }
        let viewModel = try makeViewModel(client: client, store: store)

        await viewModel.startIfNeeded()

        XCTAssertEqual(requestCount.value, 2)
        XCTAssertEqual(viewModel.pages.compactMap(\.id), ["page-1"])
        XCTAssertNotNil(viewModel.partialErrorMessage)
    }

    func testEmptyIntermediatePageIsAVisiblePaginationError() async throws {
        let (client, store) = MacTestSupport.makeAPIClient { _ in
            MacTestSupport.jsonResponse(data: [
                "pages": macReaderPagePayload(page: 1, pages: 2, docs: []),
            ])
        }
        let viewModel = try makeViewModel(client: client, store: store)

        await viewModel.startIfNeeded()

        XCTAssertTrue(viewModel.pages.isEmpty)
        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertNil(viewModel.partialErrorMessage)
    }

    func testRetryKeepsPartialPagesUntilSuccessfulAtomicReplacement() async throws {
        let requestCount = LockedValue(0)
        let retryGate = TestAsyncGate()
        let (client, store) = MacTestSupport.makeAPIClient { request in
            requestCount.value += 1
            let count = requestCount.value

            switch count {
            case 1:
                return MacTestSupport.jsonResponse(data: [
                    "pages": macReaderPagePayload(
                        page: 1,
                        pages: 2,
                        docs: [macReaderPage(id: "old-partial")]
                    ),
                ])
            case 2:
                return MacTestSupport.emptyHTTPResponse(statusCode: 500)
            case 3:
                await retryGate.wait()
                return MacTestSupport.jsonResponse(data: [
                    "pages": macReaderPagePayload(
                        page: 1,
                        pages: 2,
                        docs: [macReaderPage(id: "new-1")]
                    ),
                ])
            default:
                XCTAssertEqual(MacTestSupport.page(from: request), 2)
                return MacTestSupport.jsonResponse(data: [
                    "pages": macReaderPagePayload(
                        page: 2,
                        pages: 2,
                        docs: [macReaderPage(id: "new-2")]
                    ),
                ])
            }
        }
        let viewModel = try makeViewModel(client: client, store: store)
        await viewModel.startIfNeeded()
        XCTAssertEqual(viewModel.pages.compactMap(\.id), ["old-partial"])

        let retryTask = Task { await viewModel.retryCurrentEpisode() }
        await waitUntil { viewModel.isLoading }
        XCTAssertEqual(viewModel.pages.compactMap(\.id), ["old-partial"])

        await retryGate.open()
        await retryTask.value

        XCTAssertEqual(viewModel.pages.compactMap(\.id), ["new-1", "new-2"])
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertNil(viewModel.partialErrorMessage)
        XCTAssertFalse(viewModel.isLoading)
    }

    func testCancelLoadingStopsOwnedTaskAndRejectsResult() async throws {
        let responseGate = TestAsyncGate()
        let (client, store) = MacTestSupport.makeAPIClient { _ in
            await responseGate.wait()
            return MacTestSupport.jsonResponse(data: [
                "pages": macReaderPagePayload(
                    page: 1,
                    pages: 1,
                    docs: [macReaderPage(id: "late-page")]
                ),
            ])
        }
        let viewModel = try makeViewModel(client: client, store: store)

        let loadTask = Task { await viewModel.startIfNeeded() }
        await waitUntil { viewModel.isLoading }
        viewModel.cancelLoading()
        await responseGate.open()
        await loadTask.value

        XCTAssertFalse(viewModel.isLoading)
        XCTAssertTrue(viewModel.pages.isEmpty)
    }

    private func makeViewModel(
        client: any APIClientProtocol,
        store: InMemoryKeyValueStore
    ) throws -> MacReaderViewModel {
        let accountSession = AccountSessionStore(keyValueStore: store)
        _ = try accountSession.activate(userID: "reader-test-user")
        let readingStore = MacReadingStore(
            keyValueStore: store,
            accountSessionStore: accountSession
        )
        let episode = Episode(id: "ep-1", title: "第一话", order: 1, updated_at: nil)
        let request = MacReaderLaunchRequest(
            comicId: "reader-comic",
            comicTitle: "分页测试",
            author: nil,
            thumbPath: nil,
            thumbServer: nil,
            episodes: [MacReaderEpisode(episode: episode)],
            startEpisodeIndex: 0,
            startPageIndex: 0,
            restoreSavedProgress: false
        )

        return MacReaderViewModel(
            request: request,
            readingStore: readingStore,
            client: client,
            keyValueStore: store
        )
    }
}

nonisolated private func macReaderPagePayload(
    page: Int,
    pages: Int,
    docs: [[String: Any]]
) -> [String: Any] {
    [
        "docs": docs,
        "total": docs.count,
        "limit": max(docs.count, 1),
        "page": page,
        "pages": pages,
    ]
}

nonisolated private func macReaderPage(id: String) -> [String: Any] {
    [
        "_id": id,
        "media": [
            "originalName": "\(id).png",
            "path": "pages/\(id).png",
            "fileServer": "https://fixtures.bika.test",
        ],
    ]
}
