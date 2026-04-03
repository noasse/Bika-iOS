import SwiftUI

nonisolated enum ComicResultsQuery: Sendable {
    case favourites
    case author(String)
    case tag(String)

    var pageStorageKey: String {
        switch self {
        case .favourites:
            return "lastPage_favourites"
        case .author(let author):
            return "lastPage_author_\(author)"
        case .tag(let keyword):
            return "lastPage_tag_\(keyword)"
        }
    }

    var restorationKey: String {
        switch self {
        case .favourites:
            return "comicResults_favourites"
        case .author(let author):
            return "comicResults_author_\(author)"
        case .tag(let keyword):
            return "comicResults_tag_\(keyword)"
        }
    }

    func loadPage(
        using client: any APIClientProtocol,
        page: Int,
        sort: SortMode
    ) async throws -> APIResponse<ComicsData> {
        switch self {
        case .favourites:
            return try await client.send(.favourites(page: page, sort: sort))
        case .author(let author):
            return try await client.send(.search(keyword: author, page: page, sort: sort))
        case .tag(let keyword):
            return try await client.send(.search(keyword: keyword, page: page, sort: sort))
        }
    }
}

@Observable
final class ComicResultsViewModel {
    var comics: [Comic] = []
    var isLoading = false
    var currentPage = 0
    var totalPages = 1
    var sortMode: SortMode = .defaultSort
    var lastVisitedPage = 0
    var errorMessage: String?
    var pendingRestoreComicID: String?

    let query: ComicResultsQuery

    private let client: any APIClientProtocol
    private let keyValueStore: any KeyValueStore
    private let navigationStateStore: NavigationStateStore
    private var activeRequestID = 0
    private var initialPageToLoad: Int?

    init(
        query: ComicResultsQuery,
        client: any APIClientProtocol = APIClient.shared,
        keyValueStore: any KeyValueStore = AppDependencies.shared.keyValueStore,
        navigationStateStore: NavigationStateStore = .shared
    ) {
        self.query = query
        self.client = client
        self.keyValueStore = keyValueStore
        self.navigationStateStore = navigationStateStore
        lastVisitedPage = keyValueStore.integer(forKey: query.pageStorageKey)

        if let savedState = navigationStateStore.comicListState(for: query.restorationKey) {
            sortMode = SortMode(rawValue: savedState.sortModeRawValue) ?? .defaultSort
            initialPageToLoad = max(savedState.currentPage, 1)
            pendingRestoreComicID = savedState.anchorComicID
        }
    }

    func loadFirstPage() async {
        guard comics.isEmpty else { return }
        let initialPage = initialPageToLoad ?? max(lastVisitedPage, 1)
        initialPageToLoad = nil
        await loadPage(initialPage)
    }

    func loadPage(_ page: Int) async {
        guard page >= 1 else { return }
        let requestID = beginRequest()
        let requestedSort = sortMode
        errorMessage = nil

        do {
            let response = try await query.loadPage(using: client, page: page, sort: requestedSort)
            guard requestID == activeRequestID else { return }

            if let data = response.data {
                comics = data.comics.docs
                currentPage = data.comics.page
                totalPages = data.comics.pages
                lastVisitedPage = data.comics.page
                saveNavigationState(anchorComicID: pendingRestoreComicID)
            } else {
                comics = []
                currentPage = max(page, 1)
                totalPages = 1
                lastVisitedPage = currentPage
                saveNavigationState(anchorComicID: pendingRestoreComicID)
            }
        } catch {
            guard requestID == activeRequestID else { return }
            errorMessage = error.localizedDescription
        }

        finishRequest(requestID)
    }

    func nextPage() async {
        guard currentPage < totalPages else { return }
        lastVisitedPage = currentPage
        await loadPage(currentPage + 1)
    }

    func prevPage() async {
        guard currentPage > 1 else { return }
        lastVisitedPage = currentPage
        await loadPage(currentPage - 1)
    }

    func goToLastVisited() async {
        guard lastVisitedPage > 0, lastVisitedPage <= totalPages else { return }
        await loadPage(lastVisitedPage)
    }

    func changeSort(_ mode: SortMode) async {
        guard mode != sortMode else { return }
        sortMode = mode
        lastVisitedPage = currentPage
        errorMessage = nil
        comics = []
        currentPage = 0
        totalPages = 1
        pendingRestoreComicID = nil
        saveNavigationState(anchorComicID: nil)
        await loadPage(1)
    }

    func persistPage() {
        guard currentPage > 0 else { return }
        keyValueStore.set(currentPage, forKey: query.pageStorageKey)
        saveNavigationState(anchorComicID: pendingRestoreComicID)
    }

    func rememberNavigationAnchor(comicID: String) {
        pendingRestoreComicID = comicID
        saveNavigationState(anchorComicID: comicID)
    }

    func consumePendingRestoreComicID() {
        pendingRestoreComicID = nil
        saveNavigationState(anchorComicID: nil)
    }

    private func beginRequest() -> Int {
        activeRequestID += 1
        isLoading = true
        return activeRequestID
    }

    private func finishRequest(_ requestID: Int) {
        guard requestID == activeRequestID else { return }
        isLoading = false
    }

    private func saveNavigationState(anchorComicID: String?) {
        let state = ComicListNavigationState(
            currentPage: max(currentPage, lastVisitedPage),
            sortModeRawValue: sortMode.rawValue,
            anchorComicID: anchorComicID
        )
        navigationStateStore.saveComicListState(state, for: query.restorationKey)
    }
}
