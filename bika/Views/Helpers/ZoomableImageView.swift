import SwiftUI
import UIKit

@MainActor
final class ZoomingImageScrollView: UIScrollView {
    let readerImageView = UIImageView()
    var onBoundsSizeChange: ((CGSize) -> Void)?

    private let spinner = UIActivityIndicatorView(style: .medium)
    private var needsBaseImageLayout = true
    private var lastBaseLayoutBoundsSize = CGSize.zero
    private var layoutAspectRatio: CGFloat?
#if DEBUG
    private var textDebugOverlay: MangaTextDebugOverlayView?

    /// Shows what the translation pipeline found on this page. `nil` removes the overlay.
    func setTextDebugState(_ state: MangaTextDebugOverlayView.State?) {
        guard let state else {
            textDebugOverlay?.removeFromSuperview()
            textDebugOverlay = nil
            return
        }
        let overlay = textDebugOverlay ?? {
            let overlay = MangaTextDebugOverlayView(frame: readerImageView.bounds)
            // A subview of the image view, so it zooms and pans with the page.
            readerImageView.addSubview(overlay)
            textDebugOverlay = overlay
            return overlay
        }()
        overlay.imageSize = readerImageView.image?.size ?? .zero
        overlay.state = state
    }
#endif

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureSubviews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureSubviews()
    }

    func setImage(_ image: UIImage?) {
        let imageSize = image?.size ?? .zero
        let aspectRatio = imageSize.width > 0 && imageSize.height > 0
            ? imageSize.height / imageSize.width
            : 1
        setImage(image, layoutAspectRatio: aspectRatio)
    }

    func setImage(
        _ image: UIImage?,
        layoutAspectRatio: CGFloat
    ) {
        if readerImageView.image == nil, image == nil {
            return
        }
        if zoomScale != minimumZoomScale {
            setZoomScale(minimumZoomScale, animated: false)
        }
        readerImageView.image = image
        self.layoutAspectRatio = Self.validatedAspectRatio(layoutAspectRatio, image: image)
#if DEBUG
        // Results belong to the previous image.
        setTextDebugState(nil)
#endif
        readerImageView.frame = .zero
        contentSize = .zero
        needsBaseImageLayout = true
        setNeedsLayout()
    }

    func setLoading(_ isLoading: Bool) {
        if isLoading {
            spinner.startAnimating()
        } else {
            spinner.stopAnimating()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutImageForCurrentBounds()
        refreshPanInterception()
#if DEBUG
        // Zoom scales the image view with a transform, which leaves its bounds alone; only a
        // relayout changes them, and the overlay follows here.
        textDebugOverlay?.frame = readerImageView.bounds
#endif
        onBoundsSizeChange?(bounds.size)
    }

    /// Take pan gestures only when this page actually has somewhere to scroll.
    ///
    /// Every page sits in its own scroll view nested inside the reader's. While a page fits its
    /// row exactly — the normal state in the vertical reader — an enabled pan recognizer would
    /// swallow drags that belong to the chapter, so zooming one page used to strand the reader
    /// on it until the page was zoomed back out. Only the pan recognizer is touched: pinch and
    /// double-tap stay live, so a page can still be zoomed from rest, and panning comes back as
    /// soon as there is something to pan across.
    private func refreshPanInterception() {
        let scrollableWidth = contentSize.width - bounds.width
        let scrollableHeight = contentSize.height - bounds.height
        let hasSomewhereToScroll = scrollableWidth > 0.5 || scrollableHeight > 0.5
        panGestureRecognizer.isEnabled = hasSomewhereToScroll || zoomScale > minimumZoomScale
    }

    /// Called while zooming, when `contentSize` grows past the bounds and panning must come back.
    func refreshPanInterceptionAfterZoom() {
        refreshPanInterception()
    }

    func centerImage() {
        let boundsSize = bounds.size
        var frameToCenter = readerImageView.frame

        frameToCenter.origin.x = frameToCenter.width < boundsSize.width
            ? (boundsSize.width - frameToCenter.width) / 2
            : 0
        frameToCenter.origin.y = frameToCenter.height < boundsSize.height
            ? (boundsSize.height - frameToCenter.height) / 2
            : 0
        readerImageView.frame = frameToCenter
    }

    private func configureSubviews() {
        // Owned here rather than by the SwiftUI wrapper: pan interception is derived from the
        // zoom scale, so a scroll view that had not been configured yet would reason about
        // gestures from the wrong bounds.
        minimumZoomScale = 1
        maximumZoomScale = 4
        bouncesZoom = true
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        backgroundColor = UIColor(white: 0.1, alpha: 1)

        readerImageView.contentMode = .scaleAspectFit
        readerImageView.clipsToBounds = true
        addSubview(readerImageView)

        spinner.color = .gray
        spinner.translatesAutoresizingMaskIntoConstraints = false
        addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: frameLayoutGuide.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: frameLayoutGuide.centerYAnchor),
        ])
        spinner.startAnimating()
    }

    private func layoutImageForCurrentBounds() {
        guard readerImageView.image != nil else { return }
        let boundsSize = bounds.size
        guard boundsSize.width > 0, boundsSize.height > 0 else { return }

        let boundsChanged = boundsSize != lastBaseLayoutBoundsSize
        guard needsBaseImageLayout || boundsChanged || zoomScale != minimumZoomScale else {
            centerImage()
            return
        }

        if boundsChanged, zoomScale != minimumZoomScale {
            setZoomScale(minimumZoomScale, animated: false)
        }

        guard zoomScale == minimumZoomScale else {
            centerImage()
            return
        }

        guard let layoutAspectRatio else { return }
        let fitHeight = boundsSize.width * layoutAspectRatio
        readerImageView.frame = CGRect(x: 0, y: 0, width: boundsSize.width, height: fitHeight)
        contentSize = readerImageView.frame.size
        lastBaseLayoutBoundsSize = boundsSize
        needsBaseImageLayout = false
        // The page is always drawn at its natural ratio across the full width. While the row
        // height is still an estimate the image simply sits letterboxed or clipped inside it,
        // and settles when the real ratio lands. Hiding it until the two agreed — which is what
        // this used to do — turned any height that never converged into a permanently blank page.
        centerImage()
    }

    private static func validatedAspectRatio(
        _ aspectRatio: CGFloat,
        image: UIImage?
    ) -> CGFloat? {
        if aspectRatio.isFinite, aspectRatio > 0 {
            return aspectRatio
        }

        let imageSize = image?.size ?? .zero
        guard imageSize.width.isFinite,
              imageSize.height.isFinite,
              imageSize.width > 0,
              imageSize.height > 0 else {
            return nil
        }
        return imageSize.height / imageSize.width
    }
}

struct ZoomableImageView: UIViewRepresentable {
    let url: URL?
    let imageLoader: any ImageDataLoading
    let imageCache: ImageCache
    /// Supplied by the caller rather than derived from this view's bounds, so the prefetcher
    /// and the visible page decode — and cache — against exactly the same target.
    /// `nil` means the layout has not produced a usable size yet; nothing is loaded until it does.
    var decodeTarget: ImageDecodeTarget?
    var pageID: ReaderPageID? = nil
    var diagnosticPurpose: ImageDiagnosticPurpose = .readerVisible
    var diagnostics: any ImageDiagnosticsRecording = ImageDiagnosticsService.shared
    var onImageAspectRatio: ((CGFloat) -> Void)?
    var onSingleTap: ((CGPoint) -> Void)?
    /// Debug builds: run the translation pipeline's text recognition on this page and draw
    /// what it found. Ignored in release builds.
    var debugRecognizesText = false

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> ZoomingImageScrollView {
        let scrollView = ZoomingImageScrollView()
        scrollView.delegate = context.coordinator

        let doubleTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleDoubleTap(_:))
        )
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)

        let singleTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleSingleTap(_:))
        )
        singleTap.numberOfTapsRequired = 1
        singleTap.require(toFail: doubleTap)
        scrollView.addGestureRecognizer(singleTap)

        scrollView.onBoundsSizeChange = { [weak coordinator = context.coordinator, weak scrollView] _ in
            guard let scrollView else { return }
            coordinator?.loadImageIfNeeded(in: scrollView)
        }
        return scrollView
    }

    func updateUIView(_ scrollView: ZoomingImageScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.loadImageIfNeeded(in: scrollView)
#if DEBUG
        context.coordinator.refreshTextDebug(in: scrollView)
#endif
    }

    static func dismantleUIView(_ scrollView: ZoomingImageScrollView, coordinator: Coordinator) {
        coordinator.cancelLoading()
        scrollView.onBoundsSizeChange = nil
    }

    @MainActor
    final class Coordinator: NSObject, UIScrollViewDelegate {
        private struct DisplayIdentity: Equatable {
            let cacheIdentity: String
            let pageID: ReaderPageID?
        }

        var parent: ZoomableImageView
        private var loadedIdentity: DisplayIdentity?
        private var loadingIdentity: DisplayIdentity?
        private var loadTask: Task<Void, Never>?
#if DEBUG
        private var displayedAsset: DecodedImageAsset?
        private var recognisedIdentity: DisplayIdentity?
        private var recognitionTask: Task<Void, Never>?
#endif

        init(parent: ZoomableImageView) {
            self.parent = parent
        }

        deinit {
            loadTask?.cancel()
#if DEBUG
            recognitionTask?.cancel()
#endif
        }

#if DEBUG
        /// Runs text recognition on the page currently shown, once per page, when enabled.
        func refreshTextDebug(in scrollView: ZoomingImageScrollView) {
            guard parent.debugRecognizesText else {
                recognitionTask?.cancel()
                recognitionTask = nil
                recognisedIdentity = nil
                scrollView.setTextDebugState(nil)
                return
            }
            guard let identity = loadedIdentity,
                  let asset = displayedAsset,
                  identity != recognisedIdentity else { return }

            recognitionTask?.cancel()
            recognisedIdentity = identity
            scrollView.setTextDebugState(.recognising)

            recognitionTask = Task { [weak self, weak scrollView] in
                let outcome: Result<([MangaTextBlock], Int), Error>
                do {
                    // One page at a time, newest first, cancellable while waiting or running.
                    // The time reported is the work itself, not the wait for a turn.
                    let value = try await MangaTextRecognitionQueue.shared.run { () throws -> ([MangaTextBlock], Int) in
                        guard let cgImage = asset.image.cgImage else { throw CocoaError(.fileReadCorruptFile) }
                        let clock = ContinuousClock()
                        let start = clock.now
                        let blocks = try MangaPageTextExtractor().extract(from: cgImage)
                        let elapsed = start.duration(to: clock.now)
                        return (blocks, Int(elapsed.components.seconds * 1000)
                            + Int(elapsed.components.attoseconds / 1_000_000_000_000_000))
                    }
                    outcome = .success(value)
                } catch is CancellationError {
                    // The page went away or changed; whoever replaced it owns the overlay now.
                    return
                } catch {
                    outcome = .failure(error)
                }

                guard !Task.isCancelled, let self, let scrollView, self.recognisedIdentity == identity else { return }
                switch outcome {
                case .success(let (blocks, milliseconds)):
                    scrollView.setTextDebugState(.finished(blocks: blocks, milliseconds: milliseconds))
                case .failure(let error):
                    scrollView.setTextDebugState(.failed(error.localizedDescription))
                }
            }
        }
#endif

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            (scrollView as? ZoomingImageScrollView)?.readerImageView
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            guard let scrollView = scrollView as? ZoomingImageScrollView else { return }
            scrollView.centerImage()
            scrollView.refreshPanInterceptionAfterZoom()
        }

        func loadImageIfNeeded(in scrollView: ZoomingImageScrollView) {
            guard let url = parent.url else {
                cancelLoading()
                loadedIdentity = nil
                scrollView.setImage(nil)
                scrollView.setLoading(false)
                return
            }

            guard let target = parent.decodeTarget, target.isUsable else { return }
            let identity = DisplayIdentity(
                cacheIdentity: ImageCache.cacheIdentity(
                    for: url,
                    target: target,
                    overscan: 2
                ),
                pageID: parent.pageID
            )
            guard identity != loadedIdentity, identity != loadingIdentity else { return }

            loadTask?.cancel()
            loadedIdentity = nil
            loadingIdentity = identity
#if DEBUG
            recognitionTask?.cancel()
            recognitionTask = nil
            recognisedIdentity = nil
            displayedAsset = nil
#endif
            scrollView.setImage(nil)
            scrollView.setLoading(true)

            let imageLoader = parent.imageLoader
            let imageCache = parent.imageCache
            let diagnostics = parent.diagnostics
            let diagnosticContext = ImageDiagnosticContext(
                purpose: parent.diagnosticPurpose,
                url: url,
                pageStableID: parent.pageID.map {
                    $0.backendPageID ?? $0.imageURL.absoluteString
                }
            )
            loadTask = Task { [weak self, weak scrollView] in
                do {
                    let asset = try await imageCache.loadAsset(
                        for: url,
                        target: target,
                        overscan: 2,
                        priority: .userInitiated,
                        imageLoader: imageLoader,
                        diagnosticContext: diagnosticContext
                    )
                    try Task.checkCancellation()
                    guard let self,
                          let scrollView,
                          self.loadingIdentity == identity else {
                        diagnostics.record(
                            Self.displayEvent(
                                context: diagnosticContext,
                                action: .cancelled,
                                error: CancellationError()
                            )
                        )
                        return
                    }
                    self.display(asset, identity: identity, in: scrollView)
                    diagnostics.record(
                        Self.displayEvent(
                            context: diagnosticContext,
                            action: .succeeded
                        )
                    )
                } catch {
                    diagnostics.record(
                        Self.displayEvent(
                            context: diagnosticContext,
                            action: Self.isCancellation(error)
                                ? .cancelled
                                : .failed,
                            error: error
                        )
                    )
                    guard self?.loadingIdentity == identity else { return }
                    self?.loadingIdentity = nil
                    scrollView?.setLoading(false)
                }
            }
        }

        func cancelLoading() {
            loadTask?.cancel()
            loadTask = nil
            loadingIdentity = nil
#if DEBUG
            recognitionTask?.cancel()
            recognitionTask = nil
            // Otherwise a page kept by SwiftUI would count as recognised and never retry,
            // leaving "识别中…" on screen with nothing scheduled to replace it.
            recognisedIdentity = nil
#endif
        }

        private func display(
            _ asset: DecodedImageAsset,
            identity: DisplayIdentity,
            in scrollView: ZoomingImageScrollView
        ) {
            loadTask = nil
            loadingIdentity = nil
            loadedIdentity = identity
            scrollView.setLoading(false)
            scrollView.setImage(
                asset.image,
                layoutAspectRatio: asset.layoutAspectRatio
            )
            parent.onImageAspectRatio?(asset.layoutAspectRatio)
#if DEBUG
            displayedAsset = asset
            refreshTextDebug(in: scrollView)
#endif
        }

        private static func displayEvent(
            context: ImageDiagnosticContext,
            action: ImageDiagnosticAction,
            error: Error? = nil
        ) -> ImageDiagnosticEvent {
            ImageDiagnosticEvent(
                sequence: 0,
                timestamp: Date(),
                requestID: context.requestID,
                networkRequestID: nil,
                purpose: context.purpose,
                stage: .display,
                action: action,
                url: context.url,
                cacheIdentity: nil,
                httpStatus: nil,
                responseBytes: nil,
                durationMilliseconds: nil,
                retryAttempt: 0,
                decodeTarget: nil,
                sourcePixelSize: nil,
                decodedPixelSize: nil,
                error: error,
                metadata: ImageDiagnosticEventMetadata(
                    pageStableID: context.pageStableID,
                    contentType: nil,
                    wasCachedResponse: nil
                )
            )
        }

        private static func isCancellation(_ error: Error) -> Bool {
            error is CancellationError
                || (error as? URLError)?.code == .cancelled
        }

        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scrollView = gesture.view as? ZoomingImageScrollView else { return }
            if scrollView.zoomScale > scrollView.minimumZoomScale {
                scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
            } else {
                let location = gesture.location(in: scrollView.readerImageView)
                let zoomScale: CGFloat = 2
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

private extension ImageDecodeTarget {
    var isUsable: Bool {
        switch self {
        case .full:
            return true
        case .fit(let size), .fill(let size):
            return size.width.isFinite && size.height.isFinite && size.width > 0 && size.height > 0
        case .fitWidth(let width):
            return width.isFinite && width > 0
        }
    }
}
