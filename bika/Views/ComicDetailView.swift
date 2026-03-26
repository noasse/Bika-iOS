import SwiftUI

struct ComicDetailView: View {
    let comicId: String
    @State private var viewModel: ComicDetailViewModel
    @State private var showReader = false
    @State private var selectedEpisodeIndex = 0
    @State private var resumePageIndex = 0
    @State private var previewImageURL: URL?
    @Environment(\.colorScheme) private var colorScheme

    init(comicId: String) {
        self.comicId = comicId
        _viewModel = State(initialValue: ComicDetailViewModel(comicId: comicId))
    }

    var body: some View {
        ScrollView {
            if viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 400)
            } else if let detail = viewModel.detail {
                VStack(alignment: .leading, spacing: 16) {
                    // Header: cover + meta
                    HStack(alignment: .top, spacing: 14) {
                        MediaImageView(media: detail.thumb, cornerRadius: 8)
                            .frame(width: 120, height: 170)
                            .onTapGesture {
                                previewImageURL = detail.thumb?.imageURL
                            }

                        VStack(alignment: .leading, spacing: 6) {
                            Text(detail.title)
                                .font(.title3.bold())

                            // Clickable author → search by author
                            if let author = detail.author {
                                NavigationLink {
                                    AuthorSearchResultsView(author: author)
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "person")
                                            .font(.caption2)
                                        Text(author)
                                            .font(.subheadline)
                                    }
                                    .foregroundStyle(Color.accentPink)
                                }
                            }

                            if let chineseTeam = detail.chineseTeam, !chineseTeam.isEmpty {
                                Text("汉化: \(chineseTeam)")
                                    .font(.caption)
                                    .foregroundStyle(Color.secondaryText(for: colorScheme))
                            }

                            Spacer()

                            HStack(spacing: 16) {
                                statLabel(systemImage: "eye", value: detail.totalViews ?? detail.viewsCount ?? 0)
                                statLabel(systemImage: "heart", value: detail.totalLikes ?? detail.likesCount ?? 0)
                                if let eps = detail.epsCount {
                                    statLabel(systemImage: "book", value: eps)
                                }
                            }
                        }
                    }
                    .padding(.horizontal)

                    // Action buttons
                    HStack(spacing: 20) {
                        actionButton(
                            title: detail.isLiked == true ? "已喜欢" : "喜欢",
                            systemImage: detail.isLiked == true ? "heart.fill" : "heart",
                            tint: detail.isLiked == true ? .red : .gray
                        ) {
                            Task { await viewModel.toggleLike() }
                        }

                        actionButton(
                            title: detail.isFavourite == true ? "已收藏" : "收藏",
                            systemImage: detail.isFavourite == true ? "star.fill" : "star",
                            tint: detail.isFavourite == true ? .yellow : .gray
                        ) {
                            Task { await viewModel.toggleFavourite() }
                        }
                    }
                    .padding(.horizontal)

                    // Clickable categories
                    if let categories = detail.categories, !categories.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(categories, id: \.self) { cat in
                                    NavigationLink {
                                        ComicListView(category: cat)
                                    } label: {
                                        Text(cat)
                                            .font(.caption)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 5)
                                            .background(Color.accentPink.opacity(0.15))
                                            .foregroundStyle(Color.accentPink)
                                            .clipShape(Capsule())
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                    }

                    // Tags
                    if let tags = detail.tags, !tags.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(tags, id: \.self) { tag in
                                    NavigationLink {
                                        TagSearchResultsView(keyword: tag)
                                    } label: {
                                        Text(tag)
                                            .font(.caption)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 4)
                                            .background(Color.gray.opacity(0.15))
                                            .foregroundStyle(Color.secondaryText(for: colorScheme))
                                            .clipShape(Capsule())
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                    }

                    // Description
                    if let desc = detail.description, !desc.isEmpty {
                        Text(desc)
                            .font(.callout)
                            .foregroundStyle(Color.secondaryText(for: colorScheme))
                            .padding(.horizontal)
                    }

                    // Episodes
                    VStack(alignment: .leading, spacing: 10) {
                        Text("章节")
                            .font(.headline)
                            .padding(.horizontal)

                        if viewModel.isLoadingEpisodes {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: 8) {
                                ForEach(Array(viewModel.episodes.enumerated()), id: \.element.id) { index, episode in
                                    Button {
                                        selectedEpisodeIndex = index
                                        resumePageIndex = 0
                                        showReader = true
                                    } label: {
                                        Text(episode.title)
                                            .font(.caption)
                                            .lineLimit(1)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 8)
                                            .background(Color.cardBg(for: colorScheme))
                                            .clipShape(RoundedRectangle(cornerRadius: 6))
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("comicDetail.episode.\(episode.order)")
                                }
                            }
                            .padding(.horizontal)
                        }
                    }

                    // Continue reading
                    if let progress = ReadingProgressManager.shared.get(comicId: comicId),
                       let episodeIndex = viewModel.episodes.firstIndex(where: { $0.order == progress.episodeOrder }) {
                        Button {
                            selectedEpisodeIndex = episodeIndex
                            resumePageIndex = progress.pageIndex
                            showReader = true
                        } label: {
                            HStack {
                                Image(systemName: "book.fill")
                                Text("继续阅读 \(progress.episodeTitle)")
                                Spacer()
                                Image(systemName: "chevron.right")
                            }
                            .font(.subheadline)
                            .foregroundStyle(.white)
                            .padding()
                            .background(Color.accentPink)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .padding(.horizontal)
                        .accessibilityIdentifier("comicDetail.continueReading")
                    }

                    // Comments entry
                    NavigationLink {
                        CommentsView(comicId: comicId)
                    } label: {
                        HStack {
                            Image(systemName: "bubble.left.and.bubble.right")
                            Text("查看评论 (\(detail.totalComments ?? detail.commentsCount ?? 0)条)")
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .padding()
                        .background(Color.cardBg(for: colorScheme))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .padding(.horizontal)
                    .accessibilityIdentifier("comicDetail.openComments")

                    // Recommended comics
                    VStack(alignment: .leading, spacing: 10) {
                        Text("相关推荐")
                            .font(.headline)
                            .padding(.horizontal)

                        if viewModel.isLoadingRecommended {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding()
                                .accessibilityIdentifier("comicDetail.recommended.loading")
                        } else if !viewModel.recommended.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(viewModel.recommended) { comic in
                                        NavigationLink {
                                            ComicDetailView(comicId: comic.id)
                                        } label: {
                                            VStack(spacing: 6) {
                                                MediaImageView(media: comic.thumb, cornerRadius: 6)
                                                    .frame(width: 100, height: 140)

                                                Text(comic.title)
                                                    .font(.caption)
                                                    .lineLimit(2)
                                                    .multilineTextAlignment(.center)
                                                    .frame(width: 100)
                                            }
                                            .foregroundStyle(.primary)
                                        }
                                    }
                                }
                                .padding(.horizontal)
                            }
                        } else if let error = viewModel.recommendedError {
                            VStack(spacing: 8) {
                                Text("加载推荐失败")
                                    .font(.caption)
                                    .foregroundStyle(Color.secondaryText(for: colorScheme))
                                Text(error)
                                    .font(.caption2)
                                    .foregroundStyle(Color.secondaryText(for: colorScheme))
                                    .multilineTextAlignment(.center)
                                Button("重试") {
                                    Task { await viewModel.loadRecommended() }
                                }
                                .font(.caption)
                                .buttonStyle(.borderedProminent)
                                .tint(Color.accentPink)
                                .accessibilityIdentifier("comicDetail.recommended.retry")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                        } else {
                            Text("暂无相关推荐")
                                .font(.caption)
                                .foregroundStyle(Color.secondaryText(for: colorScheme))
                                .frame(maxWidth: .infinity)
                                .padding()
                                .accessibilityIdentifier("comicDetail.recommended.empty")
                        }
                    }
                }
                .padding(.vertical)
            } else if let error = viewModel.errorMessage {
                VStack(spacing: 12) {
                    Text("加载详情失败")
                        .font(.headline)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(Color.secondaryText(for: colorScheme))
                        .multilineTextAlignment(.center)
                    Button("重试") {
                        Task { await viewModel.load() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.accentPink)
                    .accessibilityIdentifier("comicDetail.error.retry")
                }
                .frame(maxWidth: .infinity, minHeight: 400)
                .padding(.horizontal, 24)
            } else {
                Text("暂无详情")
                    .foregroundStyle(Color.secondaryText(for: colorScheme))
                    .frame(maxWidth: .infinity, minHeight: 400)
            }
        }
        .background(Color.mainBg(for: colorScheme))
        .navigationTitle("详情")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $showReader) {
            ComicReaderView(
                comicId: comicId,
                episodes: viewModel.episodes,
                startEpisodeIndex: selectedEpisodeIndex,
                startPageIndex: resumePageIndex
            )
        }
        .onChange(of: showReader) { _, isShowing in
            if isShowing, let detail = viewModel.detail {
                ReadingHistoryManager.shared.record(
                    comicId: comicId,
                    title: detail.title,
                    thumbPath: detail.thumb?.path ?? "",
                    thumbServer: detail.thumb?.fileServer,
                    author: detail.author
                )
            }
        }
        .imagePreviewSheet(url: $previewImageURL)
        .task { await viewModel.load() }
    }

    private func statLabel(systemImage: String, value: Int) -> some View {
        Label("\(value)", systemImage: systemImage)
            .font(.caption)
            .foregroundStyle(Color.secondaryText(for: colorScheme))
    }

    private func actionButton(title: String, systemImage: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.title3)
                Text(title)
                    .font(.caption)
            }
            .foregroundStyle(tint)
        }
    }
}

// MARK: - Navigation Value Types

// MARK: - Author Search Results

struct AuthorSearchResultsView: View {
    let author: String
    @State private var comics: [Comic] = []
    @State private var isLoading = false
    @State private var currentPage = 0
    @State private var totalPages = 1
    @State private var lastVisitedPage: Int
    @State private var sortMode: SortMode = .defaultSort
    @State private var previewImageURL: URL?
    @State private var showPagination = false
    @State private var scrollPosition = ScrollPosition(edge: .top)
    @Environment(\.colorScheme) private var colorScheme

    init(author: String) {
        self.author = author
        _lastVisitedPage = State(initialValue: UserDefaults.standard.integer(forKey: "lastPage_author_\(author)"))
    }

    private let client = APIClient.shared
    private let blockedManager = BlockedCategoriesManager.shared

    private var filteredComics: [Comic] {
        blockedManager.filterComics(comics)
    }

    var body: some View {
        ScrollView {
            if isLoading && comics.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 300)
            } else if comics.isEmpty && currentPage > 0 {
                Text("暂无结果")
                    .foregroundStyle(Color.secondaryText(for: colorScheme))
                    .frame(maxWidth: .infinity, minHeight: 300)
            } else {
                sortBar

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
        .navigationTitle(author)
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
            UserDefaults.standard.set(currentPage, forKey: "lastPage_author_\(author)")
        }
    }

    private var sortBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SortMode.allCases, id: \.self) { mode in
                    Button {
                        Task { await changeSort(mode) }
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

    private func loadPage(_ page: Int) async {
        guard page >= 1, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let response: APIResponse<ComicsData> = try await client.send(
                .search(keyword: author, page: page, sort: sortMode)
            )
            if let data = response.data {
                comics = data.comics.docs
                currentPage = data.comics.page
                totalPages = data.comics.pages
            }
        } catch {}
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
}

// MARK: - Tag Search Results

struct TagSearchResultsView: View {
    let keyword: String
    @State private var comics: [Comic] = []
    @State private var isLoading = false
    @State private var currentPage = 0
    @State private var totalPages = 1
    @State private var lastVisitedPage: Int
    @State private var sortMode: SortMode = .defaultSort
    @State private var previewImageURL: URL?
    @State private var showPagination = false
    @State private var scrollPosition = ScrollPosition(edge: .top)
    @Environment(\.colorScheme) private var colorScheme

    init(keyword: String) {
        self.keyword = keyword
        _lastVisitedPage = State(initialValue: UserDefaults.standard.integer(forKey: "lastPage_tag_\(keyword)"))
    }

    private let client = APIClient.shared
    private let blockedManager = BlockedCategoriesManager.shared

    private var filteredComics: [Comic] {
        blockedManager.filterComics(comics)
    }

    var body: some View {
        ScrollView {
            if isLoading && comics.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 300)
            } else if comics.isEmpty && currentPage > 0 {
                Text("暂无结果")
                    .foregroundStyle(Color.secondaryText(for: colorScheme))
                    .frame(maxWidth: .infinity, minHeight: 300)
            } else {
                sortBar

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
        .navigationTitle(keyword)
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
            UserDefaults.standard.set(currentPage, forKey: "lastPage_tag_\(keyword)")
        }
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

    private func loadPage(_ page: Int) async {
        guard page >= 1, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let response: APIResponse<ComicsData> = try await client.send(
                .search(keyword: keyword, page: page, sort: sortMode)
            )
            if let data = response.data {
                comics = data.comics.docs
                currentPage = data.comics.page
                totalPages = data.comics.pages
            }
        } catch {}
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
}
