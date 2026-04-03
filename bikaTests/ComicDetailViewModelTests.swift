import XCTest
@testable import bika

@MainActor
final class ComicDetailViewModelTests: XCTestCase {
    override func tearDown() {
        TestSupport.restoreLiveDependencies()
        super.tearDown()
    }

    func testLoadSortsEpisodesAndStopsWhenReturnedPageDoesNotAdvance() async {
        let requestCount = LockedValue(0)
        let (client, store) = TestSupport.makeAPIClient { request in
            requestCount.value += 1
            let path = request.url?.path ?? ""
            if path == "/comics/comic-1" {
                return TestSupport.jsonResponse(data: [
                    "comic": [
                        "_id": "comic-1",
                        "title": "测试漫画",
                    ],
                ])
            }

            if path == "/comics/comic-1/recommendation" {
                return TestSupport.jsonResponse(data: [
                    "comics": [],
                ])
            }

            if path == "/comics/comic-1/comments" {
                return TestSupport.jsonResponse(data: [
                    "comments": [
                        "docs": [
                            comment(id: "comment-1", content: "第一页评论", commentsCount: 0),
                        ],
                        "total": 3,
                        "limit": 1,
                        "page": 1,
                        "pages": 3,
                    ],
                    "topComments": [
                        comment(id: "comment-top", content: "置顶评论", commentsCount: 0, isTop: true),
                    ],
                ])
            }

            let page = TestSupport.page(from: request)
            switch page {
            case 1:
                return TestSupport.jsonResponse(data: [
                    "eps": [
                        "docs": [
                            episode(id: "episode-3", title: "第3话", order: 3),
                        ],
                        "total": 3,
                        "limit": 1,
                        "page": 1,
                        "pages": 3,
                    ],
                ])
            case 2:
                return TestSupport.jsonResponse(data: [
                    "eps": [
                        "docs": [
                            episode(id: "episode-1", title: "第1话", order: 1),
                        ],
                        "total": 3,
                        "limit": 1,
                        "page": 2,
                        "pages": 3,
                    ],
                ])
            default:
                return TestSupport.jsonResponse(data: [
                    "eps": [
                        "docs": [
                            episode(id: "episode-2", title: "第2话", order: 2),
                        ],
                        "total": 3,
                        "limit": 1,
                        "page": 2,
                        "pages": 3,
                    ],
                ])
            }
        }
        _ = store

        let viewModel = ComicDetailViewModel(comicId: "comic-1", client: client)
        await viewModel.load()

        XCTAssertEqual(viewModel.episodes.map(\.order), [1, 2, 3])
        XCTAssertEqual(viewModel.commentEntryCount, 4)
        XCTAssertEqual(requestCount.value, 6)
    }

    func testLoadStartsRecommendedRequestBeforeEpisodesFinish() async {
        let recommendationRequested = LockedValue(false)
        let gate = AsyncGate()
        let (client, _) = TestSupport.makeAPIClient { request in
            let path = request.url?.path ?? ""

            if path == "/comics/comic-1" {
                return TestSupport.jsonResponse(data: [
                    "comic": [
                        "_id": "comic-1",
                        "title": "测试漫画",
                    ],
                ])
            }

            if path == "/comics/comic-1/recommendation" {
                recommendationRequested.value = true
                return TestSupport.jsonResponse(data: [
                    "comics": [
                        comic(id: "recommended-1", title: "相关推荐"),
                    ],
                ])
            }

            if path == "/comics/comic-1/comments" {
                return TestSupport.jsonResponse(data: [
                    "comments": [
                        "docs": [
                            comment(id: "comment-1", content: "第一页评论", commentsCount: 0),
                        ],
                        "total": 1,
                        "limit": 1,
                        "page": 1,
                        "pages": 1,
                    ],
                    "topComments": [],
                ])
            }

            if path == "/comics/comic-1/eps" {
                await gate.wait()
                return TestSupport.jsonResponse(data: [
                    "eps": [
                        "docs": [
                            episode(id: "episode-1", title: "第1话", order: 1),
                        ],
                        "total": 1,
                        "limit": 1,
                        "page": 1,
                        "pages": 1,
                    ],
                ])
            }

            return TestSupport.jsonResponse(data: [:])
        }

        let viewModel = ComicDetailViewModel(comicId: "comic-1", client: client)
        let loadTask = Task { await viewModel.load() }

        await waitUntil(timeout: 1.0) {
            recommendationRequested.value
        }

        await gate.open()
        await loadTask.value

        XCTAssertEqual(viewModel.recommended.map(\.id), ["recommended-1"])
        XCTAssertEqual(viewModel.episodes.map(\.order), [1])
        XCTAssertEqual(viewModel.commentEntryCount, 1)
    }

    func testLoadStopsWhenDetailRequestFails() async {
        let requestedPaths = LockedValue<[String]>([])
        let (client, _) = TestSupport.makeAPIClient { request in
            let path = request.url?.path ?? ""
            requestedPaths.value = requestedPaths.value + [path]

            if path == "/comics/comic-1" {
                return TestSupport.jsonResponse(code: 500, message: "详情加载失败", data: [:])
            }

            return TestSupport.jsonResponse(data: [:])
        }

        let viewModel = ComicDetailViewModel(comicId: "comic-1", client: client)
        await viewModel.load()

        XCTAssertNil(viewModel.detail)
        XCTAssertEqual(requestedPaths.value, ["/comics/comic-1"])
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertTrue(viewModel.recommended.isEmpty)
        XCTAssertTrue(viewModel.episodes.isEmpty)
    }
}

private actor AsyncGate {
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

private func episode(id: String, title: String, order: Int) -> [String: Any] {
    [
        "_id": id,
        "title": title,
        "order": order,
        "updated_at": "2024-01-01T00:00:00.000Z",
    ]
}

private func comment(id: String, content: String, commentsCount: Int, isTop: Bool = false) -> [String: Any] {
    [
        "_id": id,
        "content": content,
        "_user": [
            "_id": "user-\(id)",
            "name": "评论用户",
        ],
        "totalComments": commentsCount,
        "commentsCount": commentsCount,
        "isTop": isTop,
        "hide": false,
        "created_at": "2024-01-01T00:00:00.000Z",
        "likesCount": 0,
        "isLiked": false,
    ]
}
