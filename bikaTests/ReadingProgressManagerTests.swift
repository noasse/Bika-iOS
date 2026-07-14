import XCTest
@testable import bika

@MainActor
final class ReadingProgressManagerTests: XCTestCase {
    override func tearDown() {
        TestSupport.restoreLiveDependencies()
        super.tearDown()
    }

    func testSaveGetAndRemoveProgress() throws {
        let store = InMemoryKeyValueStore()
        let accountSession = AccountSessionStore(keyValueStore: store)
        _ = try accountSession.activate(userID: "user-a")
        let manager = ReadingProgressManager(
            keyValueStore: store,
            accountSessionStore: accountSession
        )

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

    @MainActor
    func testAccountScopeUsesTrimmedStableUserIDHashAndRejectsMissingID() throws {
        let store = InMemoryKeyValueStore()
        let accountSession = AccountSessionStore(keyValueStore: store)

        let scope = try accountSession.activate(userID: "  user-a  ")

        XCTAssertEqual(
            scope.rawValue,
            "0ab53791e40459dc23b75503be485a9d368df901e00ab4a053d9b33b225a7e53"
        )
        XCTAssertThrowsError(try accountSession.activate(userID: "   "))
    }

    @MainActor
    func testReadingProgressIsIsolatedByAccountAndUnavailableWithoutScope() throws {
        let store = InMemoryKeyValueStore()
        let accountSession = AccountSessionStore(keyValueStore: store)
        let manager = ReadingProgressManager(
            keyValueStore: store,
            accountSessionStore: accountSession
        )
        let progress = ReadingProgressManager.Progress(
            episodeOrder: 2,
            episodeTitle: "第2话",
            pageIndex: 8
        )

        manager.save(comicId: "comic-1", progress: progress)
        XCTAssertNil(manager.get(comicId: "comic-1"))

        _ = try accountSession.activate(userID: "user-a")
        manager.save(comicId: "comic-1", progress: progress)
        XCTAssertEqual(manager.get(comicId: "comic-1")?.pageIndex, 8)

        _ = try accountSession.activate(userID: "user-b")
        XCTAssertNil(manager.get(comicId: "comic-1"))

        _ = try accountSession.activate(userID: "user-a")
        XCTAssertEqual(manager.get(comicId: "comic-1")?.pageIndex, 8)
    }
}

@MainActor
final class ReadingHistoryManagerTests: XCTestCase {
    override func tearDown() {
        TestSupport.restoreLiveDependencies()
        super.tearDown()
    }

    @MainActor
    func testRecordStoresCurrentReadingProgressInHistoryItem() throws {
        let store = InMemoryKeyValueStore()
        let accountSession = AccountSessionStore(keyValueStore: store)
        let scope = try accountSession.activate(userID: "user-a")
        let progressManager = ReadingProgressManager(
            keyValueStore: store,
            accountSessionStore: accountSession
        )
        progressManager.save(
            comicId: "comic-1",
            progress: .init(episodeOrder: 7, episodeTitle: "第7话", pageIndex: 12)
        )
        let manager = ReadingHistoryManager(
            keyValueStore: store,
            cloudHistorySync: nil,
            readingProgressManager: progressManager,
            accountSessionStore: accountSession
        )

        manager.record(
            comicId: "comic-1",
            title: "Example Comic",
            thumbPath: "covers/comic-1.jpg",
            thumbServer: "https://cdn.invalid",
            author: "Example Author"
        )

        let key = "readingHistory.account.\(scope.rawValue)"
        let data = try XCTUnwrap(store.data(forKey: key))
        let envelope = try JSONDecoder().decode(
            PersistenceEnvelope<[ReadingHistoryManager.HistoryItem]>.self,
            from: data
        )
        let item = try XCTUnwrap(envelope.payload.first)
        XCTAssertEqual(item.episodeOrder, 7)
        XCTAssertEqual(item.episodeTitle, "第7话")
        XCTAssertEqual(item.pageIndex, 12)
    }

    @MainActor
    func testApplyingCloudHistoryItemsStoresReadingProgress() throws {
        let store = InMemoryKeyValueStore()
        let accountSession = AccountSessionStore(keyValueStore: store)
        _ = try accountSession.activate(userID: "user-a")
        let progressManager = ReadingProgressManager(
            keyValueStore: store,
            accountSessionStore: accountSession
        )
        let manager = ReadingHistoryManager(
            keyValueStore: store,
            cloudHistorySync: nil,
            readingProgressManager: progressManager,
            accountSessionStore: accountSession
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

    @MainActor
    func testCloudHistoryResponseForPreviousAccountIsDiscardedAfterSwitch() throws {
        let store = InMemoryKeyValueStore()
        let accountSession = AccountSessionStore(keyValueStore: store)
        let scopeA = try accountSession.activate(userID: "user-a")
        let progressManager = ReadingProgressManager(
            keyValueStore: store,
            accountSessionStore: accountSession
        )
        let manager = ReadingHistoryManager(
            keyValueStore: store,
            cloudHistorySync: nil,
            readingProgressManager: progressManager,
            accountSessionStore: accountSession
        )

        _ = try accountSession.activate(userID: "user-b")
        manager.applyCloudHistoryItems(
            [
                CloudHistoryItem(
                    comicID: "comic-from-a",
                    title: "账号 A 云历史",
                    lastReadAt: Date(timeIntervalSince1970: 1_710_000_000),
                    episodeOrder: 3,
                    episodeTitle: "第3话",
                    pageIndex: 5
                ),
            ],
            expectedScope: scopeA
        )

        XCTAssertTrue(manager.items.isEmpty)
        XCTAssertNil(progressManager.get(comicId: "comic-from-a"))
        _ = try accountSession.activate(userID: "user-a")
        XCTAssertTrue(manager.items.isEmpty)
        XCTAssertNil(progressManager.get(comicId: "comic-from-a"))
    }

    @MainActor
    func testHistoryAndOrphanProgressClearOnlyCurrentAccount() throws {
        let store = InMemoryKeyValueStore()
        let accountSession = AccountSessionStore(keyValueStore: store)
        let progressManager = ReadingProgressManager(
            keyValueStore: store,
            accountSessionStore: accountSession
        )
        let manager = ReadingHistoryManager(
            keyValueStore: store,
            cloudHistorySync: nil,
            readingProgressManager: progressManager,
            accountSessionStore: accountSession
        )

        _ = try accountSession.activate(userID: "user-a")
        progressManager.save(
            comicId: "orphan-a",
            progress: .init(episodeOrder: 1, episodeTitle: "A", pageIndex: 3)
        )
        manager.record(
            comicId: "history-a",
            title: "A",
            thumbPath: "a.jpg",
            thumbServer: nil,
            author: nil
        )

        _ = try accountSession.activate(userID: "user-b")
        progressManager.save(
            comicId: "orphan-b",
            progress: .init(episodeOrder: 1, episodeTitle: "B", pageIndex: 4)
        )

        _ = try accountSession.activate(userID: "user-a")
        manager.clearAll()
        XCTAssertNil(progressManager.get(comicId: "orphan-a"))
        XCTAssertTrue(manager.items.isEmpty)

        _ = try accountSession.activate(userID: "user-b")
        XCTAssertEqual(progressManager.get(comicId: "orphan-b")?.pageIndex, 4)
    }

    @MainActor
    func testLegacyDataMigratesOnlyToFirstValidatedAccountAndKeepsCorruptBackup() throws {
        let store = InMemoryKeyValueStore()
        let legacyProgress = ReadingProgressManager.Progress(
            episodeOrder: 9,
            episodeTitle: "旧章节",
            pageIndex: 11
        )
        store.set(try JSONEncoder().encode(legacyProgress), forKey: "readProgress_legacy-comic")
        store.set(Data("not-json".utf8), forKey: "readingHistory")

        let accountSession = AccountSessionStore(keyValueStore: store)
        _ = try accountSession.activate(userID: "user-a")
        let progressManager = ReadingProgressManager(
            keyValueStore: store,
            accountSessionStore: accountSession
        )
        let manager = ReadingHistoryManager(
            keyValueStore: store,
            cloudHistorySync: nil,
            readingProgressManager: progressManager,
            accountSessionStore: accountSession
        )

        XCTAssertEqual(progressManager.get(comicId: "legacy-comic")?.pageIndex, 11)
        XCTAssertTrue(manager.items.isEmpty)
        let backup = try XCTUnwrap(store.data(forKey: "readingHistory.corruptBackup"))
        XCTAssertEqual(backup, Data("not-json".utf8))

        _ = try accountSession.activate(userID: "user-b")
        XCTAssertNil(progressManager.get(comicId: "legacy-comic"))
        _ = manager.items
        XCTAssertEqual(store.data(forKey: "readingHistory.corruptBackup"), backup)
    }
}
