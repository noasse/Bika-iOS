import XCTest
@testable import BikaMacos

@MainActor
final class MacReadingScopeTests: XCTestCase {
    func testCloudHistoryResponseForPreviousAccountIsDiscardedAfterSwitch() throws {
        let store = InMemoryKeyValueStore()
        let accountSession = AccountSessionStore(keyValueStore: store)
        let scopeA = try accountSession.activate(userID: "mac-user-a")
        let readingStore = MacReadingStore(
            keyValueStore: store,
            accountSessionStore: accountSession
        )

        _ = try accountSession.activate(userID: "mac-user-b")
        readingStore.applyCloudHistoryItems(
            [
                CloudHistoryItem(
                    comicID: "comic-from-a",
                    title: "账号 A 云历史",
                    lastReadAt: Date(timeIntervalSince1970: 1_710_000_000),
                    episodeOrder: 4,
                    episodeTitle: "第4话",
                    pageIndex: 6
                ),
            ],
            expectedScope: scopeA
        )

        XCTAssertTrue(readingStore.history.isEmpty)
        XCTAssertNil(readingStore.progress(for: "comic-from-a"))
        _ = try accountSession.activate(userID: "mac-user-a")
        XCTAssertTrue(readingStore.history.isEmpty)
        XCTAssertNil(readingStore.progress(for: "comic-from-a"))
    }

    func testReaderOpenedByAccountADoesNotWriteProgressAfterSwitchingToAccountB() throws {
        let store = InMemoryKeyValueStore()
        let accountSession = AccountSessionStore(keyValueStore: store)
        _ = try accountSession.activate(userID: "mac-user-a")
        let readingStore = MacReadingStore(
            keyValueStore: store,
            accountSessionStore: accountSession
        )
        let episode = Episode(id: "ep-1", title: "第一话", order: 1, updated_at: nil)
        let readerEpisode = MacReaderEpisode(episode: episode)
        let request = MacReaderLaunchRequest(
            comicId: "comic-a-reader",
            comicTitle: "账号 A 打开的漫画",
            author: nil,
            thumbPath: nil,
            thumbServer: nil,
            episodes: [readerEpisode],
            startEpisodeIndex: 0,
            startPageIndex: 0,
            restoreSavedProgress: false
        )
        let viewModel = MacReaderViewModel(
            request: request,
            readingStore: readingStore,
            keyValueStore: store
        )

        viewModel.currentPageIndex = 2
        viewModel.saveCurrentProgress()
        XCTAssertEqual(readingStore.progress(for: request.comicId)?.pageIndex, 2)

        _ = try accountSession.activate(userID: "mac-user-b")
        viewModel.currentPageIndex = 7
        viewModel.saveCurrentProgress()
        XCTAssertNil(readingStore.progress(for: request.comicId))

        _ = try accountSession.activate(userID: "mac-user-a")
        XCTAssertEqual(readingStore.progress(for: request.comicId)?.pageIndex, 2)
    }
}
