import SwiftUI
import UIKit

@MainActor
@Observable
final class CachedAsyncImageLoadingState {
    private(set) var image: UIImage?
    private var loadingIdentity: String?

    static func cacheIdentity(
        url: URL?,
        targetSize: CGSize?,
        contentMode: ContentMode = .fit
    ) -> String {
        guard let url else { return "nil" }
        let target = decodeTarget(targetSize: targetSize, contentMode: contentMode)
        return ImageCache.cacheIdentity(for: url, target: target)
    }

    func load(
        url: URL?,
        targetSize: CGSize?,
        contentMode: ContentMode = .fit,
        imageLoader: any ImageDataLoading,
        imageCache: ImageCache,
        onImageSize: ((CGSize) -> Void)?
    ) async {
        let identity = Self.cacheIdentity(
            url: url,
            targetSize: targetSize,
            contentMode: contentMode
        )
        loadingIdentity = identity

        guard let url else {
            image = nil
            loadingIdentity = nil
            return
        }

        let target = Self.decodeTarget(
            targetSize: targetSize,
            contentMode: contentMode
        )
        if let cached = imageCache.asset(for: url, target: target) {
            image = cached.image
            onImageSize?(cached.displaySize)
            loadingIdentity = nil
            return
        }

        image = nil

        do {
            let loaded = try await imageCache.loadAsset(
                for: url,
                target: target,
                imageLoader: imageLoader
            )
            guard loadingIdentity == identity else { return }
            image = loaded.image
            onImageSize?(loaded.displaySize)
            loadingIdentity = nil
        } catch {
            guard loadingIdentity == identity else { return }
            image = nil
            loadingIdentity = nil
            // Auxiliary image requests can degrade to the placeholder without blocking the screen.
        }
    }

    private static func decodeTarget(
        targetSize: CGSize?,
        contentMode: ContentMode
    ) -> ImageDecodeTarget {
        guard let targetSize else { return .full }
        switch contentMode {
        case .fill:
            return .fill(targetSize)
        case .fit:
            return .fit(targetSize)
        @unknown default:
            return .fit(targetSize)
        }
    }
}

struct CachedAsyncImage<Placeholder: View>: View {
    let url: URL?
    var targetSize: CGSize? = nil
    var contentMode: ContentMode = .fit
    var imageLoader: any ImageDataLoading = AppDependencies.shared.imageDataLoader
    var imageCache: ImageCache = .shared
    var onImageSize: ((CGSize) -> Void)? = nil
    @ViewBuilder let placeholder: () -> Placeholder

    @State private var loadingState = CachedAsyncImageLoadingState()

    var body: some View {
        ZStack {
            if let image = loadingState.image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                placeholder()
            }
        }
        .task(id: cacheIdentity) { await loadImage(for: cacheIdentity) }
    }

    private var cacheIdentity: String {
        CachedAsyncImageLoadingState.cacheIdentity(
            url: url,
            targetSize: targetSize,
            contentMode: contentMode
        )
    }

    private func loadImage(for _: String) async {
        await loadingState.load(
            url: url,
            targetSize: targetSize,
            contentMode: contentMode,
            imageLoader: imageLoader,
            imageCache: imageCache,
            onImageSize: onImageSize
        )
    }
}
