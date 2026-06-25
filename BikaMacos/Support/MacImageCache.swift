import AppKit
import SwiftUI

final class MacImageCache: @unchecked Sendable {
    static let shared = MacImageCache()

    private let cache = NSCache<NSURL, NSImage>()
    private let session: URLSession
    private let memoryLimit = 128 * 1024 * 1024

    init(session: URLSession = .shared) {
        self.session = session
        cache.countLimit = 120
        cache.totalCostLimit = memoryLimit
    }

    func image(for url: URL) async throws -> NSImage {
        if let cached = cache.object(forKey: url as NSURL) {
            return cached
        }

        let (data, _) = try await session.data(from: url)
        guard let image = NSImage(data: data) else {
            throw URLError(.cannotDecodeContentData)
        }
        cache.setObject(image, forKey: url as NSURL, cost: estimatedCost(for: image, data: data))
        return image
    }

    private func estimatedCost(for image: NSImage, data: Data) -> Int {
        image.representations.reduce(data.count) { currentCost, representation in
            guard let bitmap = representation as? NSBitmapImageRep else { return currentCost }
            return max(currentCost, bitmap.bytesPerRow * bitmap.pixelsHigh)
        }
    }
}

struct MacCachedAsyncImage<Placeholder: View>: View {
    let url: URL?
    var contentMode: ContentMode = .fit
    var onImageLoaded: ((CGSize) -> Void)?
    @ViewBuilder let placeholder: () -> Placeholder

    @State private var image: NSImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                placeholder()
                    .overlay {
                        if failed {
                            Image(systemName: "photo")
                                .foregroundStyle(.secondary)
                        }
                    }
            }
        }
        .task(id: url) {
            image = nil
            failed = false
            guard let url else {
                failed = true
                return
            }

            do {
                let loadedImage = try await MacImageCache.shared.image(for: url)
                image = loadedImage
                onImageLoaded?(loadedImage.size)
            } catch {
                failed = true
            }
        }
    }
}

extension MacCachedAsyncImage where Placeholder == AnyView {
    init(url: URL?, contentMode: ContentMode = .fit, onImageLoaded: ((CGSize) -> Void)? = nil) {
        self.url = url
        self.contentMode = contentMode
        self.onImageLoaded = onImageLoaded
        self.placeholder = {
            AnyView(
                RoundedRectangle(cornerRadius: 6)
                    .fill(.quaternary)
            )
        }
    }
}
