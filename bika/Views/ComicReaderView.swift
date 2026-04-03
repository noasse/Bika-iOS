import SwiftUI
import UIKit

// MARK: - Zoomable Image View (UIScrollView-backed)

struct ZoomableImageView: UIViewRepresentable {
    let url: URL?
    let imageLoader: any ImageDataLoading
    let imageCache: ImageCache
    var onImageSize: ((CGSize) -> Void)?
    var onSingleTap: ((CGPoint) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = 1.0
        scrollView.maximumZoomScale = 4.0
        scrollView.bouncesZoom = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.backgroundColor = UIColor(white: 0.1, alpha: 1)

        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        scrollView.addSubview(imageView)
        context.coordinator.imageView = imageView

        // Loading spinner
        let spinner = UIActivityIndicatorView(style: .medium)
        spinner.color = .gray
        spinner.startAnimating()
        spinner.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: scrollView.frameLayoutGuide.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: scrollView.frameLayoutGuide.centerYAnchor),
        ])
        context.coordinator.spinner = spinner

        // Double tap gesture
        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)

        // Single tap gesture (requires double tap to fail first)
        let singleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleSingleTap(_:)))
        singleTap.numberOfTapsRequired = 1
        singleTap.require(toFail: doubleTap)
        scrollView.addGestureRecognizer(singleTap)

        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.loadImageIfNeeded(in: scrollView)
        context.coordinator.relayoutIfNeeded(in: scrollView)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var parent: ZoomableImageView
        var imageView: UIImageView!
        var spinner: UIActivityIndicatorView?
        private var loadedURL: URL?
        private var loadTask: Task<Void, Never>?
        private var lastBoundsSize: CGSize = .zero

        init(parent: ZoomableImageView) {
            self.parent = parent
        }

        deinit {
            loadTask?.cancel()
        }

        // MARK: UIScrollViewDelegate

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            imageView
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            centerImageInScrollView(scrollView)
        }

        // MARK: Image Loading

        func loadImageIfNeeded(in scrollView: UIScrollView) {
            guard let url = parent.url, url != loadedURL else { return }
            let targetSize = imageTargetSize(in: scrollView)
            guard targetSize.width > 0, targetSize.height > 0 else { return }
            loadTask?.cancel()

            // Check cache first
            if let cached = parent.imageCache.image(for: url, targetSize: targetSize) {
                loadedURL = url
                displayImage(cached, in: scrollView)
                return
            }

            // Async load
            loadTask = Task { [weak self] in
                do {
                    let data = try await self?.parent.imageLoader.data(from: url)
                    guard let data else {
                        await MainActor.run { self?.loadedURL = nil }
                        return
                    }
                    let decodedImage = await Task.detached(priority: .userInitiated) {
                        ImageDecoding.decodeImage(
                            from: data,
                            targetSize: targetSize,
                            overscan: 2
                        )
                    }.value

                    guard !Task.isCancelled, let image = decodedImage else {
                        await MainActor.run { self?.loadedURL = nil }
                        return
                    }
                    self?.parent.imageCache.setImage(image, for: url, targetSize: targetSize)
                    await MainActor.run {
                        self?.loadedURL = url
                        self?.displayImage(image, in: scrollView)
                    }
                } catch {
                    await MainActor.run { self?.loadedURL = nil }
                }
            }
        }

        func relayoutIfNeeded(in scrollView: UIScrollView) {
            let boundsSize = scrollView.bounds.size
            guard boundsSize.width > 0, boundsSize.height > 0 else { return }
            guard imageView.image != nil else { return }
            guard boundsSize != lastBoundsSize else { return }
            layoutImage(in: scrollView)
        }

        private func displayImage(_ image: UIImage, in scrollView: UIScrollView) {
            spinner?.stopAnimating()
            spinner?.removeFromSuperview()
            spinner = nil

            imageView.image = image
            parent.onImageSize?(image.size)

            // Reset zoom
            scrollView.zoomScale = 1.0

            layoutImage(in: scrollView)
        }

        private func layoutImage(in scrollView: UIScrollView) {
            guard let image = imageView.image else { return }
            let boundsSize = scrollView.bounds.size
            guard boundsSize.width > 0, boundsSize.height > 0 else { return }
            lastBoundsSize = boundsSize

            // Fit image width to scroll view width (aspect fit)
            let imageSize = image.size
            let widthScale = boundsSize.width / imageSize.width
            let fitHeight = imageSize.height * widthScale
            imageView.frame = CGRect(x: 0, y: 0, width: boundsSize.width, height: fitHeight)
            scrollView.contentSize = imageView.frame.size

            centerImageInScrollView(scrollView)
        }

        private func centerImageInScrollView(_ scrollView: UIScrollView) {
            let boundsSize = scrollView.bounds.size
            var frameToCenter = imageView.frame

            // Center horizontally
            if frameToCenter.size.width < boundsSize.width {
                frameToCenter.origin.x = (boundsSize.width - frameToCenter.size.width) / 2
            } else {
                frameToCenter.origin.x = 0
            }

            // Center vertically
            if frameToCenter.size.height < boundsSize.height {
                frameToCenter.origin.y = (boundsSize.height - frameToCenter.size.height) / 2
            } else {
                frameToCenter.origin.y = 0
            }

            imageView.frame = frameToCenter
        }

        private func imageTargetSize(in scrollView: UIScrollView) -> CGSize {
            scrollView.bounds.size
        }

        // MARK: Tap Gestures

        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scrollView = gesture.view as? UIScrollView else { return }
            if scrollView.zoomScale > scrollView.minimumZoomScale {
                scrollView.setZoomScale(1.0, animated: true)
            } else {
                // Zoom to 2x centered on tap point
                let location = gesture.location(in: imageView)
                let zoomScale: CGFloat = 2.0
                let size = CGSize(
                    width: scrollView.bounds.width / zoomScale,
                    height: scrollView.bounds.height / zoomScale
                )
                let origin = CGPoint(
                    x: location.x - size.width / 2,
                    y: location.y - size.height / 2
                )
                scrollView.zoom(to: CGRect(origin: origin, size: size), animated: true)
            }
        }

        @objc func handleSingleTap(_ gesture: UITapGestureRecognizer) {
            guard let scrollView = gesture.view as? UIScrollView else { return }
            let location = gesture.location(in: scrollView.superview)
            parent.onSingleTap?(CGPoint(x: location.x, y: location.y))
        }
    }
}

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
        readingProgressManager: ReadingProgressManager = .shared,
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
        self.readingProgressManager = readingProgressManager
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
            } else if let errorMessage = viewModel.errorMessage, viewModel.pages.isEmpty {
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

            if viewModel.showToolbar {
                toolbarOverlay
            }
        }
        .statusBar(hidden: !viewModel.showToolbar)
        .task {
            viewModel.startLoadingPages()
            if isUITesting {
                viewModel.showToolbar = true
            }
        }
        .onDisappear {
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
            }
        }
        .onChange(of: viewModel.pages.count) { _, count in
            guard !hasJumpedToStart, count > 0 else { return }
            let restoredPage = min(startPageIndex, count - 1)
            hasJumpedToStart = true
            if restoredPage > 0 {
                scrollPosition = restoredPage
                currentPage = restoredPage
            } else {
                currentPage = 0
            }
        }
        .onChange(of: viewModel.currentEpisodeIndex) { _, _ in
            resetImageLayoutState()
        }
    }

    // MARK: - Tap to Toggle Toolbar

    private func handleTap(_ location: CGPoint) {
        let screenWidth = UIScreen.main.bounds.width
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
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                ForEach(Array(viewModel.pages.enumerated()), id: \.offset) { index, page in
                    ZoomableImageView(
                        url: page.media.imageURL,
                        imageLoader: imageDataLoader,
                        imageCache: imageCache,
                        onImageSize: { size in
                            updateImageSize(size, for: index)
                        },
                        onSingleTap: handleTap
                    )
                    .onAppear {
                        registerSampleIndexIfNeeded(index)
                    }
                    .frame(minHeight: minHeight(for: index))
                    .id(index)
                }
            }
            .scrollTargetLayout()
        }
        .scrollPosition(id: $scrollPosition)
        .scrollIndicators(.automatic)
        .ignoresSafeArea()
    }

    private func minHeight(for index: Int) -> CGFloat {
        let screenWidth = UIScreen.main.bounds.width
        if let size = imageSizes[index], size.width > 0 {
            return screenWidth * (size.height / size.width)
        }
        if let ratio = estimatedAspectRatio {
            return screenWidth * ratio
        }
        return 500
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
