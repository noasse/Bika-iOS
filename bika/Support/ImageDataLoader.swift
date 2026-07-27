import Foundation
import ImageIO
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

nonisolated struct CoalescingTaskRegistration: Equatable, Sendable {
    let operationID: UUID
    let joinedExistingOperation: Bool
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
        try await value(
            for: key,
            onRegistration: { _ in },
            operation: { _ in try await operation() }
        )
    }

    nonisolated func value(
        for key: Key,
        onRegistration: @escaping @Sendable (CoalescingTaskRegistration) -> Void,
        operation: @escaping @Sendable (UUID) async throws -> Value
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
                onRegistration: onRegistration,
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
        onRegistration: @escaping @Sendable (CoalescingTaskRegistration) -> Void,
        operation: @escaping @Sendable (UUID) async throws -> Value
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
                onRegistration: onRegistration,
                operation: operation,
                continuation: continuation
            )
        }
    }

    private func register(
        waiterID: UUID,
        for key: Key,
        generation: Int,
        onRegistration: @escaping @Sendable (CoalescingTaskRegistration) -> Void,
        operation: @escaping @Sendable (UUID) async throws -> Value,
        continuation: CheckedContinuation<Value, Error>
    ) {
        if var entry = entries[key] {
            if entry.generation == generation {
                entry.waiters[waiterID] = continuation
                entries[key] = entry
                onRegistration(
                    CoalescingTaskRegistration(
                        operationID: entry.id,
                        joinedExistingOperation: true
                    )
                )
                return
            }

            entries.removeValue(forKey: key)
            cancel(entry)
        }

        let entryID = UUID()
        onRegistration(
            CoalescingTaskRegistration(
                operationID: entryID,
                joinedExistingOperation: false
            )
        )
        let task = Task {
            try await operation(entryID)
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

nonisolated struct ImageDataLoadResult: Sendable {
    let data: Data
    let networkRequestID: UUID?
}

nonisolated protocol ImageDataLoading: Sendable {
    func data(from url: URL) async throws -> Data
    func loadResult(
        from url: URL,
        diagnosticContext: ImageDiagnosticContext
    ) async throws -> ImageDataLoadResult
    func invalidateCachedData(for url: URL)
    func invalidateCachedData(
        for url: URL,
        diagnosticContext: ImageDiagnosticContext
    )
}

extension ImageDataLoading {
    nonisolated func loadResult(
        from url: URL,
        diagnosticContext: ImageDiagnosticContext
    ) async throws -> ImageDataLoadResult {
        ImageDataLoadResult(
            data: try await data(from: url),
            networkRequestID: nil
        )
    }

    nonisolated func invalidateCachedData(for url: URL) {}

    nonisolated func invalidateCachedData(
        for url: URL,
        diagnosticContext: ImageDiagnosticContext
    ) {
        invalidateCachedData(for: url)
    }
}

nonisolated private final class CoalescingRegistrationState: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: CoalescingTaskRegistration?

    var value: CoalescingTaskRegistration? {
        lock.withLock { storage }
    }

    func set(_ value: CoalescingTaskRegistration) {
        lock.withLock { storage = value }
    }
}

final nonisolated class URLSessionImageDataLoader: @unchecked Sendable, ImageDataLoading {
    private struct HTTPStatusError: Error, CustomNSError {
        static let errorDomain = "ImageHTTPStatus"
        let statusCode: Int
        var errorCode: Int { statusCode }
    }

    private let session: URLSession
    private let responseCache: URLCache
    private let requestRegistry: CoalescingTaskRegistry<URL, Data>
    private let diagnostics: any ImageDiagnosticsRecording
    private let retryDelays: [Duration]

    init(
        session: URLSession,
        responseCache: URLCache,
        requestRegistry: CoalescingTaskRegistry<URL, Data> = .init(),
        diagnostics: any ImageDiagnosticsRecording = URLSessionImageDataLoader.defaultDiagnostics,
        retryDelays: [Duration] = [.milliseconds(200), .milliseconds(600)]
    ) {
        self.session = session
        self.responseCache = responseCache
        self.requestRegistry = requestRegistry
        self.diagnostics = diagnostics
        self.retryDelays = retryDelays
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
        try await loadResult(
            from: url,
            diagnosticContext: ImageDiagnosticContext(
                purpose: .unspecified,
                url: url
            )
        ).data
    }

    func loadResult(
        from url: URL,
        diagnosticContext: ImageDiagnosticContext
    ) async throws -> ImageDataLoadResult {
        let registrationState = CoalescingRegistrationState()
        do {
            let data = try await requestRegistry.value(
                for: url,
                onRegistration: { [diagnostics] registration in
                    registrationState.set(registration)
                    diagnostics.record(
                        Self.makeEvent(
                            context: diagnosticContext,
                            networkRequestID: registration.operationID,
                            stage: .coalescing,
                            action: registration.joinedExistingOperation ? .joined : .started
                        )
                    )
                },
                operation: { [session, responseCache, retryDelays, diagnostics] networkRequestID in
                    try await Self.performLoad(
                        url: url,
                        context: diagnosticContext,
                        networkRequestID: networkRequestID,
                        session: session,
                        responseCache: responseCache,
                        retryDelays: retryDelays,
                        diagnostics: diagnostics
                    )
                }
            )
            return ImageDataLoadResult(
                data: data,
                networkRequestID: registrationState.value?.operationID
            )
        } catch {
            let action: ImageDiagnosticAction = Self.isCancellation(error)
                ? .cancelled
                : .failed
            diagnostics.record(
                Self.makeEvent(
                    context: diagnosticContext,
                    networkRequestID: registrationState.value?.operationID,
                    stage: .coalescing,
                    action: action,
                    error: error
                )
            )
            throw error
        }
    }

    func invalidateCachedData(for url: URL) {
        invalidateCachedData(
            for: url,
            diagnosticContext: ImageDiagnosticContext(
                purpose: .unspecified,
                url: url
            )
        )
    }

    func invalidateCachedData(
        for url: URL,
        diagnosticContext: ImageDiagnosticContext
    ) {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let cached = responseCache.cachedResponse(for: request)
        responseCache.removeCachedResponse(for: request)
        diagnostics.record(
            Self.makeEvent(
                context: diagnosticContext,
                stage: .responseCache,
                action: .evicted,
                responseBytes: cached?.data.count,
                contentType: cached?.response.mimeType,
                wasCachedResponse: true
            )
        )
    }

    private static func performLoad(
        url: URL,
        context: ImageDiagnosticContext,
        networkRequestID: UUID,
        session: URLSession,
        responseCache: URLCache,
        retryDelays: [Duration],
        diagnostics: any ImageDiagnosticsRecording
    ) async throws -> Data {
        var request = URLRequest(
            url: url,
            cachePolicy: .returnCacheDataElseLoad,
            timeoutInterval: 60
        )
        request.httpMethod = "GET"

        if let cached = responseCache.cachedResponse(for: request) {
            if isUsableImageResponse(cached.response, data: cached.data) {
                diagnostics.record(
                    makeEvent(
                        context: context,
                        networkRequestID: networkRequestID,
                        stage: .responseCache,
                        action: .hit,
                        httpStatus: (cached.response as? HTTPURLResponse)?.statusCode,
                        responseBytes: cached.data.count,
                        contentType: cached.response.mimeType,
                        wasCachedResponse: true
                    )
                )
                return cached.data
            }
            responseCache.removeCachedResponse(for: request)
            diagnostics.record(
                makeEvent(
                    context: context,
                    networkRequestID: networkRequestID,
                    stage: .responseCache,
                    action: .evicted,
                    httpStatus: (cached.response as? HTTPURLResponse)?.statusCode,
                    responseBytes: cached.data.count,
                    contentType: cached.response.mimeType,
                    wasCachedResponse: true
                )
            )
        } else {
            diagnostics.record(
                makeEvent(
                    context: context,
                    networkRequestID: networkRequestID,
                    stage: .responseCache,
                    action: .missed,
                    wasCachedResponse: false
                )
            )
        }

        request.cachePolicy = .reloadIgnoringLocalCacheData
        var attempt = 0
        let clock = ContinuousClock()
        while true {
            let startedAt = clock.now
            diagnostics.record(
                makeEvent(
                    context: context,
                    networkRequestID: networkRequestID,
                    stage: .network,
                    action: .started,
                    retryAttempt: attempt
                )
            )
            do {
                let (data, response) = try await session.data(for: request)
                try Task.checkCancellation()
                let statusCode = (response as? HTTPURLResponse)?.statusCode
                let duration = milliseconds(startedAt.duration(to: clock.now))
                diagnostics.record(
                    makeEvent(
                        context: context,
                        networkRequestID: networkRequestID,
                        stage: .network,
                        action: .response,
                        httpStatus: statusCode,
                        responseBytes: data.count,
                        durationMilliseconds: duration,
                        retryAttempt: attempt,
                        contentType: response.mimeType,
                        wasCachedResponse: false
                    )
                )
                if let statusCode, !(200...299).contains(statusCode) {
                    throw HTTPStatusError(statusCode: statusCode)
                }
                guard !data.isEmpty else {
                    throw URLError(.zeroByteResource)
                }
                guard isDecodableImageData(data) else {
                    throw URLError(.cannotDecodeContentData)
                }

                try Task.checkCancellation()
                responseCache.storeCachedResponse(
                    CachedURLResponse(
                        response: response,
                        data: data,
                        storagePolicy: .allowed
                    ),
                    for: request
                )
                diagnostics.record(
                    makeEvent(
                        context: context,
                        networkRequestID: networkRequestID,
                        stage: .network,
                        action: .succeeded,
                        httpStatus: statusCode,
                        responseBytes: data.count,
                        durationMilliseconds: milliseconds(
                            startedAt.duration(to: clock.now)
                        ),
                        retryAttempt: attempt,
                        contentType: response.mimeType,
                        wasCachedResponse: false
                    )
                )
                return data
            } catch {
                if isCancellation(error) || Task.isCancelled {
                    diagnostics.record(
                        makeEvent(
                            context: context,
                            networkRequestID: networkRequestID,
                            stage: .network,
                            action: .cancelled,
                            durationMilliseconds: milliseconds(
                                startedAt.duration(to: clock.now)
                            ),
                            retryAttempt: attempt,
                            error: error
                        )
                    )
                    throw error
                }
                guard attempt < retryDelays.count, shouldRetry(error) else {
                    diagnostics.record(
                        makeEvent(
                            context: context,
                            networkRequestID: networkRequestID,
                            stage: .network,
                            action: .failed,
                            durationMilliseconds: milliseconds(
                                startedAt.duration(to: clock.now)
                            ),
                            retryAttempt: attempt,
                            error: error
                        )
                    )
                    throw error
                }
                let delay = retryDelays[attempt]
                attempt += 1
                diagnostics.record(
                    makeEvent(
                        context: context,
                        networkRequestID: networkRequestID,
                        stage: .network,
                        action: .retrying,
                        durationMilliseconds: milliseconds(
                            startedAt.duration(to: clock.now)
                        ),
                        retryAttempt: attempt,
                        error: error
                    )
                )
                do {
                    try await Task.sleep(for: delay)
                } catch {
                    diagnostics.record(
                        makeEvent(
                            context: context,
                            networkRequestID: networkRequestID,
                            stage: .network,
                            action: .cancelled,
                            retryAttempt: attempt,
                            error: error
                        )
                    )
                    throw error
                }
            }
        }
    }

    private static func makeEvent(
        context: ImageDiagnosticContext,
        networkRequestID: UUID? = nil,
        stage: ImageDiagnosticStage,
        action: ImageDiagnosticAction,
        httpStatus: Int? = nil,
        responseBytes: Int? = nil,
        durationMilliseconds: Double? = nil,
        retryAttempt: Int = 0,
        error: Error? = nil,
        contentType: String? = nil,
        wasCachedResponse: Bool? = nil
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
            cacheIdentity: nil,
            httpStatus: httpStatus,
            responseBytes: responseBytes,
            durationMilliseconds: durationMilliseconds,
            retryAttempt: retryAttempt,
            decodeTarget: nil,
            sourcePixelSize: nil,
            decodedPixelSize: nil,
            error: error,
            metadata: ImageDiagnosticEventMetadata(
                pageStableID: context.pageStableID,
                contentType: contentType,
                wasCachedResponse: wasCachedResponse
            )
        )
    }

    private static var defaultDiagnostics: any ImageDiagnosticsRecording {
#if os(iOS)
        ImageDiagnosticsService.shared
#else
        ImageDiagnosticsNoopRecorder.shared
#endif
    }

    private static func milliseconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1_000
            + Double(duration.components.attoseconds) / 1_000_000_000_000_000
    }

    private static func isCancellation(_ error: Error) -> Bool {
        error is CancellationError
            || (error as? URLError)?.code == .cancelled
    }

    private static func isUsableImageResponse(_ response: URLResponse, data: Data) -> Bool {
        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            return false
        }
        return isDecodableImageData(data)
    }

    private static func isDecodableImageData(_ data: Data) -> Bool {
        guard !data.isEmpty,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              CGImageSourceGetType(source) != nil else {
            return false
        }
        return CGImageSourceCopyPropertiesAtIndex(source, 0, nil) != nil
    }

    private static func shouldRetry(_ error: Error) -> Bool {
        if let statusError = error as? HTTPStatusError {
            return statusError.statusCode == 408
                || statusError.statusCode == 425
                || statusError.statusCode == 429
                || (500...599).contains(statusError.statusCode)
        }

        guard let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .timedOut,
             .cannotFindHost,
             .cannotConnectToHost,
             .networkConnectionLost,
             .dnsLookupFailed,
             .notConnectedToInternet,
             .zeroByteResource,
             .cannotDecodeContentData,
             .badServerResponse:
            return true
        default:
            return false
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
