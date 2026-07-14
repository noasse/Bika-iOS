import XCTest
@testable import bika

@MainActor
final class CategoriesViewModelTests: XCTestCase {
    override func tearDown() {
        TestSupport.restoreLiveDependencies()
        super.tearDown()
    }

    func testLoadCategoriesDeduplicatesStableIdentityKeepingFirstOccurrence() async {
        let (client, _) = TestSupport.makeAPIClient { _ in
            TestSupport.jsonResponse(data: [
                "categories": [
                    ["_id": "category-1", "title": "首个分类"],
                    ["_id": "category-1", "title": "重复后端 ID"],
                    ["title": "缺 ID 分类", "link": "stable-link"],
                    ["title": "缺 ID 分类", "link": "stable-link"],
                ],
            ])
        }
        let viewModel = CategoriesViewModel(client: client)

        await viewModel.loadCategories()

        XCTAssertEqual(viewModel.categories.map(\.title), ["首个分类", "缺 ID 分类"])
    }
}
