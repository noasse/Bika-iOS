import SwiftUI

@Observable
final class ReaderViewModel {
    var pages: [ComicPage] = []
    var isLoading = false
    var errorMessage: String?
    var currentPageIndex = 0
    var showToolbar = false
    var readerMode: ReaderMode

    let comicId: String
    let episodes: [Episode]
    var currentEpisodeIndex: Int

    private let client: any APIClientProtocol
    private let keyValueStore: any KeyValueStore
    private var loadTask: Task<Void, Never>?
    private var activeLoadSequence = 0
    private var paginationPage = 0
    private var paginationTotalPages = 1
    private var displayedEpisodeID: String?

    private enum PageLoadError: LocalizedError {
        case missingData
        case pageDidNotAdvance(requested: Int, returned: Int)
        case emptyPageWithMorePages(page: Int)

        var errorDescription: String? {
            switch self {
            case .missingData:
                return "页面数据为空，请重试"
            case .pageDidNotAdvance(let requested, let returned):
                return "分页数据异常：请求第 \(requested) 页，返回第 \(returned) 页"
            case .emptyPageWithMorePages(let page):
                return "分页数据异常：第 \(page) 页为空，但服务端声明还有后续页面"
            }
        }
    }

    nonisolated enum ReaderMode: String, Sendable {
        case horizontal, vertical
    }

    init(
        comicId: String,
        episodes: [Episode],
        startEpisodeIndex: Int,
        client: any APIClientProtocol = APIClient.shared,
        keyValueStore: any KeyValueStore = AppDependencies.shared.keyValueStore
    ) {
        self.comicId = comicId
        self.episodes = episodes
        self.currentEpisodeIndex = startEpisodeIndex
        self.client = client
        self.keyValueStore = keyValueStore
        let savedMode = keyValueStore.string(forKey: "readerMode") ?? ReaderMode.horizontal.rawValue
        readerMode = ReaderMode(rawValue: savedMode) ?? .horizontal
    }

    var currentEpisode: Episode? {
        guard episodes.indices.contains(currentEpisodeIndex) else { return nil }
        return episodes[currentEpisodeIndex]
    }

    var hasPreviousEpisode: Bool { currentEpisodeIndex > 0 }
    var hasNextEpisode: Bool { currentEpisodeIndex < episodes.count - 1 }
    var showsFullScreenLoadError: Bool { errorMessage != nil && pages.isEmpty }
    var showsPaginationError: Bool { errorMessage != nil && !pages.isEmpty }

    func startLoadingPages() {
        activeLoadSequence += 1
        let loadSequence = activeLoadSequence
        loadTask?.cancel()
        errorMessage = nil
        guard let episode = currentEpisode else {
            pages = []
            displayedEpisodeID = nil
            paginationPage = 0
            paginationTotalPages = 1
            isLoading = false
            loadTask = nil
            return
        }

        let retainedPages: [ComicPage]
        if displayedEpisodeID == episode.id {
            retainedPages = pages
        } else {
            retainedPages = []
            pages = []
            displayedEpisodeID = episode.id
        }

        isLoading = true
        paginationPage = 0
        paginationTotalPages = 1

        loadTask = Task { [weak self] in
            await self?.loadPages(
                for: episode,
                loadSequence: loadSequence,
                retainedPages: retainedPages
            )
        }
    }

    func cancelLoadingPages() {
        activeLoadSequence += 1
        loadTask?.cancel()
        loadTask = nil
        isLoading = false
    }

    private func loadPages(
        for episode: Episode,
        loadSequence: Int,
        retainedPages: [ComicPage]
    ) async {
        defer {
            if activeLoadSequence == loadSequence {
                isLoading = false
                loadTask = nil
            }
        }

        var loadedPages: [ComicPage] = []
        var nextPage = 1
        var resolvedPaginationPage = 0
        var resolvedTotalPages = 1

        while nextPage <= resolvedTotalPages {
            guard !Task.isCancelled, activeLoadSequence == loadSequence else { return }
            do {
                let response: APIResponse<ComicPagesData> = try await client.send(
                    .comicPages(comicId: comicId, epsOrder: episode.order, page: nextPage)
                )
                guard !Task.isCancelled, activeLoadSequence == loadSequence else { return }

                guard let data = response.data else {
                    applyLoadFailure(
                        PageLoadError.missingData,
                        attemptedPages: loadedPages,
                        retainedPages: retainedPages,
                        episodeID: episode.id,
                        paginationPage: resolvedPaginationPage,
                        paginationTotalPages: resolvedTotalPages
                    )
                    return
                }

                let resolvedPage = data.pages.page
                let resolvedPages = max(data.pages.pages, resolvedPage)

                guard resolvedPage >= nextPage else {
                    applyLoadFailure(
                        PageLoadError.pageDidNotAdvance(requested: nextPage, returned: resolvedPage),
                        attemptedPages: loadedPages,
                        retainedPages: retainedPages,
                        episodeID: episode.id,
                        paginationPage: resolvedPaginationPage,
                        paginationTotalPages: resolvedTotalPages
                    )
                    return
                }

                if data.pages.docs.isEmpty {
                    guard resolvedPage >= resolvedPages else {
                        applyLoadFailure(
                            PageLoadError.emptyPageWithMorePages(page: resolvedPage),
                            attemptedPages: loadedPages,
                            retainedPages: retainedPages,
                            episodeID: episode.id,
                            paginationPage: resolvedPaginationPage,
                            paginationTotalPages: resolvedTotalPages
                        )
                        return
                    }

                    resolvedPaginationPage = resolvedPage
                    resolvedTotalPages = resolvedPages
                    break
                }

                loadedPages.append(contentsOf: data.pages.docs)
                resolvedPaginationPage = resolvedPage
                resolvedTotalPages = resolvedPages

                let upcomingPage = resolvedPage + 1
                if upcomingPage <= nextPage && nextPage <= resolvedTotalPages {
                    break
                }

                nextPage = upcomingPage
            } catch {
                guard !Task.isCancelled, activeLoadSequence == loadSequence else { return }
                applyLoadFailure(
                    error,
                    attemptedPages: loadedPages,
                    retainedPages: retainedPages,
                    episodeID: episode.id,
                    paginationPage: resolvedPaginationPage,
                    paginationTotalPages: resolvedTotalPages
                )
                return
            }
        }

        guard !Task.isCancelled, activeLoadSequence == loadSequence else { return }
        pages = loadedPages
        displayedEpisodeID = episode.id
        paginationPage = resolvedPaginationPage
        paginationTotalPages = resolvedTotalPages
        errorMessage = nil
    }

    private func applyLoadFailure(
        _ error: Error,
        attemptedPages: [ComicPage],
        retainedPages: [ComicPage],
        episodeID: String,
        paginationPage: Int,
        paginationTotalPages: Int
    ) {
        if retainedPages.isEmpty {
            pages = attemptedPages
        }
        displayedEpisodeID = episodeID
        self.paginationPage = paginationPage
        self.paginationTotalPages = paginationTotalPages
        errorMessage = error.localizedDescription
    }

    func goToEpisode(_ index: Int) {
        guard episodes.indices.contains(index) else { return }
        currentEpisodeIndex = index
        startLoadingPages()
    }

    func nextEpisode() {
        goToEpisode(currentEpisodeIndex + 1)
    }

    func previousEpisode() {
        goToEpisode(currentEpisodeIndex - 1)
    }

    func toggleToolbar() {
        showToolbar.toggle()
    }

    func setReaderMode(_ mode: ReaderMode) {
        readerMode = mode
        keyValueStore.set(mode.rawValue, forKey: "readerMode")
    }
}
