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
    let url: URL
    let cacheIdentity: String
    let diagnosticContext: ImageDiagnosticContext
    let networkRequestID: UUID?

    init(
        asset: DecodedImageAsset,
        url: URL,
        cacheIdentity: String,
        diagnosticContext: ImageDiagnosticContext,
        networkRequestID: UUID?
    ) {
        self.asset = asset
        self.url = url
        self.cacheIdentity = cacheIdentity
        self.diagnosticContext = diagnosticContext
        self.networkRequestID = networkRequestID
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
    private let diagnostics: any ImageDiagnosticsRecording

    init(
        costTracker: ImageCacheCostTracker,
        diagnostics: any ImageDiagnosticsRecording
    ) {
        self.costTracker = costTracker
        self.diagnostics = diagnostics
    }

    func cache(_ cache: NSCache<AnyObject, AnyObject>, willEvictObject obj: Any) {
        guard let entry = obj as? ImageCacheEntry else { return }
        costTracker.remove(entry)
        diagnostics.record(
            ImageCache.makeEvent(
                context: entry.diagnosticContext,
                networkRequestID: entry.networkRequestID,
                stage: .decodedCache,
                action: .evicted,
                cacheIdentity: entry.cacheIdentity
            )
        )
    }
}

nonisolated private struct ImageAssetLoadResult: @unchecked Sendable {
    let asset: DecodedImageAsset
    let networkRequestID: UUID?
}

nonisolated final class ImageCache: @unchecked Sendable {
    static let shared = ImageCache()

    private let cache = NSCache<ImageCacheKey, ImageCacheEntry>()
    private let requestRegistry = CoalescingTaskRegistry<String, ImageAssetLoadResult>()
    private let mutationLock = NSLock()
    private let costTracker: ImageCacheCostTracker
    private let evictionDelegate: ImageCacheEvictionDelegate
    private let diagnostics: any ImageDiagnosticsRecording
    private var cacheGeneration = 0

    init(
        countLimit: Int = 200,
        totalCostLimit: Int = 100 * 1024 * 1024,
        diagnostics: any ImageDiagnosticsRecording = ImageDiagnosticsService.shared
    ) {
        let costTracker = ImageCacheCostTracker()
        self.costTracker = costTracker
        self.diagnostics = diagnostics
        evictionDelegate = ImageCacheEvictionDelegate(
            costTracker: costTracker,
            diagnostics: diagnostics
        )
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
        let context = ImageDiagnosticContext(
            purpose: .unspecified,
            url: url
        )
        _ = storeAsset(
            asset,
            for: url,
            target: target,
            overscan: overscan,
            expectedGeneration: nil,
            diagnosticContext: context,
            networkRequestID: nil
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
        try await loadAsset(
            for: url,
            target: target,
            overscan: overscan,
            priority: priority,
            imageLoader: imageLoader,
            diagnosticContext: ImageDiagnosticContext(
                purpose: .unspecified,
                url: url
            )
        )
    }

    func loadAsset(
        for url: URL,
        target: ImageDecodeTarget,
        overscan: CGFloat = 1,
        priority: TaskPriority = .userInitiated,
        imageLoader: any ImageDataLoading,
        diagnosticContext: ImageDiagnosticContext
    ) async throws -> DecodedImageAsset {
        // Snap once, up front, so the cache key, the decoded pixel size and the diagnostics
        // all describe the same target. Callers measuring the same area through different
        // geometry sources must land on one cache entry, not two.
        let target = target.bucketed
        let identity = Self.cacheIdentity(
            for: url,
            target: target,
            overscan: overscan
        )
        diagnostics.record(
            Self.makeEvent(
                context: diagnosticContext,
                stage: .load,
                action: .started,
                cacheIdentity: identity,
                decodeTarget: target.cacheKey
            )
        )
        if let cached = asset(for: url, target: target, overscan: overscan) {
            diagnostics.record(
                Self.makeEvent(
                    context: diagnosticContext,
                    stage: .decodedCache,
                    action: .hit,
                    cacheIdentity: identity,
                    decodeTarget: target.cacheKey,
                    sourcePixelSize: ImageDiagnosticSize(cached.displaySize),
                    decodedPixelSize: Self.decodedPixelSize(cached.image)
                )
            )
            diagnostics.record(
                Self.makeEvent(
                    context: diagnosticContext,
                    stage: .load,
                    action: .succeeded,
                    cacheIdentity: identity,
                    decodeTarget: target.cacheKey
                )
            )
            return cached
        }

        diagnostics.record(
            Self.makeEvent(
                context: diagnosticContext,
                stage: .decodedCache,
                action: .missed,
                cacheIdentity: identity,
                decodeTarget: target.cacheKey
            )
        )
        let expectedGeneration = mutationLock.withLock { cacheGeneration }
        do {
            let result = try await requestRegistry.value(
                for: identity,
                onRegistration: { [diagnostics] registration in
                    diagnostics.record(
                        Self.makeEvent(
                            context: diagnosticContext,
                            stage: .coalescing,
                            action: registration.joinedExistingOperation
                                ? .joined
                                : .started,
                            cacheIdentity: identity,
                            decodeTarget: target.cacheKey
                        )
                    )
                },
                operation: { [self] _ in
                    if let cached = asset(
                        for: url,
                        target: target,
                        overscan: overscan
                    ) {
                        diagnostics.record(
                            Self.makeEvent(
                                context: diagnosticContext,
                                stage: .decodedCache,
                                action: .hit,
                                cacheIdentity: identity,
                                decodeTarget: target.cacheKey,
                                sourcePixelSize: ImageDiagnosticSize(cached.displaySize),
                                decodedPixelSize: Self.decodedPixelSize(cached.image)
                            )
                        )
                        return ImageAssetLoadResult(
                            asset: cached,
                            networkRequestID: nil
                        )
                    }

                    var decodeAttempt = 0
                    while true {
                        let loaded = try await imageLoader.loadResult(
                            from: url,
                            diagnosticContext: diagnosticContext
                        )
                        try Task.checkCancellation()
                        let clock = ContinuousClock()
                        let startedAt = clock.now
                        diagnostics.record(
                            Self.makeEvent(
                                context: diagnosticContext,
                                networkRequestID: loaded.networkRequestID,
                                stage: .decode,
                                action: .started,
                                cacheIdentity: identity,
                                retryAttempt: decodeAttempt,
                                decodeTarget: target.cacheKey
                            )
                        )

                        do {
                            let decodeTask = Task.detached(
                                priority: priority
                            ) { () throws -> DecodedImageAsset in
                                try Task.checkCancellation()
                                guard let decoded = ImageDecoding.decodeAsset(
                                    from: loaded.data,
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
                            diagnostics.record(
                                Self.makeEvent(
                                    context: diagnosticContext,
                                    networkRequestID: loaded.networkRequestID,
                                    stage: .decode,
                                    action: .succeeded,
                                    cacheIdentity: identity,
                                    durationMilliseconds: Self.milliseconds(
                                        startedAt.duration(to: clock.now)
                                    ),
                                    retryAttempt: decodeAttempt,
                                    decodeTarget: target.cacheKey,
                                    sourcePixelSize: ImageDiagnosticSize(
                                        decoded.displaySize
                                    ),
                                    decodedPixelSize: Self.decodedPixelSize(
                                        decoded.image
                                    )
                                )
                            )
                            guard storeAsset(
                                decoded,
                                for: url,
                                target: target,
                                overscan: overscan,
                                expectedGeneration: expectedGeneration,
                                diagnosticContext: diagnosticContext,
                                networkRequestID: loaded.networkRequestID
                            ) else {
                                throw CancellationError()
                            }
                            return ImageAssetLoadResult(
                                asset: decoded,
                                networkRequestID: loaded.networkRequestID
                            )
                        } catch {
                            let action: ImageDiagnosticAction = Self.isCancellation(
                                error
                            ) ? .cancelled : .failed
                            diagnostics.record(
                                Self.makeEvent(
                                    context: diagnosticContext,
                                    networkRequestID: loaded.networkRequestID,
                                    stage: .decode,
                                    action: action,
                                    cacheIdentity: identity,
                                    durationMilliseconds: Self.milliseconds(
                                        startedAt.duration(to: clock.now)
                                    ),
                                    retryAttempt: decodeAttempt,
                                    decodeTarget: target.cacheKey,
                                    error: error
                                )
                            )
                            if let urlError = error as? URLError,
                               urlError.code == .cannotDecodeContentData,
                               decodeAttempt == 0 {
                                decodeAttempt += 1
                                imageLoader.invalidateCachedData(
                                    for: url,
                                    diagnosticContext: diagnosticContext
                                )
                                continue
                            }
                            throw error
                        }
                    }
                }
            )
            diagnostics.record(
                Self.makeEvent(
                    context: diagnosticContext,
                    networkRequestID: result.networkRequestID,
                    stage: .load,
                    action: .succeeded,
                    cacheIdentity: identity,
                    decodeTarget: target.cacheKey
                )
            )
            return result.asset
        } catch {
            diagnostics.record(
                Self.makeEvent(
                    context: diagnosticContext,
                    stage: .load,
                    action: Self.isCancellation(error) ? .cancelled : .failed,
                    cacheIdentity: identity,
                    decodeTarget: target.cacheKey,
                    error: error
                )
            )
            throw error
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
        expectedGeneration: Int?,
        diagnosticContext: ImageDiagnosticContext,
        networkRequestID: UUID?
    ) -> Bool {
        let key = ImageCacheKey(url: url, target: target, overscan: overscan)
        let identity = Self.cacheIdentity(
            for: url,
            target: target,
            overscan: overscan
        )
        let entry = ImageCacheEntry(
            asset: asset,
            url: url,
            cacheIdentity: identity,
            diagnosticContext: diagnosticContext,
            networkRequestID: networkRequestID
        )
        return mutationLock.withLock {
            if let expectedGeneration,
               expectedGeneration != cacheGeneration {
                return false
            }
            if let replacedEntry = cache.object(forKey: key) {
                costTracker.remove(replacedEntry)
                diagnostics.record(
                    Self.makeEvent(
                        context: replacedEntry.diagnosticContext,
                        networkRequestID: replacedEntry.networkRequestID,
                        stage: .decodedCache,
                        action: .evicted,
                        cacheIdentity: replacedEntry.cacheIdentity
                    )
                )
            }
            costTracker.insert(entry)
            cache.setObject(entry, forKey: key, cost: entry.cost)
            return true
        }
    }

    fileprivate static func makeEvent(
        context: ImageDiagnosticContext,
        networkRequestID: UUID? = nil,
        stage: ImageDiagnosticStage,
        action: ImageDiagnosticAction,
        cacheIdentity: String? = nil,
        durationMilliseconds: Double? = nil,
        retryAttempt: Int = 0,
        decodeTarget: String? = nil,
        sourcePixelSize: ImageDiagnosticSize? = nil,
        decodedPixelSize: ImageDiagnosticSize? = nil,
        error: Error? = nil
    ) -> ImageDiagnosticEvent {
        ImageDiagnosticEvent(
            sequence: 0,
            timestamp: Date(),
            requestID: context.requestID,
            networkRequestID: networkRequestID,
            purpose: context.purpose,
            stage: stage,
            action: action,
            url: context.url,
            cacheIdentity: cacheIdentity,
            httpStatus: nil,
            responseBytes: nil,
            durationMilliseconds: durationMilliseconds,
            retryAttempt: retryAttempt,
            decodeTarget: decodeTarget,
            sourcePixelSize: sourcePixelSize,
            decodedPixelSize: decodedPixelSize,
            error: error,
            metadata: ImageDiagnosticEventMetadata(
                pageStableID: context.pageStableID,
                contentType: nil,
                wasCachedResponse: nil
            )
        )
    }

    private static func decodedPixelSize(_ image: UIImage) -> ImageDiagnosticSize {
        if let cgImage = image.cgImage {
            return ImageDiagnosticSize(
                CGSize(width: cgImage.width, height: cgImage.height)
            )
        }
        return ImageDiagnosticSize(
            CGSize(
                width: image.size.width * image.scale,
                height: image.size.height * image.scale
            )
        )
    }

    private static func milliseconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1_000
            + Double(duration.components.attoseconds) / 1_000_000_000_000_000
    }

    private static func isCancellation(_ error: Error) -> Bool {
        error is CancellationError
            || (error as? URLError)?.code == .cancelled
    }
}
