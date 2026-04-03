import XCTest
@testable import bika

@MainActor
final class AuthViewModelTests: XCTestCase {
    override func tearDown() {
        TestSupport.restoreLiveDependencies()
        super.tearDown()
    }

    func testLoginAuthenticatesAndPersistsToken() async {
        let (client, store) = TestSupport.makeAPIClient { request in
            XCTAssertEqual(request.url?.path, "/auth/sign-in")
            return TestSupport.jsonResponse(data: [
                "token": "token-abc",
            ])
        }

        let viewModel = AuthViewModel(client: client)
        await viewModel.login(email: "tester@example.com", password: "secret")
        let token = await client.tokenStore.getToken()

        XCTAssertTrue(viewModel.isAuthenticated)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(token, "token-abc")
        XCTAssertEqual(store.string(forKey: TokenStore.tokenKey), "token-abc")
    }

    func testLogoutClearsTokenAndAuthenticationState() async {
        let (client, store) = TestSupport.makeAPIClient { _ in
            TestSupport.jsonResponse(data: [:])
        }
        await client.tokenStore.setToken("token-123")

        let viewModel = AuthViewModel(client: client)
        viewModel.isAuthenticated = true

        await viewModel.logout()
        let token = await client.tokenStore.getToken()

        XCTAssertFalse(viewModel.isAuthenticated)
        XCTAssertNil(token)
        XCTAssertNil(store.string(forKey: TokenStore.tokenKey))
    }

    func testCheckTokenFallsBackToLoggedOutWhenValidationFails() async {
        let (client, store) = TestSupport.makeAPIClient { request in
            XCTAssertEqual(request.url?.path, "/users/profile")
            return TestSupport.emptyHTTPResponse(statusCode: 401)
        }
        await client.tokenStore.setToken("expired-token")

        let viewModel = AuthViewModel(client: client)
        await viewModel.checkToken()
        let token = await client.tokenStore.getToken()

        XCTAssertFalse(viewModel.isAuthenticated)
        XCTAssertFalse(viewModel.isCheckingToken)
        XCTAssertNil(token)
        XCTAssertNil(store.string(forKey: TokenStore.tokenKey))
    }
}
