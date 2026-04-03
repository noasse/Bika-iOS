import SwiftUI

struct FavouritesView: View {
    @State private var viewModel: ComicResultsViewModel
    @State private var previewImageURL: URL?
    @Environment(\.colorScheme) private var colorScheme

    private let blockedManager: BlockedCategoriesManager

    init(blockedManager: BlockedCategoriesManager = .shared) {
        self.blockedManager = blockedManager
        _viewModel = State(initialValue: ComicResultsViewModel(query: .favourites))
    }

    private var filteredComics: [Comic] {
        blockedManager.filterComics(viewModel.comics)
    }

    var body: some View {
        PaginatedComicResultsView(
            comics: filteredComics,
            isLoading: viewModel.isLoading,
            errorMessage: viewModel.errorMessage,
            emptyMessage: "暂无收藏",
            currentPage: viewModel.currentPage,
            totalPages: viewModel.totalPages,
            lastVisitedPage: viewModel.lastVisitedPage,
            pendingRestoreComicID: viewModel.pendingRestoreComicID,
            identifierPrefix: "favourites.result",
            onConsumePendingRestoreComicID: viewModel.consumePendingRestoreComicID,
            onRememberNavigationAnchor: viewModel.rememberNavigationAnchor(comicID:),
            onLoadPage: viewModel.loadPage(_:),
            onPrevPage: viewModel.prevPage,
            onNextPage: viewModel.nextPage,
            onRestoreLastPage: viewModel.goToLastVisited,
            onRetry: { await viewModel.loadPage(max(viewModel.currentPage, 1)) },
            previewImageURL: $previewImageURL
        ) {
            if viewModel.currentPage > 0 {
                sortBar
            }
        } leadingContent: { _, _ in
            EmptyView()
        }
        .background(Color.mainBg(for: colorScheme))
        .navigationTitle("我的收藏")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.loadFirstPage() }
        .onDisappear { viewModel.persistPage() }
    }

    private var sortBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SortMode.allCases, id: \.self) { mode in
                    Button {
                        Task { await viewModel.changeSort(mode) }
                    } label: {
                        Text(mode.displayName)
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(viewModel.sortMode == mode ? Color.accentPink : Color.cardBg(for: colorScheme))
                            .foregroundStyle(viewModel.sortMode == mode ? .white : .primary)
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 6)
    }
}
