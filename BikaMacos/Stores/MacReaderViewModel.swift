import Foundation
import SwiftUI

@MainActor
@Observable
final class MacReaderViewModel {
    var pages: [ComicPage] = []
    var isLoading = false
    var errorMessage: String?
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

    init(
        request: MacReaderLaunchRequest,
        readingStore: MacReadingStore,
        client: any APIClientProtocol = APIClient.shared,
        keyValueStore: any KeyValueStore = AppDependencies.shared.keyValueStore
    ) {
        self.request = request
        self.readingStore = readingStore
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
        await loadCurrentEpisode()
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
        guard hasNextEpisode, !isLoading else { return }
        currentEpisodeIndex += 1
        currentPageIndex = 0
        await loadCurrentEpisode()
    }

    func previousEpisode() async {
        guard hasPreviousEpisode, !isLoading else { return }
        currentEpisodeIndex -= 1
        currentPageIndex = 0
        await loadCurrentEpisode()
    }

    private func loadCurrentEpisode() async {
        guard let episode = currentEpisode else {
            pages = []
            errorMessage = "没有可读取的章节"
            return
        }

        activeLoadID += 1
        let loadID = activeLoadID
        isLoading = true
        errorMessage = nil
        pages = []

        do {
            let loadedPages = try await loadPages(for: episode)
            guard loadID == activeLoadID else { return }
            pages = loadedPages
            if pages.isEmpty {
                currentPageIndex = 0
            } else {
                currentPageIndex = min(max(currentPageIndex, 0), pages.count - 1)
            }
            saveProgress()
        } catch {
            guard loadID == activeLoadID else { return }
            errorMessage = error.localizedDescription
        }

        guard loadID == activeLoadID else { return }
        isLoading = false
    }

    private func loadPages(for episode: MacReaderEpisode) async throws -> [ComicPage] {
        var result: [ComicPage] = []
        var nextPage = 1
        var total = 1

        while nextPage <= total {
            let response: APIResponse<ComicPagesData> = try await client.send(
                .comicPages(comicId: request.comicId, epsOrder: episode.order, page: nextPage)
            )
            guard let page = response.data?.pages else { break }
            result.append(contentsOf: page.docs)
            total = max(page.pages, page.page)
            nextPage = page.page + 1
            if nextPage <= page.page {
                break
            }
        }

        return result
    }

    private func saveProgress() {
        guard let episode = currentEpisode else { return }
        readingStore.record(request: request, episode: episode, pageIndex: currentPageIndex)
    }
}
