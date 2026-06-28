import XCTest
@testable import BikaMacos

enum MacTestSupport {
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

    static func restoreLiveDependencies() {
        MockURLProtocol.reset()
        AppDependencies.shared.configureForLaunch()
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
