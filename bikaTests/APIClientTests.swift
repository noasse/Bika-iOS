import XCTest
@testable import bika

final class APIClientTests: XCTestCase {
    override func tearDown() {
        TestSupport.restoreLiveDependencies()
        super.tearDown()
    }

    func testSendDecodesSuccessfulResponse() async throws {
        let (client, store) = TestSupport.makeAPIClient { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "authorization"), "token-123")
            return TestSupport.jsonResponse(data: [
                "user": [
                    "_id": "user-1",
                    "name": "Tester",
                ],
            ])
        }
        _ = store
        try await client.tokenStore.setToken("token-123")

        let response: APIResponse<UserProfileData> = try await client.send(.myProfile())

        XCTAssertEqual(response.data?.user.name, "Tester")
    }

    func testSendThrowsBusinessErrorWhenResponseCodeIsFailure() async throws {
        let (client, store) = TestSupport.makeAPIClient { _ in
            TestSupport.jsonResponse(code: 500, message: "boom", data: [:])
        }
        _ = store

        do {
            let _: APIResponse<UserProfileData> = try await client.send(.myProfile())
            XCTFail("预期抛出业务错误")
        } catch let error as APIError {
            guard case .apiError(let code, let message) = error else {
                return XCTFail("错误类型不正确: \(error)")
            }

            XCTAssertEqual(code, 500)
            XCTAssertEqual(message, "boom")
        }
    }

    func testSendThrowsUnauthorizedOn401() async throws {
        let (client, store) = TestSupport.makeAPIClient { _ in
            TestSupport.emptyHTTPResponse(statusCode: 401)
        }
        _ = store

        do {
            let _: APIResponse<UserProfileData> = try await client.send(.myProfile())
            XCTFail("预期抛出未授权错误")
        } catch let error as APIError {
            guard case .unauthorized = error else {
                return XCTFail("错误类型不正确: \(error)")
            }
        }
    }

    func testSendThrowsUnauthorizedWhenBusinessCodeIs401() async throws {
        let (client, _) = TestSupport.makeAPIClient { _ in
            TestSupport.jsonResponse(code: 401, message: "expired", data: [:])
        }

        do {
            let _: APIResponse<UserProfileData> = try await client.send(.myProfile())
            XCTFail("业务 401 应抛出未授权错误")
        } catch let error as APIError {
            guard case .unauthorized = error else {
                return XCTFail("错误类型不正确: \(error)")
            }
        }
    }

    func testValidateBusinessResponseThrowsUnauthorizedWhenDecodedCodeIs401() async throws {
        let (client, _) = TestSupport.makeAPIClient { _ in
            MockHTTPResponse(
                statusCode: 200,
                headers: ["Content-Type": "application/json"],
                data: Data(#"{"code":"401","message":"expired"}"#.utf8)
            )
        }
        let endpoint = APIEndpoint<StringCodeBusinessResponse>(
            path: "business-code",
            requiresAuth: false
        )

        do {
            let _: StringCodeBusinessResponse = try await client.send(endpoint)
            XCTFail("解码后的业务 401 应抛出未授权错误")
        } catch let error as APIError {
            guard case .unauthorized = error else {
                return XCTFail("错误类型不正确: \(error)")
            }
        }
    }

    func testSendThrowsNoTokenBeforeSendingAuthenticatedRequest() async throws {
        let (client, _) = TestSupport.makeAPIClient { _ in
            XCTFail("无 token 时不应该发起请求")
            return TestSupport.jsonResponse(data: [:])
        }
        try await client.tokenStore.clear()

        do {
            let _: APIResponse<UserProfileData> = try await client.send(.myProfile())
            XCTFail("预期抛出无 token 错误")
        } catch let error as APIError {
            guard case .noToken = error else {
                return XCTFail("错误类型不正确: \(error)")
            }
        } catch {
            XCTFail("错误类型不正确: \(error)")
        }
    }

    func testSendUsesConfiguredImageQualityHeader() async throws {
        let observedImageQuality = LockedValue<String?>(nil)
        let (client, store) = TestSupport.makeAPIClient { request in
            observedImageQuality.value = request.value(forHTTPHeaderField: "image-quality")
            return TestSupport.jsonResponse(data: [
                "user": [
                    "_id": "user-1",
                    "name": "Tester",
                ],
            ])
        }
        store.set(ImageQuality.high.rawValue, forKey: APIConfig.imageQualityKey)
        AppDependencies.shared.installForTesting(apiClient: client, keyValueStore: store, imageDataLoader: FixtureImageDataLoader())

        let _: APIResponse<UserProfileData> = try await client.send(.myProfile())

        XCTAssertEqual(observedImageQuality.value, ImageQuality.high.rawValue)
    }

    func testSendThrowsDecodingErrorForInvalidPayload() async throws {
        let (client, store) = TestSupport.makeAPIClient { _ in
            MockHTTPResponse(
                statusCode: 200,
                headers: ["Content-Type": "application/json"],
                data: Data("{\"code\":200,\"message\":\"success\",\"data\":{\"user\":\"invalid\"}}".utf8)
            )
        }
        _ = store

        do {
            let _: APIResponse<UserProfileData> = try await client.send(.myProfile())
            XCTFail("预期抛出解码错误")
        } catch let error as APIError {
            guard case .decodingError = error else {
                return XCTFail("错误类型不正确: \(error)")
            }
        }
    }

    func testSecureTokenStoreMigratesLegacyTokenAndClearsUserDefaults() async throws {
        let legacyStore = InMemoryKeyValueStore()
        legacyStore.set("legacy-token", forKey: TokenStore.tokenKey)
        let keychain = TestKeychain()
        let secureStore = SecureTokenStore(
            service: "com.bika.tests.\(UUID().uuidString)",
            account: "auth-token",
            legacyStore: legacyStore,
            keychain: keychain
        )

        let tokenStore = TokenStore(secureStore: secureStore)
        let migratedToken = try await tokenStore.getToken()

        XCTAssertEqual(migratedToken, "legacy-token")
        XCTAssertNil(legacyStore.string(forKey: TokenStore.tokenKey))
    }

    func testSecureTokenStoreRetainsLegacyTokenWhenMigrationWriteFails() async {
        let legacyStore = InMemoryKeyValueStore()
        legacyStore.set("legacy-token", forKey: TokenStore.tokenKey)
        let keychain = TestKeychain(failWrites: true)
        let secureStore = SecureTokenStore(
            service: "com.bika.tests.migration-failure",
            account: "auth-token",
            legacyStore: legacyStore,
            keychain: keychain
        )
        let tokenStore = TokenStore(secureStore: secureStore)

        do {
            _ = try await tokenStore.getToken()
            XCTFail("Keychain 写入失败时应向调用方抛错")
        } catch {
            XCTAssertEqual(legacyStore.string(forKey: TokenStore.tokenKey), "legacy-token")
        }
    }

    func testTokenStoreDoesNotExposeNewTokenWhenWriteFails() async throws {
        let legacyStore = InMemoryKeyValueStore()
        let keychain = TestKeychain(token: "old-token")
        let secureStore = SecureTokenStore(
            service: "com.bika.tests.write-failure",
            account: "auth-token",
            legacyStore: legacyStore,
            keychain: keychain
        )
        let tokenStore = TokenStore(secureStore: secureStore)
        let initialToken = try await tokenStore.getToken()
        XCTAssertEqual(initialToken, "old-token")
        keychain.failWrites = true

        do {
            try await tokenStore.setToken("new-token")
            XCTFail("Keychain 写入失败时应向调用方抛错")
        } catch {
            // Expected storage failure.
        }

        let cachedToken = try await tokenStore.getToken()
        XCTAssertEqual(cachedToken, "old-token")
        XCTAssertEqual(keychain.token, "old-token")
    }

    func testClearFailureSuppressesStaleTokenAcrossSecureStoreRecreationAndRetriesDelete() async throws {
        let legacyStore = InMemoryKeyValueStore()
        let keychain = TestKeychain(token: "old-token", failDeletes: true)
        let service = "com.bika.tests.delete-failure"
        let account = "auth-token"
        let secureStore = SecureTokenStore(
            service: service,
            account: account,
            legacyStore: legacyStore,
            keychain: keychain
        )
        let tokenStore = TokenStore(secureStore: secureStore)
        let initialToken = try await tokenStore.getToken()
        XCTAssertEqual(initialToken, "old-token")

        do {
            try await tokenStore.clear()
            XCTFail("Keychain 删除失败时应向调用方抛错")
        } catch {
            // Expected storage failure after the in-memory logout.
        }

        let clearedToken = try await tokenStore.getToken()
        XCTAssertNil(clearedToken)
        XCTAssertEqual(keychain.deleteCallCount, 1)

        let rebuiltStore = SecureTokenStore(
            service: service,
            account: account,
            legacyStore: legacyStore,
            keychain: keychain
        )
        do {
            let staleToken = try rebuiltStore.token()
            XCTFail("suppression 生效时不得返回旧 token: \(String(describing: staleToken))")
        } catch {
            XCTAssertEqual(keychain.deleteCallCount, 2)
        }

        keychain.failDeletes = false
        XCTAssertNil(try rebuiltStore.token())
        XCTAssertEqual(keychain.deleteCallCount, 3)
        XCTAssertNil(keychain.token)
    }

    func testClearPersistsSuppressionBeforeRemovingLegacyToken() throws {
        let service = "com.bika.tests.clear-order"
        let account = "auth-token"
        let suppressionKey = "\(TokenStore.tokenKey).suppressed.\(service).\(account)"
        let legacyStore = RecordingKeyValueStore()
        legacyStore.set("legacy-token", forKey: TokenStore.tokenKey)
        legacyStore.resetMutationEvents()
        let keychain = TestKeychain(token: "old-token", failDeletes: true)
        let secureStore = SecureTokenStore(
            service: service,
            account: account,
            legacyStore: legacyStore,
            keychain: keychain
        )

        XCTAssertThrowsError(try secureStore.clearToken())

        let events = legacyStore.mutationEvents
        let suppressionIndex = try XCTUnwrap(events.firstIndex {
            if case .setString(let key, _) = $0 { return key == suppressionKey }
            return false
        })
        let legacyRemovalIndex = try XCTUnwrap(events.firstIndex {
            if case .remove(let key) = $0 { return key == TokenStore.tokenKey }
            return false
        })
        XCTAssertLessThan(suppressionIndex, legacyRemovalIndex)
    }

    func testCommittedReplacementSurvivesInterruptedSetTokenDuringSuppressionRecovery() throws {
        let service = "com.bika.tests.replacement-recovery"
        let account = "auth-token"
        let legacyStore = InMemoryKeyValueStore()
        let keychain = TestKeychain(token: "old-token", failDeletes: true)
        let secureStore = SecureTokenStore(
            service: service,
            account: account,
            legacyStore: legacyStore,
            keychain: keychain
        )

        XCTAssertThrowsError(try secureStore.clearToken())
        keychain.failDeletes = false
        keychain.commitWritesThenFail = true

        XCTAssertThrowsError(try secureStore.setToken("new-token"))
        XCTAssertEqual(keychain.token, "new-token")

        keychain.commitWritesThenFail = false
        let rebuiltStore = SecureTokenStore(
            service: service,
            account: account,
            legacyStore: legacyStore,
            keychain: keychain
        )

        XCTAssertEqual(try rebuiltStore.token(), "new-token")
        XCTAssertEqual(keychain.deleteCallCount, 1)
    }

    func testEndpointEncodesQuerySeparatorsInCategory() async throws {
        let observedRawQuery = LockedValue<String?>(nil)
        let (client, _) = TestSupport.makeAPIClient { request in
            observedRawQuery.value = request.url?.query
            XCTAssertEqual(TestSupport.queryValue(named: "c", from: request), "A&B= C")
            XCTAssertNil(TestSupport.queryValue(named: "B", from: request))
            return TestSupport.jsonResponse(data: [
                "comics": [
                    "docs": [],
                    "total": 0,
                    "limit": 20,
                    "page": 1,
                    "pages": 1,
                ],
            ])
        }

        let _: APIResponse<ComicsData> = try await client.send(.comics(category: "A&B= C", page: 1))

        XCTAssertTrue(observedRawQuery.value?.contains("c=A%26B%3D%20C") == true)
    }
}

private nonisolated enum TestKeychainError: Error {
    case readFailed
    case writeFailed
    case deleteFailed
}

private nonisolated struct StringCodeBusinessResponse: Decodable, Sendable, APIBusinessResponse {
    let code: Int
    let message: String

    private enum CodingKeys: String, CodingKey {
        case code
        case message
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let stringCode = try container.decode(String.self, forKey: .code)
        code = Int(stringCode) ?? -1
        message = try container.decode(String.self, forKey: .message)
    }
}

private final nonisolated class TestKeychain: @unchecked Sendable, KeychainAccessing {
    private let lock = NSLock()
    private var storedData: Data?
    private var shouldFailReads: Bool
    private var shouldFailWrites: Bool
    private var shouldCommitWritesThenFail = false
    private var shouldFailDeletes: Bool
    private var deleteCalls = 0

    init(
        token: String? = nil,
        failReads: Bool = false,
        failWrites: Bool = false,
        failDeletes: Bool = false
    ) {
        storedData = token.map { Data($0.utf8) }
        shouldFailReads = failReads
        shouldFailWrites = failWrites
        shouldFailDeletes = failDeletes
    }

    var token: String? {
        lock.withLock { storedData.flatMap { String(data: $0, encoding: .utf8) } }
    }

    var deleteCallCount: Int {
        lock.withLock { deleteCalls }
    }

    var failWrites: Bool {
        get { lock.withLock { shouldFailWrites } }
        set { lock.withLock { shouldFailWrites = newValue } }
    }

    var failDeletes: Bool {
        get { lock.withLock { shouldFailDeletes } }
        set { lock.withLock { shouldFailDeletes = newValue } }
    }

    var commitWritesThenFail: Bool {
        get { lock.withLock { shouldCommitWritesThenFail } }
        set { lock.withLock { shouldCommitWritesThenFail = newValue } }
    }

    func read(service: String, account: String) throws -> Data? {
        try lock.withLock {
            if shouldFailReads { throw TestKeychainError.readFailed }
            return storedData
        }
    }

    func write(_ data: Data, service: String, account: String) throws {
        try lock.withLock {
            if shouldFailWrites { throw TestKeychainError.writeFailed }
            storedData = data
            if shouldCommitWritesThenFail { throw TestKeychainError.writeFailed }
        }
    }

    func delete(service: String, account: String) throws {
        try lock.withLock {
            deleteCalls += 1
            if shouldFailDeletes { throw TestKeychainError.deleteFailed }
            storedData = nil
        }
    }
}

private final nonisolated class RecordingKeyValueStore: @unchecked Sendable, KeyValueStore {
    nonisolated enum Mutation: Equatable {
        case setString(key: String, value: String?)
        case remove(key: String)
    }

    private let backingStore = InMemoryKeyValueStore()
    private let lock = NSLock()
    private var events: [Mutation] = []

    var mutationEvents: [Mutation] {
        lock.withLock { events }
    }

    func resetMutationEvents() {
        lock.withLock { events.removeAll() }
    }

    func string(forKey key: String) -> String? { backingStore.string(forKey: key) }
    func integer(forKey key: String) -> Int { backingStore.integer(forKey: key) }
    func data(forKey key: String) -> Data? { backingStore.data(forKey: key) }
    func stringArray(forKey key: String) -> [String]? { backingStore.stringArray(forKey: key) }

    func set(_ value: String?, forKey key: String) {
        lock.withLock { events.append(.setString(key: key, value: value)) }
        backingStore.set(value, forKey: key)
    }

    func set(_ value: Int, forKey key: String) { backingStore.set(value, forKey: key) }
    func set(_ value: Data?, forKey key: String) { backingStore.set(value, forKey: key) }
    func set(_ value: [String]?, forKey key: String) { backingStore.set(value, forKey: key) }

    func removeObject(forKey key: String) {
        lock.withLock { events.append(.remove(key: key)) }
        backingStore.removeObject(forKey: key)
    }

    func keys(withPrefix prefix: String) -> [String] { backingStore.keys(withPrefix: prefix) }
    func resetPersistentState() { backingStore.resetPersistentState() }
}
