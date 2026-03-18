import SwiftUI

struct ComicListView: View {
    let category: String
    @State private var viewModel: ComicListViewModel
    @State private var previewImageURL: URL?
    @State private var showPagination = false
    @State private var scrollPosition = ScrollPosition(edge: .top)
    @Environment(\.colorScheme) private var colorScheme

    private let blockedManager = BlockedCategoriesManager.shared

    init(category: String) {
        self.category = category
        _viewModel = State(initialValue: ComicListViewModel(category: category))
    }

    private var filteredComics: [Comic] {
        blockedManager.filterComics(viewModel.comics)
    }

    var body: some View {
        ScrollView {
            if viewModel.isLoading && viewModel.comics.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 300)
            } else {
                sortBar

                LazyVStack(spacing: 10) {
                    ForEach(filteredComics) { comic in
                        NavigationLink(value: comic) {
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
            let atBottom = geo.contentOffset.y + geo.visibleRect.height >= geo.contentSize.height - 100
            return atBottom
        } action: { _, isAtBottom in
            showPagination = isAtBottom
        }
        .overlay(alignment: .bottom) {
            if showPagination && viewModel.totalPages > 1 {
                PaginationButtons(
                    currentPage: viewModel.currentPage,
                    totalPages: viewModel.totalPages,
                    isLoading: viewModel.isLoading,
                    onPrev: { Task {
                        await viewModel.prevPage()
                        scrollPosition.scrollTo(edge: .top)
                    }},
                    onNext: { Task {
                        await viewModel.nextPage()
                        scrollPosition.scrollTo(edge: .top)
                    }}
                )
            }
        }
        .background(Color.mainBg(for: colorScheme))
        .navigationTitle(category)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if viewModel.totalPages > 0 && viewModel.currentPage > 0 {
                ToolbarItem(placement: .topBarTrailing) {
                    PageJumpToolbarItem(
                        currentPage: viewModel.currentPage,
                        totalPages: viewModel.totalPages,
                        lastVisitedPage: viewModel.lastVisitedPage,
                        isLoading: viewModel.isLoading,
                        onGoToPage: { page in Task {
                            await viewModel.loadPage(page)
                            scrollPosition.scrollTo(edge: .top)
                        }},
                        onRestoreLast: { Task {
                            await viewModel.goToLastVisited()
                            scrollPosition.scrollTo(edge: .top)
                        }}
                    )
                }
            }
        }
        .navigationDestination(for: Comic.self) { comic in
            ComicDetailView(comicId: comic.id)
        }
        .imagePreviewSheet(url: $previewImageURL)
        .task { await viewModel.loadFirstPage() }
        .onDisappear { viewModel.persistPage() }
    }

    private var sortBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SortMode.allCases, id: \.self) { mode in
                    Button {
                        Task {
                            await viewModel.changeSort(mode)
                            scrollPosition.scrollTo(edge: .top)
                        }
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
