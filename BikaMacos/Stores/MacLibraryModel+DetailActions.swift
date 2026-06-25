import Foundation

extension MacLibraryModel {
    func selectComic(_ summary: MacComicSummary) async {
        selectedComicID = summary.id
        selectedSummary = summary
        await loadDetail(comicId: summary.id)
    }

    func selectComic(id: String) async {
        selectedComicID = id
        selectedSummary = displayedListItems.first { $0.id == id } ?? selectedSummary
        await loadDetail(comicId: id)
    }

    func toggleFavourite() async {
        guard let comicId = selectedComicID, !isTogglingFavourite else { return }
        isTogglingFavourite = true
        defer { isTogglingFavourite = false }
        do {
            let _: APIResponse<EmptyData> = try await client.send(.favouriteComic(id: comicId))
            guard selectedComicID == comicId else {
                if sidebarSelection == .favourites {
                    await loadFavourites(page: max(currentPage, 1))
                }
                return
            }
            await loadDetail(comicId: comicId)
            if sidebarSelection == .favourites {
                await loadFavourites(page: max(currentPage, 1))
            }
        } catch {
            detailError = error.localizedDescription
        }
    }

    func toggleLike() async {
        guard let comicId = selectedComicID, !isTogglingLike else { return }
        isTogglingLike = true
        defer { isTogglingLike = false }

        do {
            let _: APIResponse<LikeActionData> = try await client.send(.likeComic(id: comicId))
            guard selectedComicID == comicId else { return }
            await loadDetail(comicId: comicId)
        } catch {
            detailError = error.localizedDescription
        }
    }

    func punchIn() async {
        guard !isPunching else { return }
        isPunching = true
        defer { isPunching = false }

        do {
            let _: APIResponse<EmptyData> = try await client.send(.punchIn())
            await loadProfile()
        } catch {
            listError = error.localizedDescription
        }
    }

    func updateSlogan(_ slogan: String) async {
        let trimmedSlogan = slogan.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let _: APIResponse<EmptyData> = try await client.send(.setSlogan(trimmedSlogan))
            await loadProfile()
        } catch {
            listError = error.localizedDescription
        }
    }

    func makeContinueReaderRequest() -> MacReaderLaunchRequest? {
        guard let detail else { return nil }
        let progress = readingProgress(for: detail)
        let startIndex: Int
        let startPage: Int
        if
            let progress,
            let progressEpisodeIndex = episodes.firstIndex(where: { $0.order == progress.episodeOrder })
        {
            startIndex = progressEpisodeIndex
            startPage = progress.pageIndex
        } else {
            startIndex = 0
            startPage = 0
        }

        return makeReaderRequest(detail: detail, startEpisodeIndex: startIndex, startPageIndex: startPage, restore: true)
    }

    func readingProgress(for detail: ComicDetail) -> MacReadingProgress? {
        guard
            let progress = readingStore.progress(for: detail.id),
            episodes.contains(where: { $0.order == progress.episodeOrder })
        else {
            return nil
        }
        return progress
    }

    func readerDidClose(comicId: String) {
        if sidebarSelection == .history {
            loadHistory()
        }

        guard selectedComicID == comicId, detail?.id == comicId else { return }
        readingProgressRevision &+= 1
    }

    func makeEpisodeReaderRequest(episode: Episode) -> MacReaderLaunchRequest? {
        guard
            let detail,
            let episodeIndex = episodes.firstIndex(where: { $0.id == episode.id })
        else {
            return nil
        }

        return makeReaderRequest(detail: detail, startEpisodeIndex: episodeIndex, startPageIndex: 0, restore: false)
    }

    func makeHistoryReaderRequest(for comicId: String) async -> MacReaderLaunchRequest? {
        if selectedComicID != comicId || detail?.id != comicId || episodes.isEmpty {
            await selectComic(id: comicId)
        }
        return makeContinueReaderRequest()
    }

    func isBlocked(_ category: String) -> Bool {
        blockedCategoriesStore.isBlocked(category)
    }

    func toggleBlockedCategory(_ category: String) {
        blockedCategoriesStore.toggle(category)
    }

    func removeHistory(comicId: String) {
        readingStore.removeHistory(comicId: comicId)
        loadHistory()
        if selectedComicID == comicId {
            clearDetail()
        }
    }

    func clearHistory() {
        readingStore.clearHistory()
        loadHistory()
        clearDetail()
    }
}
