import Foundation

extension MacLibraryModel {
    func selectComic(_ summary: MacComicSummary) async {
        await detailStore.selectComic(summary)
    }

    func selectComic(id: String) async {
        let fallbackSummary = displayedListItems.first { $0.id == id }
        await detailStore.selectComic(id: id, fallbackSummary: fallbackSummary)
    }

    func toggleFavourite() async {
        let didMutate = await detailStore.toggleFavourite()
        if didMutate, sidebarSelection == .favourites {
            await listStore.loadFavourites(page: max(currentPage, 1))
        }
    }

    func toggleLike() async {
        await detailStore.toggleLike()
    }

    func makeContinueReaderRequest() -> MacReaderLaunchRequest? {
        detailStore.makeContinueReaderRequest()
    }

    func readingProgress(for detail: ComicDetail) -> MacReadingProgress? {
        detailStore.readingProgress(for: detail)
    }

    func readerDidClose(comicId: String) {
        if sidebarSelection == .history {
            listStore.loadHistory()
        }
        detailStore.readerDidClose(comicId: comicId)
    }

    func makeEpisodeReaderRequest(episode: Episode) -> MacReaderLaunchRequest? {
        detailStore.makeEpisodeReaderRequest(episode: episode)
    }

    func makeHistoryReaderRequest(for comicId: String) async -> MacReaderLaunchRequest? {
        if selectedComicID != comicId || detail?.id != comicId || episodes.isEmpty {
            await selectComic(id: comicId)
        }
        return detailStore.makeContinueReaderRequest()
    }

    func isBlocked(_ category: String) -> Bool {
        listStore.isBlocked(category)
    }

    func toggleBlockedCategory(_ category: String) {
        listStore.toggleBlockedCategory(category)
    }

    func removeHistory(comicId: String) {
        listStore.removeHistory(comicId: comicId)
        if selectedComicID == comicId {
            detailStore.clearDetail()
        }
    }

    func clearHistory() {
        listStore.clearHistory()
        detailStore.clearDetail()
    }
}
