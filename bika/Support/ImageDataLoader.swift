import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

nonisolated private final class CoalescingRegistryEpoch: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    var current: Int { lock.withLock { value } }

    func advance() -> Int {
        lock.withLock {
            value &+= 1
            return value
        }
    }
}

nonisolated private final class CoalescingWaiterCancellationState: @unchecked Sendable {
    private let lock = NSLock()
    private var isCancelled = false

    var cancelled: Bool { lock.withLock { isCancelled } }

    func cancel() {
        lock.withLock { isCancelled = true }
    }
}

actor CoalescingTaskRegistry<Key: Hashable & Sendable, Value: Sendable> {
    private struct Entry {
        let id: UUID
        let generation: Int
        let task: Task<Value, Error>
        var waiters: [UUID: CheckedContinuation<Value, Error>]
    }

    private let epoch = CoalescingRegistryEpoch()
    private var entries: [Key: Entry] = [:]

    nonisolated func value(
        for key: Key,
        operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        let generation = epoch.current
        let waiterID = UUID()
        let cancellationState = CoalescingWaiterCancellationState()

        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await registeredValue(
                for: key,
                generation: generation,
                waiterID: waiterID,
                cancellationState: cancellationState,
                operation: operation
            )
        } onCancel: {
            cancellationState.cancel()
            Task {
                await self.cancelWaiter(waiterID, for: key)
            }
        }
    }

    nonisolated func cancelAll() async {
        let generation = epoch.advance()
        await cancelEntries(olderThan: generation)
    }

    private func registeredValue(
        for key: Key,
        generation: Int,
        waiterID: UUID,
        cancellationState: CoalescingWaiterCancellationState,
        operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        guard generation == epoch.current, !cancellationState.cancelled else {
            throw CancellationError()
        }

        return try await withCheckedThrowingContinuation { continuation in
            guard generation == epoch.current, !cancellationState.cancelled else {
                continuation.resume(throwing: CancellationError())
                return
            }

            register(
                waiterID: waiterID,
                for: key,
                generation: generation,
                operation: operation,
                continuation: continuation
            )
        }
    }

    private func register(
        waiterID: UUID,
        for key: Key,
        generation: Int,
        operation: @escaping @Sendable () async throws -> Value,
        continuation: CheckedContinuation<Value, Error>
    ) {
        if var entry = entries[key] {
            if entry.generation == generation {
                entry.waiters[waiterID] = continuation
                entries[key] = entry
                return
            }

            entries.removeValue(forKey: key)
            cancel(entry)
        }

        let entryID = UUID()
        let task = Task {
            try await operation()
        }
        entries[key] = Entry(
            id: entryID,
            generation: generation,
            task: task,
            waiters: [waiterID: continuation]
        )

        Task {
            let result = await task.result
            complete(result, for: key, entryID: entryID)
        }
    }

    private func cancelEntries(olderThan generation: Int) {
        let keysToCancel = entries.compactMap { key, entry in
            entry.generation < generation ? key : nil
        }

        for key in keysToCancel {
            guard let entry = entries.removeValue(forKey: key) else { continue }
            cancel(entry)
        }
    }

    private func cancel(_ entry: Entry) {
        entry.task.cancel()
        entry.waiters.values.forEach {
            $0.resume(throwing: CancellationError())
        }
    }

    private func cancelWaiter(_ waiterID: UUID, for key: Key) {
        guard var entry = entries[key],
              let continuation = entry.waiters.removeValue(forKey: waiterID) else {
            return
        }

        continuation.resume(throwing: CancellationError())
        if entry.waiters.isEmpty {
            entries.removeValue(forKey: key)
            entry.task.cancel()
        } else {
            entries[key] = entry
        }
    }

    private func complete(
        _ result: Result<Value, Error>,
        for key: Key,
        entryID: UUID
    ) {
        guard let entry = entries[key], entry.id == entryID else { return }
        entries.removeValue(forKey: key)
        entry.waiters.values.forEach { $0.resume(with: result) }
    }
}

nonisolated protocol ImageDataLoading: Sendable {
    func data(from url: URL) async throws -> Data
}

final nonisolated class URLSessionImageDataLoader: @unchecked Sendable, ImageDataLoading {
    private let session: URLSession
    private let responseCache: URLCache
    private let requestRegistry: CoalescingTaskRegistry<URL, Data>

    init(
        session: URLSession,
        responseCache: URLCache,
        requestRegistry: CoalescingTaskRegistry<URL, Data> = .init()
    ) {
        self.session = session
        self.responseCache = responseCache
        self.requestRegistry = requestRegistry
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
            responseCache: cacheController.responseCache,
            requestRegistry: cacheController.dataRequestRegistry
        )
    }
#endif

    func data(from url: URL) async throws -> Data {
        let session = session
        let responseCache = responseCache
        return try await requestRegistry.value(for: url) {
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
            try Task.checkCancellation()
            if let httpResponse = response as? HTTPURLResponse,
               !(200...299).contains(httpResponse.statusCode) {
                throw URLError(.badServerResponse)
            }
            guard !data.isEmpty else {
                throw URLError(.zeroByteResource)
            }

            try Task.checkCancellation()
            responseCache.storeCachedResponse(
                CachedURLResponse(response: response, data: data, storagePolicy: .allowed),
                for: request
            )
            return data
        }
    }
}

final nonisolated class FixtureImageDataLoader: @unchecked Sendable, ImageDataLoading {
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
