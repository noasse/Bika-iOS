import Foundation

nonisolated struct MacImageCacheUsage: Equatable, Sendable {
    let memoryBytes: Int
    let diskBytes: Int

    var totalBytes: Int {
        max(0, memoryBytes) + max(0, diskBytes)
    }

    var formattedTotal: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(totalBytes))
    }
}

nonisolated protocol MacImageCacheManaging: Sendable {
    func usage() async -> MacImageCacheUsage
    func clear() async
}

/// Owns the macOS image caches so settings can report and reclaim their footprint.
///
/// The response cache lives on `AppDependencies` rather than here: the image data loader is
/// built during `AppDependencies` initialisation, and reaching back into this type from there
/// would recurse through `MacImageCache.shared`, which resolves its loader from
/// `AppDependencies` in turn.
final nonisolated class MacImageCacheController: @unchecked Sendable, MacImageCacheManaging {
    static let shared = MacImageCacheController()

    private let responseCache: URLCache
    private let decodedCache: @Sendable () -> MacImageCache

    init(
        responseCache: URLCache = AppDependencies.macImageResponseCache,
        decodedCache: @escaping @Sendable () -> MacImageCache = { .shared }
    ) {
        self.responseCache = responseCache
        self.decodedCache = decodedCache
    }

    func usage() async -> MacImageCacheUsage {
        MacImageCacheUsage(
            memoryBytes: responseCache.currentMemoryUsage,
            diskBytes: responseCache.currentDiskUsage
        )
    }

    func clear() async {
        await decodedCache().removeAllImages()
        responseCache.removeAllCachedResponses()
    }
}
