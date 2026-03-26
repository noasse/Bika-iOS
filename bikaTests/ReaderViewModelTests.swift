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
}

private func page(id: String) -> [String: Any] {
    [
        "_id": id,
        "media": [
            "originalName": "\(id).png",
            "path": "pages/\(id).png",
            "fileServer": "https://fixtures.bika.test",
        ],
    ]
}
