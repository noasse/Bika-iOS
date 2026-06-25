import Foundation

extension MacLibraryModel {
    func checkTokenIfNeeded() async {
        guard !didCheckToken else { return }
        didCheckToken = true
        isCheckingToken = true
        defer { isCheckingToken = false }

        guard await client.tokenStore.getToken() != nil else {
            isAuthenticated = false
            return
        }

        isAuthenticated = true
        do {
            let response: APIResponse<UserProfileData> = try await client.send(.myProfile())
            userProfile = response.data?.user
            await selectSidebar(.categories)
        } catch {
            await client.tokenStore.clear()
            isAuthenticated = false
            userProfile = nil
            authError = error.localizedDescription
        }
    }

    func login(email: String, password: String) async {
        isAuthenticating = true
        authError = nil
        defer { isAuthenticating = false }

        do {
            _ = try await client.signIn(email: email, password: password)
            isAuthenticated = true
            let profileResponse: APIResponse<UserProfileData> = try await client.send(.myProfile())
            userProfile = profileResponse.data?.user
            await selectSidebar(.categories)
        } catch {
            authError = error.localizedDescription
            isAuthenticated = false
        }
    }

    func logout() async {
        await client.tokenStore.clear()
        isAuthenticated = false
        userProfile = nil
        clearSelection()
    }
}
