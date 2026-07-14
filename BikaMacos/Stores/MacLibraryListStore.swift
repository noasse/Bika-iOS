import Foundation
import SwiftUI

@MainActor
@Observable
final class MacLibraryListStore {
    var sidebarSelection: MacSidebarItem = .categories
    var categories: [Category] = []
    var selectedCategoryTitle: String?
    var rankingType: LeaderboardType = .hour24
    var searchText = ""
    var sortMode: SortMode = .defaultSort

    var listTitle = "分类"
    var listItems: [MacComicSummary] = []
    var isListLoading = false
    var listError: String?
    var currentPage = 0
    var totalPages = 1

    let client: any APIClientProtocol
    let readingStore: MacReadingStore
    let blockedCategoriesStore: MacBlockedCategoriesStore

    private var activeListRequestID = 0

    init(
        client: any APIClientProtocol,
        readingStore: MacReadingStore,
        blockedCategoriesStore: MacBlockedCategoriesStore
    ) {
        self.client = client
        self.readingStore = readingStore
        self.blockedCategoriesStore = blockedCategoriesStore
    }

    var selectedCategory: Category? {
        categories.first { $0.title == selectedCategoryTitle }
    }

    var canPageBackward: Bool {
        currentPage > 1 && sidebarSelection != .history && sidebarSelection != .ranking
    }

    var canPageForward: Bool {
        currentPage < totalPages && sidebarSelection != .history && sidebarSelection != .ranking
    }

    var displayedListItems: [MacComicSummary] {
        if sidebarSelection == .history {
            return readingStore.history.map(MacComicSummary.init(history:))
        }
        guard !blockedCategoriesStore.blockedCategories.isEmpty else { return listItems }
        return listItems.filter { summary in
            !summary.categories.contains { blockedCategoriesStore.isBlocked($0) }
        }
    }

    var blockedCategoryCount: Int {
        blockedCategoriesStore.blockedCategories.count
    }

    func selectSidebar(
        _ item: MacSidebarItem,
        loadProfile: @escaping @MainActor () async -> Void
    ) async {
        sidebarSelection = item
        listError = nil
        selectedCategoryTitle = item == .categories ? selectedCategoryTitle : nil

        switch item {
        case .categories:
            listTitle = selectedCategoryTitle ?? "分类"
            if selectedCategoryTitle == nil {
                if !categories.isEmpty {
                    invalidateListRequest()
                }
                listItems = []
                currentPage = 0
                totalPages = 1
                await loadCategoriesIfNeeded()
            } else if let category = selectedCategoryTitle {
                await loadCategory(category, page: max(currentPage, 1))
            }
        case .ranking:
            await loadRanking()
        case .search:
            invalidateListRequest()
            listTitle = "搜索"
            listItems = []
            currentPage = 0
            totalPages = 1
        case .favourites:
            await loadFavourites(page: 1)
        case .history:
            await loadHistoryFromCloud()
        case .profile:
            invalidateListRequest()
            listTitle = "我的"
            listItems = []
            currentPage = 0
            totalPages = 1
            await loadProfile()
        case .settings:
            invalidateListRequest()
            listTitle = "设置"
            listItems = []
            currentPage = 0
            totalPages = 1
        }
    }

    func refreshCurrentSurface(
        loadProfile: @escaping @MainActor () async -> Void
    ) async {
        switch sidebarSelection {
        case .categories:
            if let selectedCategoryTitle {
                await loadCategory(selectedCategoryTitle, page: max(currentPage, 1), force: true)
            } else {
                await loadCategories(force: true)
            }
        case .ranking:
            await loadRanking()
        case .search:
            await search(page: max(currentPage, 1))
        case .favourites:
            await loadFavourites(page: max(currentPage, 1))
        case .history:
            await loadHistoryFromCloud()
        case .profile:
            await loadProfile()
        case .settings:
            break
        }
    }

    func loadCategoriesIfNeeded() async {
        guard categories.isEmpty else { return }
        await loadCategories(force: false)
    }

    func loadCategories(force: Bool) async {
        guard force || categories.isEmpty else { return }
        let requestID = beginListRequest(title: "分类")
        defer { finishListRequest(requestID) }

        do {
            let response: APIResponse<CategoriesData> = try await client.send(.categories())
            guard isActiveListRequest(requestID) else { return }
            categories = (response.data?.categories ?? [])
                .filter { $0.isWeb != true }
                .deduplicatedByIdentity()
            listError = nil
        } catch {
            guard isActiveListRequest(requestID) else { return }
            listError = error.localizedDescription
        }
    }

    func selectCategory(_ category: Category) async {
        selectedCategoryTitle = category.title
        await loadCategory(category.title, page: 1, force: true)
    }

    func showCategoryIndex() {
        invalidateListRequest()
        selectedCategoryTitle = nil
        listTitle = "分类"
        listItems = []
        currentPage = 0
        totalPages = 1
    }

    func changeSort(_ mode: SortMode) async {
        guard sortMode != mode else { return }
        sortMode = mode
        switch sidebarSelection {
        case .categories:
            if let selectedCategoryTitle {
                await loadCategory(selectedCategoryTitle, page: 1, force: true)
            }
        case .search:
            await search(page: 1)
        case .favourites:
            await loadFavourites(page: 1)
        default:
            break
        }
    }

    func changeRanking(_ type: LeaderboardType) async {
        guard rankingType != type else { return }
        rankingType = type
        await loadRanking()
    }

    func search(page: Int = 1) async {
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else {
            invalidateListRequest()
            listTitle = "搜索"
            listItems = []
            currentPage = 0
            totalPages = 1
            listError = "请输入搜索关键词"
            return
        }

        let requestID = beginListRequest(title: "搜索：\(keyword)")
        let keywords = SearchKeywordExpander.keywords(for: keyword)
        let targetPage = macClampedPage(page, totalPages: max(totalPages, page))
        do {
            let pageData = try await loadExpandedSearchPage(
                keywords: keywords.isEmpty ? [keyword] : keywords,
                page: targetPage,
                sort: sortMode,
                requestID: requestID
            )
            guard isActiveListRequest(requestID) else { return }
            applyComicsData(pageData, fallbackPage: targetPage)
            listError = nil
        } catch is CancellationError {
            // Cancellation is represented by request invalidation and must not surface as an error.
        } catch {
            guard isActiveListRequest(requestID) else { return }
            listError = error.localizedDescription
        }
        finishListRequest(requestID)
    }

    func nextPage() async {
        guard canPageForward, !isListLoading else { return }
        await loadPage(currentPage + 1)
    }

    func previousPage() async {
        guard canPageBackward, !isListLoading else { return }
        await loadPage(currentPage - 1)
    }

    func goToPage(_ page: Int) async {
        guard sidebarSelection != .history, sidebarSelection != .ranking else { return }
        guard !isListLoading else { return }
        let targetPage = macClampedPage(page, totalPages: totalPages)
        guard targetPage != currentPage else { return }
        await loadPage(targetPage)
    }

    func selectRoute(_ route: MacListRoute) async {
        sidebarSelection = .search
        selectedCategoryTitle = nil

        switch route {
        case .category(let category):
            sidebarSelection = .categories
            selectedCategoryTitle = category
            await loadCategory(category, page: 1, force: true)
        case .author(let author):
            searchText = author
            await search(page: 1)
        case .tag(let tag):
            searchText = tag
            await search(page: 1)
        }
    }

    func loadFavourites(page: Int) async {
        let requestID = beginListRequest(title: "收藏")
        let targetPage = macClampedPage(page, totalPages: max(totalPages, page))
        do {
            let response: APIResponse<ComicsData> = try await client.send(
                .favourites(page: targetPage, sort: sortMode)
            )
            guard isActiveListRequest(requestID) else { return }
            applyComicsData(response.data?.comics, fallbackPage: targetPage)
            listError = nil
        } catch {
            guard isActiveListRequest(requestID) else { return }
            listError = error.localizedDescription
        }
        finishListRequest(requestID)
    }

    func loadHistory() {
        invalidateListRequest()
        listTitle = "历史"
        listItems = readingStore.history.map(MacComicSummary.init(history:))
        currentPage = listItems.isEmpty ? 0 : 1
        totalPages = 1
        listError = nil
    }

    func loadHistoryFromCloud() async {
        await readingStore.syncFromCloud()
        loadHistory()
    }

    func loadProfile(
        fetchProfile: @escaping @MainActor () async throws -> UserProfile?,
        applyProfile: @escaping @MainActor (UserProfile?) -> Void
    ) async {
        let requestID = beginListRequest(title: "我的")
        defer { finishListRequest(requestID) }

        do {
            let profile = try await fetchProfile()
            guard isActiveListRequest(requestID) else { return }
            applyProfile(profile)
            listError = nil
        } catch {
            guard isActiveListRequest(requestID) else { return }
            listError = error.localizedDescription
        }
    }

    func setExternalError(_ error: Error) {
        listError = error.localizedDescription
    }

    func clearSelection() {
        invalidateListRequest()
        sidebarSelection = .categories
        selectedCategoryTitle = nil
        categories = []
        listItems = []
        currentPage = 0
        totalPages = 1
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
    }

    func clearHistory() {
        readingStore.clearHistory()
        loadHistory()
    }

    private func loadPage(_ page: Int) async {
        switch sidebarSelection {
        case .categories:
            if let selectedCategoryTitle {
                await loadCategory(selectedCategoryTitle, page: page)
            }
        case .search:
            await search(page: page)
        case .favourites:
            await loadFavourites(page: page)
        default:
            break
        }
    }

    private func loadCategory(_ category: String, page: Int, force: Bool = false) async {
        if !force, selectedCategoryTitle == category, currentPage == page, !listItems.isEmpty {
            return
        }

        let requestID = beginListRequest(title: category)
        let targetPage = macClampedPage(page, totalPages: max(totalPages, page))
        do {
            let response: APIResponse<ComicsData> = try await client.send(
                .comics(category: category, page: targetPage, sort: sortMode)
            )
            guard isActiveListRequest(requestID) else { return }
            applyComicsData(response.data?.comics, fallbackPage: targetPage)
            listError = nil
        } catch {
            guard isActiveListRequest(requestID) else { return }
            listError = error.localizedDescription
        }
        finishListRequest(requestID)
    }

    private func loadRanking() async {
        let requestID = beginListRequest(title: "排行榜 · \(rankingType.macTitle)")
        do {
            let response: APIResponse<LeaderboardData> = try await client.send(.leaderboard(type: rankingType))
            guard isActiveListRequest(requestID) else { return }
            listItems = response.data?.comics.map(MacComicSummary.init(comic:)) ?? []
            currentPage = 1
            totalPages = 1
            listError = nil
        } catch {
            guard isActiveListRequest(requestID) else { return }
            listError = error.localizedDescription
        }
        finishListRequest(requestID)
    }

    private func applyComicsData(_ page: PaginatedResponse<Comic>?, fallbackPage: Int) {
        guard let page else {
            listItems = []
            currentPage = fallbackPage
            totalPages = 1
            return
        }

        listItems = page.docs.map(MacComicSummary.init(comic:))
        currentPage = page.page
        totalPages = max(page.pages, page.page)
    }

    private func loadExpandedSearchPage(
        keywords: [String],
        page: Int,
        sort: SortMode,
        requestID: Int
    ) async throws -> PaginatedResponse<Comic>? {
        var loadedPages: [PaginatedResponse<Comic>] = []
        var firstError: Error?

        for keyword in keywords {
            try Task.checkCancellation()
            guard isActiveListRequest(requestID) else { throw CancellationError() }

            do {
                let response: APIResponse<ComicsData> = try await client.send(
                    .search(keyword: keyword, page: page, sort: sort)
                )
                try Task.checkCancellation()
                guard isActiveListRequest(requestID) else { throw CancellationError() }
                if let page = response.data?.comics {
                    loadedPages.append(page)
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                if firstError == nil {
                    firstError = error
                }
            }
        }

        if loadedPages.isEmpty, let firstError {
            throw firstError
        }

        return SearchResultMerger.mergedPage(from: loadedPages)
    }

    private func beginListRequest(title: String) -> Int {
        activeListRequestID &+= 1
        listTitle = title
        isListLoading = true
        listError = nil
        return activeListRequestID
    }

    private func isActiveListRequest(_ requestID: Int) -> Bool {
        requestID == activeListRequestID
    }

    private func finishListRequest(_ requestID: Int) {
        guard isActiveListRequest(requestID) else { return }
        isListLoading = false
    }

    private func invalidateListRequest() {
        activeListRequestID &+= 1
        isListLoading = false
    }
}
