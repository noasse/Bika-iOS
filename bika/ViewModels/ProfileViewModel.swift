import SwiftUI

@Observable
final class ProfileViewModel {
    var profile: UserProfile?
    var isLoading = false
    var isPunching = false
    var errorMessage: String?

    private let client: any APIClientProtocol

    init(client: any APIClientProtocol = APIClient.shared) {
        self.client = client
    }

    func loadProfile() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let response: APIResponse<UserProfileData> = try await client.send(.myProfile())
            profile = response.data?.user
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func punchIn() async {
        isPunching = true
        errorMessage = nil
        defer { isPunching = false }

        do {
            let _: APIResponse<EmptyData> = try await client.send(.punchIn())
            // Refresh profile to update isPunched
            await loadProfile()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateSlogan(_ slogan: String) async {
        errorMessage = nil
        do {
            let _: APIResponse<EmptyData> = try await client.send(.setSlogan(slogan))
            profile = profile // trigger observation
            await loadProfile()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
