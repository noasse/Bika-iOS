import Foundation
import UIKit

nonisolated private final class ImageCacheKey: NSObject {
    let value: String

    init(url: URL, target: ImageDecodeTarget, overscan: CGFloat) {
        value = ImageCache.cacheIdentity(for: url, target: target, overscan: overscan)
    }

    override var hash: Int {
        value.hashValue
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? ImageCacheKey else { return false }
        return value == other.value
    }
}

nonisolated private final class ImageCacheEntry: NSObject {
    let asset: DecodedImageAsset

    init(asset: DecodedImageAsset) {
        self.asset = asset
    }
}

nonisolated final class ImageCache: @unchecked Sendable {
    static let shared = ImageCache()

    private let cache = NSCache<ImageCacheKey, ImageCacheEntry>()
    private let requestCoordinator = ImageAssetRequestCoordinator()

    init(countLimit: Int = 200, totalCostLimit: Int = 100 * 1024 * 1024) {
        cache.countLimit = countLimit
        cache.totalCostLimit = totalCostLimit
    }

    func image(for url: URL, targetSize: CGSize? = nil) -> UIImage? {
        asset(for: url, target: targetSize.map(ImageDecodeTarget.fit) ?? .full)?.image
    }

    func setImage(_ image: UIImage, for url: URL, targetSize: CGSize? = nil) {
        setAsset(
            DecodedImageAsset(image: image, displaySize: image.size),
            for: url,
            target: targetSize.map(ImageDecodeTarget.fit) ?? .full
        )
    }

    func asset(
        for url: URL,
        target: ImageDecodeTarget,
        overscan: CGFloat = 1
    ) -> DecodedImageAsset? {
        cache.object(
            forKey: ImageCacheKey(url: url, target: target, overscan: overscan)
        )?.asset
    }

    func setAsset(
        _ asset: DecodedImageAsset,
        for url: URL,
        target: ImageDecodeTarget,
        overscan: CGFloat = 1
    ) {
        let key = ImageCacheKey(url: url, target: target, overscan: overscan)
        cache.setObject(
            ImageCacheEntry(asset: asset),
            forKey: key,
            cost: ImageDecoding.cacheCost(for: asset.image)
        )
    }

    func removeAllImages() {
        cache.removeAllObjects()
    }

    func loadAsset(
        for url: URL,
        target: ImageDecodeTarget,
        overscan: CGFloat = 1,
        priority: TaskPriority = .userInitiated,
        imageLoader: any ImageDataLoading
    ) async throws -> DecodedImageAsset {
        if let cached = asset(for: url, target: target, overscan: overscan) {
            return cached
        }

        let identity = Self.cacheIdentity(for: url, target: target, overscan: overscan)
        return try await requestCoordinator.asset(for: identity) { [self] in
            if let cached = asset(for: url, target: target, overscan: overscan) {
                return cached
            }

            let data = try await imageLoader.data(from: url)
            let decoded = await Task.detached(priority: priority) {
                ImageDecoding.decodeAsset(
                    from: data,
                    target: target,
                    overscan: overscan
                )
            }.value
            guard let decoded else {
                throw URLError(.cannotDecodeContentData)
            }

            setAsset(decoded, for: url, target: target, overscan: overscan)
            return decoded
        }
    }

    static func cacheIdentity(
        for url: URL,
        target: ImageDecodeTarget,
        overscan: CGFloat = 1
    ) -> String {
        let resolvedOverscan = overscan.isFinite ? max(overscan, 1) : 1
        let overscanKey = Int((resolvedOverscan * 100).rounded())
        return "\(url.absoluteString)#\(target.cacheKey)#overscan-\(overscanKey)"
    }
}

private actor ImageAssetRequestCoordinator {
    private var inFlightTasks: [String: Task<DecodedImageAsset, Error>] = [:]

    func asset(
        for identity: String,
        operation: @escaping @Sendable () async throws -> DecodedImageAsset
    ) async throws -> DecodedImageAsset {
        if let task = inFlightTasks[identity] {
            return try await task.value
        }

        let task = Task { try await operation() }
        inFlightTasks[identity] = task
        defer { inFlightTasks[identity] = nil }
        return try await task.value
    }
}
