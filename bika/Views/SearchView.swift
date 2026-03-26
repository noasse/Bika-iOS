import SwiftUI

struct SearchView: View {
    @State private var viewModel = SearchViewModel()
    @State private var previewImageURL: URL?
    @State private var showPagination = false
    @State private var scrollPosition = ScrollPosition(edge: .top)
    @Environment(\.colorScheme) private var colorScheme

    private let blockedManager = BlockedCategoriesManager.shared

    private var filteredComics: [Comic] {
        blockedManager.filterComics(viewModel.comics)
    }

    private let quickCategories = [
        "嗶咔漢化", "全彩", "長篇", "同人",
        "純愛", "百合花園", "耽美花園", "偽娘哲學",
        "後宮閃光", "凌辱", "SM", "足控",
        "單行本", "短篇", "圓神領域", "碧藍幻想",
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack {
                if viewModel.hasSearched {
                    Button {
                        viewModel.reset()
                    } label: {
                        Image(systemName: "chevron.left")
                            .foregroundStyle(Color.accentPink)
                    }
                }

                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.gray)
                TextField("搜索漫画...", text: $viewModel.keyword)
                    .accessibilityIdentifier("search.keywordField")
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit {
                        Task { await viewModel.search() }
                    }
                if !viewModel.keyword.isEmpty {
                    Button {
                        viewModel.keyword = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.gray)
                    }
                }
            }
            .padding(10)
            .background(Color.cardBg(for: colorScheme))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal)
            .padding(.top)

            // Sort bar
            if viewModel.hasSearched && !viewModel.comics.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(searchSortOptions, id: \.mode) { option in
                            Button {
                                Task {
                                    await viewModel.changeSort(option.mode)
                                    scrollPosition.scrollTo(edge: .top)
                                }
                            } label: {
                                Text(option.label)
                                    .font(.caption)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(viewModel.sortMode == option.mode ? Color.accentPink : Color.cardBg(for: colorScheme))
                                    .foregroundStyle(viewModel.sortMode == option.mode ? .white : .primary)
                                    .clipShape(Capsule())
                            }
                            .accessibilityIdentifier("search.sort.\(option.mode.rawValue)")
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical, 6)
            }

            if viewModel.isLoading && viewModel.comics.isEmpty && viewModel.hasSearched {
                Spacer()
                ProgressView()
                Spacer()
            } else if viewModel.comics.isEmpty && viewModel.hasSearched {
                Spacer()
                Text("没有找到相关漫画")
                    .foregroundStyle(Color.secondaryText(for: colorScheme))
                Spacer()
            } else if !viewModel.comics.isEmpty {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(filteredComics) { comic in
                            NavigationLink(value: comic) {
                                ComicCardView(comic: comic, previewImageURL: $previewImageURL)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("search.result.\(comic.id)")
                        }
                    }
                    .padding(.horizontal)
                }
                .scrollPosition($scrollPosition)
                .onScrollGeometryChange(for: Bool.self) { geo in
                    geo.contentOffset.y + geo.visibleRect.height >= geo.contentSize.height - 100
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
            } else {
                quickCategoriesGrid
            }
        }
        .background(Color.mainBg(for: colorScheme))
        .navigationTitle("搜索")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if viewModel.hasSearched && viewModel.totalPages > 0 && viewModel.currentPage > 0 {
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
        .onDisappear { viewModel.persistPage() }
    }

    private var quickCategoriesGrid: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("常用分类")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.secondaryText(for: colorScheme))
                    .padding(.horizontal)
                    .padding(.top, 8)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 75))], spacing: 8) {
                    ForEach(quickCategories, id: \.self) { cat in
                        Button {
                            viewModel.keyword = cat
                            Task { await viewModel.search() }
                        } label: {
                            Text(cat)
                                .font(.caption)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(Color.cardBg(for: colorScheme))
                                .foregroundStyle(.primary)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private var searchSortOptions: [(mode: SortMode, label: String)] {
        [
            (.defaultSort, "默认"),
            (.views, "最多观看"),
            (.liked, "最多爱心"),
            (.newest, "从新到旧"),
            (.oldest, "从旧到新"),
        ]
    }
}
