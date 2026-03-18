import SwiftUI

@Observable
final class LeaderboardViewModel {
    var comics: [Comic] = []
    var isLoading = false
    var selectedType: LeaderboardType = .hour24
    var errorMessage: String?

    private let client = APIClient.shared

    func load() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let response: APIResponse<LeaderboardData> = try await client.send(.leaderboard(type: selectedType))
            comics = response.data?.comics ?? []
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func switchType(_ type: LeaderboardType) async {
        guard type != selectedType else { return }
        selectedType = type
        await load()
    }
}
