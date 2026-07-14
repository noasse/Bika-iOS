import Foundation
import SwiftUI

@MainActor
@Observable
final class MacReaderViewModel {
    var pages: [ComicPage] = []
    var isLoading = false
    var errorMessage: String?
    var partialErrorMessage: String?
    var currentPageIndex: Int
    var currentEpisodeIndex: Int
    var readerMode: MacReaderMode
    var imageScale: Double

    let request: MacReaderLaunchRequest

    private let client: any APIClientProtocol
    private let readingStore: MacReadingStore
    private let keyValueStore: any KeyValueStore
    private var didStart = false
    private var activeLoadID = 0
    private var loadTask: Task<Void, Never>?

    init(
        request: MacReaderLaunchRequest,
        readingStore: MacReadingStore,
        client: any APIClientProtocol = APIClient.shared,
        keyValueStore: any KeyValueStore = AppDependencies.shared.keyValueStore
    ) {
        self.request = request
        self.readingStore = readingStore.scopedForReader()
        self.client = client
        self.keyValueStore = keyValueStore

        let savedMode = keyValueStore.string(forKey: "macReaderMode") ?? MacReaderMode.waterfall.rawValue
        readerMode = MacReaderMode(rawValue: savedMode) ?? .waterfall
        let savedScale = keyValueStore.string(forKey: "macReaderImageScale").flatMap(Double.init)
        imageScale = savedScale.map { min(max($0, 0.55), 2.4) } ?? 1.0

        currentEpisodeIndex = min(max(request.startEpisodeIndex, 0), max(request.episodes.count - 1, 0))
        currentPageIndex = max(request.startPageIndex, 0)

        if
            request.restoreSavedProgress,
            let progress = readingStore.progress(for: request.comicId),
            let episodeIndex = request.episodes.firstIndex(where: { $0.order == progress.episodeOrder })
        {
            currentEpisodeIndex = episodeIndex
            currentPageIndex = max(progress.pageIndex, 0)
        }
    }

    var currentEpisode: MacReaderEpisode? {
        guard request.episodes.indices.contains(currentEpisodeIndex) else { return nil }
        return request.episodes[currentEpisodeIndex]
    }

    var pageDisplayText: String {
        guard !pages.isEmpty else { return "0 / 0" }
        return "\(currentPageIndex + 1) / \(pages.count)"
    }

    var hasPreviousEpisode: Bool { currentEpisodeIndex > 0 }
    var hasNextEpisode: Bool { currentEpisodeIndex < request.episodes.count - 1 }

    var episodeDisplayText: String {
        currentEpisode?.title ?? "未选择章节"
    }

    func startIfNeeded() async {
        guard !didStart else { return }
        didStart = true
        await loadCurrentEpisode(preservingExistingPages: false)
    }

    func setReaderMode(_ mode: MacReaderMode) {
        readerMode = mode
        keyValueStore.set(mode.rawValue, forKey: "macReaderMode")
    }

    func setImageScale(_ scale: Double) {
        imageScale = min(max(scale, 0.55), 2.4)
        keyValueStore.set(String(imageScale), forKey: "macReaderImageScale")
    }

    func stepImageScale(_ delta: Double) {
        setImageScale(imageScale + delta)
    }

    func setCurrentPage(_ index: Int) {
        guard pages.indices.contains(index), currentPageIndex != index else { return }
        currentPageIndex = index
        saveProgress()
    }

    func nextPage() {
        guard !pages.isEmpty, !isLoading else { return }
        if currentPageIndex < pages.count - 1 {
            currentPageIndex += 1
            saveProgress()
        }
    }

    func previousPage() {
        guard !pages.isEmpty, !isLoading else { return }
        if currentPageIndex > 0 {
            currentPageIndex -= 1
            saveProgress()
        }
    }

    func goToPage(_ displayPage: Int) {
        guard !pages.isEmpty, !isLoading else { return }
        currentPageIndex = macClampedPage(displayPage, totalPages: pages.count) - 1
        saveProgress()
    }

    func saveCurrentProgress() {
        saveProgress()
    }

    func nextEpisode() async {
        guard hasNextEpisode else { return }
        currentEpisodeIndex += 1
        currentPageIndex = 0
        await loadCurrentEpisode(preservingExistingPages: false)
    }

    func previousEpisode() async {
        guard hasPreviousEpisode else { return }
        currentEpisodeIndex -= 1
        currentPageIndex = 0
        await loadCurrentEpisode(preservingExistingPages: false)
    }

    func retryCurrentEpisode() async {
        didStart = true
        await loadCurrentEpisode(preservingExistingPages: !pages.isEmpty)
    }

    func cancelLoading() {
        let wasLoading = isLoading
        activeLoadID += 1
        loadTask?.cancel()
        loadTask = nil
        isLoading = false
        if wasLoading, pages.isEmpty {
            didStart = false
        }
    }

    private func loadCurrentEpisode(preservingExistingPages: Bool) async {
        guard let episode = currentEpisode else {
            cancelLoading()
            pages = []
            errorMessage = "没有可读取的章节"
            partialErrorMessage = nil
            return
        }

        loadTask?.cancel()
        activeLoadID += 1
        let loadID = activeLoadID
        let previousPages = pages
        isLoading = true
        errorMessage = nil
        partialErrorMessage = nil
        if !preservingExistingPages {
            pages = []
        }

        let task = Task { [weak self] in
            guard let self else { return }
            await self.performLoad(
                for: episode,
                loadID: loadID,
                preservingExistingPages: preservingExistingPages,
                previousPages: previousPages
            )
        }
        loadTask = task
        await task.value

        guard loadID == activeLoadID else { return }
        loadTask = nil
    }

    private func performLoad(
        for episode: MacReaderEpisode,
        loadID: Int,
        preservingExistingPages: Bool,
        previousPages: [ComicPage]
    ) async {
        guard let outcome = await loadPages(for: episode, loadID: loadID) else { return }
        guard !Task.isCancelled, loadID == activeLoadID else { return }

        if let failureMessage = outcome.failureMessage {
            let retainedPages: [ComicPage]
            if preservingExistingPages, !previousPages.isEmpty {
                retainedPages = previousPages
            } else {
                retainedPages = outcome.pages
            }
            pages = retainedPages
            if retainedPages.isEmpty {
                errorMessage = failureMessage
                partialErrorMessage = nil
            } else {
                errorMessage = nil
                partialErrorMessage = failureMessage
            }
        } else {
            pages = outcome.pages
            errorMessage = nil
            partialErrorMessage = nil
        }

        if pages.isEmpty {
            currentPageIndex = 0
        } else {
            currentPageIndex = min(max(currentPageIndex, 0), pages.count - 1)
            saveProgress()
        }
        isLoading = false
    }

    private func loadPages(for episode: MacReaderEpisode, loadID: Int) async -> PageLoadOutcome? {
        var result: [ComicPage] = []
        var requestedPage = 1
        var totalPages = 1
        var returnedPages: Set<Int> = []

        while requestedPage <= totalPages {
            guard !Task.isCancelled, loadID == activeLoadID else { return nil }

            do {
                let response: APIResponse<ComicPagesData> = try await client.send(
                    .comicPages(
                        comicId: request.comicId,
                        epsOrder: episode.order,
                        page: requestedPage
                    )
                )
                guard !Task.isCancelled, loadID == activeLoadID else { return nil }
                guard let page = response.data?.pages else {
                    return PageLoadOutcome(
                        pages: result,
                        failureMessage: "页面响应缺少分页数据，请重试"
                    )
                }

                let returnedPage = page.page
                let resolvedTotalPages = max(page.pages, returnedPage)
                guard returnedPage >= requestedPage else {
                    return PageLoadOutcome(
                        pages: result,
                        failureMessage: "服务器返回了重复或倒退的页码（请求第 \(requestedPage) 页，返回第 \(returnedPage) 页）"
                    )
                }
                guard returnedPages.insert(returnedPage).inserted else {
                    return PageLoadOutcome(
                        pages: result,
                        failureMessage: "服务器重复返回第 \(returnedPage) 页，已停止继续加载"
                    )
                }

                if page.docs.isEmpty {
                    if returnedPage < resolvedTotalPages {
                        return PageLoadOutcome(
                            pages: result,
                            failureMessage: "第 \(returnedPage) 页为空，但服务器声明仍有后续页面"
                        )
                    }
                    return PageLoadOutcome(pages: result, failureMessage: nil)
                }

                result.append(contentsOf: page.docs)
                totalPages = resolvedTotalPages
                if returnedPage >= totalPages {
                    return PageLoadOutcome(pages: result, failureMessage: nil)
                }

                requestedPage = returnedPage + 1
            } catch {
                guard !Task.isCancelled, loadID == activeLoadID else { return nil }
                return PageLoadOutcome(pages: result, failureMessage: error.localizedDescription)
            }
        }

        return PageLoadOutcome(pages: result, failureMessage: nil)
    }

    private func saveProgress() {
        guard let episode = currentEpisode else { return }
        readingStore.record(request: request, episode: episode, pageIndex: currentPageIndex)
    }
}

private struct PageLoadOutcome {
    let pages: [ComicPage]
    let failureMessage: String?
}
