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
        await client.tokenStore.setToken("token-123")

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

    func testSendThrowsNoTokenBeforeSendingAuthenticatedRequest() async {
        let (client, _) = TestSupport.makeAPIClient { _ in
            XCTFail("无 token 时不应该发起请求")
            return TestSupport.jsonResponse(data: [:])
        }
        await client.tokenStore.clear()

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

    func testSecureTokenStoreMigratesLegacyTokenAndClearsUserDefaults() async {
        let legacyStore = InMemoryKeyValueStore()
        legacyStore.set("legacy-token", forKey: TokenStore.tokenKey)
        let secureStore = SecureTokenStore(
            service: "com.bika.tests.\(UUID().uuidString)",
            account: "auth-token",
            legacyStore: legacyStore
        )
        defer { secureStore.clearToken() }

        let tokenStore = TokenStore(secureStore: secureStore)
        let migratedToken = await tokenStore.getToken()

        XCTAssertEqual(migratedToken, "legacy-token")
        XCTAssertNil(legacyStore.string(forKey: TokenStore.tokenKey))
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
