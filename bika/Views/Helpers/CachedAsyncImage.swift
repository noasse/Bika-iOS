import SwiftUI
import UIKit

private final class ImageCacheKey: NSObject {
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

final class ImageCache: @unchecked Sendable {
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

struct CachedAsyncImage<Placeholder: View>: View {
    let url: URL?
    var targetSize: CGSize? = nil
    var imageLoader: any ImageDataLoading = AppDependencies.shared.imageDataLoader
    var imageCache: ImageCache = .shared
    var onImageSize: ((CGSize) -> Void)? = nil
    @ViewBuilder let placeholder: () -> Placeholder

    @State private var image: UIImage?
    @State private var isLoading = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
            } else {
                placeholder()
                    .task(id: cacheIdentity) { await loadImage() }
            }
        }
    }

    private var cacheIdentity: String {
        guard let url else { return "nil" }
        return "\(url.absoluteString)#\(ImageDecoding.cacheKeySuffix(for: targetSize))"
    }

    private func loadImage() async {
        guard let url, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        if let cached = imageCache.image(for: url, targetSize: targetSize) {
            image = cached
            onImageSize?(cached.size)
            return
        }

        do {
            let data = try await imageLoader.data(from: url)
            let requestedSize = targetSize
            let loaded = await Task.detached(priority: .userInitiated) {
                ImageDecoding.decodeImage(from: data, targetSize: requestedSize)
            }.value

            guard let loaded else { return }
            imageCache.setImage(loaded, for: url, targetSize: targetSize)
            image = loaded
            onImageSize?(loaded.size)
        } catch {
            // Auxiliary image requests can degrade to the placeholder without blocking the screen.
        }
    }
}
