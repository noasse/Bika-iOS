import Foundation
import SwiftUI

@MainActor
@Observable
final class MacLibraryModel {
    var isCheckingToken = true
    var isAuthenticated = false
    var authError: String?
    var isAuthenticating = false

    var sidebarSelection: MacSidebarItem = .categories
    var userProfile: UserProfile?

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

    var selectedComicID: String?
    var selectedSummary: MacComicSummary?
    var detail: ComicDetail?
    var episodes: [Episode] = []
    var recommended: [Comic] = []
    var isLoadingRecommended = false
    var recommendedError: String?
    var commentEntryCount: Int?
    var isDetailLoading = false
    var detailError: String?
    var isTogglingLike = false
    var isTogglingFavourite = false
    var isPunching = false
    var readingProgressRevision = 0

    let client: any APIClientProtocol
    let readingStore: MacReadingStore
    let blockedCategoriesStore: MacBlockedCategoriesStore
    var didCheckToken = false
    private var activeListRequestID = 0
    private var activeDetailRequestID = 0
    private var activeRecommendationRequestID = 0

    init(
        client: any APIClientProtocol = APIClient.shared,
        readingStore: MacReadingStore,
        blockedCategoriesStore: MacBlockedCategoriesStore? = nil
    ) {
        self.client = client
        self.readingStore = readingStore
        self.blockedCategoriesStore = blockedCategoriesStore ?? MacBlockedCategoriesStore()
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

    var displayedRecommended: [Comic] {
        blockedCategoriesStore.filter(recommended)
    }

    var blockedCategoryCount: Int {
        blockedCategoriesStore.blockedCategories.count
    }

    func selectSidebar(_ item: MacSidebarItem) async {
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

    func refreshCurrentSurface() async {
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
            categories = response.data?.categories.filter { $0.isWeb != true } ?? []
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
        do {
            let response: APIResponse<ComicsData> = try await client.send(
                .search(keyword: keyword, page: macClampedPage(page, totalPages: max(totalPages, page)), sort: sortMode)
            )
            guard isActiveListRequest(requestID) else { return }
            applyComicsData(response.data?.comics, fallbackPage: page)
            listError = nil
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

    func loadFavourites(page: Int) async {
        let requestID = beginListRequest(title: "收藏")
        let targetPage = macClampedPage(page, totalPages: max(totalPages, page))
        do {
            let response: APIResponse<ComicsData> = try await client.send(.favourites(page: targetPage, sort: sortMode))
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

    func loadProfile() async {
        let requestID = beginListRequest(title: "我的")
        defer { finishListRequest(requestID) }

        do {
            let response: APIResponse<UserProfileData> = try await client.send(.myProfile())
            guard isActiveListRequest(requestID) else { return }
            userProfile = response.data?.user
            listError = nil
        } catch {
            guard isActiveListRequest(requestID) else { return }
            listError = error.localizedDescription
        }
    }

    func loadDetail(comicId: String) async {
        activeDetailRequestID += 1
        let requestID = activeDetailRequestID
        isDetailLoading = true
        detailError = nil
        detail = nil
        episodes = []
        recommended = []
        recommendedError = nil
        commentEntryCount = nil

        do {
            async let detailResponse: APIResponse<ComicDetailData> = client.send(.comicDetail(id: comicId))
            async let loadedEpisodes = loadAllEpisodes(comicId: comicId)
            async let loadedComments = loadCommentEntryCount(comicId: comicId)
            let resolvedDetail = try await detailResponse.data?.comic
            let resolvedEpisodes = try await loadedEpisodes
            let resolvedCommentCount = await loadedComments

            guard requestID == activeDetailRequestID else { return }
            detail = resolvedDetail
            episodes = resolvedEpisodes.sorted { $0.order < $1.order }
            commentEntryCount = resolvedCommentCount ?? resolvedDetail?.totalComments ?? resolvedDetail?.commentsCount
        } catch {
            guard requestID == activeDetailRequestID else { return }
            detailError = error.localizedDescription
        }

        guard requestID == activeDetailRequestID else { return }
        isDetailLoading = false
        await loadRecommended(comicId: comicId)
    }

    private func loadAllEpisodes(comicId: String) async throws -> [Episode] {
        var result: [Episode] = []
        var nextPage = 1
        var total = 1

        while nextPage <= total {
            let response: APIResponse<EpisodesData> = try await client.send(.episodes(comicId: comicId, page: nextPage))
            guard let page = response.data?.eps else { break }
            result.append(contentsOf: page.docs)
            total = max(page.pages, page.page)
            nextPage = page.page + 1
            if nextPage <= page.page {
                break
            }
        }

        return result
    }

    private func loadRecommended(comicId: String) async {
        activeRecommendationRequestID += 1
        let requestID = activeRecommendationRequestID
        isLoadingRecommended = true
        recommendedError = nil
        defer {
            if requestID == activeRecommendationRequestID {
                isLoadingRecommended = false
            }
        }

        do {
            let response: APIResponse<RecommendedData> = try await client.send(.recommended(comicId: comicId))
            guard requestID == activeRecommendationRequestID else { return }
            recommended = response.data?.comics ?? []
            if recommended.isEmpty {
                recommendedError = response.data == nil ? "推荐数据为空" : nil
            }
        } catch {
            guard requestID == activeRecommendationRequestID else { return }
            recommended = []
            recommendedError = error.localizedDescription
        }
    }

    private func loadCommentEntryCount(comicId: String) async -> Int? {
        do {
            let response: APIResponse<CommentsData> = try await client.send(.comments(comicId: comicId, page: 1))
            return response.data?.topLevelCommentDisplayCount
        } catch {
            return nil
        }
    }

    func makeReaderRequest(
        detail: ComicDetail,
        startEpisodeIndex: Int,
        startPageIndex: Int,
        restore: Bool
    ) -> MacReaderLaunchRequest? {
        guard !episodes.isEmpty else { return nil }
        let clampedEpisodeIndex = min(max(startEpisodeIndex, 0), episodes.count - 1)
        return MacReaderLaunchRequest(
            comicId: detail.id,
            comicTitle: detail.title,
            author: detail.author,
            thumbPath: detail.thumb?.path,
            thumbServer: detail.thumb?.fileServer,
            episodes: episodes.map(MacReaderEpisode.init(episode:)),
            startEpisodeIndex: clampedEpisodeIndex,
            startPageIndex: max(startPageIndex, 0),
            restoreSavedProgress: restore
        )
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

    private func beginListRequest(title: String) -> Int {
        activeListRequestID += 1
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
        activeListRequestID += 1
        isListLoading = false
    }

    private func invalidateDetailRequest() {
        activeDetailRequestID += 1
        activeRecommendationRequestID += 1
        isDetailLoading = false
        isLoadingRecommended = false
    }

    func clearSelection() {
        invalidateListRequest()
        invalidateDetailRequest()
        sidebarSelection = .categories
        selectedCategoryTitle = nil
        categories = []
        listItems = []
        currentPage = 0
        totalPages = 1
        clearDetail()
    }

    func clearDetail() {
        selectedComicID = nil
        selectedSummary = nil
        detail = nil
        episodes = []
        recommended = []
        recommendedError = nil
        commentEntryCount = nil
        detailError = nil
        isDetailLoading = false
    }
}
