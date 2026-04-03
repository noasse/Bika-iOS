import SwiftUI

struct ComicDetailView: View {
    let comicId: String
    @State private var viewModel: ComicDetailViewModel
    @State private var showReader = false
    @State private var selectedEpisodeIndex = 0
    @State private var resumePageIndex = 0
    @State private var previewImageURL: URL?
    @Environment(\.colorScheme) private var colorScheme
    private let readingProgressManager: ReadingProgressManager
    private let readingHistoryManager: ReadingHistoryManager

    init(
        comicId: String,
        readingProgressManager: ReadingProgressManager = .shared,
        readingHistoryManager: ReadingHistoryManager = .shared
    ) {
        self.comicId = comicId
        self.readingProgressManager = readingProgressManager
        self.readingHistoryManager = readingHistoryManager
        _viewModel = State(initialValue: ComicDetailViewModel(comicId: comicId))
    }

    var body: some View {
        ScrollView {
            if viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 400)
            } else if let detail = viewModel.detail {
                detailContent(detail)
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
        .alert("操作失败", isPresented: actionErrorIsPresented) {
            Button("确定", role: .cancel) {
                viewModel.actionErrorMessage = nil
            }
        } message: {
            Text(viewModel.actionErrorMessage ?? "")
        }
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
                readingHistoryManager.record(
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

    private var commentEntryLabel: String {
        if let count = viewModel.commentEntryCount {
            return "查看评论 (\(count)条)"
        }

        return "查看评论"
    }

    private var actionErrorIsPresented: Binding<Bool> {
        Binding(
            get: { viewModel.actionErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    viewModel.actionErrorMessage = nil
                }
            }
        )
    }

    @ViewBuilder
    private func detailContent(_ detail: ComicDetail) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            ComicDetailHeaderSection(
                detail: detail,
                colorScheme: colorScheme,
                onPreviewImage: { previewImageURL = detail.thumb?.imageURL }
            )

            ComicDetailActionsSection(
                detail: detail,
                onToggleLike: { Task { await viewModel.toggleLike() } },
                onToggleFavourite: { Task { await viewModel.toggleFavourite() } }
            )

            if let categories = detail.categories, !categories.isEmpty {
                ComicCategoriesSection(categories: categories)
            }

            if let tags = detail.tags, !tags.isEmpty {
                ComicTagsSection(tags: tags, colorScheme: colorScheme)
            }

            if let description = detail.description, !description.isEmpty {
                ComicDescriptionSection(description: description, colorScheme: colorScheme)
            }

            ComicEpisodesSection(
                episodes: viewModel.episodes,
                isLoading: viewModel.isLoadingEpisodes,
                errorMessage: viewModel.episodesError,
                colorScheme: colorScheme,
                onSelectEpisode: selectEpisode(at:),
                onRetry: { Task { await viewModel.reloadEpisodes() } }
            )

            if let progress = readingProgressManager.get(comicId: comicId),
               let episodeIndex = viewModel.episodes.firstIndex(where: { $0.order == progress.episodeOrder }) {
                ContinueReadingSection(progress: progress) {
                    selectedEpisodeIndex = episodeIndex
                    resumePageIndex = progress.pageIndex
                    showReader = true
                }
            }

            ComicCommentEntrySection(
                label: commentEntryLabel,
                colorScheme: colorScheme,
                comicId: comicId
            )

            RecommendedComicsSection(
                comics: viewModel.recommended,
                isLoading: viewModel.isLoadingRecommended,
                errorMessage: viewModel.recommendedError,
                colorScheme: colorScheme,
                onRetry: { Task { await viewModel.loadRecommended() } }
            )
        }
        .padding(.vertical)
    }

    private func selectEpisode(at index: Int) {
        selectedEpisodeIndex = index
        resumePageIndex = 0
        showReader = true
    }
}
