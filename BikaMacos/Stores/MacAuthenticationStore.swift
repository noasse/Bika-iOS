import Foundation
import SwiftUI

@MainActor
@Observable
final class MacAuthenticationStore {
    var isCheckingToken = true
    var isAuthenticated = false
    var authError: String?
    var isAuthenticating = false
    var requiresProfileValidation = false
    var userProfile: UserProfile?
    var isPunching = false

    let client: any APIClientProtocol
    let accountSessionStore: AccountSessionStore

    private var didCheckToken = false
    private var activeAuthenticationGeneration = 0

    init(
        client: any APIClientProtocol,
        accountSessionStore: AccountSessionStore
    ) {
        self.client = client
        self.accountSessionStore = accountSessionStore
    }

    func checkTokenIfNeeded(
        onAuthenticated: @escaping @MainActor () async -> Void
    ) async {
        guard !didCheckToken else { return }
        didCheckToken = true
        let operationID = beginAuthenticationOperation()
        isCheckingToken = true
        authError = nil
        defer {
            if isCurrentAuthenticationOperation(operationID) {
                isCheckingToken = false
            }
        }

        let hasStoredToken: Bool
        do {
            hasStoredToken = try await client.tokenStore.getToken() != nil
        } catch {
            guard isCurrentAuthenticationOperation(operationID) else { return }
            authError = error.localizedDescription
            isAuthenticated = false
            requiresProfileValidation = true
            return
        }

        guard isCurrentAuthenticationOperation(operationID) else { return }
        guard hasStoredToken else {
            accountSessionStore.deactivate()
            isAuthenticated = false
            requiresProfileValidation = false
            return
        }

        let hasPersistedScope = accountSessionStore.currentScope != nil
        isAuthenticated = hasPersistedScope
        await validateProfile(
            keepExistingSessionOnTransientFailure: hasPersistedScope,
            operationID: operationID,
            onAuthenticated: onAuthenticated
        )
    }

    func login(
        email: String,
        password: String,
        onAuthenticated: @escaping @MainActor () async -> Void
    ) async {
        let operationID = beginAuthenticationOperation()
        isCheckingToken = false
        isAuthenticating = true
        authError = nil
        requiresProfileValidation = false
        accountSessionStore.deactivate()
        defer {
            if isCurrentAuthenticationOperation(operationID) {
                isAuthenticating = false
            }
        }

        do {
            let token = try await client.requestSignInToken(email: email, password: password)
            guard isCurrentAuthenticationOperation(operationID) else { return }
            try await client.tokenStore.setToken(token)
            guard isCurrentAuthenticationOperation(operationID) else { return }
            await validateProfile(
                keepExistingSessionOnTransientFailure: false,
                operationID: operationID,
                onAuthenticated: onAuthenticated
            )
        } catch {
            guard isCurrentAuthenticationOperation(operationID) else { return }
            authError = error.localizedDescription
            isAuthenticated = false
        }
    }

    func retryProfileValidation(
        onAuthenticated: @escaping @MainActor () async -> Void
    ) async {
        guard !isAuthenticating else { return }
        let operationID = beginAuthenticationOperation()
        isCheckingToken = false
        isAuthenticating = true
        authError = nil
        defer {
            if isCurrentAuthenticationOperation(operationID) {
                isAuthenticating = false
            }
        }

        do {
            let hasStoredToken = try await client.tokenStore.getToken() != nil
            guard isCurrentAuthenticationOperation(operationID) else { return }
            guard hasStoredToken else {
                accountSessionStore.deactivate()
                isAuthenticated = false
                requiresProfileValidation = false
                authError = APIError.noToken.localizedDescription
                return
            }
            await validateProfile(
                keepExistingSessionOnTransientFailure: accountSessionStore.currentScope != nil,
                operationID: operationID,
                onAuthenticated: onAuthenticated
            )
        } catch {
            guard isCurrentAuthenticationOperation(operationID) else { return }
            isAuthenticated = false
            requiresProfileValidation = true
            authError = error.localizedDescription
        }
    }

    func logout() async {
        let operationID = beginAuthenticationOperation()
        isAuthenticated = false
        isAuthenticating = false
        isCheckingToken = false
        requiresProfileValidation = false
        userProfile = nil
        authError = nil
        accountSessionStore.deactivate()
        do {
            try await client.tokenStore.clear()
        } catch {
            guard isCurrentAuthenticationOperation(operationID) else { return }
            authError = error.localizedDescription
        }
    }

    func fetchProfile() async throws -> UserProfile? {
        let response: APIResponse<UserProfileData> = try await client.send(.myProfile())
        return response.data?.user
    }

    func applyProfile(_ profile: UserProfile?) {
        userProfile = profile
    }

    func punchIn() async throws -> Bool {
        guard !isPunching else { return false }
        isPunching = true
        defer { isPunching = false }

        let _: APIResponse<EmptyData> = try await client.send(.punchIn())
        return true
    }

    func updateSlogan(_ slogan: String) async throws {
        let trimmedSlogan = slogan.trimmingCharacters(in: .whitespacesAndNewlines)
        let _: APIResponse<EmptyData> = try await client.send(.setSlogan(trimmedSlogan))
    }

    private func validateProfile(
        keepExistingSessionOnTransientFailure: Bool,
        operationID: Int,
        onAuthenticated: @escaping @MainActor () async -> Void
    ) async {
        do {
            let response: APIResponse<UserProfileData> = try await client.send(.myProfile())
            guard isCurrentAuthenticationOperation(operationID) else { return }
            let profile = response.data?.user
            _ = try accountSessionStore.activate(userID: profile?.id ?? "")
            userProfile = profile
            isAuthenticated = true
            requiresProfileValidation = false
            authError = nil
            await onAuthenticated()
        } catch APIError.unauthorized {
            guard isCurrentAuthenticationOperation(operationID) else { return }
            await invalidateUnauthorizedSession(operationID: operationID)
        } catch let error as AccountSessionError {
            guard isCurrentAuthenticationOperation(operationID) else { return }
            accountSessionStore.deactivate()
            isAuthenticated = false
            requiresProfileValidation = true
            userProfile = nil
            authError = error.localizedDescription
        } catch {
            guard isCurrentAuthenticationOperation(operationID) else { return }
            isAuthenticated = keepExistingSessionOnTransientFailure && accountSessionStore.currentScope != nil
            requiresProfileValidation = !isAuthenticated
            authError = error.localizedDescription
        }
    }

    private func invalidateUnauthorizedSession(operationID: Int) async {
        guard isCurrentAuthenticationOperation(operationID) else { return }
        accountSessionStore.deactivate()
        isAuthenticated = false
        requiresProfileValidation = false
        userProfile = nil
        do {
            try await client.tokenStore.clear()
            guard isCurrentAuthenticationOperation(operationID) else { return }
            authError = APIError.unauthorized.localizedDescription
        } catch {
            guard isCurrentAuthenticationOperation(operationID) else { return }
            authError = error.localizedDescription
        }
    }

    private func beginAuthenticationOperation() -> Int {
        activeAuthenticationGeneration &+= 1
        return activeAuthenticationGeneration
    }

    private func isCurrentAuthenticationOperation(_ operationID: Int) -> Bool {
        operationID == activeAuthenticationGeneration
    }
}
