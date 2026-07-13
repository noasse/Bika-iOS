import Foundation

nonisolated struct ImageCacheUsage: Equatable, Sendable {
    let memoryBytes: Int
    let diskBytes: Int

    var totalBytes: Int {
        max(0, memoryBytes) + max(0, diskBytes)
    }
}

nonisolated protocol ImageCacheManaging: Sendable {
    func usage() async -> ImageCacheUsage
    func clear() async
}

final nonisolated class ImageCacheController: @unchecked Sendable, ImageCacheManaging {
    static let shared = ImageCacheController()

    let responseCache: URLCache
    private let decodedCache: ImageCache

    init(
        responseCache: URLCache = ImageCacheController.makeResponseCache(),
        decodedCache: ImageCache = .shared
    ) {
        self.responseCache = responseCache
        self.decodedCache = decodedCache
    }

    func usage() async -> ImageCacheUsage {
        ImageCacheUsage(
            memoryBytes: responseCache.currentMemoryUsage,
            diskBytes: responseCache.currentDiskUsage
        )
    }

    func clear() async {
        responseCache.removeAllCachedResponses()
        decodedCache.removeAllImages()
    }

    private static func makeResponseCache() -> URLCache {
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("ImageResponses", isDirectory: true)
        return URLCache(
            memoryCapacity: 32 * 1024 * 1024,
            diskCapacity: 512 * 1024 * 1024,
            directory: directory
        )
    }
}
