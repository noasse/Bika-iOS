import XCTest
@testable import bika

final class CloudHistorySyncTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    func testCloudHistoryConfigPersistsAndLoadsFromKeyValueStore() throws {
        let store = InMemoryKeyValueStore()
        let config = CloudHistoryConfig(
            baseURL: try XCTUnwrap(URL(string: "https://history-sync.invalid")),
            bearerToken: "unit-test-token",
            certificateSHA256Pins: [String(repeating: "a", count: 64)]
        )

        store.setCloudHistoryConfig(config)

        XCTAssertEqual(store.cloudHistoryConfig(), config)

        store.clearCloudHistoryConfig()
        XCTAssertNil(store.cloudHistoryConfig())
    }

    func testCloudHistoryConfigPersistsAndLoadsWithoutCertificatePins() throws {
        let store = InMemoryKeyValueStore()
        let config = CloudHistoryConfig(
            baseURL: try XCTUnwrap(URL(string: "https://history-sync.invalid")),
            bearerToken: "unit-test-token",
            certificateSHA256Pins: []
        )

        store.setCloudHistoryConfig(config)

        XCTAssertEqual(store.cloudHistoryConfig(), config)
    }

    func testCloudHistoryConfigLoadsMissingCertificatePinsAsEmptyPins() throws {
        let store = InMemoryKeyValueStore()
        store.set("1", forKey: CloudHistoryConfig.StorageKeys.isEnabled)
        store.set("https://history-sync.invalid", forKey: CloudHistoryConfig.StorageKeys.baseURL)
        store.set("unit-test-token", forKey: CloudHistoryConfig.StorageKeys.bearerToken)

        let config = try XCTUnwrap(store.cloudHistoryConfig())

        XCTAssertEqual(config.certificateSHA256Pins, [])
    }

    func testCloudHistoryConfigDoesNotLoadIncompleteConfiguration() throws {
        let store = InMemoryKeyValueStore()
        store.set("https://history-sync.invalid", forKey: CloudHistoryConfig.StorageKeys.baseURL)
        store.set([String(repeating: "b", count: 64)], forKey: CloudHistoryConfig.StorageKeys.certificateSHA256Pins)

        XCTAssertNil(store.cloudHistoryConfig())
    }

    func testCloudHistoryItemEncodesStableJSONFields() throws {
        let item = CloudHistoryItem(
            comicID: "comic-1",
            title: "Example Comic",
            author: "Example Author",
            thumbPath: "covers/comic-1.jpg",
            thumbServer: "https://cdn.invalid",
            lastReadAt: Date(timeIntervalSince1970: 1_710_000_000)
        )

        let encoded = try CloudHistoryJSON.encoder.encode(item)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])

        XCTAssertEqual(object["comicId"] as? String, "comic-1")
        XCTAssertEqual(object["title"] as? String, "Example Comic")
        XCTAssertEqual(object["author"] as? String, "Example Author")
        XCTAssertEqual(object["thumbPath"] as? String, "covers/comic-1.jpg")
        XCTAssertEqual(object["thumbServer"] as? String, "https://cdn.invalid")
        XCTAssertEqual(object["lastReadAt"] as? String, "2024-03-09T16:00:00Z")
    }

    func testFetchHistoryUsesGetEndpointAndBearerToken() async throws {
        let observedRequest = LockedValue<URLRequest?>(nil)
        let session = makeCloudHistorySession { request in
            observedRequest.value = request
            return MockHTTPResponse(
                statusCode: 200,
                headers: ["Content-Type": "application/json"],
                data: Data("""
                {
                  "items": [
                    {
                      "comicId": "comic-1",
                      "title": "Example Comic",
                      "author": "Example Author",
                      "thumbPath": "covers/comic-1.jpg",
                      "thumbServer": "https://cdn.invalid",
                      "lastReadAt": "2024-03-09T16:00:00Z"
                    }
                  ]
                }
                """.utf8)
            )
        }
        let client = CloudHistoryClient(config: try makeConfig(), session: session)

        let items = try await client.fetchHistory()

        let request = try XCTUnwrap(observedRequest.value)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.absoluteString, "https://history-sync.invalid/v1/history?limit=200")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer unit-test-token")
        XCTAssertNil(request.resolvedHTTPBodyData())
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.comicID, "comic-1")
        XCTAssertEqual(items.first?.thumbPath, "covers/comic-1.jpg")
    }

    func testConnectionUsesAuthorizedHistoryEndpoint() async throws {
        let observedRequest = LockedValue<URLRequest?>(nil)
        let session = makeCloudHistorySession { request in
            observedRequest.value = request
            return MockHTTPResponse(
                statusCode: 200,
                headers: ["Content-Type": "application/json"],
                data: Data("""
                {
                  "items": []
                }
                """.utf8)
            )
        }
        let client = CloudHistoryClient(config: try makeConfig(), session: session)

        try await client.testConnection()

        let request = try XCTUnwrap(observedRequest.value)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.absoluteString, "https://history-sync.invalid/v1/history?limit=1")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer unit-test-token")
        XCTAssertNil(request.resolvedHTTPBodyData())
    }

    func testUploadHistoryPostsBatchPayloadAndBearerToken() async throws {
        let observedRequest = LockedValue<URLRequest?>(nil)
        let session = makeCloudHistorySession { request in
            observedRequest.value = request
            return MockHTTPResponse(
                statusCode: 204,
                headers: [:],
                data: Data()
            )
        }
        let client = CloudHistoryClient(config: try makeConfig(), session: session)
        let item = CloudHistoryItem(
            comicID: "comic-2",
            title: "Second Comic",
            thumbPath: nil,
            thumbServer: nil,
            lastReadAt: Date(timeIntervalSince1970: 1_710_086_400)
        )

        try await client.uploadHistory([item])

        let request = try XCTUnwrap(observedRequest.value)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.absoluteString, "https://history-sync.invalid/v1/history/batch")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer unit-test-token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json; charset=utf-8")

        let bodyData = try XCTUnwrap(request.resolvedHTTPBodyData())
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
        let items = try XCTUnwrap(body["items"] as? [[String: Any]])
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?["comicId"] as? String, "comic-2")
        XCTAssertNil(items.first?["thumbPath"])
        XCTAssertNil(items.first?["thumbServer"])
    }

    private func makeConfig() throws -> CloudHistoryConfig {
        CloudHistoryConfig(
            baseURL: try XCTUnwrap(URL(string: "https://history-sync.invalid")),
            bearerToken: "unit-test-token",
            certificateSHA256Pins: [String(repeating: "c", count: 64)]
        )
    }

    private func makeCloudHistorySession(
        handler: @escaping MockURLProtocolHandler
    ) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        MockURLProtocol.reset()
        MockURLProtocol.requestHandler = handler
        return URLSession(configuration: configuration)
    }
}
