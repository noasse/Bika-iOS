import SwiftUI
import UIKit

final class ImageCache: @unchecked Sendable {
    static let shared = ImageCache()
    private let cache = NSCache<NSURL, UIImage>()

    private init() {
        cache.countLimit = 200
        cache.totalCostLimit = 100 * 1024 * 1024 // 100MB
    }

    func image(for url: URL) -> UIImage? {
        cache.object(forKey: url as NSURL)
    }

    func setImage(_ image: UIImage, for url: URL) {
        cache.setObject(image, forKey: url as NSURL, cost: image.pngData()?.count ?? 0)
    }
}

struct CachedAsyncImage<Placeholder: View>: View {
    let url: URL?
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
                    .task(id: url) { await loadImage() }
            }
        }
    }

    private func loadImage() async {
        guard let url, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        if let cached = ImageCache.shared.image(for: url) {
            image = cached
            onImageSize?(cached.size)
            return
        }

        do {
            let data = try await AppDependencies.shared.imageDataLoader.data(from: url)
            if let loaded = UIImage(data: data) {
                ImageCache.shared.setImage(loaded, for: url)
                image = loaded
                onImageSize?(loaded.size)
            }
        } catch {
            // silently fail, placeholder remains
        }
    }
}
