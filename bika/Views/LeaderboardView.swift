import SwiftUI

struct LeaderboardView: View {
    @Environment(\.colorScheme) private var colorScheme

    @State private var viewModel: LeaderboardViewModel
    @State private var previewImageURL: URL?

    private let blockedManager: BlockedCategoriesManager
    private let topAnchorID = "leaderboard.top"

    init(
        viewModel: LeaderboardViewModel = LeaderboardViewModel(),
        blockedManager: BlockedCategoriesManager = .shared
    ) {
        _viewModel = State(initialValue: viewModel)
        self.blockedManager = blockedManager
    }

    private var filteredComics: [Comic] {
        blockedManager.filterComics(viewModel.comics)
    }

    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                Picker("排行榜", selection: Binding(
                    get: { viewModel.selectedType },
                    set: { type in
                        Task {
                            await viewModel.switchType(type)
                            scrollToTop(using: proxy)
                        }
                    }
                )) {
                    Text("24小时").tag(LeaderboardType.hour24)
                    Text("7天").tag(LeaderboardType.day7)
                    Text("30天").tag(LeaderboardType.day30)
                }
                .pickerStyle(.segmented)
                .padding()

                content(using: proxy)
            }
            .background(Color.mainBg(for: colorScheme))
            .navigationTitle("排行榜")
            .navigationBarTitleDisplayMode(.inline)
            .imagePreviewSheet(url: $previewImageURL)
            .task {
                await viewModel.loadIfNeeded()
            }
            .onChange(of: viewModel.comics.map(\.id)) { _, _ in
                restoreSavedPosition(using: proxy)
            }
        }
    }

    @ViewBuilder
    private func content(using proxy: ScrollViewProxy) -> some View {
        if viewModel.isLoading && viewModel.comics.isEmpty {
            Spacer(minLength: 0)
            ProgressView()
            Spacer(minLength: 0)
        } else if let errorMessage = viewModel.errorMessage, filteredComics.isEmpty {
            VStack(spacing: 12) {
                Text("排行榜加载失败")
                    .font(.headline)
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(Color.secondaryText(for: colorScheme))
                    .multilineTextAlignment(.center)
                Button("重试") {
                    Task { await viewModel.load() }
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.accentPink)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 24)
        } else if filteredComics.isEmpty {
            Text("暂无排行内容")
                .foregroundStyle(Color.secondaryText(for: colorScheme))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                Color.clear
                    .frame(height: 0)
                    .id(topAnchorID)

                LazyVStack(spacing: 10) {
                    ForEach(Array(filteredComics.enumerated()), id: \.element.id) { index, comic in
                        NavigationLink {
                            ComicDetailView(comicId: comic.id)
                        } label: {
                            HStack(spacing: 0) {
                                Text("\(index + 1)")
                                    .font(.headline)
                                    .foregroundStyle(index < 3 ? Color.accentPink : Color.secondaryText(for: colorScheme))
                                    .frame(width: 32)

                                ComicCardView(comic: comic, previewImageURL: $previewImageURL)
                            }
                        }
                        .id(comic.id)
                        .simultaneousGesture(
                            TapGesture().onEnded {
                                viewModel.rememberNavigationAnchor(comicID: comic.id)
                            }
                        )
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private func restoreSavedPosition(using proxy: ScrollViewProxy) {
        guard let comicID = viewModel.pendingRestoreComicID else { return }
        guard filteredComics.contains(where: { $0.id == comicID }) else { return }

        DispatchQueue.main.async {
            proxy.scrollTo(comicID, anchor: .top)
            viewModel.consumePendingRestoreComicID()
        }
    }

    private func scrollToTop(using proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            proxy.scrollTo(topAnchorID, anchor: .top)
        }
    }
}
