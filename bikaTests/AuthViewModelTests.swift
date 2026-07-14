import XCTest
@testable import bika

@MainActor
final class AuthViewModelTests: XCTestCase {
    override func tearDown() {
        TestSupport.restoreLiveDependencies()
        super.tearDown()
    }

    func testLoginAuthenticatesAndPersistsToken() async throws {
        let (client, store) = TestSupport.makeAPIClient { request in
            switch request.url?.path {
            case "/auth/sign-in":
                return TestSupport.jsonResponse(data: ["token": "token-abc"])
            case "/users/profile":
                return TestSupport.jsonResponse(data: [
                    "user": ["_id": "user-1", "name": "Tester"],
                ])
            default:
                throw MockURLProtocolError.unsupportedScenario
            }
        }
        let accountSession = AccountSessionStore(keyValueStore: store)

        let viewModel = AuthViewModel(client: client, accountSessionStore: accountSession)
        await viewModel.login(email: "tester@example.com", password: "secret")
        let token = try await client.tokenStore.getToken()

        XCTAssertTrue(viewModel.isAuthenticated)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(token, "token-abc")
        XCTAssertEqual(store.string(forKey: TokenStore.tokenKey), "token-abc")
    }

    func testLogoutClearsTokenAndAuthenticationState() async throws {
        let (client, store) = TestSupport.makeAPIClient { _ in
            TestSupport.jsonResponse(data: [:])
        }
        try await client.tokenStore.setToken("token-123")
        let accountSession = AccountSessionStore(keyValueStore: store)
        _ = try accountSession.activate(userID: "user-1")

        let viewModel = AuthViewModel(client: client, accountSessionStore: accountSession)
        viewModel.isAuthenticated = true

        await viewModel.logout()
        let token = try await client.tokenStore.getToken()

        XCTAssertFalse(viewModel.isAuthenticated)
        XCTAssertNil(accountSession.currentScope)
        XCTAssertNil(token)
        XCTAssertNil(store.string(forKey: TokenStore.tokenKey))
    }

    func testCheckTokenFallsBackToLoggedOutWhenValidationFails() async throws {
        let (client, store) = TestSupport.makeAPIClient { request in
            XCTAssertEqual(request.url?.path, "/users/profile")
            return TestSupport.emptyHTTPResponse(statusCode: 401)
        }
        try await client.tokenStore.setToken("expired-token")
        let accountSession = AccountSessionStore(keyValueStore: store)
        _ = try accountSession.activate(userID: "user-1")

        let viewModel = AuthViewModel(client: client, accountSessionStore: accountSession)
        await viewModel.checkToken()
        let token = try await client.tokenStore.getToken()

        XCTAssertFalse(viewModel.isAuthenticated)
        XCTAssertFalse(viewModel.isCheckingToken)
        XCTAssertNil(accountSession.currentScope)
        XCTAssertNil(token)
        XCTAssertNil(store.string(forKey: TokenStore.tokenKey))
    }
}
