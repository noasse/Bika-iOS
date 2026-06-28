import XCTest
@testable import bika

@MainActor
final class SearchViewModelTests: XCTestCase {
    override func tearDown() {
        TestSupport.restoreLiveDependencies()
        super.tearDown()
    }

    func testSearchTrimsKeywordAndLoadsFirstPage() async throws {
        let (client, store) = TestSupport.makeAPIClient { request in
            XCTAssertEqual(TestSupport.page(from: request), 1)
            return TestSupport.jsonResponse(data: [
                "comics": [
                    "docs": [
                        [
                            "_id": "comic-1",
                            "title": "Trimmed Result",
                        ],
                    ],
                    "total": 1,
                    "limit": 20,
                    "page": 1,
                    "pages": 1,
                ],
            ])
        }

        let viewModel = SearchViewModel(client: client, keyValueStore: store)
        viewModel.keyword = "  冒烟关键字  "

        await viewModel.search()

        XCTAssertEqual(viewModel.keyword, "冒烟关键字")
        XCTAssertEqual(viewModel.activeKeyword, "冒烟关键字")
        XCTAssertEqual(viewModel.comics.first?.title, "Trimmed Result")
        XCTAssertEqual(viewModel.currentPage, 1)
    }

    func testSearchKeywordExpanderCreatesBracketAliasKeywords() {
        XCTAssertEqual(
            SearchKeywordExpander.keywords(for: " 生蚝（花生） "),
            ["生蚝（花生）", "生蚝", "花生"]
        )
        XCTAssertEqual(
            SearchKeywordExpander.keywords(for: "生蚝(花生)"),
            ["生蚝(花生)", "生蚝", "花生"]
        )
        XCTAssertEqual(
            SearchKeywordExpander.keywords(for: "生蚝【花生】"),
            ["生蚝【花生】", "生蚝", "花生"]
        )
        XCTAssertTrue(SearchKeywordExpander.matchesExpandedName("生蚝（花生）", query: "花生"))
        XCTAssertTrue(SearchKeywordExpander.matchesExpandedName("生蚝 ( 花生 )", query: "生蚝（花生）"))
    }

    func testSearchExpandsBracketedAuthorAliasesAndDeduplicatesResults() async throws {
        let requestKeywords = LockedValue<[String]>([])

        let (client, store) = TestSupport.makeAPIClient { request in
            let body = try XCTUnwrap(request.resolvedHTTPBodyData())
            let requestBody = try JSONDecoder().decode(SearchRequestBody.self, from: body)
            var keywords = requestKeywords.value
            keywords.append(requestBody.keyword)
            requestKeywords.value = keywords

            let docs: [[String: Any]]
            switch requestBody.keyword {
            case "生蚝（花生）":
                docs = [
                    searchComic(id: "comic-full", title: "完整作者名"),
                    searchComic(id: "comic-shared", title: "重复结果"),
                ]
            case "生蚝":
                docs = [
                    searchComic(id: "comic-main", title: "主名结果"),
                    searchComic(id: "comic-shared", title: "重复结果"),
                ]
            case "花生":
                docs = [
                    searchComic(id: "comic-alias", title: "括号名结果"),
                ]
            default:
                docs = []
            }

            return TestSupport.jsonResponse(data: [
                "comics": searchComicsPage(page: 1, pages: 1, docs: docs),
            ])
        }

        let viewModel = SearchViewModel(client: client, keyValueStore: store)
        viewModel.keyword = "生蚝（花生）"

        await viewModel.search()

        XCTAssertEqual(requestKeywords.value, ["生蚝（花生）", "生蚝", "花生"])
        XCTAssertEqual(
            viewModel.comics.map(\.id),
            ["comic-full", "comic-shared", "comic-main", "comic-alias"]
        )
        XCTAssertEqual(viewModel.currentPage, 1)
        XCTAssertEqual(viewModel.totalPages, 1)
    }

    func testNextPageUsesActiveKeywordInsteadOfEditedKeyword() async throws {
        let requestKeywords = LockedValue<[String]>([])

        let (client, store) = TestSupport.makeAPIClient { request in
            let body = try XCTUnwrap(request.resolvedHTTPBodyData())
            let requestBody = try JSONDecoder().decode(SearchRequestBody.self, from: body)
            var keywords = requestKeywords.value
            keywords.append(requestBody.keyword)
            requestKeywords.value = keywords

            let page = TestSupport.page(from: request)
            return TestSupport.jsonResponse(data: [
                "comics": [
                    "docs": [
                        [
                            "_id": "comic-\(page)",
                            "title": "Page \(page)",
                        ],
                    ],
                    "total": 2,
                    "limit": 20,
                    "page": page,
                    "pages": 2,
                ],
            ])
        }

        let viewModel = SearchViewModel(client: client, keyValueStore: store)
        viewModel.keyword = "foo"
        await viewModel.search()

        viewModel.keyword = "bar"
        await viewModel.nextPage()

        XCTAssertEqual(requestKeywords.value, ["foo", "foo"])
        XCTAssertEqual(viewModel.currentPage, 2)
        XCTAssertEqual(viewModel.comics.first?.title, "Page 2")
    }

    func testPersistPageUsesActiveKeywordKey() async throws {
        let (client, store) = TestSupport.makeAPIClient { request in
            let page = TestSupport.page(from: request)
            return TestSupport.jsonResponse(data: [
                "comics": [
                    "docs": [
                        [
                            "_id": "comic-\(page)",
                            "title": "Page \(page)",
                        ],
                    ],
                    "total": 2,
                    "limit": 20,
                    "page": page,
                    "pages": 2,
                ],
            ])
        }

        let viewModel = SearchViewModel(client: client, keyValueStore: store)
        viewModel.keyword = "persist"
        await viewModel.search()
        await viewModel.nextPage()
        viewModel.persistPage()

        XCTAssertEqual(store.integer(forKey: "lastPage_search_persist"), 2)
    }

    func testWhitespaceKeywordDoesNotSendRequest() async {
        let (client, store) = TestSupport.makeAPIClient { _ in
            XCTFail("空关键词不应该发起请求")
            return TestSupport.jsonResponse(data: [:])
        }

        let viewModel = SearchViewModel(client: client, keyValueStore: store)
        viewModel.keyword = "   \n "

        await viewModel.search()

        XCTAssertFalse(viewModel.hasSearched)
        XCTAssertTrue(viewModel.comics.isEmpty)
    }
}

private struct SearchRequestBody: Decodable {
    let keyword: String
    let sort: String?
    let categories: [String]?
}

private func searchComicsPage(page: Int, pages: Int, docs: [[String: Any]]) -> [String: Any] {
    [
        "docs": docs,
        "total": docs.count,
        "limit": max(docs.count, 1),
        "page": page,
        "pages": pages,
    ]
}

private func searchComic(id: String, title: String) -> [String: Any] {
    [
        "_id": id,
        "title": title,
        "author": "生蚝（花生）",
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
}
