import SwiftUI
import UIKit

nonisolated private final class ImageCacheKey: NSObject {
    let value: String

    init(url: URL, targetSize: CGSize?) {
        value = "\(url.absoluteString)#\(ImageDecoding.cacheKeySuffix(for: targetSize))"
    }

    override var hash: Int {
        value.hashValue
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? ImageCacheKey else { return false }
        return value == other.value
    }
}

nonisolated final class ImageCache: @unchecked Sendable {
    static let shared = ImageCache()
    private let cache = NSCache<ImageCacheKey, UIImage>()

    private init() {
        cache.countLimit = 200
        cache.totalCostLimit = 100 * 1024 * 1024 // 100MB
    }

    func image(for url: URL, targetSize: CGSize? = nil) -> UIImage? {
        cache.object(forKey: ImageCacheKey(url: url, targetSize: targetSize))
    }

    func setImage(_ image: UIImage, for url: URL, targetSize: CGSize? = nil) {
        let key = ImageCacheKey(url: url, targetSize: targetSize)
        cache.setObject(image, forKey: key, cost: ImageDecoding.cacheCost(for: image))
    }
}

@MainActor
@Observable
final class CachedAsyncImageLoadingState {
    private(set) var image: UIImage?
    private var loadingIdentity: String?

    static func cacheIdentity(url: URL?, targetSize: CGSize?) -> String {
        guard let url else { return "nil" }
        return "\(url.absoluteString)#\(ImageDecoding.cacheKeySuffix(for: targetSize))"
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

        if let cached = imageCache.image(for: url, targetSize: targetSize) {
            image = cached
            onImageSize?(cached.size)
            loadingIdentity = nil
            return
        }

        image = nil

        do {
            let data = try await imageLoader.data(from: url)
            let requestedSize = targetSize
            let loaded = await Task.detached(priority: .userInitiated) {
                ImageDecoding.decodeImage(from: data, targetSize: requestedSize)
            }.value

            guard let loaded else {
                if loadingIdentity == identity {
                    image = nil
                    loadingIdentity = nil
                }
                return
            }
            guard loadingIdentity == identity else { return }
            imageCache.setImage(loaded, for: url, targetSize: targetSize)
            image = loaded
            onImageSize?(loaded.size)
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
