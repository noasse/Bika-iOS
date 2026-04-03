import SwiftUI

@Observable
final class AuthViewModel {
    var isAuthenticated = false
    var isLoading = false
    var isCheckingToken = true
    var errorMessage: String?

    private let client: any APIClientProtocol

    init(client: any APIClientProtocol = APIClient.shared) {
        self.client = client
    }

    func login(email: String, password: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            _ = try await client.signIn(email: email, password: password)
            isAuthenticated = true
        } catch let error as APIError {
            errorMessage = error.localizedDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func logout() async {
        await client.tokenStore.clear()
        isAuthenticated = false
    }

    func checkToken() async {
        if await client.tokenStore.getToken() != nil {
            // Trust the token immediately — show main UI right away
            isAuthenticated = true
            isCheckingToken = false
            // Validate in background; if invalid, kick back to login
            do {
                let _: APIResponse<UserProfileData> = try await client.send(.myProfile())
            } catch {
                await client.tokenStore.clear()
                isAuthenticated = false
            }
        } else {
            isCheckingToken = false
        }
    }
}
