import XCTest
@testable import BikaMacos

@MainActor
final class MacReaderProgressTests: XCTestCase {
    func testRapidPageTurnsCoalesceIntoASingleHistoryWrite() async throws {
        let store = CountingKeyValueStore()
        let (viewModel, readingStore) = try makeViewModel(store: store, pageCount: 20)

        for _ in 0..<10 {
            viewModel.nextPage()
        }

        XCTAssertEqual(viewModel.currentPageIndex, 10)
        XCTAssertEqual(
            store.writeCount(forKeyPrefix: "macReadingHistory.account."),
            0,
            "翻页过程中不应该立刻落盘"
        )

        try await Task.sleep(for: .milliseconds(150))

        XCTAssertEqual(store.writeCount(forKeyPrefix: "macReadingHistory.account."), 1)
        XCTAssertEqual(readingStore.progress(for: "comic-progress")?.pageIndex, 10)
    }

    func testSaveCurrentProgressFlushesImmediatelyWithoutWaiting() throws {
        let store = CountingKeyValueStore()
        let (viewModel, readingStore) = try makeViewModel(store: store, pageCount: 20)

        viewModel.nextPage()
        viewModel.nextPage()
        viewModel.saveCurrentProgress()

        XCTAssertEqual(store.writeCount(forKeyPrefix: "macReadingHistory.account."), 1)
        XCTAssertEqual(readingStore.progress(for: "comic-progress")?.pageIndex, 2)
    }

    func testFlushedProgressIsNotOverwrittenByAPendingPageTurn() async throws {
        let store = CountingKeyValueStore()
        let (viewModel, readingStore) = try makeViewModel(store: store, pageCount: 20)

        viewModel.nextPage()
        viewModel.saveCurrentProgress()
        XCTAssertEqual(readingStore.progress(for: "comic-progress")?.pageIndex, 1)

        // The pending debounce from the page turn must not fire a second, stale write.
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(store.writeCount(forKeyPrefix: "macReadingHistory.account."), 1)
    }

    // MARK: - Helpers

    private func makeViewModel(
        store: CountingKeyValueStore,
        pageCount: Int
    ) throws -> (MacReaderViewModel, MacReadingStore) {
        let accountSession = AccountSessionStore(keyValueStore: store)
        _ = try accountSession.activate(userID: "mac-user")
        let readingStore = MacReadingStore(
            keyValueStore: store,
            accountSessionStore: accountSession
        )
        let episode = Episode(id: "ep-1", title: "第一话", order: 1, updated_at: nil)
        let request = MacReaderLaunchRequest(
            comicId: "comic-progress",
            comicTitle: "进度漫画",
            author: "作者",
            thumbPath: nil,
            thumbServer: nil,
            episodes: [MacReaderEpisode(episode: episode)],
            startEpisodeIndex: 0,
            startPageIndex: 0,
            restoreSavedProgress: false
        )

        let viewModel = MacReaderViewModel(
            request: request,
            readingStore: readingStore,
            keyValueStore: store,
            progressSaveDelay: .milliseconds(50)
        )
        viewModel.pages = (0..<pageCount).map {
            ComicPage(id: "page-\($0)", media: Media(originalName: nil, path: "p\($0).jpg", fileServer: nil))
        }
        return (viewModel, readingStore)
    }
}
