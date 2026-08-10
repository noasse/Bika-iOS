import XCTest
@testable import bika

@MainActor
final class ReaderViewModelTests: XCTestCase {
    override func tearDown() {
        TestSupport.restoreLiveDependencies()
        super.tearDown()
    }

    func testLaterEpisodeLoadWinsOverEarlierDelayedResponse() async throws {
        let (client, store) = TestSupport.makeAPIClient { request in
            let path = request.url?.path ?? ""
            if path.contains("/order/1/") {
                try await Task.sleep(nanoseconds: 300_000_000)
                return TestSupport.jsonResponse(data: [
                    "pages": [
                        "docs": [
                            page(id: "old-1"),
                        ],
                        "total": 1,
                        "limit": 1,
                        "page": 1,
                        "pages": 1,
                    ],
                ])
            }

            return TestSupport.jsonResponse(data: [
                "pages": [
                    "docs": [
                        page(id: "new-1"),
                        page(id: "new-2"),
                    ],
                    "total": 2,
                    "limit": 2,
                    "page": 1,
                    "pages": 1,
                ],
            ])
        }

        let episodes = [
            Episode(id: "episode-1", title: "第1话", order: 1, updated_at: nil),
            Episode(id: "episode-2", title: "第2话", order: 2, updated_at: nil),
        ]

        let viewModel = ReaderViewModel(
            comicId: "comic-1",
            episodes: episodes,
            startEpisodeIndex: 0,
            client: client,
            keyValueStore: store
        )

        viewModel.startLoadingPages()
        viewModel.nextEpisode()

        await waitUntil {
            !viewModel.isLoading && viewModel.currentEpisode?.order == 2 && viewModel.pages.count == 2
        }

        XCTAssertEqual(viewModel.currentEpisode?.order, 2)
        XCTAssertEqual(viewModel.pages.compactMap(\.id), ["new-1", "new-2"])
    }

    func testChapterSwitchDiscardsCancellationIgnoringEarlierResponse() async {
        let oldChapterGate = TestAsyncGate()
        let oldChapterStarted = LockedValue(false)
        let oldChapterReturned = LockedValue(false)
        let client = ReaderAPIClientStub { path in
            if path.contains("/order/1/") {
                oldChapterStarted.value = true
                await oldChapterGate.wait()
                oldChapterReturned.value = true
                return comicPagesResponse(ids: ["late-old"])
            }
            return comicPagesResponse(ids: ["current-new"])
        }
        let store = InMemoryKeyValueStore()
        let viewModel = ReaderViewModel(
            comicId: "comic-1",
            episodes: [
                Episode(id: "episode-1", title: "第1话", order: 1, updated_at: nil),
                Episode(id: "episode-2", title: "第2话", order: 2, updated_at: nil),
            ],
            startEpisodeIndex: 0,
            client: client,
            keyValueStore: store
        )

        viewModel.startLoadingPages()
        await waitUntil { oldChapterStarted.value }
        viewModel.nextEpisode()
        await waitUntil {
            !viewModel.isLoading && viewModel.pages.compactMap(\.id) == ["current-new"]
        }

        await oldChapterGate.open()
        await waitUntil { oldChapterReturned.value }
        await Task.yield()
        XCTAssertEqual(viewModel.currentEpisode?.id, "episode-2")
        XCTAssertEqual(viewModel.pages.compactMap(\.id), ["current-new"])
        XCTAssertNil(viewModel.errorMessage)
    }

    func testCancelLoadingPagesStopsLoadingAndDiscardsCancellationIgnoringResponse() async {
        let responseGate = TestAsyncGate()
        let requestStarted = LockedValue(false)
        let responseReturned = LockedValue(false)
        let client = ReaderAPIClientStub { _ in
            requestStarted.value = true
            await responseGate.wait()
            responseReturned.value = true
            return comicPagesResponse(ids: ["late-page"])
        }
        let store = InMemoryKeyValueStore()
        let viewModel = makeReaderViewModel(client: client, store: store)

        viewModel.startLoadingPages()
        await waitUntil { requestStarted.value }

        viewModel.cancelLoadingPages()
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertTrue(viewModel.pages.isEmpty)

        await responseGate.open()
        await waitUntil { responseReturned.value }
        await Task.yield()
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertTrue(viewModel.pages.isEmpty)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testStopsLoadingWhenPaginationDoesNotAdvance() async throws {
        let (client, store) = TestSupport.makeAPIClient { request in
            let pageNumber = TestSupport.page(from: request)
            if pageNumber == 1 {
                return TestSupport.jsonResponse(data: [
                    "pages": [
                        "docs": [
                            page(id: "page-1"),
                        ],
                        "total": 2,
                        "limit": 1,
                        "page": 1,
                        "pages": 2,
                    ],
                ])
            }

            return TestSupport.jsonResponse(data: [
                "pages": [
                    "docs": [
                        page(id: "page-2"),
                    ],
                    "total": 2,
                    "limit": 1,
                    "page": 1,
                    "pages": 2,
                ],
                "ep": [
                    "_id": "episode-1",
                    "title": "第1话",
                ],
            ])
        }

        let viewModel = ReaderViewModel(
            comicId: "comic-1",
            episodes: [Episode(id: "episode-1", title: "第1话", order: 1, updated_at: nil)],
            startEpisodeIndex: 0,
            client: client,
            keyValueStore: store
        )

        viewModel.startLoadingPages()

        await waitUntil {
            !viewModel.isLoading
        }

        XCTAssertEqual(viewModel.pages.compactMap(\.id), ["page-1"])
    }

    func testAcceptsReturnedPageAheadOfRequestedPage() async {
        let requestedPages = LockedValue<[Int]>([])
        let (client, store) = TestSupport.makeAPIClient { request in
            let requestedPage = TestSupport.page(from: request)
            var recordedPages = requestedPages.value
            recordedPages.append(requestedPage)
            requestedPages.value = recordedPages

            switch requestedPage {
            case 1:
                return pagesResponse(ids: ["page-2"], returnedPage: 2, totalPages: 3)
            case 3:
                return pagesResponse(ids: ["page-3"], returnedPage: 3, totalPages: 3)
            default:
                throw MockURLProtocolError.unsupportedScenario
            }
        }
        let viewModel = makeReaderViewModel(client: client, store: store)

        viewModel.startLoadingPages()

        await waitUntil { !viewModel.isLoading }
        XCTAssertEqual(requestedPages.value, [1, 3])
        XCTAssertEqual(viewModel.pages.compactMap(\.id), ["page-2", "page-3"])
        XCTAssertNil(viewModel.errorMessage)
    }

    func testBackwardReturnedPageShowsPaginationErrorAndKeepsLoadedPages() async {
        let (client, store) = TestSupport.makeAPIClient { request in
            switch TestSupport.page(from: request) {
            case 1:
                return pagesResponse(ids: ["page-1"], returnedPage: 1, totalPages: 2)
            case 2:
                return pagesResponse(ids: ["duplicate-page"], returnedPage: 1, totalPages: 2)
            default:
                throw MockURLProtocolError.unsupportedScenario
            }
        }
        let viewModel = makeReaderViewModel(client: client, store: store)

        viewModel.startLoadingPages()

        await waitUntil { !viewModel.isLoading }
        XCTAssertEqual(viewModel.pages.compactMap(\.id), ["page-1"])
        XCTAssertTrue(viewModel.errorMessage?.contains("分页") == true)
    }

    func testEmptyPageWithDeclaredFollowingPageShowsPaginationErrorAndKeepsLoadedPages() async {
        let (client, store) = TestSupport.makeAPIClient { request in
            switch TestSupport.page(from: request) {
            case 1:
                return pagesResponse(ids: ["page-1"], returnedPage: 1, totalPages: 3)
            case 2:
                return pagesResponse(ids: [], returnedPage: 2, totalPages: 3)
            default:
                throw MockURLProtocolError.unsupportedScenario
            }
        }
        let viewModel = makeReaderViewModel(client: client, store: store)

        viewModel.startLoadingPages()

        await waitUntil { !viewModel.isLoading }
        XCTAssertEqual(viewModel.pages.compactMap(\.id), ["page-1"])
        XCTAssertTrue(viewModel.errorMessage?.contains("分页") == true)
    }

    func testFirstEmptyPageWithDeclaredFollowingPageShowsFullScreenErrorState() async {
        let (client, store) = TestSupport.makeAPIClient { _ in
            pagesResponse(ids: [], returnedPage: 1, totalPages: 2)
        }
        let viewModel = makeReaderViewModel(client: client, store: store)

        viewModel.startLoadingPages()

        await waitUntil { !viewModel.isLoading }
        XCTAssertTrue(viewModel.pages.isEmpty)
        XCTAssertTrue(viewModel.errorMessage?.contains("分页") == true)
        XCTAssertTrue(viewModel.showsFullScreenLoadError)
        XCTAssertFalse(viewModel.showsPaginationError)
    }

    func testLaterPageFailureKeepsLoadedPagesAndExposesCompactErrorState() async {
        let (client, store) = TestSupport.makeAPIClient { request in
            guard TestSupport.page(from: request) == 1 else {
                throw URLError(.timedOut)
            }
            return pagesResponse(ids: ["page-1"], returnedPage: 1, totalPages: 2)
        }
        let viewModel = makeReaderViewModel(client: client, store: store)

        viewModel.startLoadingPages()

        await waitUntil { !viewModel.isLoading }
        XCTAssertEqual(viewModel.pages.compactMap(\.id), ["page-1"])
        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.showsFullScreenLoadError)
        XCTAssertTrue(viewModel.showsPaginationError)
    }

    func testSameEpisodeRetryStartsAtFirstPageKeepsPartialUntilSuccessAndAtomicallyReplaces() async {
        let retryFirstPageGate = TestAsyncGate()
        let retrySecondPageGate = TestAsyncGate()
        let firstPageCalls = LockedValue(0)
        let secondPageCalls = LockedValue(0)
        let (client, store) = TestSupport.makeAPIClient { request in
            switch TestSupport.page(from: request) {
            case 1:
                firstPageCalls.value += 1
                if firstPageCalls.value == 1 {
                    return pagesResponse(ids: ["old-partial"], returnedPage: 1, totalPages: 2)
                }

                await retryFirstPageGate.wait()
                return pagesResponse(ids: ["new-1"], returnedPage: 1, totalPages: 2)
            case 2:
                secondPageCalls.value += 1
                if secondPageCalls.value == 1 {
                    throw URLError(.timedOut)
                }

                await retrySecondPageGate.wait()
                return pagesResponse(ids: ["new-2"], returnedPage: 2, totalPages: 2)
            default:
                throw MockURLProtocolError.unsupportedScenario
            }
        }
        let viewModel = makeReaderViewModel(client: client, store: store)

        viewModel.startLoadingPages()
        await waitUntil { !viewModel.isLoading }
        XCTAssertEqual(viewModel.pages.compactMap(\.id), ["old-partial"])
        XCTAssertNotNil(viewModel.errorMessage)

        viewModel.startLoadingPages()
        await waitUntil { firstPageCalls.value == 2 }
        XCTAssertTrue(viewModel.isLoading)
        XCTAssertEqual(viewModel.pages.compactMap(\.id), ["old-partial"])

        await retryFirstPageGate.open()
        await waitUntil { secondPageCalls.value == 2 }
        XCTAssertEqual(viewModel.pages.compactMap(\.id), ["old-partial"])

        await retrySecondPageGate.open()
        await waitUntil { !viewModel.isLoading }
        XCTAssertEqual(viewModel.pages.compactMap(\.id), ["new-1", "new-2"])
        XCTAssertNil(viewModel.errorMessage)
    }

    func testReaderModePersistsToInjectedStore() {
        let store = InMemoryKeyValueStore()
        let viewModel = ReaderViewModel(
            comicId: "comic-1",
            episodes: [],
            startEpisodeIndex: 0,
            keyValueStore: store
        )

        viewModel.setReaderMode(.vertical)

        XCTAssertEqual(store.string(forKey: "readerMode"), ReaderViewModel.ReaderMode.vertical.rawValue)
    }

    func testImagePrefetchWindowSkipsCurrentPageAndStaysWithinBounds() {
        XCTAssertEqual(
            ReaderImagePrefetchPlan.indices(
                currentIndex: 5,
                pageCount: 10,
                lookBehind: 1,
                lookAhead: 3
            ),
            [6, 7, 8, 4]
        )

        XCTAssertEqual(
            ReaderImagePrefetchPlan.indices(
                currentIndex: 0,
                pageCount: 3,
                lookBehind: 2,
                lookAhead: 4
            ),
            [1, 2]
        )

        XCTAssertEqual(
            ReaderImagePrefetchPlan.indices(
                currentIndex: 4,
                pageCount: 5,
                lookBehind: 2,
                lookAhead: 3
            ),
            [3, 2]
        )
    }

    func testViewportUpdateAcceptsFirstValidMeasurementWhenCallbackValuesMatch() {
        let measuredSize = CGSize(width: 390, height: 844)

        XCTAssertTrue(
            ReaderViewportUpdate.shouldApply(
                currentSize: .zero,
                newSize: measuredSize
            )
        )
    }

    func testViewportUpdateAcceptsAnyPositiveInitialMeasurement() {
        XCTAssertTrue(
            ReaderViewportUpdate.shouldApply(
                currentSize: .zero,
                newSize: CGSize(width: 0.5, height: 0.5)
            )
        )
    }

    func testViewportUpdateIgnoresNearlyEqualStoredMeasurement() {
        XCTAssertFalse(
            ReaderViewportUpdate.shouldApply(
                currentSize: CGSize(width: 390, height: 844),
                newSize: CGSize(width: 390.5, height: 844.5)
            )
        )
    }

    func testViewportUpdateRejectsInvalidMeasurement() {
        XCTAssertFalse(
            ReaderViewportUpdate.shouldApply(
                currentSize: .zero,
                newSize: CGSize(width: 0, height: 844)
            )
        )
    }

    func testVerticalReaderPageHeightUsesExactAspectRatioBeforeEstimate() {
        let height = ReaderVerticalImageLayout.pageHeight(
            viewportWidth: 320,
            exactAspectRatio: 3,
            estimatedAspectRatio: 1.25
        )

        XCTAssertEqual(height, 960, accuracy: 0.01)
    }

    func testVerticalReaderPageHeightUsesEstimatedRatioBeforeFallback() {
        let height = ReaderVerticalImageLayout.pageHeight(
            viewportWidth: 320,
            exactAspectRatio: nil,
            estimatedAspectRatio: 1.5
        )

        XCTAssertEqual(height, 480, accuracy: 0.01)
    }

    func testVerticalReaderPageHeightUsesDefaultRatioWithoutExactOrEstimate() {
        let height = ReaderVerticalImageLayout.pageHeight(
            viewportWidth: 320,
            exactAspectRatio: nil,
            estimatedAspectRatio: nil
        )

        XCTAssertEqual(height, 480, accuracy: 0.01)
    }

    func testVerticalReaderPageHeightIgnoresInvalidExactAspectRatio() {
        let height = ReaderVerticalImageLayout.pageHeight(
            viewportWidth: 320,
            exactAspectRatio: 0,
            estimatedAspectRatio: 1.5
        )

        XCTAssertEqual(height, 480, accuracy: 0.01)
    }

    // MARK: - ReaderPageLayoutStore
    //
    // These rules used to live as four pieces of view state mutated from several SwiftUI
    // callbacks, so none of them could be asserted directly.

    @MainActor
    func testLayoutStorePrefersAMeasuredPageOverTheEstimate() {
        let store = ReaderPageLayoutStore()
        let measured = makePageID("measured")
        let unmeasured = makePageID("unmeasured")

        store.registerSample(measured)
        store.record(3, for: measured)

        XCTAssertEqual(store.pageHeight(for: measured, viewportWidth: 320), 960, accuracy: 0.01)
        // The unmeasured page falls back to the estimate the sample produced.
        XCTAssertEqual(store.pageHeight(for: unmeasured, viewportWidth: 320), 960, accuracy: 0.01)
    }

    @MainActor
    func testLayoutStoreEstimatesFromTheMedianOfItsSamples() {
        let store = ReaderPageLayoutStore()
        let samples = (0..<3).map { makePageID("sample-\($0)") }
        samples.forEach(store.registerSample)

        store.record(1, for: samples[0])
        store.record(5, for: samples[1])
        store.record(2, for: samples[2])

        // Median of [1, 2, 5] is 2 — an outlier page must not drag every other page's height.
        XCTAssertEqual(store.estimatedAspectRatio ?? 0, 2, accuracy: 0.0001)
    }

    @MainActor
    func testLayoutStoreStopsTakingSamplesAtItsLimit() {
        let store = ReaderPageLayoutStore()
        let pageIDs = (0..<5).map { makePageID("page-\($0)") }
        pageIDs.forEach(store.registerSample)

        XCTAssertEqual(store.sampledPageIDs.count, ReaderPageLayoutStore.sampleCount)

        // A page beyond the limit still records its own height, it just does not steer the estimate.
        store.record(9, for: pageIDs[4])
        XCTAssertEqual(store.pageHeight(for: pageIDs[4], viewportWidth: 320), 2880, accuracy: 0.01)
        XCTAssertNil(store.estimatedAspectRatio)
    }

    @MainActor
    func testLayoutStoreIgnoresRepeatAndInvalidMeasurements() {
        let store = ReaderPageLayoutStore()
        let pageID = makePageID("page")

        XCTAssertTrue(store.record(2, for: pageID))
        XCTAssertFalse(store.record(2, for: pageID), "an unchanged ratio must not churn layout")
        XCTAssertFalse(store.record(0, for: pageID))
        XCTAssertFalse(store.record(.nan, for: pageID))
        XCTAssertFalse(store.record(.infinity, for: pageID))

        XCTAssertEqual(store.pageHeight(for: pageID, viewportWidth: 320), 640, accuracy: 0.01)
    }

    @MainActor
    func testLayoutStoreDropsEverythingWhenTheEpisodeChanges() {
        let store = ReaderPageLayoutStore()
        let pageID = makePageID("page")
        store.registerSample(pageID)
        store.record(3, for: pageID)

        store.reset()

        XCTAssertNil(store.estimatedAspectRatio)
        XCTAssertTrue(store.sampledPageIDs.isEmpty)
        // Back to the default ratio, not the previous episode's measurement.
        XCTAssertEqual(store.pageHeight(for: pageID, viewportWidth: 320), 480, accuracy: 0.01)
    }

    @MainActor
    func testLayoutStoreAcceptsPrefetchedRatiosInBulk() {
        let store = ReaderPageLayoutStore()
        let first = makePageID("first")
        let second = makePageID("second")

        store.record([first: 2, second: 4])

        XCTAssertEqual(store.pageHeight(for: first, viewportWidth: 320), 640, accuracy: 0.01)
        XCTAssertEqual(store.pageHeight(for: second, viewportWidth: 320), 1280, accuracy: 0.01)
    }

    private func makePageID(_ id: String) -> ReaderPageID {
        ReaderPageID(
            episodeID: "episode-1",
            backendPageID: id,
            imageURL: URL(string: "https://images.bika.test/\(id).jpg")!
        )
    }

    private func makeReaderViewModel(client: any APIClientProtocol, store: InMemoryKeyValueStore) -> ReaderViewModel {
        ReaderViewModel(
            comicId: "comic-1",
            episodes: [Episode(id: "episode-1", title: "第1话", order: 1, updated_at: nil)],
            startEpisodeIndex: 0,
            client: client,
            keyValueStore: store
        )
    }
}

nonisolated private func pagesResponse(ids: [String], returnedPage: Int, totalPages: Int) -> MockHTTPResponse {
    TestSupport.jsonResponse(data: [
        "pages": [
            "docs": ids.map(page),
            "total": ids.count,
            "limit": max(ids.count, 1),
            "page": returnedPage,
            "pages": totalPages,
        ],
    ])
}

nonisolated private func comicPagesResponse(
    ids: [String],
    returnedPage: Int = 1,
    totalPages: Int = 1
) -> APIResponse<ComicPagesData> {
    APIResponse(
        code: 200,
        message: "success",
        data: ComicPagesData(
            pages: PaginatedResponse(
                docs: ids.map { id in
                    ComicPage(
                        id: id,
                        media: Media(
                            originalName: "\(id).png",
                            path: "pages/\(id).png",
                            fileServer: "https://fixtures.bika.test"
                        )
                    )
                },
                total: ids.count,
                limit: max(ids.count, 1),
                page: returnedPage,
                pages: totalPages
            ),
            ep: nil
        )
    )
}

private enum ReaderAPIClientStubError: Error {
    case unsupportedEndpoint
    case unexpectedResponseType
}

private final class ReaderAPIClientStub: APIClientProtocol, @unchecked Sendable {
    let tokenStore = TokenStore(store: InMemoryKeyValueStore())

    private let handler: @Sendable (String) async throws -> APIResponse<ComicPagesData>

    init(handler: @escaping @Sendable (String) async throws -> APIResponse<ComicPagesData>) {
        self.handler = handler
    }

    func send<T>(_ endpoint: APIEndpoint<T>) async throws -> T where T: Decodable, T: Sendable {
        guard T.self == APIResponse<ComicPagesData>.self else {
            throw ReaderAPIClientStubError.unsupportedEndpoint
        }
        let response = try await handler(endpoint.path)
        guard let typedResponse = response as? T else {
            throw ReaderAPIClientStubError.unexpectedResponseType
        }
        return typedResponse
    }

    func requestSignInToken(email: String, password: String) async throws -> String {
        throw ReaderAPIClientStubError.unsupportedEndpoint
    }

    func signIn(email: String, password: String) async throws -> String {
        throw ReaderAPIClientStubError.unsupportedEndpoint
    }
}

nonisolated private func page(id: String) -> [String: Any] {
    [
        "_id": id,
        "media": [
            "originalName": "\(id).png",
            "path": "pages/\(id).png",
            "fileServer": "https://fixtures.bika.test",
        ],
    ]
}
