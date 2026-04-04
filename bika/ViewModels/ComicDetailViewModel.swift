import SwiftUI

@Observable
final class ComicDetailViewModel {
    var detail: ComicDetail?
    var episodes: [Episode] = []
    var recommended: [Comic] = []
    var commentEntryCount: Int?
    var isLoading = false
    var isLoadingEpisodes = false
    var isLoadingRecommended = false
    var errorMessage: String?
    var episodesError: String?
    var recommendedError: String?
    var actionErrorMessage: String?

    let comicId: String
    private let client: any APIClientProtocol
    private var episodePage = 0
    private var episodeTotalPages = 1

    init(comicId: String, client: any APIClientProtocol = APIClient.shared) {
        self.comicId = comicId
        self.client = client
    }

    @MainActor
    func load() async {
        guard detail == nil else { return }
        isLoading = true
        errorMessage = nil

        do {
            let response: APIResponse<ComicDetailData> = try await client.send(.comicDetail(id: comicId))
            guard let comic = response.data?.comic else {
                errorMessage = "漫画详情为空"
                isLoading = false
                return
            }
            detail = comic
            commentEntryCount = comic.totalComments ?? comic.commentsCount
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
            return
        }

        isLoading = false

        async let recommendedTask: Void = loadRecommended()
        async let episodesTask: Void = loadAllEpisodes()
        async let commentCountTask: Void = loadCommentEntryCount()
        _ = await (recommendedTask, episodesTask, commentCountTask)
    }

    @MainActor
    private func loadAllEpisodes() async {
        isLoadingEpisodes = true
        episodesError = nil
        defer { isLoadingEpisodes = false }
        episodePage = 0
        episodeTotalPages = 1
        episodes = []

        var loadedEpisodes: [Episode] = []
        var nextPage = 1
        var resolvedEpisodePage = 0
        var resolvedEpisodeTotalPages = 1

        while nextPage <= resolvedEpisodeTotalPages {
            do {
                let response: APIResponse<EpisodesData> = try await client.send(
                    .episodes(comicId: comicId, page: nextPage)
                )

                guard let data = response.data else {
                    break
                }

                let resolvedPage = data.eps.page
                let resolvedPages = max(data.eps.pages, resolvedPage)
                let existingEpisodeIDs = Set(loadedEpisodes.map(\.id))
                let newEpisodes = data.eps.docs.filter { !existingEpisodeIDs.contains($0.id) }

                guard !newEpisodes.isEmpty else {
                    resolvedEpisodePage = resolvedPage
                    resolvedEpisodeTotalPages = resolvedPages
                    break
                }

                loadedEpisodes.append(contentsOf: newEpisodes)

                guard resolvedPage >= nextPage else {
                    resolvedEpisodePage = resolvedPages
                    resolvedEpisodeTotalPages = resolvedPages
                    break
                }

                resolvedEpisodePage = resolvedPage
                resolvedEpisodeTotalPages = resolvedPages

                let upcomingPage = resolvedPage + 1
                if upcomingPage <= nextPage && nextPage <= resolvedEpisodeTotalPages {
                    break
                }

                nextPage = upcomingPage
            } catch {
                episodesError = error.localizedDescription
                break
            }
        }

        episodePage = resolvedEpisodePage
        episodeTotalPages = resolvedEpisodeTotalPages
        episodes = loadedEpisodes.sorted { $0.order < $1.order }
    }

    @MainActor
    func reloadEpisodes() async {
        await loadAllEpisodes()
    }

    @MainActor
    func toggleLike() async {
        do {
            let _: APIResponse<LikeActionData> = try await client.send(.likeComic(id: comicId))
            // Refresh detail to get updated state
            let response: APIResponse<ComicDetailData> = try await client.send(.comicDetail(id: comicId))
            detail = response.data?.comic
        } catch {
            actionErrorMessage = error.localizedDescription
        }
    }

    @MainActor
    func toggleFavourite() async {
        do {
            let _: APIResponse<EmptyData> = try await client.send(.favouriteComic(id: comicId))
            let response: APIResponse<ComicDetailData> = try await client.send(.comicDetail(id: comicId))
            detail = response.data?.comic
        } catch {
            actionErrorMessage = error.localizedDescription
        }
    }

    @MainActor
    func loadRecommended() async {
        isLoadingRecommended = true
        recommendedError = nil
        defer { isLoadingRecommended = false }

        do {
            let response: APIResponse<RecommendedData> = try await client.send(
                .recommended(comicId: comicId)
            )
            guard let data = response.data else {
                recommended = []
                recommendedError = "推荐数据为空"
                return
            }
            recommended = data.comics
        } catch {
            recommendedError = error.localizedDescription
        }
    }

    @MainActor
    private func loadCommentEntryCount() async {
        do {
            let response: APIResponse<CommentsData> = try await client.send(
                .comments(comicId: comicId, page: 1)
            )
            commentEntryCount = response.data?.topLevelCommentDisplayCount
        } catch {
            commentEntryCount = commentEntryCount ?? detail?.totalComments ?? detail?.commentsCount
        }
    }
}
