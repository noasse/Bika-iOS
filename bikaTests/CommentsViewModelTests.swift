import XCTest
@testable import bika

@MainActor
final class CommentsViewModelTests: XCTestCase {
    override func tearDown() {
        TestSupport.restoreLiveDependencies()
        super.tearDown()
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

private func comment(id: String, content: String, commentsCount: Int) -> [String: Any] {
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
        "likesCount": 0,
        "isLiked": false,
    ]
}
