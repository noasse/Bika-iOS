import SwiftUI

@Observable
final class LeaderboardViewModel {
    var comics: [Comic] = []
    var isLoading = false
    var selectedType: LeaderboardType = .hour24
    var errorMessage: String?
    var pendingRestoreComicID: String?

    private let client: any APIClientProtocol
    private let navigationStateStore: NavigationStateStore
    private var activeRequestID = 0

    init(
        client: any APIClientProtocol = APIClient.shared,
        navigationStateStore: NavigationStateStore = .shared
    ) {
        self.client = client
        self.navigationStateStore = navigationStateStore

        if let savedState = navigationStateStore.loadLeaderboardState() {
            selectedType = LeaderboardType(rawValue: savedState.selectedTypeRawValue) ?? .hour24
            pendingRestoreComicID = savedState.anchorComicID
        }
    }

    func loadIfNeeded() async {
        guard comics.isEmpty else { return }
        await load()
    }

    func load() async {
        let requestID = beginRequest()
        let requestedType = selectedType
        errorMessage = nil

        do {
            let response: APIResponse<LeaderboardData> = try await client.send(.leaderboard(type: requestedType))
            guard requestID == activeRequestID else { return }
            comics = response.data?.comics ?? []
            errorMessage = nil
            saveNavigationState(anchorComicID: pendingRestoreComicID)
        } catch {
            guard requestID == activeRequestID else { return }
            errorMessage = error.localizedDescription
        }

        finishRequest(requestID)
    }

    func switchType(_ type: LeaderboardType) async {
        guard type != selectedType else { return }
        selectedType = type
        comics = []
        errorMessage = nil
        pendingRestoreComicID = nil
        saveNavigationState(anchorComicID: nil)
        await load()
    }

    func rememberNavigationAnchor(comicID: String) {
        pendingRestoreComicID = comicID
        saveNavigationState(anchorComicID: comicID)
    }

    func consumePendingRestoreComicID() {
        pendingRestoreComicID = nil
        saveNavigationState(anchorComicID: nil)
    }

    private func beginRequest() -> Int {
        activeRequestID += 1
        isLoading = true
        return activeRequestID
    }

    private func finishRequest(_ requestID: Int) {
        guard requestID == activeRequestID else { return }
        isLoading = false
    }

    private func saveNavigationState(anchorComicID: String?) {
        let state = LeaderboardNavigationState(
            selectedTypeRawValue: selectedType.rawValue,
            anchorComicID: anchorComicID
        )
        navigationStateStore.saveLeaderboardState(state)
    }
}
