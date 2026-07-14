import XCTest
@testable import BikaMacos

@MainActor
final class MacAuthenticationSessionTests: XCTestCase {
    override func tearDown() {
        MacTestSupport.restoreLiveDependencies()
        super.tearDown()
    }

    func testMacTransientProfileFailureKeepsPersistedScopeAndToken() async throws {
        let (client, store) = MacTestSupport.makeAPIClient { _ in
            throw URLError(.timedOut)
        }
        try await client.tokenStore.setToken("persisted-token")
        let accountSession = AccountSessionStore(keyValueStore: store)
        let expectedScope = try accountSession.activate(userID: "mac-user")
        let readingStore = MacReadingStore(
            keyValueStore: store,
            accountSessionStore: accountSession
        )
        let model = MacLibraryModel(
            client: client,
            readingStore: readingStore,
            blockedCategoriesStore: MacBlockedCategoriesStore(keyValueStore: store),
            accountSessionStore: accountSession
        )

        await model.checkTokenIfNeeded()
        let storedToken = try await client.tokenStore.getToken()

        XCTAssertTrue(model.isAuthenticated)
        XCTAssertEqual(accountSession.currentScope, expectedScope)
        XCTAssertEqual(storedToken, "persisted-token")
        XCTAssertNotNil(model.authError)
    }

    func testMacLoginActivatesScopeOnlyAfterProfileValidation() async throws {
        let (client, store) = MacTestSupport.makeAPIClient { request in
            switch request.url?.path {
            case "/auth/sign-in":
                return MacTestSupport.jsonResponse(data: ["token": "new-token"])
            case "/users/profile":
                return MacTestSupport.jsonResponse(data: [
                    "user": ["_id": "mac-user", "name": "Mac Tester"],
                ])
            case "/categories":
                return MacTestSupport.jsonResponse(data: ["categories": []])
            default:
                throw MockURLProtocolError.unsupportedScenario
            }
        }
        let accountSession = AccountSessionStore(keyValueStore: store)
        let model = MacLibraryModel(
            client: client,
            readingStore: MacReadingStore(
                keyValueStore: store,
                accountSessionStore: accountSession
            ),
            blockedCategoriesStore: MacBlockedCategoriesStore(keyValueStore: store),
            accountSessionStore: accountSession
        )

        await model.login(email: "tester@example.com", password: "secret")

        XCTAssertTrue(model.isAuthenticated)
        XCTAssertNotNil(accountSession.currentScope)
        XCTAssertEqual(model.userProfile?.id, "mac-user")
    }

    func testMacProfileRetryUsesStoredTokenWithoutNewSignIn() async throws {
        let profileAttempts = LockedValue(0)
        let signInAttempts = LockedValue(0)
        let (client, store) = MacTestSupport.makeAPIClient { request in
            switch request.url?.path {
            case "/auth/sign-in":
                signInAttempts.value += 1
                return MacTestSupport.jsonResponse(data: ["token": "new-token"])
            case "/users/profile":
                let attempt = profileAttempts.value
                profileAttempts.value = attempt + 1
                if attempt == 0 {
                    throw URLError(.networkConnectionLost)
                }
                return MacTestSupport.jsonResponse(data: [
                    "user": ["_id": "mac-user", "name": "Mac Tester"],
                ])
            case "/categories":
                return MacTestSupport.jsonResponse(data: ["categories": []])
            default:
                throw MockURLProtocolError.unsupportedScenario
            }
        }
        let accountSession = AccountSessionStore(keyValueStore: store)
        let model = MacLibraryModel(
            client: client,
            readingStore: MacReadingStore(
                keyValueStore: store,
                accountSessionStore: accountSession
            ),
            blockedCategoriesStore: MacBlockedCategoriesStore(keyValueStore: store),
            accountSessionStore: accountSession
        )

        await model.login(email: "tester@example.com", password: "secret")
        XCTAssertTrue(model.requiresProfileValidation)
        XCTAssertFalse(model.isAuthenticated)

        await model.retryProfileValidation()

        XCTAssertTrue(model.isAuthenticated)
        XCTAssertFalse(model.requiresProfileValidation)
        XCTAssertEqual(signInAttempts.value, 1)
        XCTAssertEqual(profileAttempts.value, 2)
    }

    func testMacPersistedAccountSessionStopsExposingHistoryWhenProfileHasNoUserID() async throws {
        let (client, store) = MacTestSupport.makeAPIClient { request in
            XCTAssertEqual(request.url?.path, "/users/profile")
            return MacTestSupport.jsonResponse(data: [
                "user": ["name": "Missing ID"],
            ])
        }
        try await client.tokenStore.setToken("persisted-token")
        let accountSession = AccountSessionStore(keyValueStore: store)
        let oldScope = try accountSession.activate(userID: "mac-user")
        let historyKey = "macReadingHistory.account.\(oldScope.rawValue)"
        let oldHistory = [
            MacHistoryItem(
                comicId: "old-account-comic",
                title: "旧账号记录",
                author: nil,
                thumbPath: "old.jpg",
                thumbServer: nil,
                episodeOrder: 1,
                episodeTitle: "第一话",
                pageIndex: 3,
                updatedAt: Date()
            ),
        ]
        store.set(
            try JSONEncoder().encode(PersistenceEnvelope(payload: oldHistory)),
            forKey: historyKey
        )
        let readingStore = MacReadingStore(
            keyValueStore: store,
            accountSessionStore: accountSession
        )
        let model = MacLibraryModel(
            client: client,
            readingStore: readingStore,
            blockedCategoriesStore: MacBlockedCategoriesStore(keyValueStore: store),
            accountSessionStore: accountSession
        )

        await model.checkTokenIfNeeded()

        let storedToken = try await client.tokenStore.getToken()
        XCTAssertFalse(model.isAuthenticated)
        XCTAssertTrue(model.requiresProfileValidation)
        XCTAssertNil(accountSession.currentScope)
        XCTAssertEqual(storedToken, "persisted-token")
        XCTAssertNotNil(model.authError)
        XCTAssertTrue(readingStore.history.isEmpty)
        XCTAssertNotNil(store.data(forKey: historyKey), "旧账号数据应保留，只是不再暴露")
    }

    func testMacLogoutInvalidatesInFlightProfileValidation() async throws {
        let profileStarted = expectation(description: "profile validation started")
        let profileGate = TestAsyncGate()
        let (client, store) = MacTestSupport.makeAPIClient { request in
            XCTAssertEqual(request.url?.path, "/users/profile")
            profileStarted.fulfill()
            await profileGate.wait()
            return MacTestSupport.jsonResponse(data: [
                "user": ["_id": "mac-user", "name": "Old User"],
            ])
        }
        try await client.tokenStore.setToken("persisted-token")
        let accountSession = AccountSessionStore(keyValueStore: store)
        _ = try accountSession.activate(userID: "mac-user")
        let model = MacLibraryModel(
            client: client,
            readingStore: MacReadingStore(
                keyValueStore: store,
                accountSessionStore: accountSession
            ),
            blockedCategoriesStore: MacBlockedCategoriesStore(keyValueStore: store),
            accountSessionStore: accountSession
        )

        let validationTask = Task { await model.checkTokenIfNeeded() }
        await fulfillment(of: [profileStarted], timeout: 1)

        await model.logout()
        XCTAssertFalse(model.isAuthenticated)
        XCTAssertFalse(model.isCheckingToken)
        XCTAssertNil(accountSession.currentScope)

        await profileGate.open()
        await validationTask.value

        let storedToken = try await client.tokenStore.getToken()
        XCTAssertFalse(model.isAuthenticated)
        XCTAssertNil(accountSession.currentScope)
        XCTAssertNil(storedToken)
    }

    func testMacSuccessfulLogoutClearsStaleAuthenticationError() async {
        let (client, store) = MacTestSupport.makeAPIClient { _ in
            throw MockURLProtocolError.unsupportedScenario
        }
        let accountSession = AccountSessionStore(keyValueStore: store)
        let model = MacLibraryModel(
            client: client,
            readingStore: MacReadingStore(
                keyValueStore: store,
                accountSessionStore: accountSession
            ),
            blockedCategoriesStore: MacBlockedCategoriesStore(keyValueStore: store),
            accountSessionStore: accountSession
        )
        model.authError = "stale validation error"

        await model.logout()

        XCTAssertNil(model.authError)
    }

    func testMacLogoutSuppressesTokenFromLateSignInResponse() async throws {
        let signInStarted = expectation(description: "sign in started")
        let signInGate = TestAsyncGate()
        let profileRequests = LockedValue(0)
        let (client, store) = MacTestSupport.makeAPIClient { request in
            switch request.url?.path {
            case "/auth/sign-in":
                signInStarted.fulfill()
                await signInGate.wait()
                return MacTestSupport.jsonResponse(data: ["token": "late-token"])
            case "/users/profile":
                profileRequests.value += 1
                return MacTestSupport.jsonResponse(data: [
                    "user": ["_id": "late-user", "name": "Late User"],
                ])
            case "/categories":
                return MacTestSupport.jsonResponse(data: ["categories": []])
            default:
                throw MockURLProtocolError.unsupportedScenario
            }
        }
        let accountSession = AccountSessionStore(keyValueStore: store)
        let model = MacLibraryModel(
            client: client,
            readingStore: MacReadingStore(
                keyValueStore: store,
                accountSessionStore: accountSession
            ),
            blockedCategoriesStore: MacBlockedCategoriesStore(keyValueStore: store),
            accountSessionStore: accountSession
        )

        let loginTask = Task {
            await model.login(email: "late@example.com", password: "secret")
        }
        await fulfillment(of: [signInStarted], timeout: 1)

        await model.logout()
        await signInGate.open()
        await loginTask.value

        let storedToken = try await client.tokenStore.getToken()
        XCTAssertNil(storedToken)
        XCTAssertFalse(model.isAuthenticated)
        XCTAssertNil(accountSession.currentScope)
        XCTAssertEqual(profileRequests.value, 0)
    }
}
