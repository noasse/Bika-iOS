import SwiftUI
import UIKit

nonisolated enum ZoomableImageSizing: Equatable, Sendable {
    case viewport
    case fitWidth(CGFloat)
}

@MainActor
final class ZoomingImageScrollView: UIScrollView {
    let readerImageView = UIImageView()
    var onBoundsSizeChange: ((CGSize) -> Void)?

    private let spinner = UIActivityIndicatorView(style: .medium)
    private var needsBaseImageLayout = true
    private var lastBaseLayoutBoundsSize = CGSize.zero
    private var layoutAspectRatio: CGFloat?
    private var waitsForFitWidthBounds = false

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
        setImage(
            image,
            layoutAspectRatio: aspectRatio,
            waitsForFitWidthBounds: false
        )
    }

    func setImage(
        _ image: UIImage?,
        layoutAspectRatio: CGFloat,
        waitsForFitWidthBounds: Bool
    ) {
        if readerImageView.image == nil, image == nil {
            return
        }
        if zoomScale != minimumZoomScale {
            setZoomScale(minimumZoomScale, animated: false)
        }
        readerImageView.image = image
        self.layoutAspectRatio = Self.validatedAspectRatio(layoutAspectRatio, image: image)
        self.waitsForFitWidthBounds = waitsForFitWidthBounds
        readerImageView.isHidden = image != nil && waitsForFitWidthBounds
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
        onBoundsSizeChange?(bounds.size)
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
        readerImageView.isHidden = waitsForFitWidthBounds
            && abs(boundsSize.height - fitHeight) >= 1
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
    var sizing: ZoomableImageSizing = .viewport
    var pageID: ReaderPageID? = nil
    var diagnosticPurpose: ImageDiagnosticPurpose = .readerVisible
    var diagnostics: any ImageDiagnosticsRecording = ImageDiagnosticsService.shared
    var onImageAspectRatio: ((CGFloat) -> Void)?
    var onSingleTap: ((CGPoint) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> ZoomingImageScrollView {
        let scrollView = ZoomingImageScrollView()
        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 4
        scrollView.bouncesZoom = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.backgroundColor = UIColor(white: 0.1, alpha: 1)

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

        init(parent: ZoomableImageView) {
            self.parent = parent
        }

        deinit {
            loadTask?.cancel()
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            (scrollView as? ZoomingImageScrollView)?.readerImageView
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            (scrollView as? ZoomingImageScrollView)?.centerImage()
        }

        func loadImageIfNeeded(in scrollView: ZoomingImageScrollView) {
            guard let url = parent.url else {
                cancelLoading()
                loadedIdentity = nil
                scrollView.setImage(nil)
                scrollView.setLoading(false)
                return
            }

            let target = decodeTarget(in: scrollView)
            guard target.isUsable else { return }
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
                layoutAspectRatio: asset.layoutAspectRatio,
                waitsForFitWidthBounds: parent.sizing.isFitWidth
            )
            parent.onImageAspectRatio?(asset.layoutAspectRatio)
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

        private func decodeTarget(in scrollView: ZoomingImageScrollView) -> ImageDecodeTarget {
            switch parent.sizing {
            case .viewport:
                return .fit(scrollView.bounds.size)
            case .fitWidth(let width):
                return .fitWidth(width)
            }
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

private extension ZoomableImageSizing {
    var isFitWidth: Bool {
        if case .fitWidth = self {
            return true
        }
        return false
    }
}
