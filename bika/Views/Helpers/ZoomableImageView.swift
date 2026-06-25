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

        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)

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

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            imageView
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            centerImageInScrollView(scrollView)
        }

        func loadImageIfNeeded(in scrollView: UIScrollView) {
            guard let url = parent.url, url != loadedURL else { return }
            let targetSize = imageTargetSize(in: scrollView)
            guard targetSize.width > 0, targetSize.height > 0 else { return }
            loadTask?.cancel()

            if let cached = parent.imageCache.image(for: url, targetSize: targetSize) {
                loadedURL = url
                displayImage(cached, in: scrollView)
                return
            }

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
            scrollView.zoomScale = 1.0
            layoutImage(in: scrollView)
        }

        private func layoutImage(in scrollView: UIScrollView) {
            guard let image = imageView.image else { return }
            let boundsSize = scrollView.bounds.size
            guard boundsSize.width > 0, boundsSize.height > 0 else { return }
            lastBoundsSize = boundsSize

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

            if frameToCenter.size.width < boundsSize.width {
                frameToCenter.origin.x = (boundsSize.width - frameToCenter.size.width) / 2
            } else {
                frameToCenter.origin.x = 0
            }

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

        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scrollView = gesture.view as? UIScrollView else { return }
            if scrollView.zoomScale > scrollView.minimumZoomScale {
                scrollView.setZoomScale(1.0, animated: true)
            } else {
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
