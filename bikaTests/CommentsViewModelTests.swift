import XCTest
@testable import bika

@MainActor
final class CommentsViewModelTests: XCTestCase {
    override func tearDown() {
        TestSupport.restoreLiveDependencies()
        super.tearDown()
    }

    func testInitialLoadDoesNotReplaceAlreadyLoadedPaginationWhenViewReappears() async throws {
        let callCount = LockedValue(0)
        let (client, _) = TestSupport.makeAPIClient { request in
            callCount.value += 1
            let page = TestSupport.page(from: request)
            return TestSupport.jsonResponse(data: [
                "comments": [
                    "docs": [
                        comment(
                            id: page == 1 ? "comment-1" : "comment-2",
                            content: "第\(page)页评论",
                            commentsCount: 1
                        ),
                    ],
                    "total": 2,
                    "limit": 1,
                    "page": page,
                    "pages": 2,
                ],
                "topComments": [],
            ])
        }
        let viewModel = CommentsViewModel(comicId: "comic-1", client: client)

        await viewModel.loadInitialPageIfNeeded()
        await viewModel.loadMore()
        await viewModel.loadInitialPageIfNeeded()

        XCTAssertEqual(callCount.value, 2)
        XCTAssertEqual(viewModel.comments.map(\.id), ["comment-1", "comment-2"])
        XCTAssertEqual(viewModel.currentPage, 2)
    }

    func testLoadMoreIfNeededOnlyTriggersOnceForSameLastItem() async throws {
        let callCount = LockedValue(0)

        let (client, _) = TestSupport.makeAPIClient { request in
            callCount.value += 1
            let page = TestSupport.page(from: request)
            if page == 1 {
                return TestSupport.jsonResponse(data: [
                    "comments": [
                        "docs": [
                            comment(id: "comment-1", content: "第一页评论 1", commentsCount: 1),
                            comment(id: "comment-2", content: "第一页评论 2", commentsCount: 0),
                        ],
                        "total": 3,
                        "limit": 2,
                        "page": 1,
                        "pages": 2,
                    ],
                    "topComments": [],
                ])
            }

            return TestSupport.jsonResponse(data: [
                "comments": [
                    "docs": [
                        comment(id: "comment-3", content: "第二页评论", commentsCount: 0),
                    ],
                    "total": 3,
                    "limit": 2,
                    "page": 2,
                    "pages": 2,
                ],
                "topComments": [],
            ])
        }

        let viewModel = CommentsViewModel(comicId: "comic-1", client: client)
        await viewModel.loadFirstPage()
        let lastID = try XCTUnwrap(viewModel.comments.last?.id)

        await viewModel.loadMoreIfNeeded(currentItemID: lastID)
        await viewModel.loadMoreIfNeeded(currentItemID: lastID)

        XCTAssertEqual(callCount.value, 2)
        XCTAssertEqual(viewModel.comments.map(\.id), ["comment-1", "comment-2", "comment-3"])
    }

    func testPostCommentReplacesInFlightPaginationAndStalePageCannotFinishReplacementLoading() async {
        let pageTwoGate = TestAsyncGate()
        let replacementGate = TestAsyncGate()
        let firstPageRequestCount = LockedValue(0)
        let pageTwoStarted = LockedValue(false)
        let replacementStarted = LockedValue(false)

        let (client, _) = TestSupport.makeAPIClient { request in
            if request.httpMethod == "POST" {
                return TestSupport.jsonResponse(data: [:])
            }

            let page = TestSupport.page(from: request)
            if page == 2 {
                pageTwoStarted.value = true
                await pageTwoGate.wait()
                return TestSupport.jsonResponse(
                    data: commentsPage(
                        page: 2,
                        pages: 2,
                        docs: [comment(id: "stale-page-2", content: "旧分页", commentsCount: 0)]
                    )
                )
            }

            firstPageRequestCount.value += 1
            if firstPageRequestCount.value == 1 {
                return TestSupport.jsonResponse(
                    data: commentsPage(
                        page: 1,
                        pages: 2,
                        docs: [comment(id: "initial", content: "旧首页", commentsCount: 0)]
                    )
                )
            }

            replacementStarted.value = true
            await replacementGate.wait()
            return TestSupport.jsonResponse(
                data: commentsPage(
                    page: 1,
                    pages: 1,
                    docs: [comment(id: "fresh", content: "新评论", commentsCount: 0)]
                )
            )
        }

        let viewModel = CommentsViewModel(comicId: "comic-1", client: client)
        await viewModel.loadFirstPage()

        let paginationTask = Task { await viewModel.loadMore() }
        await waitUntil { pageTwoStarted.value }

        viewModel.commentText = "新评论"
        let postTask = Task { await viewModel.postComment() }
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

        XCTAssertTrue(viewModel.isLoading)
        XCTAssertFalse(viewModel.comments.contains { $0.id == "stale-page-2" })

        await replacementGate.open()
        await postTask.value

        XCTAssertEqual(viewModel.comments.map(\.id), ["fresh"])
        XCTAssertEqual(viewModel.currentPage, 1)
        XCTAssertFalse(viewModel.isLoading)
    }

    func testPostReplyReplacesInFlightPaginationAndStalePageCannotFinishReplacementLoading() async {
        let pageTwoGate = TestAsyncGate()
        let replacementGate = TestAsyncGate()
        let firstPageRequestCount = LockedValue(0)
        let pageTwoStarted = LockedValue(false)
        let replacementStarted = LockedValue(false)

        let (client, _) = TestSupport.makeAPIClient { request in
            if request.httpMethod == "POST" {
                return TestSupport.jsonResponse(data: [:])
            }

            let page = TestSupport.page(from: request)
            if page == 2 {
                pageTwoStarted.value = true
                await pageTwoGate.wait()
                return TestSupport.jsonResponse(
                    data: childCommentsPage(
                        page: 2,
                        pages: 2,
                        docs: [comment(id: "stale-child-page-2", content: "旧分页回复", commentsCount: 0)]
                    )
                )
            }

            firstPageRequestCount.value += 1
            if firstPageRequestCount.value == 1 {
                return TestSupport.jsonResponse(
                    data: childCommentsPage(
                        page: 1,
                        pages: 2,
                        docs: [comment(id: "initial-child", content: "旧首页回复", commentsCount: 0)]
                    )
                )
            }

            replacementStarted.value = true
            await replacementGate.wait()
            return TestSupport.jsonResponse(
                data: childCommentsPage(
                    page: 1,
                    pages: 1,
                    docs: [comment(id: "fresh-child", content: "新回复", commentsCount: 0)]
                )
            )
        }

        let viewModel = ChildCommentsViewModel(commentId: "comment-1", client: client)
        await viewModel.loadFirstPage()

        let paginationTask = Task { await viewModel.loadMore() }
        await waitUntil { pageTwoStarted.value }

        viewModel.replyText = "新回复"
        let postTask = Task { await viewModel.postReply() }
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

        XCTAssertTrue(viewModel.isLoading)
        XCTAssertFalse(viewModel.comments.contains { $0.id == "stale-child-page-2" })

        await replacementGate.open()
        await postTask.value

        XCTAssertEqual(viewModel.comments.map(\.id), ["fresh-child"])
        XCTAssertEqual(viewModel.currentPage, 1)
        XCTAssertFalse(viewModel.isLoading)
    }

    func testLoadMoreStopsWhenPageDoesNotAdvance() async throws {
        let (client, _) = TestSupport.makeAPIClient { request in
            let page = TestSupport.page(from: request)
            if page == 1 {
                return TestSupport.jsonResponse(data: [
                    "comments": [
                        "docs": [
                            comment(id: "comment-1", content: "第一页评论", commentsCount: 0),
                        ],
                        "total": 2,
                        "limit": 1,
                        "page": 1,
                        "pages": 2,
                    ],
                    "topComments": [],
                ])
            }

            return TestSupport.jsonResponse(data: [
                "comments": [
                    "docs": [
                        comment(id: "comment-2", content: "不会被追加", commentsCount: 0),
                    ],
                    "total": 2,
                    "limit": 1,
                    "page": 1,
                    "pages": 2,
                ],
                "topComments": [],
            ])
        }

        let viewModel = CommentsViewModel(comicId: "comic-1", client: client)
        await viewModel.loadFirstPage()
        await viewModel.loadMore()

        XCTAssertEqual(viewModel.comments.map(\.id), ["comment-1"])
        XCTAssertEqual(viewModel.currentPage, 2)
        XCTAssertFalse(viewModel.hasMore)
    }

    func testLoadMoreStopsWhenNewPageContainsOnlyDuplicateComments() async throws {
        let (client, _) = TestSupport.makeAPIClient { request in
            let page = TestSupport.page(from: request)
            if page == 1 {
                return TestSupport.jsonResponse(data: [
                    "comments": [
                        "docs": [
                            comment(id: "comment-1", content: "第一页评论", commentsCount: 0),
                        ],
                        "total": 2,
                        "limit": 1,
                        "page": 1,
                        "pages": 2,
                    ],
                    "topComments": [],
                ])
            }

            return TestSupport.jsonResponse(data: [
                "comments": [
                    "docs": [
                        comment(id: "comment-1", content: "重复评论", commentsCount: 0),
                    ],
                    "total": 2,
                    "limit": 1,
                    "page": 2,
                    "pages": 2,
                ],
                "topComments": [],
            ])
        }

        let viewModel = CommentsViewModel(comicId: "comic-1", client: client)
        await viewModel.loadFirstPage()
        await viewModel.loadMore()

        XCTAssertEqual(viewModel.comments.map(\.id), ["comment-1"])
        XCTAssertEqual(viewModel.currentPage, 2)
        XCTAssertFalse(viewModel.hasMore)
    }

    func testLoadFirstPageSetsErrorMessageOnBusinessError() async {
        let (client, _) = TestSupport.makeAPIClient { _ in
            TestSupport.jsonResponse(code: 500, message: "评论加载失败", data: [:])
        }

        let viewModel = CommentsViewModel(comicId: "comic-1", client: client)
        await viewModel.loadFirstPage()

        XCTAssertEqual(viewModel.errorMessage, "API error (500): 评论加载失败")
    }

    func testLoadFirstPageFiltersPinnedCommentsOutOfRegularList() async {
        let (client, _) = TestSupport.makeAPIClient { _ in
            TestSupport.jsonResponse(data: [
                "comments": [
                    "docs": [
                        comment(id: "comment-top", content: "重复置顶评论", commentsCount: 0),
                        comment(id: "comment-1", content: "普通评论", commentsCount: 0),
                    ],
                    "total": 2,
                    "limit": 2,
                    "page": 1,
                    "pages": 1,
                ],
                "topComments": [
                    comment(id: "comment-top", content: "置顶评论", commentsCount: 0),
                ],
            ])
        }

        let viewModel = CommentsViewModel(comicId: "comic-1", client: client)
        await viewModel.loadFirstPage()

        XCTAssertEqual(viewModel.topComments.map(\.id), ["comment-top"])
        XCTAssertEqual(viewModel.comments.map(\.id), ["comment-1"])
        XCTAssertEqual(viewModel.totalVisibleComments, 2)
    }

    func testLikeCommentUsesServerActionAndDoesNotCreateNegativeCount() async {
        let (client, _) = TestSupport.makeAPIClient { request in
            if request.url?.path == "/comments/comment-1/like" {
                return TestSupport.jsonResponse(data: ["action": "unlike"])
            }

            return TestSupport.jsonResponse(data: [
                "comments": [
                    "docs": [
                        comment(
                            id: "comment-1",
                            content: "已被服务端取消点赞",
                            commentsCount: 0,
                            likesCount: 0,
                            isLiked: false
                        ),
                    ],
                    "total": 1,
                    "limit": 1,
                    "page": 1,
                    "pages": 1,
                ],
                "topComments": [],
            ])
        }

        let viewModel = CommentsViewModel(comicId: "comic-1", client: client)
        await viewModel.loadFirstPage()
        await viewModel.likeComment(id: "comment-1")

        XCTAssertEqual(viewModel.comments.first?.isLiked, false)
        XCTAssertEqual(viewModel.comments.first?.likesCount, 0)
    }

    func testChildCommentsStopWhenResponseContainsDuplicateDocs() async throws {
        let (client, _) = TestSupport.makeAPIClient { request in
            let page = TestSupport.page(from: request)
            if page == 1 {
                return TestSupport.jsonResponse(data: [
                    "comments": [
                        "docs": [
                            comment(id: "child-1", content: "子评论", commentsCount: 0),
                        ],
                        "total": 2,
                        "limit": 1,
                        "page": 1,
                        "pages": 2,
                    ],
                ])
            }

            return TestSupport.jsonResponse(data: [
                "comments": [
                    "docs": [
                        comment(id: "child-1", content: "重复子评论", commentsCount: 0),
                    ],
                    "total": 2,
                    "limit": 1,
                    "page": 2,
                    "pages": 2,
                ],
            ])
        }

        let viewModel = ChildCommentsViewModel(commentId: "comment-1", client: client)
        await viewModel.loadFirstPage()
        await viewModel.loadMore()

        XCTAssertEqual(viewModel.comments.map(\.id), ["child-1"])
        XCTAssertEqual(viewModel.currentPage, 2)
        XCTAssertFalse(viewModel.hasMore)
    }
}

nonisolated private func comment(
    id: String,
    content: String,
    commentsCount: Int,
    likesCount: Int = 0,
    isLiked: Bool = false
) -> [String: Any] {
    [
        "_id": id,
        "content": content,
        "_user": [
            "_id": "user-\(id)",
            "name": "评论用户",
        ],
        "totalComments": commentsCount,
        "commentsCount": commentsCount,
        "isTop": false,
        "hide": false,
        "created_at": "2024-01-01T00:00:00.000Z",
        "likesCount": likesCount,
        "isLiked": isLiked,
    ]
}

nonisolated private func commentsPage(page: Int, pages: Int, docs: [[String: Any]]) -> [String: Any] {
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

nonisolated private func childCommentsPage(page: Int, pages: Int, docs: [[String: Any]]) -> [String: Any] {
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
