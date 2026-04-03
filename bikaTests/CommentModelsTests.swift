import XCTest
@testable import bika

final class CommentModelsTests: XCTestCase {
    func testCommentDecodingFailsWhenIDIsMissing() {
        let data = jsonData([
            "content": "缺少 id",
        ])

        XCTAssertThrowsError(try JSONDecoder().decode(Comment.self, from: data)) { error in
            guard case DecodingError.keyNotFound(let key, _) = error else {
                return XCTFail("预期 keyNotFound，实际为 \(error)")
            }

            XCTAssertEqual(key.stringValue, "_id")
        }
    }

    func testCommentDecodingDropsInvalidNonCriticalFields() throws {
        let data = jsonData([
            "_id": "comment-1",
            "content": 123,
            "likesCount": "oops",
            "isLiked": "nope",
        ])

        let comment = try JSONDecoder().decode(Comment.self, from: data)

        XCTAssertEqual(comment.id, "comment-1")
        XCTAssertNil(comment.content)
        XCTAssertNil(comment.likesCount)
        XCTAssertNil(comment.isLiked)
    }

    func testCommentsDataDecodingFailsWhenCriticalPaginationFieldIsMissing() {
        let data = jsonData([
            "comments": [
                "docs": [
                    ["_id": "comment-1"],
                ],
                "total": 1,
                "pages": 1,
            ],
        ])

        XCTAssertThrowsError(try JSONDecoder().decode(CommentsData.self, from: data)) { error in
            guard case DecodingError.keyNotFound(let key, _) = error else {
                return XCTFail("预期 keyNotFound，实际为 \(error)")
            }

            XCTAssertEqual(key.stringValue, "page")
        }
    }

    func testCommentsDataDefaultsMissingTopCommentsToEmptyArray() throws {
        let data = jsonData([
            "comments": [
                "docs": [
                    ["_id": "comment-1"],
                ],
                "total": 1,
                "page": 1,
                "pages": 1,
            ],
        ])

        let comments = try JSONDecoder().decode(CommentsData.self, from: data)

        XCTAssertEqual(comments.docs.map(\.id), ["comment-1"])
        XCTAssertTrue(comments.topComments.isEmpty)
    }
}

private func jsonData(_ object: Any) -> Data {
    (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
}
