import XCTest
@testable import BikaMacos

nonisolated enum MacTestSupport {
    static func makeAPIClient(
        store: InMemoryKeyValueStore = InMemoryKeyValueStore(),
        handler: @escaping MockURLProtocolHandler
    ) -> (APIClient, InMemoryKeyValueStore) {
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [MockURLProtocol.self]

        MockURLProtocol.reset()
        MockURLProtocol.requestHandler = handler
        MockURLProtocol.keyValueStore = store
        store.set("mac-unit-test-token", forKey: TokenStore.tokenKey)

        let session = URLSession(configuration: sessionConfiguration)
        let tokenStore = TokenStore(store: store)
        let client = APIClient(session: session, tokenStore: tokenStore)

        AppDependencies.shared.installForTesting(
            apiClient: client,
            keyValueStore: store,
            imageDataLoader: FixtureImageDataLoader()
        )

        return (client, store)
    }

    static func jsonResponse(
        statusCode: Int = 200,
        code: Int = 200,
        message: String = "success",
        data: Any
    ) -> MockHTTPResponse {
        let body = try? JSONSerialization.data(withJSONObject: [
            "code": code,
            "message": message,
            "data": data,
        ])

        return MockHTTPResponse(
            statusCode: statusCode,
            headers: ["Content-Type": "application/json"],
            data: body ?? Data()
        )
    }

    static func emptyHTTPResponse(statusCode: Int) -> MockHTTPResponse {
        MockHTTPResponse(
            statusCode: statusCode,
            headers: ["Content-Type": "application/json"],
            data: Data("{}".utf8)
        )
    }

    static func page(from request: URLRequest) -> Int {
        guard let url = request.url,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return 1
        }

        return Int(components.queryItems?.first(where: { $0.name == "page" })?.value ?? "1") ?? 1
    }

    static func restoreLiveDependencies() {
        MockURLProtocol.reset()
        AppDependencies.shared.configureForLaunch()
    }
}

extension XCTestCase {
    @MainActor
    func waitUntil(
        timeout: TimeInterval = 2.0,
        pollInterval: UInt64 = 50_000_000,
        file: StaticString = #filePath,
        line: UInt = #line,
        condition: @escaping () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try? await Task.sleep(nanoseconds: pollInterval)
        }

        XCTFail("等待条件满足超时", file: file, line: line)
    }
}

final nonisolated class LockedValue<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: T

    init(_ initialValue: T) {
        storage = initialValue
    }

    var value: T {
        get { lock.withLock { storage } }
        set { lock.withLock { storage = newValue } }
    }
}

actor TestAsyncGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { continuation in
            if isOpen {
                continuation.resume()
            } else {
                waiters.append(continuation)
            }
        }
    }

    func open() {
        guard !isOpen else { return }
        isOpen = true
        let pendingWaiters = waiters
        waiters.removeAll()
        pendingWaiters.forEach { $0.resume() }
    }
}

/// Records image-cache maintenance so tests can assert on it without touching the real caches.
final class SpyImageCacheManager: MacImageCacheManaging, @unchecked Sendable {
    private let state = LockedValue(State())

    private struct State {
        var clearCount = 0
        var usage = MacImageCacheUsage(memoryBytes: 0, diskBytes: 0)
    }

    init(usage: MacImageCacheUsage = MacImageCacheUsage(memoryBytes: 0, diskBytes: 0)) {
        state.value = State(clearCount: 0, usage: usage)
    }

    var clearCount: Int { state.value.clearCount }

    func usage() async -> MacImageCacheUsage {
        state.value.usage
    }

    func clear() async {
        var current = state.value
        current.clearCount += 1
        current.usage = MacImageCacheUsage(memoryBytes: 0, diskBytes: 0)
        state.value = current
    }
}
