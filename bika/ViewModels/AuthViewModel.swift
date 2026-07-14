import SwiftUI

@MainActor
@Observable
final class AuthViewModel {
    var isAuthenticated = false
    var isLoading = false
    var isCheckingToken = true
    var requiresProfileValidation = false
    var errorMessage: String?

    private let client: any APIClientProtocol
    private let accountSessionStore: AccountSessionStore
    private var didCheckToken = false
    private var activeAuthenticationGeneration = 0

    init(
        client: any APIClientProtocol = APIClient.shared,
        accountSessionStore: AccountSessionStore? = nil
    ) {
        self.client = client
        self.accountSessionStore = accountSessionStore ?? .shared
    }

    func login(email: String, password: String) async {
        let operationID = beginAuthenticationOperation()
        isCheckingToken = false
        isLoading = true
        errorMessage = nil
        requiresProfileValidation = false
        accountSessionStore.deactivate()
        defer {
            if isCurrentAuthenticationOperation(operationID) {
                isLoading = false
            }
        }

        do {
            let token = try await client.requestSignInToken(email: email, password: password)
            guard isCurrentAuthenticationOperation(operationID) else { return }
            try await client.tokenStore.setToken(token)
            guard isCurrentAuthenticationOperation(operationID) else { return }
            await validateProfile(
                keepExistingSessionOnTransientFailure: false,
                operationID: operationID
            )
        } catch {
            guard isCurrentAuthenticationOperation(operationID) else { return }
            isAuthenticated = false
            errorMessage = error.localizedDescription
        }
    }

    func logout() async {
        let operationID = beginAuthenticationOperation()
        isAuthenticated = false
        isLoading = false
        isCheckingToken = false
        requiresProfileValidation = false
        errorMessage = nil
        accountSessionStore.deactivate()
        do {
            try await client.tokenStore.clear()
        } catch {
            guard isCurrentAuthenticationOperation(operationID) else { return }
            errorMessage = error.localizedDescription
        }
    }

    func checkToken() async {
        guard !didCheckToken else { return }
        didCheckToken = true
        let operationID = beginAuthenticationOperation()
        isCheckingToken = true
        errorMessage = nil

        let hasStoredToken: Bool
        do {
            hasStoredToken = try await client.tokenStore.getToken() != nil
        } catch {
            guard isCurrentAuthenticationOperation(operationID) else { return }
            errorMessage = error.localizedDescription
            isAuthenticated = false
            requiresProfileValidation = true
            isCheckingToken = false
            return
        }

        guard isCurrentAuthenticationOperation(operationID) else { return }
        guard hasStoredToken else {
            accountSessionStore.deactivate()
            isAuthenticated = false
            requiresProfileValidation = false
            isCheckingToken = false
            return
        }

        let hasPersistedScope = accountSessionStore.currentScope != nil
        isAuthenticated = hasPersistedScope
        isCheckingToken = !hasPersistedScope
        await validateProfile(
            keepExistingSessionOnTransientFailure: hasPersistedScope,
            operationID: operationID
        )
        guard isCurrentAuthenticationOperation(operationID) else { return }
        isCheckingToken = false
    }

    func retryProfileValidation() async {
        guard !isLoading else { return }
        let operationID = beginAuthenticationOperation()
        isCheckingToken = false
        isLoading = true
        errorMessage = nil
        defer {
            if isCurrentAuthenticationOperation(operationID) {
                isLoading = false
            }
        }

        do {
            let hasStoredToken = try await client.tokenStore.getToken() != nil
            guard isCurrentAuthenticationOperation(operationID) else { return }
            guard hasStoredToken else {
                accountSessionStore.deactivate()
                isAuthenticated = false
                requiresProfileValidation = false
                errorMessage = APIError.noToken.localizedDescription
                return
            }
            await validateProfile(
                keepExistingSessionOnTransientFailure: accountSessionStore.currentScope != nil,
                operationID: operationID
            )
        } catch {
            guard isCurrentAuthenticationOperation(operationID) else { return }
            isAuthenticated = false
            requiresProfileValidation = true
            errorMessage = error.localizedDescription
        }
    }

    private func validateProfile(
        keepExistingSessionOnTransientFailure: Bool,
        operationID: Int
    ) async {
        do {
            let response: APIResponse<UserProfileData> = try await client.send(.myProfile())
            guard isCurrentAuthenticationOperation(operationID) else { return }
            let scope = try accountSessionStore.activate(userID: response.data?.user.id ?? "")
            guard !scope.rawValue.isEmpty else {
                throw AccountSessionError.missingUserID
            }
            isAuthenticated = true
            requiresProfileValidation = false
            errorMessage = nil
        } catch APIError.unauthorized {
            guard isCurrentAuthenticationOperation(operationID) else { return }
            await invalidateUnauthorizedSession(operationID: operationID)
        } catch let error as AccountSessionError {
            guard isCurrentAuthenticationOperation(operationID) else { return }
            accountSessionStore.deactivate()
            isAuthenticated = false
            requiresProfileValidation = true
            errorMessage = error.localizedDescription
        } catch {
            guard isCurrentAuthenticationOperation(operationID) else { return }
            isAuthenticated = keepExistingSessionOnTransientFailure && accountSessionStore.currentScope != nil
            requiresProfileValidation = !isAuthenticated
            errorMessage = error.localizedDescription
        }
    }

    private func invalidateUnauthorizedSession(operationID: Int) async {
        guard isCurrentAuthenticationOperation(operationID) else { return }
        accountSessionStore.deactivate()
        isAuthenticated = false
        requiresProfileValidation = false
        do {
            try await client.tokenStore.clear()
            guard isCurrentAuthenticationOperation(operationID) else { return }
            errorMessage = APIError.unauthorized.localizedDescription
        } catch {
            guard isCurrentAuthenticationOperation(operationID) else { return }
            errorMessage = error.localizedDescription
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
