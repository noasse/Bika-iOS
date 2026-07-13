import SwiftUI
import UIKit

@MainActor
@Observable
final class CachedAsyncImageLoadingState {
    private(set) var image: UIImage?
    private var loadingIdentity: String?

    static func cacheIdentity(url: URL?, targetSize: CGSize?) -> String {
        guard let url else { return "nil" }
        let target = targetSize.map(ImageDecodeTarget.fit) ?? .full
        return ImageCache.cacheIdentity(for: url, target: target)
    }

    func load(
        url: URL?,
        targetSize: CGSize?,
        imageLoader: any ImageDataLoading,
        imageCache: ImageCache,
        onImageSize: ((CGSize) -> Void)?
    ) async {
        let identity = Self.cacheIdentity(url: url, targetSize: targetSize)
        loadingIdentity = identity

        guard let url else {
            image = nil
            loadingIdentity = nil
            return
        }

        let target = targetSize.map(ImageDecodeTarget.fit) ?? .full
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
}

struct CachedAsyncImage<Placeholder: View>: View {
    let url: URL?
    var targetSize: CGSize? = nil
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
            } else {
                placeholder()
            }
        }
        .task(id: cacheIdentity) { await loadImage(for: cacheIdentity) }
    }

    private var cacheIdentity: String {
        CachedAsyncImageLoadingState.cacheIdentity(url: url, targetSize: targetSize)
    }

    private func loadImage(for _: String) async {
        await loadingState.load(
            url: url,
            targetSize: targetSize,
            imageLoader: imageLoader,
            imageCache: imageCache,
            onImageSize: onImageSize
        )
    }
}
