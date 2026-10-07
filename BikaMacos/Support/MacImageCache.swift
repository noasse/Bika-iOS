import AppKit
import ImageIO
import SwiftUI

nonisolated enum MacImageDecodeTarget: Sendable, Equatable {
    case full
    case fit(CGSize)
    case fill(CGSize)
    case fitWidth(CGFloat)

    var cacheKey: String {
        switch self {
        case .full:
            return "full"
        case .fit(let size):
            return "fit-\(Self.rounded(size.width))x\(Self.rounded(size.height))"
        case .fill(let size):
            return "fill-\(Self.rounded(size.width))x\(Self.rounded(size.height))"
        case .fitWidth(let width):
            return "width-\(Self.rounded(width))"
        }
    }

    private static func rounded(_ value: CGFloat) -> Int {
        guard value.isFinite, value > 0 else { return 0 }
        return Int(value.rounded())
    }
}

nonisolated struct MacDecodedImageAsset: @unchecked Sendable {
    let image: NSImage
    let displaySize: CGSize
    let pixelSize: CGSize
    let decodedCost: Int
}

nonisolated enum MacImageDecoding {
    static func decodeAsset(
        from data: Data,
        target: MacImageDecodeTarget,
        pixelScale: CGFloat,
        maximumPixelSize: Int
    ) -> MacDecodedImageAsset? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let displaySize = displaySize(for: source) else {
            return nil
        }

        let maxPixelSize = thumbnailMaxPixelSize(
            target: target,
            displaySize: displaySize,
            pixelScale: pixelScale,
            maximumPixelSize: maximumPixelSize
        )
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            options as CFDictionary
        ) else {
            return nil
        }

        return MacDecodedImageAsset(
            image: NSImage(cgImage: cgImage, size: .zero),
            displaySize: displaySize,
            pixelSize: CGSize(width: cgImage.width, height: cgImage.height),
            decodedCost: cgImage.bytesPerRow * cgImage.height
        )
    }

    private static func displaySize(for source: CGImageSource) -> CGSize? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = number(from: properties[kCGImagePropertyPixelWidth] ?? properties[kCGImagePropertyWidth]),
              let height = number(from: properties[kCGImagePropertyPixelHeight] ?? properties[kCGImagePropertyHeight]),
              width > 0,
              height > 0 else {
            return nil
        }

        let rawOrientation = number(from: properties[kCGImagePropertyOrientation]).map(UInt32.init) ?? 1
        let orientation = CGImagePropertyOrientation(rawValue: rawOrientation) ?? .up
        switch orientation {
        case .leftMirrored, .right, .rightMirrored, .left:
            return CGSize(width: height, height: width)
        default:
            return CGSize(width: width, height: height)
        }
    }

    private static func thumbnailMaxPixelSize(
        target: MacImageDecodeTarget,
        displaySize: CGSize,
        pixelScale: CGFloat,
        maximumPixelSize: Int
    ) -> Int {
        let resolvedScale = pixelScale.isFinite ? max(pixelScale, 1) : 1
        let resolvedMaximum = max(maximumPixelSize, 1)
        let desiredDimension: CGFloat

        switch target {
        case .full:
            desiredDimension = max(displaySize.width, displaySize.height)
        case .fit(let size), .fill(let size):
            guard size.width.isFinite,
                  size.height.isFinite,
                  size.width > 0,
                  size.height > 0 else {
                return resolvedMaximum
            }
            let widthScale = size.width / max(displaySize.width, 1)
            let heightScale = size.height / max(displaySize.height, 1)
            let targetScale: CGFloat
            switch target {
            case .fit:
                targetScale = min(widthScale, heightScale)
            case .fill:
                targetScale = max(widthScale, heightScale)
            default:
                targetScale = 1
            }
            desiredDimension = max(displaySize.width, displaySize.height)
                * targetScale
                * resolvedScale
        case .fitWidth(let width):
            guard width.isFinite, width > 0 else { return resolvedMaximum }
            let fittedHeight = width * displaySize.height / max(displaySize.width, 1)
            desiredDimension = max(width, fittedHeight) * resolvedScale
        }

        return min(resolvedMaximum, max(1, Int(desiredDimension.rounded(.up))))
    }

    private static func number(from value: Any?) -> CGFloat? {
        guard let number = value as? NSNumber else { return nil }
        return CGFloat(number.doubleValue)
    }
}

nonisolated struct MacReaderImageVariant: Equatable, Sendable {
    let viewportWidth: CGFloat
    let pixelScale: CGFloat
    let maximumPixelSize: Int
}

nonisolated enum MacReaderImageResolutionPlan {
    static let upgradeMagnificationThreshold: CGFloat = 1.25
    private static let bucketSize: CGFloat = 128

    static func viewportBucket(for width: CGFloat) -> CGFloat {
        guard width.isFinite, width > 0 else { return bucketSize }
        return max(bucketSize, ceil(width / bucketSize) * bucketSize)
    }

    static func variant(
        viewportWidth: CGFloat,
        magnification: CGFloat
    ) -> MacReaderImageVariant {
        let isUpgrade = magnification >= upgradeMagnificationThreshold
        return MacReaderImageVariant(
            viewportWidth: viewportBucket(for: viewportWidth),
            pixelScale: isUpgrade ? 8 : 2,
            maximumPixelSize: isUpgrade ? 16_384 : 8_192
        )
    }
}

nonisolated private final class MacImageCacheKey: NSObject {
    let value: String

    init(value: String) {
        self.value = value
    }

    override var hash: Int { value.hashValue }

    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? MacImageCacheKey else { return false }
        return value == other.value
    }
}

nonisolated private final class MacImageCacheEntry: NSObject {
    let asset: MacDecodedImageAsset

    init(asset: MacDecodedImageAsset) {
        self.asset = asset
    }
}

nonisolated final class MacImageCache: @unchecked Sendable {
    static let shared = MacImageCache()

    private let cache = NSCache<MacImageCacheKey, MacImageCacheEntry>()
    private let imageLoader: any ImageDataLoading
    private let requestRegistry = CoalescingTaskRegistry<String, MacDecodedImageAsset>()
    private let mutationLock = NSLock()
    private var cacheGeneration = 0

    init(
        imageLoader: any ImageDataLoading = AppDependencies.shared.imageDataLoader,
        countLimit: Int = 120,
        totalCostLimit: Int = 128 * 1024 * 1024
    ) {
        self.imageLoader = imageLoader
        cache.countLimit = countLimit
        cache.totalCostLimit = totalCostLimit
    }

    convenience init(session: URLSession) {
        self.init(imageLoader: URLSessionImageDataLoader(session: session))
    }

    func asset(
        for url: URL,
        target: MacImageDecodeTarget,
        pixelScale: CGFloat,
        maximumPixelSize: Int
    ) async throws -> MacDecodedImageAsset {
        if let cached = cachedAsset(
            for: url,
            target: target,
            pixelScale: pixelScale,
            maximumPixelSize: maximumPixelSize
        ) {
            return cached
        }

        let identity = Self.cacheIdentity(
            for: url,
            target: target,
            pixelScale: pixelScale,
            maximumPixelSize: maximumPixelSize
        )
        let expectedGeneration = mutationLock.withLock { cacheGeneration }
        return try await requestRegistry.value(for: identity) { [self] in
            if let cached = cachedAsset(
                for: url,
                target: target,
                pixelScale: pixelScale,
                maximumPixelSize: maximumPixelSize
            ) {
                return cached
            }

            try Task.checkCancellation()
            let data = try await imageLoader.data(from: url)
            try Task.checkCancellation()
            let decodeTask = Task.detached(priority: .userInitiated) { () throws -> MacDecodedImageAsset in
                try Task.checkCancellation()
                guard let asset = MacImageDecoding.decodeAsset(
                    from: data,
                    target: target,
                    pixelScale: pixelScale,
                    maximumPixelSize: maximumPixelSize
                ) else {
                    throw URLError(.cannotDecodeContentData)
                }
                try Task.checkCancellation()
                return asset
            }
            let asset = try await withTaskCancellationHandler {
                try await decodeTask.value
            } onCancel: {
                decodeTask.cancel()
            }
            try Task.checkCancellation()

            guard setAsset(
                asset,
                forIdentity: identity,
                expectedGeneration: expectedGeneration
            ) else {
                throw CancellationError()
            }
            return asset
        }
    }

    func cachedAsset(
        for url: URL,
        target: MacImageDecodeTarget,
        pixelScale: CGFloat,
        maximumPixelSize: Int
    ) -> MacDecodedImageAsset? {
        let identity = Self.cacheIdentity(
            for: url,
            target: target,
            pixelScale: pixelScale,
            maximumPixelSize: maximumPixelSize
        )
        return cache.object(forKey: MacImageCacheKey(value: identity))?.asset
    }

    func removeAllImages() async {
        await requestRegistry.cancelAll()
        mutationLock.withLock {
            cacheGeneration &+= 1
            cache.removeAllObjects()
        }
    }

    static func cacheIdentity(
        for url: URL,
        target: MacImageDecodeTarget,
        pixelScale: CGFloat,
        maximumPixelSize: Int
    ) -> String {
        let resolvedScale = pixelScale.isFinite ? max(pixelScale, 1) : 1
        let scaleKey = Int((resolvedScale * 100).rounded())
        return "\(url.absoluteString)#\(target.cacheKey)#scale-\(scaleKey)#max-\(max(maximumPixelSize, 1))"
    }

    private func setAsset(
        _ asset: MacDecodedImageAsset,
        forIdentity identity: String,
        expectedGeneration: Int
    ) -> Bool {
        mutationLock.withLock {
            guard expectedGeneration == cacheGeneration else { return false }
            cache.setObject(
                MacImageCacheEntry(asset: asset),
                forKey: MacImageCacheKey(value: identity),
                cost: asset.decodedCost
            )
            return true
        }
    }
}

struct MacCachedAsyncImage<Placeholder: View>: View {
    let url: URL?
    var contentMode: ContentMode = .fit
    var targetSize: CGSize
    var pixelScale: CGFloat = 2
    var maximumPixelSize = 4_096
    var imageCache: MacImageCache = .shared
    var onImageLoaded: ((CGSize) -> Void)?
    @ViewBuilder let placeholder: () -> Placeholder

    @State private var image: NSImage?
    @State private var failed = false

    private var decodeTarget: MacImageDecodeTarget {
        switch contentMode {
        case .fit:
            return .fit(targetSize)
        case .fill:
            return .fill(targetSize)
        }
    }

    private var loadIdentity: String {
        guard let url else { return "missing" }
        return MacImageCache.cacheIdentity(
            for: url,
            target: decodeTarget,
            pixelScale: pixelScale,
            maximumPixelSize: maximumPixelSize
        )
    }

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
        .task(id: loadIdentity) {
            image = nil
            failed = false
            guard let url else {
                failed = true
                return
            }

            do {
                let asset = try await imageCache.asset(
                    for: url,
                    target: decodeTarget,
                    pixelScale: pixelScale,
                    maximumPixelSize: maximumPixelSize
                )
                try Task.checkCancellation()
                image = asset.image
                onImageLoaded?(asset.displaySize)
            } catch is CancellationError {
                return
            } catch {
                failed = true
            }
        }
    }
}

extension MacCachedAsyncImage where Placeholder == AnyView {
    init(
        url: URL?,
        contentMode: ContentMode = .fit,
        targetSize: CGSize,
        pixelScale: CGFloat = 2,
        maximumPixelSize: Int = 4_096,
        imageCache: MacImageCache = .shared,
        onImageLoaded: ((CGSize) -> Void)? = nil
    ) {
        self.url = url
        self.contentMode = contentMode
        self.targetSize = targetSize
        self.pixelScale = pixelScale
        self.maximumPixelSize = maximumPixelSize
        self.imageCache = imageCache
        self.onImageLoaded = onImageLoaded
        self.placeholder = {
            AnyView(
                RoundedRectangle(cornerRadius: 6)
                    .fill(.quaternary)
            )
        }
    }
}
