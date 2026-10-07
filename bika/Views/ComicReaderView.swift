import SwiftUI
import UIKit

// MARK: - Comic Reader View

struct ComicReaderView: View {
    @State private var viewModel: ReaderViewModel
    @State private var currentPage = 0
    @State private var hasJumpedToStart = false
    @State private var pageLayout = ReaderPageLayoutStore()
    @State private var imagePrefetchTask: Task<Void, Never>?
    @State private var imagePrefetchKey: [ReaderImagePrefetchRequest]?
    /// Size of the box pages are actually rendered into, measured after safe-area expansion.
    /// Both readers lay out inside `.ignoresSafeArea()`, so this — not the safe-area-inset
    /// container — is the size images must be decoded for.
    @State private var contentSize = CGSize.zero
    /// Debug builds: draw what the translation pipeline recognises on each page.
    @State private var debugRecognizesText = false
#if DEBUG
    /// Progress of a chapter recognition report: pages done out of total.
    @State private var recognitionReportProgress: (done: Int, total: Int)?
    @State private var recognitionReportTask: Task<Void, Never>?
    @State private var recognitionReportItem: DiagnosticsExportItem?
    @State private var recognitionReportMessage: String?
#endif
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

#if DEBUG
            if let progress = recognitionReportProgress {
                recognitionReportBadge(progress)
            }
#endif
        }
        .background(contentGeometryProbe)
        .statusBar(hidden: !viewModel.showToolbar)
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
#if DEBUG
            recognitionReportTask?.cancel()
#endif
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase != .active {
                saveProgress()
            }
        }
        .onChange(of: currentPage) { _, newPage in
            scheduleImagePrefetch(around: newPage)
        }
        .onChange(of: viewModel.pages.count) { _, count in
            guard count > 0 else {
                cancelImagePrefetch()
                return
            }

            if !hasJumpedToStart {
                let restoredPage = min(startPageIndex, count - 1)
                hasJumpedToStart = true
                currentPage = restoredPage
            }

            scheduleImagePrefetch(around: currentPage)
        }
        .onChange(of: viewModel.currentEpisodeIndex) { _, _ in
            pageLayout.reset()
            cancelImagePrefetch()
        }
        .onChange(of: viewModel.readerMode) { _, _ in
            imagePrefetchKey = nil
            scheduleImagePrefetch(around: currentPage)
        }
#if DEBUG
        .sheet(item: $recognitionReportItem) { item in
            ActivityShareSheet(fileURL: item.url)
        }
        .alert(
            "识别报告",
            isPresented: Binding(
                get: { recognitionReportMessage != nil },
                set: { if !$0 { recognitionReportMessage = nil } }
            )
        ) {
            Button("好", role: .cancel) {}
        } message: {
            Text(recognitionReportMessage ?? "")
        }
#endif
    }

    /// `scrollPosition(id:)` reports `nil` whenever the scroll view is between items. Dropping
    /// those keeps `currentPage` — the one place the reader records where the reader is — always
    /// answerable, which is what progress saving and the page counter need.
    private var scrollPositionBinding: Binding<Int?> {
        Binding(
            get: { currentPage },
            set: { newPosition in
                guard let newPosition else { return }
                currentPage = newPosition
            }
        )
    }

    /// Measures the same `.ignoresSafeArea()` box the two readers lay out in, so the decode
    /// target the prefetcher uses is the one the visible page will ask for.
    private var contentGeometryProbe: some View {
        Color.clear
            .ignoresSafeArea()
            .onGeometryChange(for: CGSize.self) { geometry in
                geometry.size
            } action: { _, newSize in
                guard ReaderViewportUpdate.shouldApply(
                    currentSize: contentSize,
                    newSize: newSize
                ) else {
                    return
                }
                contentSize = newSize
                imagePrefetchKey = nil
                scheduleImagePrefetch(around: currentPage)
            }
    }

    /// The one decode target every page in the reader is loaded at, whether it is being
    /// prefetched or displayed.
    private func readerDecodeTarget() -> ImageDecodeTarget? {
        ReaderDecodeTargetResolver.target(
            mode: viewModel.readerMode,
            contentSize: contentSize
        )
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
        // No usable width yet means no meaningful centre band. Bail out instead of clamping to
        // 1pt, which used to silently produce a tap zone nothing could ever hit.
        guard contentSize.width.isFinite, contentSize.width > 0 else { return }
        let screenWidth = contentSize.width
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
                        decodeTarget: readerDecodeTarget(),
                        pageID: readerPageID(for: index),
                        onSingleTap: handleTap,
                        debugRecognizesText: debugRecognizesText
                    )
                        .containerRelativeFrame(.horizontal)
                        .id(index)
                }
            }
            .scrollTargetLayout()
        }
        .scrollPosition(id: scrollPositionBinding)
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
                        let pageID = readerPageID(for: index)
                        ZoomableImageView(
                            url: page.media.imageURL,
                            imageLoader: imageDataLoader,
                            imageCache: imageCache,
                            decodeTarget: readerDecodeTarget(),
                            pageID: pageID,
                            onImageAspectRatio: { aspectRatio in
                                guard let pageID else { return }
                                pageLayout.record(aspectRatio, for: pageID)
                            },
                            onSingleTap: handleTap,
                            debugRecognizesText: debugRecognizesText
                        )
                        .onAppear {
                            guard let pageID else { return }
                            pageLayout.registerSample(pageID)
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
            .scrollPosition(id: scrollPositionBinding)
            .scrollIndicators(.automatic)
        }
        .ignoresSafeArea()
    }

    private func pageHeight(for index: Int, viewportWidth: CGFloat) -> CGFloat {
        pageLayout.pageHeight(
            for: readerPageID(for: index),
            viewportWidth: viewportWidth
        )
    }

    private func readerPageID(for index: Int) -> ReaderPageID? {
        guard viewModel.pages.indices.contains(index),
              let episodeID = viewModel.currentEpisode?.id,
              let imageURL = viewModel.pages[index].media.imageURL else {
            return nil
        }

        let page = viewModel.pages[index]
        let backendID = page.id?.trimmingCharacters(in: .whitespacesAndNewlines)
        return ReaderPageID(
            episodeID: episodeID,
            backendPageID: backendID.flatMap { $0.isEmpty ? nil : $0 },
            imageURL: imageURL
        )
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

        let nextKey = requests
        guard nextKey != imagePrefetchKey else { return }
        imagePrefetchKey = nextKey

        imagePrefetchTask?.cancel()
        guard !requests.isEmpty else { return }

        let imageLoader = imageDataLoader
        let imageCache = imageCache
        let prefetchKey = nextKey
        imagePrefetchTask = Task(priority: .utility) {
            let prefetchedAspectRatios = await ReaderImagePrefetcher.prefetch(
                requests: requests,
                imageLoader: imageLoader,
                imageCache: imageCache
            )
            guard !Task.isCancelled, imagePrefetchKey == prefetchKey else { return }
            pageLayout.record(prefetchedAspectRatios)
        }
    }

    private func cancelImagePrefetch() {
        imagePrefetchTask?.cancel()
        imagePrefetchTask = nil
        imagePrefetchKey = nil
    }

    private func imagePrefetchRequest(for index: Int) -> ReaderImagePrefetchRequest? {
        guard viewModel.pages.indices.contains(index),
              let url = viewModel.pages[index].media.imageURL,
              let pageID = readerPageID(for: index) else {
            return nil
        }

        guard let target = readerDecodeTarget() else { return nil }
        return ReaderImagePrefetchRequest(
            pageID: pageID,
            url: url,
            target: target,
            diagnosticContext: ImageDiagnosticContext(
                purpose: .readerPrefetch,
                url: url,
                pageStableID: pageID.backendPageID ?? pageID.imageURL.absoluteString
            )
        )
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

#if DEBUG
                Menu {
                    Toggle("显示识别框", isOn: $debugRecognizesText)
                    Button("识别并导出本章") {
                        startRecognitionReport()
                    }
                    .disabled(recognitionReportTask != nil)
                } label: {
                    Image(systemName: debugRecognizesText ? "text.viewfinder" : "viewfinder")
                        .font(.subheadline)
                }
                .accessibilityLabel("文字识别调试")
                .accessibilityIdentifier("reader.debugTextRecognition")
#endif

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
                } label: {
                    Image(systemName: viewModel.readerMode == .horizontal ? "arrow.up.arrow.down" : "arrow.left.arrow.right")
                    Text(viewModel.readerMode == .horizontal ? "滚动" : "翻页")
                }
                .accessibilityIdentifier("reader.toggleMode")

                Spacer()

                Button {
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

#if DEBUG
// MARK: - Recognition report (debug)

extension ComicReaderView {
    private func recognitionReportBadge(_ progress: (done: Int, total: Int)) -> some View {
        VStack {
            HStack(spacing: 10) {
                ProgressView()
                    .tint(.white)
                Text("识别本章 \(progress.done)/\(progress.total)")
                    .font(.subheadline.monospacedDigit())
                Button("取消") {
                    recognitionReportTask?.cancel()
                }
                .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(.top, viewModel.showToolbar ? 64 : 12)
            Spacer()
        }
    }

    /// Recognises every page of the current chapter, one at a time through the same queue as
    /// the overlay, and offers the result as a JSON file. A page that fails is recorded and the
    /// run continues; cancelling, or leaving the reader, stops it without exporting.
    private func startRecognitionReport() {
        guard recognitionReportTask == nil else { return }
        guard let episode = viewModel.currentEpisode,
              !viewModel.pages.isEmpty,
              let target = readerDecodeTarget() else {
            recognitionReportMessage = "页面尚未加载完成，请稍后再试。"
            return
        }

        let urls = viewModel.pages.map(\.media.imageURL)
        let loader = imageDataLoader
        let cache = imageCache
        let comicID = viewModel.comicId
        recognitionReportProgress = (0, urls.count)

        recognitionReportTask = Task {
            defer {
                recognitionReportTask = nil
                recognitionReportProgress = nil
            }
            var pages: [MangaRecognitionReport.Page] = []
            for (index, url) in urls.enumerated() {
                guard !Task.isCancelled else { return }
                pages.append(await Self.recognisePage(index: index, url: url, target: target, loader: loader, cache: cache))
                recognitionReportProgress = (index + 1, urls.count)
            }
            guard !Task.isCancelled else { return }

            let report = MangaRecognitionReport(
                textRecognizer: MangaPageTextExtractor().recognizerIdentifier,
                appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?",
                buildNumber: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?",
                deviceModel: Self.deviceModelIdentifier(),
                systemVersion: UIDevice.current.systemVersion,
                comicID: comicID,
                episodeOrder: episode.order,
                episodeTitle: episode.title,
                pages: pages
            )
            do {
                recognitionReportItem = DiagnosticsExportItem(url: try report.write())
            } catch {
                recognitionReportMessage = "写入报告失败：\(error.localizedDescription)"
            }
        }
    }

    private static func recognisePage(
        index: Int,
        url: URL?,
        target: ImageDecodeTarget,
        loader: any ImageDataLoading,
        cache: ImageCache
    ) async -> MangaRecognitionReport.Page {
        func failed(_ message: String) -> MangaRecognitionReport.Page {
            .init(index: index, pixelWidth: nil, pixelHeight: nil, milliseconds: nil, error: message, blocks: [])
        }
        guard let url else { return failed("页面没有图片地址") }
        do {
            // Same decode target and cache as the reader, so pages already on screen are not
            // downloaded or decoded again.
            let asset = try await cache.loadAsset(
                for: url,
                target: target,
                overscan: 2,
                priority: .utility,
                imageLoader: loader,
                diagnosticContext: ImageDiagnosticContext(purpose: .readerPrefetch, url: url)
            )
            guard let cgImage = asset.image.cgImage else { return failed("图片无法解码") }
            let result = try await MangaTextRecognitionQueue.shared.run {
                try MangaPageTextExtractor().timedExtract(from: cgImage)
            }
            return .init(
                index: index,
                pixelWidth: cgImage.width,
                pixelHeight: cgImage.height,
                milliseconds: result.milliseconds,
                error: nil,
                blocks: result.blocks
            )
        } catch is CancellationError {
            return failed("已取消")
        } catch {
            return failed(error.localizedDescription)
        }
    }

    /// The hardware identifier, e.g. iPhone17,1 — more useful than "iPhone" when comparing runs.
    private static func deviceModelIdentifier() -> String {
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { bytes in
            String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        }
    }
}
#endif

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

nonisolated struct ReaderImagePrefetchRequest: Equatable, Sendable {
    let pageID: ReaderPageID
    let url: URL
    let target: ImageDecodeTarget
    let diagnosticContext: ImageDiagnosticContext

    static func == (
        lhs: ReaderImagePrefetchRequest,
        rhs: ReaderImagePrefetchRequest
    ) -> Bool {
        lhs.pageID == rhs.pageID
            && lhs.url == rhs.url
            && lhs.target == rhs.target
    }
}

nonisolated private struct ReaderImagePrefetchResult: Sendable {
    let pageID: ReaderPageID
    let layoutAspectRatio: CGFloat
}

nonisolated enum ReaderImagePrefetcher {
    private static let maximumConcurrentRequests = 2

    static func prefetch(
        requests: [ReaderImagePrefetchRequest],
        imageLoader: any ImageDataLoading,
        imageCache: ImageCache
    ) async -> [ReaderPageID: CGFloat] {
        guard !requests.isEmpty else { return [:] }

        var nextIndex = 0
        var layoutAspectRatios: [ReaderPageID: CGFloat] = [:]
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
                    layoutAspectRatios[result.pageID] = result.layoutAspectRatio
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
        return layoutAspectRatios
    }

    private static func prefetch(
        request: ReaderImagePrefetchRequest,
        imageLoader: any ImageDataLoading,
        imageCache: ImageCache
    ) async -> ReaderImagePrefetchResult? {
        guard !Task.isCancelled else { return nil }

        do {
            let asset = try await imageCache.loadAsset(
                for: request.url,
                target: request.target,
                overscan: 2,
                priority: .utility,
                imageLoader: imageLoader,
                diagnosticContext: request.diagnosticContext
            )
            guard !Task.isCancelled else { return nil }
            return ReaderImagePrefetchResult(
                pageID: request.pageID,
                layoutAspectRatio: asset.layoutAspectRatio
            )
        } catch {
            // Prefetch failures should never block reading; the visible page loader still handles retries.
            return nil
        }
    }
}
