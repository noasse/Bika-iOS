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

    enum ReaderMode: String {
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

    func startLoadingPages() {
        activeLoadSequence += 1
        let loadSequence = activeLoadSequence
        errorMessage = nil
        guard let episode = currentEpisode else {
            loadTask?.cancel()
            pages = []
            paginationPage = 0
            paginationTotalPages = 1
            isLoading = false
            return
        }

        loadTask?.cancel()
        isLoading = true
        pages = []
        paginationPage = 0
        paginationTotalPages = 1

        loadTask = Task { [weak self] in
            await self?.loadPages(for: episode, loadSequence: loadSequence)
        }
    }

    private func loadPages(for episode: Episode, loadSequence: Int) async {
        defer {
            if activeLoadSequence == loadSequence {
                isLoading = false
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
                    break
                }

                let resolvedPage = data.pages.page
                let resolvedPages = max(data.pages.pages, resolvedPage)

                guard resolvedPage >= nextPage else {
                    resolvedPaginationPage = resolvedPages
                    resolvedTotalPages = resolvedPages
                    break
                }

                guard !data.pages.docs.isEmpty else {
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
                errorMessage = error.localizedDescription
                break
            }
        }

        guard !Task.isCancelled, activeLoadSequence == loadSequence else { return }
        pages = loadedPages
        paginationPage = resolvedPaginationPage
        paginationTotalPages = resolvedTotalPages
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
