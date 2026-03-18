import SwiftUI

@Observable
final class ComicDetailViewModel {
    var detail: ComicDetail?
    var episodes: [Episode] = []
    var recommended: [Comic] = []
    var isLoading = false
    var isLoadingEpisodes = false
    var errorMessage: String?
    var recommendedError: String?

    let comicId: String
    private let client = APIClient.shared
    private var episodePage = 0
    private var episodeTotalPages = 1

    init(comicId: String) {
        self.comicId = comicId
    }

    func load() async {
        guard detail == nil else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let response: APIResponse<ComicDetailData> = try await client.send(.comicDetail(id: comicId))
            detail = response.data?.comic
        } catch {
            errorMessage = error.localizedDescription
        }

        await loadAllEpisodes()
        await loadRecommended()
    }

    private func loadAllEpisodes() async {
        isLoadingEpisodes = true
        defer { isLoadingEpisodes = false }
        episodePage = 0
        episodeTotalPages = 1
        episodes = []

        while episodePage < episodeTotalPages {
            let page = episodePage + 1
            do {
                let response: APIResponse<EpisodesData> = try await client.send(
                    .episodes(comicId: comicId, page: page)
                )
                if let data = response.data {
                    episodes.append(contentsOf: data.eps.docs)
                    episodePage = data.eps.page
                    episodeTotalPages = data.eps.pages
                }
            } catch {
                break
            }
        }

        episodes.sort { $0.order < $1.order }
    }

    func toggleLike() async {
        do {
            let _: APIResponse<LikeActionData> = try await client.send(.likeComic(id: comicId))
            // Refresh detail to get updated state
            let response: APIResponse<ComicDetailData> = try await client.send(.comicDetail(id: comicId))
            detail = response.data?.comic
        } catch {}
    }

    func toggleFavourite() async {
        do {
            let _: APIResponse<FavouriteData> = try await client.send(.favouriteComic(id: comicId))
            let response: APIResponse<ComicDetailData> = try await client.send(.comicDetail(id: comicId))
            detail = response.data?.comic
        } catch {}
    }

    func loadRecommended() async {
        recommendedError = nil
        do {
            let response: APIResponse<RecommendedData> = try await client.send(
                .recommended(comicId: comicId)
            )
            recommended = response.data?.comics ?? []
        } catch {
            recommendedError = error.localizedDescription
        }
    }
}
