import XCTest
@testable import bika

enum TestSupport {
    static func makeAPIClient(
        store: InMemoryKeyValueStore = InMemoryKeyValueStore(),
        handler: @escaping MockURLProtocolHandler
    ) -> (APIClient, InMemoryKeyValueStore) {
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [MockURLProtocol.self]

        MockURLProtocol.reset()
        MockURLProtocol.requestHandler = handler
        MockURLProtocol.keyValueStore = store
        store.set("unit-test-token", forKey: TokenStore.tokenKey)

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

    static func queryValue(named name: String, from request: URLRequest) -> String? {
        guard let url = request.url,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }

        return components.queryItems?.first(where: { $0.name == name })?.value
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

final class LockedValue<T>: @unchecked Sendable {
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
