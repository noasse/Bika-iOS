import XCTest
@testable import bika

final class CommonModelsTests: XCTestCase {
    func testImageURLAddsStaticPrefixWhenPathIsRelative() {
        let media = Media(
            originalName: "cover.jpg",
            path: "covers/comic-1.jpg",
            fileServer: "https://cdn.example.com"
        )

        XCTAssertEqual(
            media.imageURL?.absoluteString,
            "https://cdn.example.com/static/covers/comic-1.jpg"
        )
    }

    func testImageURLKeepsExistingStaticPrefix() {
        let media = Media(
            originalName: "cover.jpg",
            path: "static/covers/comic-1.jpg",
            fileServer: "https://cdn.example.com/"
        )

        XCTAssertEqual(
            media.imageURL?.absoluteString,
            "https://cdn.example.com/static/covers/comic-1.jpg"
        )
    }
}
