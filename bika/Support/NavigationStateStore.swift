import Foundation

struct ComicListNavigationState: Sendable {
    let currentPage: Int
    let sortModeRawValue: String
    let anchorComicID: String?
}

struct LeaderboardNavigationState: Sendable {
    let selectedTypeRawValue: String
    let anchorComicID: String?
}

final nonisolated class NavigationStateStore: @unchecked Sendable {
    static let shared = NavigationStateStore()

    private let lock = NSLock()
    private var comicListStates: [String: ComicListNavigationState] = [:]
    private var leaderboardState: LeaderboardNavigationState?

    private init() {}

    func comicListState(for key: String) -> ComicListNavigationState? {
        lock.withLock { comicListStates[key] }
    }

    func saveComicListState(_ state: ComicListNavigationState, for key: String) {
        lock.withLock {
            comicListStates[key] = state
        }
    }

    func clearComicListState(for key: String) {
        lock.withLock {
            comicListStates.removeValue(forKey: key)
        }
    }

    func loadLeaderboardState() -> LeaderboardNavigationState? {
        lock.withLock { leaderboardState }
    }

    func saveLeaderboardState(_ state: LeaderboardNavigationState) {
        lock.withLock {
            leaderboardState = state
        }
    }

    func clearLeaderboardState() {
        lock.withLock {
            leaderboardState = nil
        }
    }
}
