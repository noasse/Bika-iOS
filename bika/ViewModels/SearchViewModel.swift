import SwiftUI

@Observable
final class SearchViewModel {
    var comics: [Comic] = []
    var keyword = ""
    var activeKeyword = ""
    var isLoading = false
    var hasSearched = false
    var errorMessage: String?
    var sortMode: SortMode = .defaultSort
    var currentPage = 0
    var totalPages = 1
    var lastVisitedPage = 0

    private let client: any APIClientProtocol
    private let keyValueStore: any KeyValueStore

    init(
        client: any APIClientProtocol = APIClient.shared,
        keyValueStore: any KeyValueStore = AppDependencies.shared.keyValueStore
    ) {
        self.client = client
        self.keyValueStore = keyValueStore
    }

    func search() async {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        keyword = trimmed
        activeKeyword = trimmed

        lastVisitedPage = keyValueStore.integer(forKey: "lastPage_search_\(activeKeyword)")

        isLoading = true
        hasSearched = true
        errorMessage = nil
        comics = []
        currentPage = 0
        totalPages = 1
        defer { isLoading = false }

        await loadPage(1)
    }

    func loadPage(_ page: Int) async {
        guard page >= 1, !activeKeyword.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let response: APIResponse<ComicsData> = try await client.send(
                .search(keyword: activeKeyword, page: page, sort: sortMode)
            )
            if let data = response.data {
                comics = data.comics.docs
                currentPage = data.comics.page
                totalPages = data.comics.pages
            }
        } catch {
            errorMessage = error.localizedDescription
        }
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
        await loadPage(1)
    }

    func reset() {
        keyword = ""
        activeKeyword = ""
        comics = []
        hasSearched = false
        currentPage = 0
        totalPages = 1
        lastVisitedPage = 0
        sortMode = .defaultSort
        errorMessage = nil
    }

    func persistPage() {
        guard currentPage > 0, !activeKeyword.isEmpty else { return }
        keyValueStore.set(currentPage, forKey: "lastPage_search_\(activeKeyword)")
    }
}
