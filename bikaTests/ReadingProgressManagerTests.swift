import XCTest
@testable import bika

final class ReadingProgressManagerTests: XCTestCase {
    override func tearDown() {
        TestSupport.restoreLiveDependencies()
        super.tearDown()
    }

    func testSaveGetAndRemoveProgress() throws {
        let store = InMemoryKeyValueStore()
        let manager = ReadingProgressManager(keyValueStore: store)

        manager.save(
            comicId: "comic-1",
            progress: .init(episodeOrder: 2, episodeTitle: "第2话", pageIndex: 8)
        )

        let progress = try XCTUnwrap(manager.get(comicId: "comic-1"))
        XCTAssertEqual(progress.episodeOrder, 2)
        XCTAssertEqual(progress.episodeTitle, "第2话")
        XCTAssertEqual(progress.pageIndex, 8)

        manager.remove(comicId: "comic-1")
        XCTAssertNil(manager.get(comicId: "comic-1"))
    }
}
