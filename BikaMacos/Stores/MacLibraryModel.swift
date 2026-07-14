import Foundation
import SwiftUI

/// Compatibility façade retained while macOS views migrate to focused stores.
@MainActor
@Observable
final class MacLibraryModel {
    let client: any APIClientProtocol
    let readingStore: MacReadingStore
    let blockedCategoriesStore: MacBlockedCategoriesStore
    let accountSessionStore: AccountSessionStore

    let authenticationStore: MacAuthenticationStore
    let listStore: MacLibraryListStore
    let detailStore: MacComicDetailStore

    init(
        client: any APIClientProtocol = APIClient.shared,
        readingStore: MacReadingStore,
        blockedCategoriesStore: MacBlockedCategoriesStore? = nil,
        accountSessionStore: AccountSessionStore? = nil
    ) {
        let resolvedBlockedCategoriesStore = blockedCategoriesStore ?? MacBlockedCategoriesStore()
        let resolvedAccountSessionStore = accountSessionStore ?? .shared

        self.client = client
        self.readingStore = readingStore
        self.blockedCategoriesStore = resolvedBlockedCategoriesStore
        self.accountSessionStore = resolvedAccountSessionStore
        self.authenticationStore = MacAuthenticationStore(
            client: client,
            accountSessionStore: resolvedAccountSessionStore
        )
        self.listStore = MacLibraryListStore(
            client: client,
            readingStore: readingStore,
            blockedCategoriesStore: resolvedBlockedCategoriesStore
        )
        self.detailStore = MacComicDetailStore(
            client: client,
            readingStore: readingStore,
            blockedCategoriesStore: resolvedBlockedCategoriesStore
        )
    }

    // MARK: Authentication façade

    var isCheckingToken: Bool {
        get { authenticationStore.isCheckingToken }
        set { authenticationStore.isCheckingToken = newValue }
    }

    var isAuthenticated: Bool {
        get { authenticationStore.isAuthenticated }
        set { authenticationStore.isAuthenticated = newValue }
    }

    var authError: String? {
        get { authenticationStore.authError }
        set { authenticationStore.authError = newValue }
    }

    var isAuthenticating: Bool {
        get { authenticationStore.isAuthenticating }
        set { authenticationStore.isAuthenticating = newValue }
    }

    var requiresProfileValidation: Bool {
        get { authenticationStore.requiresProfileValidation }
        set { authenticationStore.requiresProfileValidation = newValue }
    }

    var userProfile: UserProfile? {
        get { authenticationStore.userProfile }
        set { authenticationStore.userProfile = newValue }
    }

    var isPunching: Bool {
        get { authenticationStore.isPunching }
        set { authenticationStore.isPunching = newValue }
    }

    // MARK: List façade

    var sidebarSelection: MacSidebarItem {
        get { listStore.sidebarSelection }
        set { listStore.sidebarSelection = newValue }
    }

    var categories: [Category] {
        get { listStore.categories }
        set { listStore.categories = newValue }
    }

    var selectedCategoryTitle: String? {
        get { listStore.selectedCategoryTitle }
        set { listStore.selectedCategoryTitle = newValue }
    }

    var rankingType: LeaderboardType {
        get { listStore.rankingType }
        set { listStore.rankingType = newValue }
    }

    var searchText: String {
        get { listStore.searchText }
        set { listStore.searchText = newValue }
    }

    var sortMode: SortMode {
        get { listStore.sortMode }
        set { listStore.sortMode = newValue }
    }

    var listTitle: String {
        get { listStore.listTitle }
        set { listStore.listTitle = newValue }
    }

    var listItems: [MacComicSummary] {
        get { listStore.listItems }
        set { listStore.listItems = newValue }
    }

    var isListLoading: Bool {
        get { listStore.isListLoading }
        set { listStore.isListLoading = newValue }
    }

    var listError: String? {
        get { listStore.listError }
        set { listStore.listError = newValue }
    }

    var currentPage: Int {
        get { listStore.currentPage }
        set { listStore.currentPage = newValue }
    }

    var totalPages: Int {
        get { listStore.totalPages }
        set { listStore.totalPages = newValue }
    }

    var selectedCategory: Category? { listStore.selectedCategory }
    var canPageBackward: Bool { listStore.canPageBackward }
    var canPageForward: Bool { listStore.canPageForward }
    var displayedListItems: [MacComicSummary] { listStore.displayedListItems }
    var blockedCategoryCount: Int { listStore.blockedCategoryCount }

    // MARK: Detail façade

    var selectedComicID: String? {
        get { detailStore.selectedComicID }
        set { detailStore.selectedComicID = newValue }
    }

    var selectedSummary: MacComicSummary? {
        get { detailStore.selectedSummary }
        set { detailStore.selectedSummary = newValue }
    }

    var detail: ComicDetail? {
        get { detailStore.detail }
        set { detailStore.detail = newValue }
    }

    var episodes: [Episode] {
        get { detailStore.episodes }
        set { detailStore.episodes = newValue }
    }

    var recommended: [Comic] {
        get { detailStore.recommended }
        set { detailStore.recommended = newValue }
    }

    var isLoadingRecommended: Bool {
        get { detailStore.isLoadingRecommended }
        set { detailStore.isLoadingRecommended = newValue }
    }

    var recommendedError: String? {
        get { detailStore.recommendedError }
        set { detailStore.recommendedError = newValue }
    }

    var commentEntryCount: Int? {
        get { detailStore.commentEntryCount }
        set { detailStore.commentEntryCount = newValue }
    }

    var isDetailLoading: Bool {
        get { detailStore.isDetailLoading }
        set { detailStore.isDetailLoading = newValue }
    }

    var detailError: String? {
        get { detailStore.detailError }
        set { detailStore.detailError = newValue }
    }

    var isLoadingEpisodes: Bool {
        get { detailStore.isLoadingEpisodes }
        set { detailStore.isLoadingEpisodes = newValue }
    }

    var episodesError: String? {
        get { detailStore.episodesError }
        set { detailStore.episodesError = newValue }
    }

    var isTogglingLike: Bool {
        get { detailStore.isTogglingLike }
        set { detailStore.isTogglingLike = newValue }
    }

    var isTogglingFavourite: Bool {
        get { detailStore.isTogglingFavourite }
        set { detailStore.isTogglingFavourite = newValue }
    }

    var readingProgressRevision: Int {
        get { detailStore.readingProgressRevision }
        set { detailStore.readingProgressRevision = newValue }
    }

    var isPerformingDetailAction: Bool { detailStore.isPerformingDetailAction }
    var displayedRecommended: [Comic] { detailStore.displayedRecommended }

    // MARK: List forwarding

    func selectSidebar(_ item: MacSidebarItem) async {
        await listStore.selectSidebar(item) { [weak self] in
            await self?.loadProfile()
        }
    }

    func refreshCurrentSurface() async {
        await listStore.refreshCurrentSurface { [weak self] in
            await self?.loadProfile()
        }
    }

    func loadCategoriesIfNeeded() async {
        await listStore.loadCategoriesIfNeeded()
    }

    func loadCategories(force: Bool) async {
        await listStore.loadCategories(force: force)
    }

    func selectCategory(_ category: Category) async {
        await listStore.selectCategory(category)
    }

    func showCategoryIndex() {
        listStore.showCategoryIndex()
    }

    func changeSort(_ mode: SortMode) async {
        await listStore.changeSort(mode)
    }

    func changeRanking(_ type: LeaderboardType) async {
        await listStore.changeRanking(type)
    }

    func search(page: Int = 1) async {
        await listStore.search(page: page)
    }

    func nextPage() async {
        await listStore.nextPage()
    }

    func previousPage() async {
        await listStore.previousPage()
    }

    func goToPage(_ page: Int) async {
        await listStore.goToPage(page)
    }

    func selectRoute(_ route: MacListRoute) async {
        await listStore.selectRoute(route)
    }

    func loadFavourites(page: Int) async {
        await listStore.loadFavourites(page: page)
    }

    func loadHistory() {
        listStore.loadHistory()
    }

    func loadHistoryFromCloud() async {
        await listStore.loadHistoryFromCloud()
    }

    // MARK: Detail forwarding

    func loadDetail(comicId: String) async {
        await detailStore.loadDetail(comicId: comicId)
    }

    func reloadEpisodes() async {
        await detailStore.reloadEpisodes()
    }

    func refreshDetailAfterMutation(comicId: String) async {
        await detailStore.refreshDetailAfterMutation(comicId: comicId)
    }

    func makeReaderRequest(
        detail: ComicDetail,
        startEpisodeIndex: Int,
        startPageIndex: Int,
        restore: Bool
    ) -> MacReaderLaunchRequest? {
        detailStore.makeReaderRequest(
            detail: detail,
            startEpisodeIndex: startEpisodeIndex,
            startPageIndex: startPageIndex,
            restore: restore
        )
    }

    func clearSelection() {
        listStore.clearSelection()
        detailStore.clearDetail()
    }

    func clearDetail() {
        detailStore.clearDetail()
    }
}
