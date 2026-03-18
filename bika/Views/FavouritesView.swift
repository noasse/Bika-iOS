import SwiftUI

struct FavouritesView: View {
    @State private var comics: [Comic] = []
    @State private var isLoading = false
    @State private var currentPage = 0
    @State private var totalPages = 1
    @State private var lastVisitedPage: Int
    @State private var previewImageURL: URL?
    @State private var showPagination = false
    @State private var scrollPosition = ScrollPosition(edge: .top)
    @State private var sortMode: SortMode = .defaultSort
    @Environment(\.colorScheme) private var colorScheme

    private let client = APIClient.shared
    private let blockedManager = BlockedCategoriesManager.shared
    private let storageKey = "lastPage_favourites"

    init() {
        _lastVisitedPage = State(initialValue: UserDefaults.standard.integer(forKey: "lastPage_favourites"))
    }

    private var filteredComics: [Comic] {
        blockedManager.filterComics(comics)
    }

    var body: some View {
        ScrollView {
            if isLoading && comics.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 300)
            } else if comics.isEmpty && currentPage > 0 {
                Text("暂无收藏")
                    .foregroundStyle(Color.secondaryText(for: colorScheme))
                    .frame(maxWidth: .infinity, minHeight: 300)
            } else {
                if currentPage > 0 {
                    sortBar
                }

                LazyVStack(spacing: 10) {
                    ForEach(filteredComics) { comic in
                        NavigationLink {
                            ComicDetailView(comicId: comic.id)
                        } label: {
                            ComicCardView(comic: comic, previewImageURL: $previewImageURL)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
        .scrollPosition($scrollPosition)
        .onScrollGeometryChange(for: Bool.self) { geo in
            geo.contentOffset.y + geo.visibleRect.height >= geo.contentSize.height - 100
        } action: { _, isAtBottom in
            showPagination = isAtBottom
        }
        .overlay(alignment: .bottom) {
            if showPagination && totalPages > 1 {
                PaginationButtons(
                    currentPage: currentPage,
                    totalPages: totalPages,
                    isLoading: isLoading,
                    onPrev: { Task {
                        await prevPage()
                        scrollPosition.scrollTo(edge: .top)
                    }},
                    onNext: { Task {
                        await nextPage()
                        scrollPosition.scrollTo(edge: .top)
                    }}
                )
            }
        }
        .background(Color.mainBg(for: colorScheme))
        .navigationTitle("我的收藏")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if totalPages > 0 && currentPage > 0 {
                ToolbarItem(placement: .topBarTrailing) {
                    PageJumpToolbarItem(
                        currentPage: currentPage,
                        totalPages: totalPages,
                        lastVisitedPage: lastVisitedPage,
                        isLoading: isLoading,
                        onGoToPage: { page in Task {
                            await loadPage(page)
                            scrollPosition.scrollTo(edge: .top)
                        }},
                        onRestoreLast: { Task {
                            await goToLastVisited()
                            scrollPosition.scrollTo(edge: .top)
                        }}
                    )
                }
            }
        }
        .imagePreviewSheet(url: $previewImageURL)
        .task { await loadPage(1) }
        .onDisappear {
            guard currentPage > 0 else { return }
            UserDefaults.standard.set(currentPage, forKey: storageKey)
        }
    }

    private func loadPage(_ page: Int) async {
        guard page >= 1, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let response: APIResponse<ComicsData> = try await client.send(.favourites(page: page, sort: sortMode))
            if let data = response.data {
                comics = data.comics.docs
                currentPage = data.comics.page
                totalPages = data.comics.pages
            }
        } catch {}
    }

    private func nextPage() async {
        guard currentPage < totalPages else { return }
        lastVisitedPage = currentPage
        await loadPage(currentPage + 1)
    }

    private func prevPage() async {
        guard currentPage > 1 else { return }
        lastVisitedPage = currentPage
        await loadPage(currentPage - 1)
    }

    private func goToLastVisited() async {
        guard lastVisitedPage > 0, lastVisitedPage <= totalPages else { return }
        await loadPage(lastVisitedPage)
    }

    private func changeSort(_ mode: SortMode) async {
        guard mode != sortMode else { return }
        sortMode = mode
        lastVisitedPage = currentPage
        comics = []
        currentPage = 0
        totalPages = 1
        await loadPage(1)
    }

    private var sortBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SortMode.allCases, id: \.self) { mode in
                    Button {
                        Task {
                            await changeSort(mode)
                            scrollPosition.scrollTo(edge: .top)
                        }
                    } label: {
                        Text(mode.displayName)
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(sortMode == mode ? Color.accentPink : Color.cardBg(for: colorScheme))
                            .foregroundStyle(sortMode == mode ? .white : .primary)
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 6)
    }
}
