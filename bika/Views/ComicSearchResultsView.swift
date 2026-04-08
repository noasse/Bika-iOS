import SwiftUI

struct AuthorSearchResultsView: View {
    let author: String
    @State private var viewModel: ComicResultsViewModel
    @State private var previewImageURL: URL?
    @Environment(\.colorScheme) private var colorScheme

    private let blockedManager: BlockedCategoriesManager

    init(author: String, blockedManager: BlockedCategoriesManager = .shared) {
        self.author = author
        self.blockedManager = blockedManager
        _viewModel = State(initialValue: ComicResultsViewModel(query: .author(author)))
    }

    private var filteredComics: [Comic] {
        let exactAuthorMatches = viewModel.comics.filter {
            normalizedAuthorName($0.author) == normalizedAuthorName(author)
        }
        let visibleComics = blockedManager.filterComics(exactAuthorMatches)

        switch viewModel.sortMode {
        case .liked:
            return visibleComics.sorted { lhs, rhs in
                let lhsLikes = lhs.displayLikes ?? 0
                let rhsLikes = rhs.displayLikes ?? 0
                if lhsLikes == rhsLikes {
                    return lhs.id < rhs.id
                }
                return lhsLikes > rhsLikes
            }
        case .views:
            return visibleComics.sorted { lhs, rhs in
                let lhsViews = lhs.displayViews ?? 0
                let rhsViews = rhs.displayViews ?? 0
                if lhsViews == rhsViews {
                    return lhs.id < rhs.id
                }
                return lhsViews > rhsViews
            }
        default:
            return visibleComics
        }
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
            identifierPrefix: "author.result",
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
        .navigationTitle(author)
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

    private func normalizedAuthorName(_ name: String?) -> String {
        (name ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}

struct TagSearchResultsView: View {
    let keyword: String
    @State private var viewModel: ComicResultsViewModel
    @State private var previewImageURL: URL?
    @Environment(\.colorScheme) private var colorScheme

    private let blockedManager: BlockedCategoriesManager

    init(keyword: String, blockedManager: BlockedCategoriesManager = .shared) {
        self.keyword = keyword
        self.blockedManager = blockedManager
        _viewModel = State(initialValue: ComicResultsViewModel(query: .tag(keyword)))
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
            identifierPrefix: "tag.result",
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
        .navigationTitle(keyword)
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
