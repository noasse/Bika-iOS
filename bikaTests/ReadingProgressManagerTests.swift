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

final class ReadingHistoryManagerTests: XCTestCase {
    override func tearDown() {
        TestSupport.restoreLiveDependencies()
        super.tearDown()
    }

    @MainActor
    func testRecordStoresCurrentReadingProgressInHistoryItem() throws {
        let store = InMemoryKeyValueStore()
        let progressManager = ReadingProgressManager(keyValueStore: store)
        progressManager.save(
            comicId: "comic-1",
            progress: .init(episodeOrder: 7, episodeTitle: "第7话", pageIndex: 12)
        )
        let manager = ReadingHistoryManager(
            keyValueStore: store,
            cloudHistorySync: nil,
            readingProgressManager: progressManager
        )

        manager.record(
            comicId: "comic-1",
            title: "Example Comic",
            thumbPath: "covers/comic-1.jpg",
            thumbServer: "https://cdn.invalid",
            author: "Example Author"
        )

        let data = try XCTUnwrap(store.data(forKey: "readingHistory"))
        let items = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        let item = try XCTUnwrap(items.first)
        XCTAssertEqual(item["episodeOrder"] as? Int, 7)
        XCTAssertEqual(item["episodeTitle"] as? String, "第7话")
        XCTAssertEqual(item["pageIndex"] as? Int, 12)
    }

    @MainActor
    func testApplyingCloudHistoryItemsStoresReadingProgress() throws {
        let store = InMemoryKeyValueStore()
        let progressManager = ReadingProgressManager(keyValueStore: store)
        let manager = ReadingHistoryManager(
            keyValueStore: store,
            cloudHistorySync: nil,
            readingProgressManager: progressManager
        )

        manager.applyCloudHistoryItems([
            CloudHistoryItem(
                comicID: "comic-2",
                title: "Cloud Comic",
                author: nil,
                thumbPath: nil,
                thumbServer: nil,
                lastReadAt: Date(timeIntervalSince1970: 1_710_000_000),
                episodeOrder: 3,
                episodeTitle: "第3话",
                pageIndex: 5
            )
        ])

        let progress = try XCTUnwrap(progressManager.get(comicId: "comic-2"))
        XCTAssertEqual(progress.episodeOrder, 3)
        XCTAssertEqual(progress.episodeTitle, "第3话")
        XCTAssertEqual(progress.pageIndex, 5)
    }
}
