import XCTest
@testable import bika

@MainActor
final class AuthSessionTests: XCTestCase {
    override func tearDown() {
        TestSupport.restoreLiveDependencies()
        super.tearDown()
    }

    func testTransientProfileValidationFailureKeepsPersistedAccountSessionAndToken() async throws {
        let (client, store) = TestSupport.makeAPIClient { request in
            XCTAssertEqual(request.url?.path, "/users/profile")
            throw URLError(.timedOut)
        }
        try await client.tokenStore.setToken("persisted-token")
        let accountSession = AccountSessionStore(keyValueStore: store)
        let expectedScope = try accountSession.activate(userID: "user-a")
        let viewModel = AuthViewModel(
            client: client,
            accountSessionStore: accountSession
        )

        await viewModel.checkToken()

        let storedToken = try await client.tokenStore.getToken()
        XCTAssertTrue(viewModel.isAuthenticated)
        XCTAssertEqual(accountSession.currentScope, expectedScope)
        XCTAssertEqual(storedToken, "persisted-token")
        XCTAssertNotNil(viewModel.errorMessage)
    }

    func testUnauthorizedProfileValidationClearsTokenAndAccountScope() async throws {
        let (client, store) = TestSupport.makeAPIClient { _ in
            TestSupport.emptyHTTPResponse(statusCode: 401)
        }
        try await client.tokenStore.setToken("expired-token")
        let accountSession = AccountSessionStore(keyValueStore: store)
        _ = try accountSession.activate(userID: "user-a")
        let viewModel = AuthViewModel(
            client: client,
            accountSessionStore: accountSession
        )

        await viewModel.checkToken()

        let storedToken = try await client.tokenStore.getToken()
        XCTAssertFalse(viewModel.isAuthenticated)
        XCTAssertNil(accountSession.currentScope)
        XCTAssertNil(storedToken)
    }

    func testLoginFetchesProfileAndActivatesAccountScopeBeforeAuthentication() async throws {
        let (client, store) = TestSupport.makeAPIClient { request in
            switch request.url?.path {
            case "/auth/sign-in":
                return TestSupport.jsonResponse(data: ["token": "new-token"])
            case "/users/profile":
                return TestSupport.jsonResponse(data: [
                    "user": ["_id": "user-a", "name": "Tester"],
                ])
            default:
                throw MockURLProtocolError.unsupportedScenario
            }
        }
        let accountSession = AccountSessionStore(keyValueStore: store)
        let viewModel = AuthViewModel(
            client: client,
            accountSessionStore: accountSession
        )

        await viewModel.login(email: "tester@example.com", password: "secret")

        let storedToken = try await client.tokenStore.getToken()
        XCTAssertTrue(viewModel.isAuthenticated)
        XCTAssertEqual(
            accountSession.currentScope?.rawValue,
            "0ab53791e40459dc23b75503be485a9d368df901e00ab4a053d9b33b225a7e53"
        )
        XCTAssertEqual(storedToken, "new-token")
    }

    func testTransientProfileFailureAfterLoginRetainsTokenAndCanRetryWithoutPassword() async throws {
        let profileAttempts = LockedValue(0)
        let (client, store) = TestSupport.makeAPIClient { request in
            switch request.url?.path {
            case "/auth/sign-in":
                return TestSupport.jsonResponse(data: ["token": "new-token"])
            case "/users/profile":
                let attempt = profileAttempts.value
                profileAttempts.value = attempt + 1
                if attempt == 0 {
                    throw URLError(.networkConnectionLost)
                }
                return TestSupport.jsonResponse(data: [
                    "user": ["_id": "user-a", "name": "Tester"],
                ])
            default:
                throw MockURLProtocolError.unsupportedScenario
            }
        }
        let accountSession = AccountSessionStore(keyValueStore: store)
        let viewModel = AuthViewModel(
            client: client,
            accountSessionStore: accountSession
        )

        await viewModel.login(email: "tester@example.com", password: "secret")
        let storedTokenAfterLogin = try await client.tokenStore.getToken()
        XCTAssertFalse(viewModel.isAuthenticated)
        XCTAssertTrue(viewModel.requiresProfileValidation)
        XCTAssertEqual(storedTokenAfterLogin, "new-token")

        await viewModel.retryProfileValidation()

        XCTAssertTrue(viewModel.isAuthenticated)
        XCTAssertFalse(viewModel.requiresProfileValidation)
        XCTAssertNotNil(accountSession.currentScope)
        XCTAssertEqual(profileAttempts.value, 2)
    }

    func testProfileWithoutUserIDDoesNotExposeAccountHistory() async throws {
        let (client, store) = TestSupport.makeAPIClient { request in
            switch request.url?.path {
            case "/auth/sign-in":
                return TestSupport.jsonResponse(data: ["token": "new-token"])
            case "/users/profile":
                return TestSupport.jsonResponse(data: [
                    "user": ["name": "Missing ID"],
                ])
            default:
                throw MockURLProtocolError.unsupportedScenario
            }
        }
        let accountSession = AccountSessionStore(keyValueStore: store)
        let viewModel = AuthViewModel(
            client: client,
            accountSessionStore: accountSession
        )

        await viewModel.login(email: "tester@example.com", password: "secret")

        let storedToken = try await client.tokenStore.getToken()
        XCTAssertFalse(viewModel.isAuthenticated)
        XCTAssertTrue(viewModel.requiresProfileValidation)
        XCTAssertNil(accountSession.currentScope)
        XCTAssertEqual(storedToken, "new-token")
    }

    func testPersistedAccountSessionStopsExposingHistoryWhenProfileHasNoUserID() async throws {
        let (client, store) = TestSupport.makeAPIClient { request in
            XCTAssertEqual(request.url?.path, "/users/profile")
            return TestSupport.jsonResponse(data: [
                "user": ["name": "Missing ID"],
            ])
        }
        try await client.tokenStore.setToken("persisted-token")
        let accountSession = AccountSessionStore(keyValueStore: store)
        let oldScope = try accountSession.activate(userID: "user-a")
        let oldHistory = [
            ReadingHistoryManager.HistoryItem(
                comicId: "old-account-comic",
                title: "旧账号记录",
                thumbPath: "old.jpg",
                thumbServer: nil,
                author: nil,
                lastReadDate: Date(),
                episodeOrder: 1,
                episodeTitle: "第一话",
                pageIndex: 3
            ),
        ]
        let historyKey = "readingHistory.account.\(oldScope.rawValue)"
        store.set(
            try JSONEncoder().encode(PersistenceEnvelope(payload: oldHistory)),
            forKey: historyKey
        )
        let viewModel = AuthViewModel(
            client: client,
            accountSessionStore: accountSession
        )

        await viewModel.checkToken()

        let storedToken = try await client.tokenStore.getToken()
        XCTAssertFalse(viewModel.isAuthenticated)
        XCTAssertTrue(viewModel.requiresProfileValidation)
        XCTAssertNil(accountSession.currentScope)
        XCTAssertEqual(storedToken, "persisted-token")
        XCTAssertNotNil(viewModel.errorMessage)
        let historyManager = ReadingHistoryManager(
            keyValueStore: store,
            accountSessionStore: accountSession
        )
        XCTAssertTrue(historyManager.items.isEmpty)
        XCTAssertNotNil(store.data(forKey: historyKey), "旧账号数据应保留，只是不再暴露")
    }

    func testLogoutInvalidatesInFlightProfileValidation() async throws {
        let profileStarted = expectation(description: "profile validation started")
        let profileGate = TestAsyncGate()
        let (client, store) = TestSupport.makeAPIClient { request in
            XCTAssertEqual(request.url?.path, "/users/profile")
            profileStarted.fulfill()
            await profileGate.wait()
            return TestSupport.jsonResponse(data: [
                "user": ["_id": "user-a", "name": "Old User"],
            ])
        }
        try await client.tokenStore.setToken("persisted-token")
        let accountSession = AccountSessionStore(keyValueStore: store)
        _ = try accountSession.activate(userID: "user-a")
        let viewModel = AuthViewModel(
            client: client,
            accountSessionStore: accountSession
        )

        let validationTask = Task { await viewModel.checkToken() }
        await fulfillment(of: [profileStarted], timeout: 1)

        await viewModel.logout()
        XCTAssertFalse(viewModel.isAuthenticated)
        XCTAssertFalse(viewModel.isCheckingToken)
        XCTAssertNil(accountSession.currentScope)

        await profileGate.open()
        await validationTask.value

        let storedToken = try await client.tokenStore.getToken()
        XCTAssertFalse(viewModel.isAuthenticated)
        XCTAssertNil(accountSession.currentScope)
        XCTAssertNil(storedToken)
    }

    func testSuccessfulLogoutClearsStaleAuthenticationError() async {
        let (client, store) = TestSupport.makeAPIClient { _ in
            throw MockURLProtocolError.unsupportedScenario
        }
        let accountSession = AccountSessionStore(keyValueStore: store)
        let viewModel = AuthViewModel(
            client: client,
            accountSessionStore: accountSession
        )
        viewModel.errorMessage = "stale validation error"

        await viewModel.logout()

        XCTAssertNil(viewModel.errorMessage)
    }

    func testLogoutSuppressesTokenFromLateSignInResponse() async throws {
        let signInStarted = expectation(description: "sign in started")
        let signInGate = TestAsyncGate()
        let profileRequests = LockedValue(0)
        let (client, store) = TestSupport.makeAPIClient { request in
            switch request.url?.path {
            case "/auth/sign-in":
                signInStarted.fulfill()
                await signInGate.wait()
                return TestSupport.jsonResponse(data: ["token": "late-token"])
            case "/users/profile":
                profileRequests.value += 1
                return TestSupport.jsonResponse(data: [
                    "user": ["_id": "late-user", "name": "Late User"],
                ])
            default:
                throw MockURLProtocolError.unsupportedScenario
            }
        }
        let accountSession = AccountSessionStore(keyValueStore: store)
        let viewModel = AuthViewModel(
            client: client,
            accountSessionStore: accountSession
        )

        let loginTask = Task {
            await viewModel.login(email: "late@example.com", password: "secret")
        }
        await fulfillment(of: [signInStarted], timeout: 1)

        await viewModel.logout()
        await signInGate.open()
        await loginTask.value

        let storedToken = try await client.tokenStore.getToken()
        XCTAssertNil(storedToken)
        XCTAssertFalse(viewModel.isAuthenticated)
        XCTAssertNil(accountSession.currentScope)
        XCTAssertEqual(profileRequests.value, 0)
    }
}
