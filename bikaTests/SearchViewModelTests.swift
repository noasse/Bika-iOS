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
