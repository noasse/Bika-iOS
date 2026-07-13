import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

nonisolated protocol ImageDataLoading: Sendable {
    func data(from url: URL) async throws -> Data
}

final nonisolated class URLSessionImageDataLoader: @unchecked Sendable, ImageDataLoading {
    private let session: URLSession
    private let responseCache: URLCache
    private let requestCoordinator = ImageDataRequestCoordinator()

    init(session: URLSession, responseCache: URLCache) {
        self.session = session
        self.responseCache = responseCache
    }

    convenience init(session: URLSession) {
        self.init(
            session: session,
            responseCache: session.configuration.urlCache ?? .shared
        )
    }

    convenience init() {
        let configuration = URLSessionConfiguration.default
        let responseCache = configuration.urlCache ?? .shared
        configuration.urlCache = responseCache
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        self.init(
            session: URLSession(configuration: configuration),
            responseCache: responseCache
        )
    }

#if os(iOS)
    convenience init(cacheController: ImageCacheController) {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = cacheController.responseCache
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        self.init(
            session: URLSession(configuration: configuration),
            responseCache: cacheController.responseCache
        )
    }
#endif

    func data(from url: URL) async throws -> Data {
        let session = session
        let responseCache = responseCache
        return try await requestCoordinator.data(for: url) {
            var request = URLRequest(
                url: url,
                cachePolicy: .returnCacheDataElseLoad,
                timeoutInterval: 60
            )
            request.httpMethod = "GET"

            if let cached = responseCache.cachedResponse(for: request), !cached.data.isEmpty {
                return cached.data
            }

            let (data, response) = try await session.data(for: request)
            if let httpResponse = response as? HTTPURLResponse,
               !(200...299).contains(httpResponse.statusCode) {
                throw URLError(.badServerResponse)
            }
            guard !data.isEmpty else {
                throw URLError(.zeroByteResource)
            }

            responseCache.storeCachedResponse(
                CachedURLResponse(response: response, data: data, storagePolicy: .allowed),
                for: request
            )
            return data
        }
    }
}

private actor ImageDataRequestCoordinator {
    private var inFlightTasks: [URL: Task<Data, Error>] = [:]

    func data(
        for url: URL,
        operation: @escaping @Sendable () async throws -> Data
    ) async throws -> Data {
        if let task = inFlightTasks[url] {
            return try await task.value
        }

        let task = Task { try await operation() }
        inFlightTasks[url] = task
        defer { inFlightTasks[url] = nil }
        return try await task.value
    }
}

final class FixtureImageDataLoader: @unchecked Sendable, ImageDataLoading {
    private static let placeholderImageData: Data = {
        #if canImport(UIKit)
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 24, height: 24))
        let image = renderer.image { context in
            UIColor.systemPink.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 24, height: 24))

            UIColor.white.setFill()
            context.cgContext.fillEllipse(in: CGRect(x: 7, y: 7, width: 10, height: 10))
        }
        return image.pngData() ?? Data()
        #elseif canImport(AppKit)
        let image = NSImage(size: NSSize(width: 24, height: 24))
        image.lockFocus()
        NSColor.systemPink.setFill()
        NSRect(x: 0, y: 0, width: 24, height: 24).fill()
        NSColor.white.setFill()
        NSBezierPath(ovalIn: NSRect(x: 7, y: 7, width: 10, height: 10)).fill()
        image.unlockFocus()

        guard
            let tiffData = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiffData),
            let pngData = bitmap.representation(using: .png, properties: [:])
        else {
            return Data()
        }
        return pngData
        #else
        return Data()
        #endif
    }()

    func data(from url: URL) async throws -> Data {
        Self.placeholderImageData
    }
}
