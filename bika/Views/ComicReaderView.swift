import SwiftUI

// MARK: - Zoomable Image View

struct ZoomableImageView: View {
    let url: URL?
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0

    var body: some View {
        CachedAsyncImage(url: url) {
            ProgressView().tint(.white)
        }
        .aspectRatio(contentMode: .fit)
        .scaleEffect(scale)
        .simultaneousGesture(
            MagnifyGesture()
                .onChanged { value in
                    let newScale = lastScale * value.magnification
                    scale = min(max(newScale, 1.0), 4.0)
                }
                .onEnded { _ in
                    withAnimation(.easeOut(duration: 0.2)) {
                        scale = 1.0
                        lastScale = 1.0
                    }
                }
        )
        .onTapGesture(count: 2) {
            withAnimation(.easeOut(duration: 0.2)) {
                if scale > 1.0 {
                    scale = 1.0
                    lastScale = 1.0
                } else {
                    scale = 2.0
                    lastScale = 2.0
                }
            }
        }
    }
}

// MARK: - Comic Reader View

struct ComicReaderView: View {
    @State private var viewModel: ReaderViewModel
    @State private var currentPage = 0
    @State private var didJumpToInitialPage = false
    @Environment(\.dismiss) private var dismiss
    private let startPageIndex: Int

    init(comicId: String, episodes: [Episode], startEpisodeIndex: Int, startPageIndex: Int = 0) {
        _viewModel = State(initialValue: ReaderViewModel(
            comicId: comicId,
            episodes: episodes,
            startEpisodeIndex: startEpisodeIndex
        ))
        self.startPageIndex = startPageIndex
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if viewModel.isLoading && viewModel.pages.isEmpty {
                ProgressView()
                    .tint(.white)
            } else if viewModel.pages.isEmpty {
                Text("暂无页面")
                    .foregroundStyle(.white)
            } else {
                Group {
                    switch viewModel.readerMode {
                    case .horizontal:
                        horizontalReader

                    case .vertical:
                        verticalReader
                    }
                }
                .simultaneousGesture(
                    SpatialTapGesture()
                        .onEnded { value in
                            let screenWidth = UIScreen.main.bounds.width
                            let center = screenWidth / 2
                            let margin = screenWidth * 0.3
                            if value.location.x > center - margin && value.location.x < center + margin {
                                viewModel.toggleToolbar()
                            }
                        }
                )
            }

            if viewModel.showToolbar {
                toolbarOverlay
            }
        }
        .statusBar(hidden: !viewModel.showToolbar)
        .task {
            await viewModel.loadPages()
        }
        .onDisappear {
            saveProgress()
        }
    }

    // MARK: - Horizontal Reader

    private var horizontalReader: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(Array(viewModel.pages.enumerated()), id: \.offset) { index, page in
                        ZoomableImageView(url: page.media.imageURL)
                            .containerRelativeFrame(.horizontal)
                            .id(index)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollIndicators(.automatic)
            .onScrollGeometryChange(for: Int.self) { geo in
                let pageWidth = geo.visibleRect.width
                guard pageWidth > 0 else { return 0 }
                return max(0, Int(round(geo.contentOffset.x / pageWidth)))
            } action: { _, newPage in
                currentPage = newPage
            }
            .ignoresSafeArea()
            .onChange(of: viewModel.pages.count) { _, count in
                if !didJumpToInitialPage && startPageIndex > 0 && count > startPageIndex {
                    didJumpToInitialPage = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        proxy.scrollTo(startPageIndex, anchor: .leading)
                        currentPage = startPageIndex
                    }
                }
            }
        }
    }

    // MARK: - Vertical Reader

    private var verticalReader: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(Array(viewModel.pages.enumerated()), id: \.offset) { index, page in
                        ZoomableImageView(url: page.media.imageURL)
                            .id(index)
                            .onAppear {
                                currentPage = index
                            }
                    }
                }
            }
            .scrollIndicators(.automatic)
            .ignoresSafeArea()
            .onChange(of: viewModel.pages.count) { _, count in
                if !didJumpToInitialPage && startPageIndex > 0 && count > startPageIndex {
                    didJumpToInitialPage = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        proxy.scrollTo(startPageIndex, anchor: .top)
                        currentPage = startPageIndex
                    }
                }
            }
        }
    }

    // MARK: - Save Progress

    private func saveProgress() {
        guard let episode = viewModel.currentEpisode else { return }
        ReadingProgressManager.shared.save(
            comicId: viewModel.comicId,
            progress: .init(
                episodeOrder: episode.order,
                episodeTitle: episode.title,
                pageIndex: currentPage
            )
        )
    }

    // MARK: - Toolbar

    private var toolbarOverlay: some View {
        VStack {
            HStack {
                Button {
                    saveProgress()
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.title3)
                }

                Spacer()

                Text(viewModel.currentEpisode?.title ?? "")
                    .font(.subheadline)

                Spacer()

                Text("\(currentPage + 1)/\(viewModel.pages.count)")
                    .font(.caption)
            }
            .padding()
            .background(.ultraThinMaterial)

            Spacer()

            HStack(spacing: 20) {
                Button {
                    Task {
                        didJumpToInitialPage = true
                        await viewModel.previousEpisode()
                        currentPage = 0
                    }
                } label: {
                    Image(systemName: "chevron.left")
                    Text("上一章")
                }
                .disabled(!viewModel.hasPreviousEpisode)

                Spacer()

                Button {
                    let newMode: ReaderViewModel.ReaderMode = viewModel.readerMode == .horizontal ? .vertical : .horizontal
                    viewModel.setReaderMode(newMode)
                } label: {
                    Image(systemName: viewModel.readerMode == .horizontal ? "arrow.up.arrow.down" : "arrow.left.arrow.right")
                    Text(viewModel.readerMode == .horizontal ? "滚动" : "翻页")
                }

                Spacer()

                Button {
                    Task {
                        didJumpToInitialPage = true
                        await viewModel.nextEpisode()
                        currentPage = 0
                    }
                } label: {
                    Text("下一章")
                    Image(systemName: "chevron.right")
                }
                .disabled(!viewModel.hasNextEpisode)
            }
            .font(.subheadline)
            .padding()
            .background(.ultraThinMaterial)
        }
        .foregroundStyle(.white)
    }
}
