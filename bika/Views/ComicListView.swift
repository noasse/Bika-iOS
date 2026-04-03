import SwiftUI

struct ComicListView: View {
    let category: String
    @State private var viewModel: ComicListViewModel
    @State private var previewImageURL: URL?
    @Environment(\.colorScheme) private var colorScheme

    private let blockedManager: BlockedCategoriesManager

    init(category: String, blockedManager: BlockedCategoriesManager = .shared) {
        self.category = category
        self.blockedManager = blockedManager
        _viewModel = State(initialValue: ComicListViewModel(category: category))
    }

    private var filteredComics: [Comic] {
        blockedManager.filterComics(viewModel.comics)
    }

    var body: some View {
        PaginatedComicResultsView(
            comics: filteredComics,
            isLoading: viewModel.isLoading,
            errorMessage: viewModel.errorMessage,
            emptyMessage: "暂无结果",
            currentPage: viewModel.currentPage,
            totalPages: viewModel.totalPages,
            lastVisitedPage: viewModel.lastVisitedPage,
            pendingRestoreComicID: viewModel.pendingRestoreComicID,
            identifierPrefix: "comicList.result",
            onConsumePendingRestoreComicID: viewModel.consumePendingRestoreComicID,
            onRememberNavigationAnchor: viewModel.rememberNavigationAnchor(comicID:),
            onLoadPage: viewModel.loadPage(_:),
            onPrevPage: viewModel.prevPage,
            onNextPage: viewModel.nextPage,
            onRestoreLastPage: viewModel.goToLastVisited,
            onRetry: { await viewModel.loadPage(max(viewModel.currentPage, 1)) },
            previewImageURL: $previewImageURL
        ) {
            sortBar
        } leadingContent: { _, _ in
            EmptyView()
        }
        .background(Color.mainBg(for: colorScheme))
        .navigationTitle(category)
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

// MARK: - SortMode Display Name

extension SortMode {
    var displayName: String {
        switch self {
        case .defaultSort: "默认"
        case .newest: "最新"
        case .oldest: "最旧"
        case .liked: "最多爱心"
        case .views: "最多观看"
        }
    }
}
