import Foundation

extension MacLibraryModel {
    func checkTokenIfNeeded() async {
        await authenticationStore.checkTokenIfNeeded { [weak self] in
            await self?.selectSidebar(.categories)
        }
    }

    func login(email: String, password: String) async {
        await authenticationStore.login(email: email, password: password) { [weak self] in
            await self?.selectSidebar(.categories)
        }
    }

    func retryProfileValidation() async {
        await authenticationStore.retryProfileValidation { [weak self] in
            await self?.selectSidebar(.categories)
        }
    }

    func logout() async {
        clearSelection()
        await authenticationStore.logout()
    }

    func loadProfile() async {
        await listStore.loadProfile(
            fetchProfile: { [authenticationStore] in
                try await authenticationStore.fetchProfile()
            },
            applyProfile: { [authenticationStore] profile in
                authenticationStore.applyProfile(profile)
            }
        )
    }

    func punchIn() async {
        do {
            guard try await authenticationStore.punchIn() else { return }
            await loadProfile()
        } catch {
            listStore.setExternalError(error)
        }
    }

    func updateSlogan(_ slogan: String) async {
        do {
            try await authenticationStore.updateSlogan(slogan)
            await loadProfile()
        } catch {
            listStore.setExternalError(error)
        }
    }
}
