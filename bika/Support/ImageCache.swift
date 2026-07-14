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
    let id = UUID()
    let asset: DecodedImageAsset
    let cost: Int

    init(asset: DecodedImageAsset) {
        self.asset = asset
        cost = ImageDecoding.cacheCost(for: asset.image)
    }
}

nonisolated private final class ImageCacheCostTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var costsByEntryID: [UUID: Int] = [:]

    var totalCost: Int {
        lock.withLock { costsByEntryID.values.reduce(0, +) }
    }

    func insert(_ entry: ImageCacheEntry) {
        lock.withLock { costsByEntryID[entry.id] = entry.cost }
    }

    func remove(_ entry: ImageCacheEntry) {
        lock.withLock { _ = costsByEntryID.removeValue(forKey: entry.id) }
    }

    func removeAll() {
        lock.withLock { costsByEntryID.removeAll() }
    }
}

nonisolated private final class ImageCacheEvictionDelegate: NSObject, NSCacheDelegate {
    private let costTracker: ImageCacheCostTracker

    init(costTracker: ImageCacheCostTracker) {
        self.costTracker = costTracker
    }

    func cache(_ cache: NSCache<AnyObject, AnyObject>, willEvictObject obj: Any) {
        guard let entry = obj as? ImageCacheEntry else { return }
        costTracker.remove(entry)
    }
}

nonisolated final class ImageCache: @unchecked Sendable {
    static let shared = ImageCache()

    private let cache = NSCache<ImageCacheKey, ImageCacheEntry>()
    private let requestRegistry = CoalescingTaskRegistry<String, DecodedImageAsset>()
    private let mutationLock = NSLock()
    private let costTracker: ImageCacheCostTracker
    private let evictionDelegate: ImageCacheEvictionDelegate
    private var cacheGeneration = 0

    init(countLimit: Int = 200, totalCostLimit: Int = 100 * 1024 * 1024) {
        let costTracker = ImageCacheCostTracker()
        self.costTracker = costTracker
        evictionDelegate = ImageCacheEvictionDelegate(costTracker: costTracker)
        cache.countLimit = countLimit
        cache.totalCostLimit = totalCostLimit
        cache.delegate = evictionDelegate
    }

    var currentMemoryUsage: Int { costTracker.totalCost }

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
        _ = storeAsset(
            asset,
            for: url,
            target: target,
            overscan: overscan,
            expectedGeneration: nil
        )
    }

    func removeAllImages() async {
        await requestRegistry.cancelAll()
        mutationLock.withLock {
            cacheGeneration &+= 1
            cache.removeAllObjects()
            costTracker.removeAll()
        }
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
        let expectedGeneration = mutationLock.withLock { cacheGeneration }
        return try await requestRegistry.value(for: identity) { [self] in
            if let cached = asset(for: url, target: target, overscan: overscan) {
                return cached
            }

            let data = try await imageLoader.data(from: url)
            try Task.checkCancellation()
            let decodeTask = Task.detached(priority: priority) { () throws -> DecodedImageAsset in
                try Task.checkCancellation()
                guard let decoded = ImageDecoding.decodeAsset(
                    from: data,
                    target: target,
                    overscan: overscan
                ) else {
                    throw URLError(.cannotDecodeContentData)
                }
                try Task.checkCancellation()
                return decoded
            }
            let decoded = try await withTaskCancellationHandler {
                try await decodeTask.value
            } onCancel: {
                decodeTask.cancel()
            }

            try Task.checkCancellation()
            guard storeAsset(
                decoded,
                for: url,
                target: target,
                overscan: overscan,
                expectedGeneration: expectedGeneration
            ) else {
                throw CancellationError()
            }
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

    private func storeAsset(
        _ asset: DecodedImageAsset,
        for url: URL,
        target: ImageDecodeTarget,
        overscan: CGFloat,
        expectedGeneration: Int?
    ) -> Bool {
        let key = ImageCacheKey(url: url, target: target, overscan: overscan)
        let entry = ImageCacheEntry(asset: asset)
        return mutationLock.withLock {
            if let expectedGeneration,
               expectedGeneration != cacheGeneration {
                return false
            }
            if let replacedEntry = cache.object(forKey: key) {
                costTracker.remove(replacedEntry)
            }
            costTracker.insert(entry)
            cache.setObject(entry, forKey: key, cost: entry.cost)
            return true
        }
    }
}
