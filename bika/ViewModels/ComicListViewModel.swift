import SwiftUI

@Observable
final class ComicListViewModel {
    var comics: [Comic] = []
    var isLoading = false
    var currentPage = 0
    var totalPages = 1
    var sortMode: SortMode = .defaultSort
    var lastVisitedPage = 0
    var errorMessage: String?

    let category: String
    private let client = APIClient.shared
    private var storageKey: String { "lastPage_category_\(category)" }

    init(category: String) {
        self.category = category
        self.lastVisitedPage = UserDefaults.standard.integer(forKey: "lastPage_category_\(category)")
    }

    func loadFirstPage() async {
        guard comics.isEmpty else { return }
        await loadPage(1)
    }

    func loadPage(_ page: Int) async {
        guard page >= 1, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let response: APIResponse<ComicsData> = try await client.send(
                .comics(category: category, page: page, sort: sortMode)
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
        comics = []
        currentPage = 0
        totalPages = 1
        await loadPage(1)
    }

    func persistPage() {
        guard currentPage > 0 else { return }
        UserDefaults.standard.set(currentPage, forKey: storageKey)
    }
}
