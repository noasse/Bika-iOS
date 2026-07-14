import Foundation
import SwiftUI

@MainActor
@Observable
final class MacComicDetailStore {
    var selectedComicID: String?
    var selectedSummary: MacComicSummary?
    var detail: ComicDetail?
    var episodes: [Episode] = []
    var recommended: [Comic] = []
    var isLoadingRecommended = false
    var recommendedError: String?
    var commentEntryCount: Int?
    var isDetailLoading = false
    var detailError: String?
    var isLoadingEpisodes = false
    var episodesError: String?
    var isTogglingLike = false
    var isTogglingFavourite = false
    var readingProgressRevision = 0

    let client: any APIClientProtocol
    let readingStore: MacReadingStore
    let blockedCategoriesStore: MacBlockedCategoriesStore

    private var activeDetailRequestID = 0
    private var activeEpisodeRequestID = 0
    private var activeRecommendationRequestID = 0

    init(
        client: any APIClientProtocol,
        readingStore: MacReadingStore,
        blockedCategoriesStore: MacBlockedCategoriesStore
    ) {
        self.client = client
        self.readingStore = readingStore
        self.blockedCategoriesStore = blockedCategoriesStore
    }

    var isPerformingDetailAction: Bool {
        isTogglingLike || isTogglingFavourite
    }

    var displayedRecommended: [Comic] {
        blockedCategoriesStore.filter(recommended)
    }

    func selectComic(_ summary: MacComicSummary) async {
        selectedComicID = summary.id
        selectedSummary = summary
        await loadDetail(comicId: summary.id)
    }

    func selectComic(id: String, fallbackSummary: MacComicSummary?) async {
        selectedComicID = id
        selectedSummary = fallbackSummary ?? selectedSummary
        await loadDetail(comicId: id)
    }

    func loadDetail(comicId: String) async {
        activeDetailRequestID &+= 1
        let requestID = activeDetailRequestID
        activeRecommendationRequestID &+= 1
        isDetailLoading = true
        detailError = nil
        detail = nil
        episodes = []
        episodesError = nil
        recommended = []
        recommendedError = nil
        commentEntryCount = nil

        let episodeRequestID = beginEpisodeRequest(replacingContent: true)
        async let episodesTask: Void = loadEpisodes(
            comicId: comicId,
            detailRequestID: requestID,
            episodeRequestID: episodeRequestID
        )
        async let commentsTask: Int? = loadCommentEntryCount(comicId: comicId)
        async let recommendedTask: Void = loadRecommended(comicId: comicId)

        do {
            let response: APIResponse<ComicDetailData> = try await client.send(.comicDetail(id: comicId))
            guard requestID == activeDetailRequestID else { return }
            guard let resolvedDetail = response.data?.comic else {
                detailError = "漫画详情为空"
                isDetailLoading = false
                _ = await (episodesTask, commentsTask, recommendedTask)
                return
            }
            detail = resolvedDetail
            isDetailLoading = false
        } catch {
            guard requestID == activeDetailRequestID else { return }
            detailError = error.localizedDescription
            isDetailLoading = false
        }

        let resolvedCommentCount = await commentsTask
        _ = await (episodesTask, recommendedTask)

        guard requestID == activeDetailRequestID else { return }
        commentEntryCount = resolvedCommentCount ?? detail?.totalComments ?? detail?.commentsCount
    }

    func reloadEpisodes() async {
        guard let comicId = selectedComicID ?? detail?.id else { return }
        let episodeRequestID = beginEpisodeRequest(replacingContent: false)
        await loadEpisodes(
            comicId: comicId,
            detailRequestID: activeDetailRequestID,
            episodeRequestID: episodeRequestID
        )
    }

    func toggleFavourite() async -> Bool {
        guard let comicId = selectedComicID, !isPerformingDetailAction else { return false }
        isTogglingFavourite = true
        defer { isTogglingFavourite = false }
        do {
            let _: APIResponse<EmptyData> = try await client.send(.favouriteComic(id: comicId))
            guard selectedComicID == comicId else { return true }
            await refreshDetailAfterMutation(comicId: comicId)
            return true
        } catch {
            guard selectedComicID == comicId else { return false }
            detailError = error.localizedDescription
            return false
        }
    }

    func toggleLike() async {
        guard let comicId = selectedComicID, !isPerformingDetailAction else { return }
        isTogglingLike = true
        defer { isTogglingLike = false }

        do {
            let _: APIResponse<LikeActionData> = try await client.send(.likeComic(id: comicId))
            guard selectedComicID == comicId else { return }
            await refreshDetailAfterMutation(comicId: comicId)
        } catch {
            guard selectedComicID == comicId else { return }
            detailError = error.localizedDescription
        }
    }

    func refreshDetailAfterMutation(comicId: String) async {
        let requestID = activeDetailRequestID
        do {
            let response: APIResponse<ComicDetailData> = try await client.send(.comicDetail(id: comicId))
            guard selectedComicID == comicId,
                  requestID == activeDetailRequestID else { return }
            if let refreshedDetail = response.data?.comic {
                detail = refreshedDetail
            }
        } catch {
            guard selectedComicID == comicId,
                  requestID == activeDetailRequestID else { return }
            detailError = error.localizedDescription
        }
    }

    func makeReaderRequest(
        detail: ComicDetail,
        startEpisodeIndex: Int,
        startPageIndex: Int,
        restore: Bool
    ) -> MacReaderLaunchRequest? {
        guard !episodes.isEmpty else { return nil }
        let clampedEpisodeIndex = min(max(startEpisodeIndex, 0), episodes.count - 1)
        return MacReaderLaunchRequest(
            comicId: detail.id,
            comicTitle: detail.title,
            author: detail.author,
            thumbPath: detail.thumb?.path,
            thumbServer: detail.thumb?.fileServer,
            episodes: episodes.map(MacReaderEpisode.init(episode:)),
            startEpisodeIndex: clampedEpisodeIndex,
            startPageIndex: max(startPageIndex, 0),
            restoreSavedProgress: restore
        )
    }

    func makeContinueReaderRequest() -> MacReaderLaunchRequest? {
        guard let detail else { return nil }
        let progress = readingProgress(for: detail)
        let startIndex: Int
        let startPage: Int
        if
            let progress,
            let progressEpisodeIndex = episodes.firstIndex(where: { $0.order == progress.episodeOrder })
        {
            startIndex = progressEpisodeIndex
            startPage = progress.pageIndex
        } else {
            startIndex = 0
            startPage = 0
        }

        return makeReaderRequest(
            detail: detail,
            startEpisodeIndex: startIndex,
            startPageIndex: startPage,
            restore: true
        )
    }

    func readingProgress(for detail: ComicDetail) -> MacReadingProgress? {
        guard
            let progress = readingStore.progress(for: detail.id),
            episodes.contains(where: { $0.order == progress.episodeOrder })
        else {
            return nil
        }
        return progress
    }

    func readerDidClose(comicId: String) {
        guard selectedComicID == comicId, detail?.id == comicId else { return }
        readingProgressRevision &+= 1
    }

    func makeEpisodeReaderRequest(episode: Episode) -> MacReaderLaunchRequest? {
        guard
            let detail,
            let episodeIndex = episodes.firstIndex(where: { $0.id == episode.id })
        else {
            return nil
        }

        return makeReaderRequest(
            detail: detail,
            startEpisodeIndex: episodeIndex,
            startPageIndex: 0,
            restore: false
        )
    }

    func clearDetail() {
        invalidateDetailRequest()
        selectedComicID = nil
        selectedSummary = nil
        detail = nil
        episodes = []
        recommended = []
        recommendedError = nil
        commentEntryCount = nil
        detailError = nil
        episodesError = nil
        isDetailLoading = false
        isLoadingEpisodes = false
    }

    private func beginEpisodeRequest(replacingContent: Bool) -> Int {
        activeEpisodeRequestID &+= 1
        isLoadingEpisodes = true
        episodesError = nil
        if replacingContent {
            episodes = []
        }
        return activeEpisodeRequestID
    }

    private func loadEpisodes(
        comicId: String,
        detailRequestID: Int,
        episodeRequestID: Int
    ) async {
        let result = await fetchAllEpisodes(comicId: comicId)
        guard detailRequestID == activeDetailRequestID,
              episodeRequestID == activeEpisodeRequestID else { return }

        episodes = result.episodes.sorted { $0.order < $1.order }
        episodesError = result.errorMessage
        isLoadingEpisodes = false
    }

    private func fetchAllEpisodes(comicId: String) async -> (episodes: [Episode], errorMessage: String?) {
        var result: [Episode] = []
        var nextPage = 1
        var total = 1

        while nextPage <= total {
            let requestedPage = nextPage
            do {
                let response: APIResponse<EpisodesData> = try await client.send(
                    .episodes(comicId: comicId, page: requestedPage)
                )
                guard !Task.isCancelled else {
                    return (result, nil)
                }
                guard let page = response.data?.eps else {
                    return (result, "章节页面数据为空")
                }
                guard page.page >= requestedPage else {
                    return (result, "章节分页未继续前进")
                }

                let resolvedTotal = max(page.pages, page.page)
                if page.docs.isEmpty {
                    if result.isEmpty, page.page == 1, resolvedTotal <= 1 {
                        return ([], nil)
                    }
                    return (result, "章节页面数据不完整")
                }

                let existingIDs = Set(result.map(\.id))
                let newEpisodes = page.docs.filter { !existingIDs.contains($0.id) }
                guard !newEpisodes.isEmpty else {
                    return (result, "章节分页数据重复")
                }
                result.append(contentsOf: newEpisodes)
                total = resolvedTotal

                if page.page >= total {
                    return (result, nil)
                }
                nextPage = page.page + 1
            } catch {
                guard !Task.isCancelled else {
                    return (result, nil)
                }
                return (result, error.localizedDescription)
            }
        }

        return (result, nil)
    }

    private func loadRecommended(comicId: String) async {
        activeRecommendationRequestID &+= 1
        let requestID = activeRecommendationRequestID
        isLoadingRecommended = true
        recommendedError = nil
        defer {
            if requestID == activeRecommendationRequestID {
                isLoadingRecommended = false
            }
        }

        do {
            let response: APIResponse<RecommendedData> = try await client.send(.recommended(comicId: comicId))
            guard requestID == activeRecommendationRequestID else { return }
            recommended = response.data?.comics ?? []
            if recommended.isEmpty {
                recommendedError = response.data == nil ? "推荐数据为空" : nil
            }
        } catch {
            guard requestID == activeRecommendationRequestID else { return }
            recommended = []
            recommendedError = error.localizedDescription
        }
    }

    private func loadCommentEntryCount(comicId: String) async -> Int? {
        do {
            let response: APIResponse<CommentsData> = try await client.send(
                .comments(comicId: comicId, page: 1)
            )
            return response.data?.topLevelCommentDisplayCount
        } catch {
            return nil
        }
    }

    private func invalidateDetailRequest() {
        activeDetailRequestID &+= 1
        activeEpisodeRequestID &+= 1
        activeRecommendationRequestID &+= 1
        isDetailLoading = false
        isLoadingEpisodes = false
        isLoadingRecommended = false
    }
}
