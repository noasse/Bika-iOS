import SwiftUI
import UIKit

// MARK: - Comic Reader View

struct ComicReaderView: View {
    @State private var viewModel: ReaderViewModel
    @State private var currentPage = 0
    @State private var scrollPosition: Int?
    @State private var hasJumpedToStart = false
    @State private var imageSizes: [Int: CGSize] = [:]
    @State private var sampledIndices: [Int] = []
    @State private var sampledAspectRatios: [Int: CGFloat] = [:]
    @State private var estimatedAspectRatio: CGFloat?
    @State private var imagePrefetchTask: Task<Void, Never>?
    @State private var imagePrefetchKey: String?
    @State private var viewportSize = CGSize.zero
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    private let startPageIndex: Int
    private let readingProgressManager: ReadingProgressManager
    private let imageDataLoader: any ImageDataLoading
    private let imageCache: ImageCache
    private let isUITesting: Bool

    init(
        comicId: String,
        episodes: [Episode],
        startEpisodeIndex: Int,
        startPageIndex: Int = 0,
        readingProgressManager: ReadingProgressManager? = nil,
        imageDataLoader: any ImageDataLoading = AppDependencies.shared.imageDataLoader,
        imageCache: ImageCache = .shared,
        isUITesting: Bool = AppDependencies.shared.isUITesting
    ) {
        _viewModel = State(initialValue: ReaderViewModel(
            comicId: comicId,
            episodes: episodes,
            startEpisodeIndex: startEpisodeIndex
        ))
        self.startPageIndex = startPageIndex
        self.readingProgressManager = readingProgressManager ?? .shared
        self.imageDataLoader = imageDataLoader
        self.imageCache = imageCache
        self.isUITesting = isUITesting
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if viewModel.isLoading && viewModel.pages.isEmpty {
                ProgressView()
                    .tint(.white)
            } else if viewModel.showsFullScreenLoadError,
                      let errorMessage = viewModel.errorMessage {
                VStack(spacing: 12) {
                    Text("页面加载失败")
                        .font(.headline)
                    Text(errorMessage)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white.opacity(0.8))
                    Button("重试") {
                        viewModel.startLoadingPages()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.accentPink)
                }
                .padding(24)
                .foregroundStyle(.white)
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
            }

            if viewModel.showsPaginationError,
               let errorMessage = viewModel.errorMessage {
                paginationErrorBanner(errorMessage)
            }

            if viewModel.showToolbar {
                toolbarOverlay
            }
        }
        .statusBar(hidden: !viewModel.showToolbar)
        .onGeometryChange(for: CGSize.self) { geometry in
            geometry.size
        } action: { oldSize, newSize in
            guard newSize.width > 0, newSize.height > 0 else { return }
            guard !isNearlyEqual(oldSize, newSize) else { return }
            viewportSize = newSize
            imagePrefetchKey = nil
            scheduleImagePrefetch(around: currentPage)
        }
        .task {
            viewModel.startLoadingPages()
            if isUITesting {
                viewModel.showToolbar = true
            }
        }
        .onDisappear {
            viewModel.cancelLoadingPages()
            cancelImagePrefetch()
            saveProgress()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase != .active {
                saveProgress()
            }
        }
        .onChange(of: scrollPosition) { _, newPos in
            if let newPos {
                currentPage = newPos
                scheduleImagePrefetch(around: newPos)
            }
        }
        .onChange(of: viewModel.pages.count) { _, count in
            guard count > 0 else {
                cancelImagePrefetch()
                return
            }

            if !hasJumpedToStart {
                let restoredPage = min(startPageIndex, count - 1)
                hasJumpedToStart = true
                if restoredPage > 0 {
                    scrollPosition = restoredPage
                    currentPage = restoredPage
                } else {
                    currentPage = 0
                }
            }

            scheduleImagePrefetch(around: currentPage)
        }
        .onChange(of: viewModel.currentEpisodeIndex) { _, _ in
            resetImageLayoutState()
            cancelImagePrefetch()
        }
        .onChange(of: viewModel.readerMode) { _, _ in
            imagePrefetchKey = nil
            scheduleImagePrefetch(around: currentPage)
        }
    }

    private func paginationErrorBanner(_ errorMessage: String) -> some View {
        VStack {
            Spacer()
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)

                VStack(alignment: .leading, spacing: 2) {
                    Text("后续页面加载失败")
                        .font(.subheadline.weight(.semibold))
                    Text(errorMessage)
                        .font(.caption)
                        .lineLimit(2)
                        .foregroundStyle(.white.opacity(0.8))
                }

                Spacer(minLength: 8)

                Button("重试") {
                    viewModel.startLoadingPages()
                }
                .buttonStyle(.bordered)
                .tint(.white)
                .accessibilityIdentifier("reader.paginationRetry")
            }
            .padding(12)
            .foregroundStyle(.white)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
            .accessibilityIdentifier("reader.paginationError")
        }
        .padding(.horizontal, 16)
        .padding(.bottom, viewModel.showToolbar ? 88 : 16)
    }

    // MARK: - Tap to Toggle Toolbar

    private func handleTap(_ location: CGPoint) {
        let screenWidth = max(viewportSize.width, 1)
        let center = screenWidth / 2
        let margin = screenWidth * 0.3
        if location.x > center - margin && location.x < center + margin {
            withAnimation(.easeInOut(duration: 0.2)) {
                viewModel.toggleToolbar()
            }
        }
    }

    // MARK: - Horizontal Reader

    private var horizontalReader: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(Array(viewModel.pages.enumerated()), id: \.offset) { index, page in
                    ZoomableImageView(
                        url: page.media.imageURL,
                        imageLoader: imageDataLoader,
                        imageCache: imageCache,
                        onSingleTap: handleTap
                    )
                        .containerRelativeFrame(.horizontal)
                        .id(index)
                }
            }
            .scrollTargetLayout()
        }
        .scrollPosition(id: $scrollPosition)
        .scrollTargetBehavior(.paging)
        .scrollIndicators(.automatic)
        .ignoresSafeArea()
    }

    // MARK: - Vertical Reader

    private var verticalReader: some View {
        GeometryReader { geometry in
            let viewportWidth = max(geometry.size.width, 1)
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(Array(viewModel.pages.enumerated()), id: \.offset) { index, page in
                        ZoomableImageView(
                            url: page.media.imageURL,
                            imageLoader: imageDataLoader,
                            imageCache: imageCache,
                            sizing: .fitWidth(viewportWidth),
                            onImageSize: { size in
                                updateImageSize(size, for: index)
                            },
                            onSingleTap: handleTap
                        )
                        .onAppear {
                            registerSampleIndexIfNeeded(index)
                        }
                        .frame(
                            width: viewportWidth,
                            height: pageHeight(for: index, viewportWidth: viewportWidth)
                        )
                        .id(index)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollPosition(id: $scrollPosition)
            .scrollIndicators(.automatic)
        }
        .ignoresSafeArea()
    }

    private func pageHeight(for index: Int, viewportWidth: CGFloat) -> CGFloat {
        ReaderVerticalImageLayout.pageHeight(
            viewportWidth: viewportWidth,
            imageSize: imageSizes[index],
            estimatedAspectRatio: estimatedAspectRatio
        )
    }

    private func registerSampleIndexIfNeeded(_ index: Int) {
        guard sampledIndices.count < 3 else { return }
        guard !sampledIndices.contains(index) else { return }
        sampledIndices.append(index)
    }

    private func updateImageSize(_ size: CGSize, for index: Int) {
        guard size.width > 0, size.height > 0 else { return }

        if let previous = imageSizes[index], isNearlyEqual(previous, size) {
            return
        }

        imageSizes[index] = size

        guard sampledIndices.contains(index) else { return }
        sampledAspectRatios[index] = size.height / size.width
        estimatedAspectRatio = sampledMedianAspectRatio()
    }

    private func sampledMedianAspectRatio() -> CGFloat? {
        let ratios = sampledIndices.compactMap { sampledAspectRatios[$0] }.sorted()
        guard !ratios.isEmpty else { return nil }
        let mid = ratios.count / 2
        if ratios.count.isMultiple(of: 2) {
            return (ratios[mid - 1] + ratios[mid]) / 2
        }
        return ratios[mid]
    }

    private func resetImageLayoutState() {
        imageSizes = [:]
        sampledIndices = []
        sampledAspectRatios = [:]
        estimatedAspectRatio = nil
    }

    private func isNearlyEqual(_ lhs: CGSize, _ rhs: CGSize) -> Bool {
        abs(lhs.width - rhs.width) < 1 && abs(lhs.height - rhs.height) < 1
    }

    // MARK: - Image Prefetch

    private func scheduleImagePrefetch(around index: Int) {
        let pageCount = viewModel.pages.count
        guard pageCount > 0 else {
            cancelImagePrefetch()
            return
        }

        let clampedIndex = min(max(index, 0), pageCount - 1)
        let requests = ReaderImagePrefetchPlan.indices(
            currentIndex: clampedIndex,
            pageCount: pageCount,
            lookBehind: 1,
            lookAhead: 4
        )
        .compactMap(imagePrefetchRequest)

        let nextKey = requests.map(\.cacheIdentity).joined(separator: "|")
        guard nextKey != imagePrefetchKey else { return }
        imagePrefetchKey = nextKey

        imagePrefetchTask?.cancel()
        guard !requests.isEmpty else { return }

        let imageLoader = imageDataLoader
        let imageCache = imageCache
        let prefetchKey = nextKey
        imagePrefetchTask = Task(priority: .utility) {
            let prefetchedSizes = await ReaderImagePrefetcher.prefetch(
                requests: requests,
                imageLoader: imageLoader,
                imageCache: imageCache
            )
            guard !Task.isCancelled, imagePrefetchKey == prefetchKey else { return }
            for (index, size) in prefetchedSizes {
                updateImageSize(size, for: index)
            }
        }
    }

    private func cancelImagePrefetch() {
        imagePrefetchTask?.cancel()
        imagePrefetchTask = nil
        imagePrefetchKey = nil
    }

    private func imagePrefetchRequest(for index: Int) -> ReaderImagePrefetchRequest? {
        guard viewModel.pages.indices.contains(index),
              let url = viewModel.pages[index].media.imageURL else {
            return nil
        }

        guard let target = imagePrefetchTarget() else { return nil }
        return ReaderImagePrefetchRequest(index: index, url: url, target: target)
    }

    private func imagePrefetchTarget() -> ImageDecodeTarget? {
        guard viewportSize.width.isFinite, viewportSize.width > 0 else { return nil }

        switch viewModel.readerMode {
        case .horizontal:
            guard viewportSize.height.isFinite, viewportSize.height > 0 else { return nil }
            return .fit(viewportSize)

        case .vertical:
            return .fitWidth(viewportSize.width)
        }
    }

    // MARK: - Save Progress

    private func saveProgress() {
        guard let episode = viewModel.currentEpisode else { return }
        readingProgressManager.save(
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
        VStack(spacing: 0) {
            // 顶部栏：背景延伸到顶部安全区
            HStack {
                Button {
                    saveProgress()
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.title3)
                }
                .accessibilityIdentifier("reader.close")

                Spacer()

                Text(viewModel.currentEpisode?.title ?? "")
                    .font(.subheadline)

                Spacer()

                Text("\(currentPage + 1)/\(viewModel.pages.count)")
                    .font(.caption)
            }
            .padding()
            .background(
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .ignoresSafeArea(edges: .top)
            )

            Spacer()

            // 底部栏：背景延伸到底部安全区
            HStack(spacing: 20) {
                Button {
                    scrollPosition = 0
                    currentPage = 0
                    viewModel.previousEpisode()
                } label: {
                    Image(systemName: "chevron.left")
                    Text("上一章")
                }
                .disabled(!viewModel.hasPreviousEpisode || viewModel.isLoading)
                .accessibilityIdentifier("reader.previousEpisode")

                Spacer()

                Button {
                    let newMode: ReaderViewModel.ReaderMode = viewModel.readerMode == .horizontal ? .vertical : .horizontal
                    viewModel.setReaderMode(newMode)
                    scrollPosition = currentPage
                } label: {
                    Image(systemName: viewModel.readerMode == .horizontal ? "arrow.up.arrow.down" : "arrow.left.arrow.right")
                    Text(viewModel.readerMode == .horizontal ? "滚动" : "翻页")
                }
                .accessibilityIdentifier("reader.toggleMode")

                Spacer()

                Button {
                    scrollPosition = 0
                    currentPage = 0
                    viewModel.nextEpisode()
                } label: {
                    Text("下一章")
                    Image(systemName: "chevron.right")
                }
                .disabled(!viewModel.hasNextEpisode || viewModel.isLoading)
                .accessibilityIdentifier("reader.nextEpisode")
            }
            .font(.subheadline)
            .padding()
            .background(
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .ignoresSafeArea(edges: .bottom)
            )
        }
        .foregroundStyle(.white)
    }
}

nonisolated enum ReaderVerticalImageLayout {
    static let fallbackPageHeight: CGFloat = 500

    static func pageHeight(
        viewportWidth: CGFloat,
        imageSize: CGSize?,
        estimatedAspectRatio: CGFloat?,
        fallbackHeight: CGFloat = fallbackPageHeight
    ) -> CGFloat {
        guard viewportWidth.isFinite, viewportWidth > 0 else { return fallbackHeight }

        if let imageSize,
           imageSize.width.isFinite,
           imageSize.height.isFinite,
           imageSize.width > 0,
           imageSize.height > 0 {
            return viewportWidth * (imageSize.height / imageSize.width)
        }

        if let estimatedAspectRatio,
           estimatedAspectRatio.isFinite,
           estimatedAspectRatio > 0 {
            return viewportWidth * estimatedAspectRatio
        }

        return fallbackHeight
    }
}

nonisolated enum ReaderImagePrefetchPlan {
    static func indices(
        currentIndex: Int,
        pageCount: Int,
        lookBehind: Int,
        lookAhead: Int
    ) -> [Int] {
        guard pageCount > 0 else { return [] }

        let current = min(max(currentIndex, 0), pageCount - 1)
        let forwardEnd = min(pageCount - 1, current + max(lookAhead, 0))
        var indices: [Int] = []
        if current < forwardEnd {
            indices.append(contentsOf: (current + 1)...forwardEnd)
        }

        let backwardEnd = max(0, current - max(lookBehind, 0))
        if backwardEnd < current {
            indices.append(contentsOf: stride(from: current - 1, through: backwardEnd, by: -1))
        }

        return indices
    }
}

nonisolated struct ReaderImagePrefetchRequest: Sendable {
    let index: Int
    let url: URL
    let target: ImageDecodeTarget

    var cacheIdentity: String {
        ImageCache.cacheIdentity(for: url, target: target, overscan: 2)
    }
}

nonisolated private struct ReaderImagePrefetchResult: Sendable {
    let index: Int
    let displaySize: CGSize
}

nonisolated enum ReaderImagePrefetcher {
    private static let maximumConcurrentRequests = 2

    static func prefetch(
        requests: [ReaderImagePrefetchRequest],
        imageLoader: any ImageDataLoading,
        imageCache: ImageCache
    ) async -> [Int: CGSize] {
        guard !requests.isEmpty else { return [:] }

        var nextIndex = 0
        var displaySizes: [Int: CGSize] = [:]
        await withTaskGroup(of: ReaderImagePrefetchResult?.self) { group in
            let initialRequestCount = min(maximumConcurrentRequests, requests.count)
            for _ in 0..<initialRequestCount {
                let request = requests[nextIndex]
                nextIndex += 1
                group.addTask {
                    await prefetch(request: request, imageLoader: imageLoader, imageCache: imageCache)
                }
            }

            while let result = await group.next() {
                if let result {
                    displaySizes[result.index] = result.displaySize
                }

                if Task.isCancelled {
                    group.cancelAll()
                    return
                }

                guard nextIndex < requests.count else { continue }
                let request = requests[nextIndex]
                nextIndex += 1
                group.addTask {
                    await prefetch(request: request, imageLoader: imageLoader, imageCache: imageCache)
                }
            }
        }
        return displaySizes
    }

    private static func prefetch(
        request: ReaderImagePrefetchRequest,
        imageLoader: any ImageDataLoading,
        imageCache: ImageCache
    ) async -> ReaderImagePrefetchResult? {
        guard !Task.isCancelled else { return nil }
        if let cached = imageCache.asset(
            for: request.url,
            target: request.target,
            overscan: 2
        ) {
            return ReaderImagePrefetchResult(
                index: request.index,
                displaySize: cached.displaySize
            )
        }

        do {
            let asset = try await imageCache.loadAsset(
                for: request.url,
                target: request.target,
                overscan: 2,
                priority: .utility,
                imageLoader: imageLoader
            )
            guard !Task.isCancelled else { return nil }
            return ReaderImagePrefetchResult(
                index: request.index,
                displaySize: asset.displaySize
            )
        } catch {
            // Prefetch failures should never block reading; the visible page loader still handles retries.
            return nil
        }
    }
}
