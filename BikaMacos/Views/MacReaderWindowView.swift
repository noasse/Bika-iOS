import AppKit
import SwiftUI

struct MacReaderWindowView: View {
    @State private var viewModel: MacReaderViewModel
    let onClose: (String) -> Void
    @State private var waterfallScrollRequest: Int?
    @State private var showPageInput = false
    @State private var pageInputText = ""
    @State private var imageSizes: [Int: CGSize] = [:]
    @State private var sampledIndices: [Int] = []
    @State private var sampledAspectRatios: [Int: CGFloat] = [:]
    @State private var estimatedAspectRatio: CGFloat?
    @State private var zoomedPageIndices: Set<Int> = []
    @State private var isWaterfallPageTrackingPaused = false
    @State private var isHorizontalResizing = false
    @State private var horizontalResizeGeneration = 0
    @State private var lastHorizontalReaderSize: CGSize = .zero
    @State private var imagePrefetchTask: Task<Void, Never>?
    @State private var imagePrefetchKey: String?
    @Environment(\.colorScheme) private var colorScheme
    private let keyValueStore: any KeyValueStore

    private let horizontalPageAnimation = Animation.interactiveSpring(response: 0.28, dampingFraction: 0.9, blendDuration: 0.06)

    init(
        request: MacReaderLaunchRequest,
        readingStore: MacReadingStore,
        keyValueStore: any KeyValueStore = AppDependencies.shared.keyValueStore,
        onClose: @escaping (String) -> Void = { _ in }
    ) {
        let initialViewModel = MacReaderViewModel(request: request, readingStore: readingStore)
        _viewModel = State(initialValue: initialViewModel)
        _waterfallScrollRequest = State(initialValue: Self.initialWaterfallScrollRequest(for: initialViewModel))
        self.keyValueStore = keyValueStore
        self.onClose = onClose
    }

    static func initialWaterfallScrollRequest(for viewModel: MacReaderViewModel) -> Int? {
        guard viewModel.readerMode == .waterfall, viewModel.currentPageIndex > 0 else { return nil }
        return viewModel.currentPageIndex
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            readerBody
            MacReaderKeyboardBridge(isEnabled: !showPageInput) {
                navigatePreviousPage()
            } onRight: {
                navigateNextPage()
            }
            .frame(width: 0, height: 0)
            MacReaderWindowSizeBridge(keyValueStore: keyValueStore)
                .frame(width: 0, height: 0)

            if !viewModel.pages.isEmpty {
                readerHUD
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
        }
        .navigationTitle(viewModel.request.comicTitle)
        .background(.black)
        .environment(\.colorScheme, .dark)
        .task {
            await viewModel.startIfNeeded()
            scheduleImagePrefetch(around: viewModel.currentPageIndex)
        }
        .onChange(of: viewModel.pages.count) { _, count in
            guard count > 0 else {
                cancelImagePrefetch()
                return
            }
            reconcileWaterfallScrollRequestWithLoadedPages()
            scheduleImagePrefetch(around: viewModel.currentPageIndex)
        }
        .onChange(of: viewModel.currentPageIndex) { _, pageIndex in
            scheduleImagePrefetch(around: pageIndex)
        }
        .onChange(of: viewModel.readerMode) { _, _ in
            zoomedPageIndices = []
            imagePrefetchKey = nil
            scheduleImagePrefetch(around: viewModel.currentPageIndex)
        }
        .onChange(of: viewModel.currentEpisodeIndex) { _, _ in
            resetImageLayoutState()
            waterfallScrollRequest = nil
            cancelImagePrefetch()
        }
        .onDisappear {
            viewModel.saveCurrentProgress()
            cancelImagePrefetch()
            onClose(viewModel.request.comicId)
        }
        .alert("跳转到页面", isPresented: $showPageInput) {
            TextField("页码 1-\(max(viewModel.pages.count, 1))", text: $pageInputText)
            Button("跳转") {
                if let page = Int(pageInputText) {
                    goToDisplayPage(page)
                }
            }
            Button("取消", role: .cancel) {}
        }
    }

    @ViewBuilder
    private var readerBody: some View {
        if viewModel.isLoading {
            VStack(spacing: 12) {
                ProgressView()
                    .tint(.white)
                Text("正在载入 \(viewModel.episodeDisplayText)")
                    .foregroundStyle(.white.opacity(0.72))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = viewModel.errorMessage {
            ContentUnavailableView("页面载入失败", systemImage: "exclamationmark.triangle", description: Text(error))
        } else if viewModel.pages.isEmpty {
            ContentUnavailableView("这一章没有页面", systemImage: "photo.on.rectangle")
        } else {
            switch viewModel.readerMode {
            case .waterfall:
                waterfallReader
            case .horizontal:
                horizontalReader
            }
        }
    }

    private var waterfallReader: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(viewModel.pages.enumerated()), id: \.offset) { index, page in
                            let imageWidth = pageViewportWidth(in: geometry.size)
                            MacZoomableImageView(url: page.media.imageURL, onImageLoaded: { size in
                                updateImageSize(size, for: index)
                            }, onZoomStateChanged: { isZoomed in
                                setZoomState(isZoomed, for: index)
                            }) {
                                Color.black
                                    .frame(minHeight: minHeight(for: index, width: imageWidth))
                            }
                                .frame(width: imageWidth)
                                .frame(minHeight: minHeight(for: index, width: imageWidth))
                                .id(index)
                                .contentShape(Rectangle())
                                .onAppear {
                                    registerSampleIndexIfNeeded(index)
                                    guard !isWaterfallPageTrackingPaused, waterfallScrollRequest == nil else { return }
                                    viewModel.setCurrentPage(index)
                                }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .background(.black)
                .onAppear {
                    scrollToRequestedWaterfallPage(with: proxy)
                }
                .onChange(of: waterfallScrollRequest) { _, _ in
                    scrollToRequestedWaterfallPage(with: proxy)
                }
                .onChange(of: viewModel.currentPageIndex) { _, pageIndex in
                    guard waterfallScrollRequest == pageIndex else { return }
                    scrollToRequestedWaterfallPage(with: proxy)
                }
            }
        }
    }

    private var horizontalReader: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black

                ZStack {
                    ForEach(horizontalVisiblePageIndices, id: \.self) { pageIndex in
                        horizontalPage(pageIndex, in: geometry.size)
                            .offset(x: horizontalOffset(for: pageIndex, in: geometry.size))
                    }
                }
                .clipped()
                .animation(isHorizontalResizing ? nil : horizontalPageAnimation, value: viewModel.currentPageIndex)

                if !isHorizontalResizing && !zoomedPageIndices.contains(viewModel.currentPageIndex) {
                    MacHorizontalScrollBridge(isEnabled: true) {
                        navigatePreviousPage()
                    } onNext: {
                        navigateNextPage()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                HStack {
                    readerPageButton(
                        title: "上一张",
                        systemImage: "chevron.left.circle.fill",
                        isDisabled: viewModel.currentPageIndex == 0,
                        action: navigatePreviousPage
                    )

                    Spacer()

                    readerPageButton(
                        title: "下一张",
                        systemImage: "chevron.right.circle.fill",
                        isDisabled: viewModel.currentPageIndex >= viewModel.pages.count - 1,
                        action: navigateNextPage
                    )
                }
                .padding(.horizontal, 18)
            }
            .onAppear {
                lastHorizontalReaderSize = geometry.size
            }
            .onChange(of: geometry.size) { _, newSize in
                guard hasMeaningfulSizeChange(newSize, from: lastHorizontalReaderSize) else { return }
                lastHorizontalReaderSize = newSize
                beginHorizontalResizeGuard()
            }
        }
    }

    private var horizontalVisiblePageIndices: [Int] {
        guard !viewModel.pages.isEmpty else { return [] }

        let current = viewModel.currentPageIndex
        return [current - 1, current, current + 1].filter { viewModel.pages.indices.contains($0) }
    }

    private func horizontalPage(_ pageIndex: Int, in size: CGSize) -> some View {
        MacZoomableImageView(url: viewModel.pages[pageIndex].media.imageURL, onImageLoaded: { imageSize in
            updateImageSize(imageSize, for: pageIndex)
        }, onZoomStateChanged: { isZoomed in
            setZoomState(isZoomed, for: pageIndex)
        }) {
            Color.black
        }
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
    }

    private func horizontalOffset(for pageIndex: Int, in size: CGSize) -> CGFloat {
        CGFloat(pageIndex - viewModel.currentPageIndex) * max(size.width, 1)
    }

    private func readerPageButton(
        title: String,
        systemImage: String,
        isDisabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 34, weight: .semibold))
                .frame(width: 46, height: 46)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white.opacity(isDisabled ? 0.2 : 0.74))
        .background(.black.opacity(isDisabled ? 0.12 : 0.34), in: Circle())
        .disabled(isDisabled)
        .help(title)
    }

    private var readerHUD: some View {
        ViewThatFits(in: .horizontal) {
            readerHUDControls

            ScrollView(.horizontal) {
                readerHUDControls
                    .padding(.horizontal, 1)
            }
            .scrollIndicators(.hidden)
            .frame(maxWidth: 360)
        }
        .font(.caption)
        .controlSize(.mini)
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.black.opacity(0.62), in: RoundedRectangle(cornerRadius: MacUI.cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: MacUI.cornerRadius)
                .stroke(.white.opacity(0.14))
        }
        .shadow(color: .black.opacity(0.32), radius: 14, y: 6)
        .padding(.bottom, 10)
    }

    private var readerHUDControls: some View {
        HStack(spacing: 9) {
            Picker("模式", selection: readerModeBinding) {
                ForEach(MacReaderMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 108)
            .tint(MacUI.accentPink)

            Button {
                pageInputText = "\(viewModel.currentPageIndex + 1)"
                showPageInput = true
            } label: {
                Text(viewModel.pageDisplayText)
                    .monospacedDigit()
                    .frame(minWidth: 54)
            }
            .buttonStyle(.plain)
            .foregroundStyle(MacUI.accentPink)
            .help("跳转到页面")

            Button {
                Task { await viewModel.previousEpisode() }
            } label: {
                Label("上一章", systemImage: "chevron.left.2")
            }
            .labelStyle(.iconOnly)
            .disabled(!viewModel.hasPreviousEpisode || viewModel.isLoading)
            .help("上一章")

            Button {
                Task { await viewModel.nextEpisode() }
            } label: {
                Label("下一章", systemImage: "chevron.right.2")
            }
            .labelStyle(.iconOnly)
            .disabled(!viewModel.hasNextEpisode || viewModel.isLoading)
            .help("下一章")
        }
    }

    private func pageViewportWidth(in size: CGSize) -> CGFloat {
        max(220, size.width)
    }

    private func setZoomState(_ isZoomed: Bool, for pageIndex: Int) {
        guard viewModel.pages.indices.contains(pageIndex) else { return }
        if isZoomed {
            zoomedPageIndices.insert(pageIndex)
        } else {
            zoomedPageIndices.remove(pageIndex)
        }
    }

    private func scrollToRequestedWaterfallPage(with proxy: ScrollViewProxy) {
        guard let pageIndex = waterfallScrollRequest else { return }
        guard viewModel.pages.indices.contains(pageIndex) else { return }
        isWaterfallPageTrackingPaused = true

        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.18)) {
                proxy.scrollTo(pageIndex, anchor: .top)
            }
            waterfallScrollRequest = nil
            resumeWaterfallPageTrackingSoon()
        }
    }

    private func reconcileWaterfallScrollRequestWithLoadedPages() {
        guard let pageIndex = waterfallScrollRequest else { return }
        guard !viewModel.pages.indices.contains(pageIndex) else { return }

        if viewModel.pages.indices.contains(viewModel.currentPageIndex) {
            waterfallScrollRequest = viewModel.currentPageIndex
        } else {
            waterfallScrollRequest = nil
        }
    }

    private func resumeWaterfallPageTrackingSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
            isWaterfallPageTrackingPaused = false
        }
    }

    private func hasMeaningfulSizeChange(_ newSize: CGSize, from oldSize: CGSize) -> Bool {
        guard oldSize != .zero else { return false }
        return abs(newSize.width - oldSize.width) > 1 || abs(newSize.height - oldSize.height) > 1
    }

    private func beginHorizontalResizeGuard() {
        horizontalResizeGeneration += 1
        let generation = horizontalResizeGeneration
        isHorizontalResizing = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            guard generation == horizontalResizeGeneration else { return }
            isHorizontalResizing = false
        }
    }

    private func minHeight(for index: Int, width: CGFloat) -> CGFloat {
        if let size = imageSizes[index], size.width > 0 {
            return width * (size.height / size.width)
        }

        if let ratio = estimatedAspectRatio {
            return width * ratio
        }

        return max(360, width * 1.45)
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
        zoomedPageIndices = []
    }

    private func isNearlyEqual(_ lhs: CGSize, _ rhs: CGSize) -> Bool {
        abs(lhs.width - rhs.width) < 1 && abs(lhs.height - rhs.height) < 1
    }

    private func scheduleImagePrefetch(around index: Int) {
        let pageCount = viewModel.pages.count
        guard pageCount > 0 else {
            cancelImagePrefetch()
            return
        }

        let clampedIndex = min(max(index, 0), pageCount - 1)
        let excludedIndices = imagePrefetchExcludedIndices(around: clampedIndex)
        let urls = MacReaderImagePrefetchPlan.indices(
            currentIndex: clampedIndex,
            pageCount: pageCount,
            lookBehind: 1,
            lookAhead: 4
        )
        .compactMap { pageIndex -> URL? in
            guard !excludedIndices.contains(pageIndex) else { return nil }
            guard viewModel.pages.indices.contains(pageIndex) else { return nil }
            return viewModel.pages[pageIndex].media.imageURL
        }

        let nextKey = urls.map(\.absoluteString).joined(separator: "|")
        guard nextKey != imagePrefetchKey else { return }
        imagePrefetchKey = nextKey

        imagePrefetchTask?.cancel()
        guard !urls.isEmpty else { return }

        imagePrefetchTask = Task(priority: .utility) {
            await MacReaderImagePrefetcher.prefetch(urls: urls, imageCache: .shared)
        }
    }

    private func imagePrefetchExcludedIndices(around index: Int) -> Set<Int> {
        switch viewModel.readerMode {
        case .horizontal:
            return Set(horizontalVisiblePageIndices)
        case .waterfall:
            return [index]
        }
    }

    private func cancelImagePrefetch() {
        imagePrefetchTask?.cancel()
        imagePrefetchTask = nil
        imagePrefetchKey = nil
    }

    private func goToDisplayPage(_ page: Int) {
        let oldPage = viewModel.currentPageIndex
        updatePageSelection {
            viewModel.goToPage(page)
        }
        if viewModel.readerMode == .waterfall, viewModel.currentPageIndex != oldPage {
            waterfallScrollRequest = viewModel.currentPageIndex
        }
    }

    private var readerModeBinding: Binding<MacReaderMode> {
        Binding {
            viewModel.readerMode
        } set: { mode in
            guard mode != viewModel.readerMode else { return }
            let currentPage = viewModel.currentPageIndex
            if mode == .waterfall {
                isWaterfallPageTrackingPaused = true
                waterfallScrollRequest = currentPage
            }
            viewModel.setReaderMode(mode)
        }
    }

    private func navigatePreviousPage() {
        let oldPage = viewModel.currentPageIndex
        updatePageSelection {
            viewModel.previousPage()
        }
        requestWaterfallScrollIfNeeded(from: oldPage)
    }

    private func navigateNextPage() {
        let oldPage = viewModel.currentPageIndex
        updatePageSelection {
            viewModel.nextPage()
        }
        requestWaterfallScrollIfNeeded(from: oldPage)
    }

    private func requestWaterfallScrollIfNeeded(from oldPage: Int) {
        guard viewModel.readerMode == .waterfall else { return }
        guard viewModel.currentPageIndex != oldPage else { return }
        waterfallScrollRequest = viewModel.currentPageIndex
    }

    private func updatePageSelection(_ update: () -> Void) {
        if viewModel.readerMode == .horizontal, !isHorizontalResizing {
            withAnimation(horizontalPageAnimation, update)
        } else {
            update()
        }
    }
}

nonisolated enum MacZoomableImageLayout {
    static let minimumMagnification: CGFloat = 1
    static let maximumMagnification: CGFloat = 4
    static let doubleClickMagnification: CGFloat = 2
    private static let zoomStateEpsilon: CGFloat = 0.01

    static func fittedImageFrame(imageSize: CGSize, viewportSize: CGSize) -> CGRect {
        let viewportWidth = max(viewportSize.width, 1)
        let viewportHeight = max(viewportSize.height, 1)
        guard imageSize.width > 0, imageSize.height > 0 else {
            return CGRect(origin: .zero, size: CGSize(width: viewportWidth, height: viewportHeight))
        }

        let imageHeight = viewportWidth * (imageSize.height / imageSize.width)
        return CGRect(
            x: 0,
            y: max((viewportHeight - imageHeight) / 2, 0),
            width: viewportWidth,
            height: imageHeight
        )
    }

    static func documentSize(imageFrame: CGRect, viewportSize: CGSize) -> CGSize {
        CGSize(
            width: max(max(viewportSize.width, 1), imageFrame.maxX),
            height: max(max(viewportSize.height, 1), imageFrame.maxY)
        )
    }

    static func zoomCenter(tapLocation: CGPoint, imageFrame: CGRect) -> CGPoint {
        guard !imageFrame.isEmpty else { return tapLocation }
        return CGPoint(
            x: min(max(tapLocation.x, imageFrame.minX), imageFrame.maxX),
            y: min(max(tapLocation.y, imageFrame.minY), imageFrame.maxY)
        )
    }

    static func isZoomed(_ magnification: CGFloat, minimumMagnification: CGFloat = minimumMagnification) -> Bool {
        magnification > minimumMagnification + zoomStateEpsilon
    }
}

private struct MacZoomableImageView<Placeholder: View>: View {
    let url: URL?
    var onImageLoaded: ((CGSize) -> Void)?
    var onZoomStateChanged: ((Bool) -> Void)?
    @ViewBuilder let placeholder: () -> Placeholder

    @State private var isLoaded = false

    init(
        url: URL?,
        onImageLoaded: ((CGSize) -> Void)? = nil,
        onZoomStateChanged: ((Bool) -> Void)? = nil,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.onImageLoaded = onImageLoaded
        self.onZoomStateChanged = onZoomStateChanged
        self.placeholder = placeholder
    }

    var body: some View {
        ZStack {
            if !isLoaded {
                placeholder()
            }

            MacZoomableImageRepresentable(
                url: url,
                onImageLoaded: { size in
                    isLoaded = true
                    onImageLoaded?(size)
                },
                onZoomStateChanged: onZoomStateChanged,
                onLoadStateChanged: { loaded in
                    isLoaded = loaded
                }
            )
        }
        .onChange(of: url) { _, _ in
            isLoaded = false
        }
    }
}

private struct MacZoomableImageRepresentable: NSViewRepresentable {
    let url: URL?
    var onImageLoaded: ((CGSize) -> Void)?
    var onZoomStateChanged: ((Bool) -> Void)?
    var onLoadStateChanged: ((Bool) -> Void)?

    func makeNSView(context: Context) -> MacZoomableImageContainerView {
        MacZoomableImageContainerView()
    }

    func updateNSView(_ nsView: MacZoomableImageContainerView, context: Context) {
        nsView.configure(
            url: url,
            onImageLoaded: onImageLoaded,
            onZoomStateChanged: onZoomStateChanged,
            onLoadStateChanged: onLoadStateChanged
        )
    }
}

private final class MacZoomableImageContainerView: NSView {
    private let scrollView = MacZoomableScrollView()
    private let canvasView = MacZoomableImageCanvasView()
    private let imageView = NSImageView()
    private let failureLabel = NSTextField(labelWithString: "图片载入失败")
    private var currentURL: URL?
    private var imageSize: CGSize?
    private var loadTask: Task<Void, Never>?
    private var onImageLoaded: ((CGSize) -> Void)?
    private var onZoomStateChanged: ((Bool) -> Void)?
    private var onLoadStateChanged: ((Bool) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureViews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        loadTask?.cancel()
    }

    override func layout() {
        super.layout()
        scrollView.frame = bounds
        failureLabel.frame = bounds
        layoutImageIfPossible()
    }

    func configure(
        url: URL?,
        onImageLoaded: ((CGSize) -> Void)?,
        onZoomStateChanged: ((Bool) -> Void)?,
        onLoadStateChanged: ((Bool) -> Void)?
    ) {
        self.onImageLoaded = onImageLoaded
        self.onZoomStateChanged = onZoomStateChanged
        self.onLoadStateChanged = onLoadStateChanged

        guard currentURL != url else { return }
        currentURL = url
        loadTask?.cancel()
        imageSize = nil
        imageView.image = nil
        failureLabel.isHidden = true
        scrollView.isHidden = true
        scrollView.magnification = scrollView.minMagnification
        DispatchQueue.main.async { [weak self] in
            self?.notifyZoomState()
        }

        guard let url else {
            failureLabel.isHidden = false
            return
        }

        loadTask = Task { [weak self] in
            do {
                let image = try await MacImageCache.shared.image(for: url)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard self?.currentURL == url else { return }
                    self?.show(image)
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard self?.currentURL == url else { return }
                    self?.showFailure()
                }
            }
        }
    }

    private func configureViews() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.allowsMagnification = true
        scrollView.minMagnification = MacZoomableImageLayout.minimumMagnification
        scrollView.maxMagnification = MacZoomableImageLayout.maximumMagnification
        scrollView.documentView = canvasView
        scrollView.isHidden = true
        scrollView.onMagnificationChanged = { [weak self] _ in
            self?.notifyZoomState()
        }

        canvasView.addSubview(imageView)
        canvasView.onDoubleClick = { [weak self] location in
            self?.toggleZoom(at: location)
        }

        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        imageView.wantsLayer = true
        imageView.layer?.backgroundColor = NSColor.clear.cgColor

        failureLabel.alignment = .center
        failureLabel.textColor = .secondaryLabelColor
        failureLabel.isHidden = true

        addSubview(scrollView)
        addSubview(failureLabel)
    }

    private func show(_ image: NSImage) {
        let loadedSize = image.size
        imageSize = loadedSize
        imageView.image = image
        failureLabel.isHidden = true
        scrollView.isHidden = false
        scrollView.magnification = scrollView.minMagnification
        needsLayout = true
        layoutSubtreeIfNeeded()
        onLoadStateChanged?(true)
        onImageLoaded?(loadedSize)
        notifyZoomState()
    }

    private func showFailure() {
        imageSize = nil
        imageView.image = nil
        scrollView.isHidden = true
        failureLabel.isHidden = false
        onLoadStateChanged?(false)
        notifyZoomState()
    }

    private func layoutImageIfPossible() {
        guard let imageSize else { return }
        let viewportSize = scrollView.contentView.bounds.size == .zero ? bounds.size : scrollView.contentView.bounds.size
        let imageFrame = MacZoomableImageLayout.fittedImageFrame(imageSize: imageSize, viewportSize: viewportSize)
        let documentSize = MacZoomableImageLayout.documentSize(imageFrame: imageFrame, viewportSize: viewportSize)
        canvasView.setFrameSize(documentSize)
        canvasView.imageFrame = imageFrame
        imageView.frame = imageFrame
    }

    private func toggleZoom(at tapLocation: CGPoint) {
        guard imageView.image != nil else { return }
        let zoomCenter = MacZoomableImageLayout.zoomCenter(tapLocation: tapLocation, imageFrame: canvasView.imageFrame)
        let targetMagnification: CGFloat
        if MacZoomableImageLayout.isZoomed(scrollView.magnification, minimumMagnification: scrollView.minMagnification) {
            targetMagnification = scrollView.minMagnification
        } else {
            targetMagnification = min(MacZoomableImageLayout.doubleClickMagnification, scrollView.maxMagnification)
        }

        scrollView.setMagnification(targetMagnification, centeredAt: zoomCenter)
        scrollView.notifyMagnificationChanged()
    }

    private func notifyZoomState() {
        onZoomStateChanged?(
            MacZoomableImageLayout.isZoomed(
                scrollView.magnification,
                minimumMagnification: scrollView.minMagnification
            )
        )
    }
}

private final class MacZoomableScrollView: NSScrollView {
    var onMagnificationChanged: ((CGFloat) -> Void)?

    override func scrollWheel(with event: NSEvent) {
        guard MacZoomableImageLayout.isZoomed(magnification, minimumMagnification: minMagnification) else {
            if let nextResponder {
                nextResponder.scrollWheel(with: event)
            } else {
                super.scrollWheel(with: event)
            }
            return
        }

        super.scrollWheel(with: event)
    }

    override func magnify(with event: NSEvent) {
        super.magnify(with: event)
        notifyMagnificationChanged()
    }

    func notifyMagnificationChanged() {
        onMagnificationChanged?(magnification)
    }
}

private final class MacZoomableImageCanvasView: NSView {
    var imageFrame: CGRect = .zero
    var onDoubleClick: ((CGPoint) -> Void)?

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        guard event.clickCount == 2 else {
            super.mouseDown(with: event)
            return
        }

        onDoubleClick?(convert(event.locationInWindow, from: nil))
    }
}

private struct MacReaderWindowSizeBridge: NSViewRepresentable {
    let keyValueStore: any KeyValueStore

    func makeNSView(context: Context) -> MacReaderWindowSizeView {
        MacReaderWindowSizeView(keyValueStore: keyValueStore)
    }

    func updateNSView(_ nsView: MacReaderWindowSizeView, context: Context) {
        nsView.keyValueStore = keyValueStore
        nsView.attachToCurrentWindowIfNeeded()
    }
}

private final class MacReaderWindowSizeView: NSView {
    var keyValueStore: any KeyValueStore
    private weak var observedWindow: NSWindow?
    private var notificationObservers: [NSObjectProtocol] = []

    init(keyValueStore: any KeyValueStore) {
        self.keyValueStore = keyValueStore
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        removeNotificationObservers()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        attachToCurrentWindowIfNeeded()
    }

    func attachToCurrentWindowIfNeeded() {
        guard observedWindow !== window else { return }
        removeNotificationObservers()
        observedWindow = window

        guard let window else { return }
        applyStoredContentSize(to: window)
        observe(window)
    }

    private func applyStoredContentSize(to window: NSWindow) {
        guard let storedSize = MacReaderWindowSizePersistence.restoredContentSize(from: keyValueStore) else { return }
        let fittedSize = MacReaderWindowSizePersistence.fittedContentSize(
            storedSize,
            visibleFrame: window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
        )
        window.setContentSize(fittedSize)
    }

    private func observe(_ window: NSWindow) {
        let notificationCenter = NotificationCenter.default
        notificationObservers = [
            notificationCenter.addObserver(
                forName: NSWindow.didResizeNotification,
                object: window,
                queue: .main
            ) { [weak self, weak window] _ in
                guard let self, let window else { return }
                self.saveContentSize(of: window)
            },
            notificationCenter.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { [weak self, weak window] _ in
                guard let self, let window else { return }
                self.saveContentSize(of: window)
            },
        ]
    }

    private func saveContentSize(of window: NSWindow) {
        let contentSize = window.contentView?.bounds.size ?? window.contentLayoutRect.size
        MacReaderWindowSizePersistence.saveContentSize(contentSize, to: keyValueStore)
    }

    private func removeNotificationObservers() {
        for observer in notificationObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        notificationObservers = []
    }
}

nonisolated enum MacReaderImagePrefetchPlan {
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

nonisolated enum MacReaderImagePrefetcher {
    private static let maximumConcurrentRequests = 2

    static func prefetch(urls: [URL], imageCache: MacImageCache) async {
        guard !urls.isEmpty else { return }

        var nextIndex = 0
        await withTaskGroup(of: Void.self) { group in
            let initialRequestCount = min(maximumConcurrentRequests, urls.count)
            for _ in 0..<initialRequestCount {
                let url = urls[nextIndex]
                nextIndex += 1
                group.addTask {
                    await prefetch(url: url, imageCache: imageCache)
                }
            }

            while await group.next() != nil {
                if Task.isCancelled {
                    group.cancelAll()
                    return
                }

                guard nextIndex < urls.count else { continue }
                let url = urls[nextIndex]
                nextIndex += 1
                group.addTask {
                    await prefetch(url: url, imageCache: imageCache)
                }
            }
        }
    }

    private static func prefetch(url: URL, imageCache: MacImageCache) async {
        guard !Task.isCancelled else { return }
        do {
            _ = try await imageCache.image(for: url)
        } catch {
            // Prefetch failures should never block the visible page loader.
        }
    }
}
