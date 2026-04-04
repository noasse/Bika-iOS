import XCTest
@testable import bika

final class ComicModelsTests: XCTestCase {
    func testComicDecodingAcceptsNumericStringMetrics() throws {
        let data = jsonData([
            "_id": "comic-1",
            "title": "测试漫画",
            "totalViews": "12",
            "viewsCount": "13",
            "totalLikes": "14",
            "pagesCount": "15",
            "epsCount": "16",
            "likesCount": "17",
        ])

        let comic = try JSONDecoder().decode(Comic.self, from: data)

        XCTAssertEqual(comic.id, "comic-1")
        XCTAssertEqual(comic.title, "测试漫画")
        XCTAssertEqual(comic.totalViews, 12)
        XCTAssertEqual(comic.viewsCount, 13)
        XCTAssertEqual(comic.totalLikes, 14)
        XCTAssertEqual(comic.pagesCount, 15)
        XCTAssertEqual(comic.epsCount, 16)
        XCTAssertEqual(comic.likesCount, 17)
    }

    func testRecommendedDataThrowsWhenAllComicsAreMalformed() {
        let data = jsonData([
            "comics": [
                [
                    "title": "缺少 id",
                ],
                [
                    "_id": "comic-2",
                ],
            ],
        ])

        XCTAssertThrowsError(try JSONDecoder().decode(RecommendedData.self, from: data))
    }
}

private func jsonData(_ object: Any) -> Data {
    (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
}
