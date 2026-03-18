import SwiftUI

@Observable
final class ReaderViewModel {
    var pages: [ComicPage] = []
    var isLoading = false
    var currentPageIndex = 0
    var showToolbar = false
    var readerMode: ReaderMode = {
        let saved = UserDefaults.standard.string(forKey: "readerMode") ?? "horizontal"
        return ReaderMode(rawValue: saved) ?? .horizontal
    }()

    let comicId: String
    let episodes: [Episode]
    var currentEpisodeIndex: Int

    private let client = APIClient.shared
    private var paginationPage = 0
    private var paginationTotalPages = 1

    enum ReaderMode: String {
        case horizontal, vertical
    }

    init(comicId: String, episodes: [Episode], startEpisodeIndex: Int) {
        self.comicId = comicId
        self.episodes = episodes
        self.currentEpisodeIndex = startEpisodeIndex
    }

    var currentEpisode: Episode? {
        guard episodes.indices.contains(currentEpisodeIndex) else { return nil }
        return episodes[currentEpisodeIndex]
    }

    var hasPreviousEpisode: Bool { currentEpisodeIndex > 0 }
    var hasNextEpisode: Bool { currentEpisodeIndex < episodes.count - 1 }

    func loadPages() async {
        guard let episode = currentEpisode else { return }
        isLoading = true
        defer { isLoading = false }

        pages = []
        paginationPage = 0
        paginationTotalPages = 1

        while paginationPage < paginationTotalPages {
            let page = paginationPage + 1
            do {
                let response: APIResponse<ComicPagesData> = try await client.send(
                    .comicPages(comicId: comicId, epsOrder: episode.order, page: page)
                )
                if let data = response.data {
                    pages.append(contentsOf: data.pages.docs)
                    paginationPage = data.pages.page
                    paginationTotalPages = data.pages.pages
                }
            } catch {
                break
            }
        }
    }

    func goToEpisode(_ index: Int) async {
        guard episodes.indices.contains(index) else { return }
        currentEpisodeIndex = index
        await loadPages()
    }

    func nextEpisode() async {
        await goToEpisode(currentEpisodeIndex + 1)
    }

    func previousEpisode() async {
        await goToEpisode(currentEpisodeIndex - 1)
    }

    func toggleToolbar() {
        showToolbar.toggle()
    }

    func setReaderMode(_ mode: ReaderMode) {
        readerMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: "readerMode")
    }
}
