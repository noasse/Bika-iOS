import Foundation
import SwiftUI

enum MacSidebarGroup: String, CaseIterable, Identifiable {
    case discover = "发现"
    case shelf = "书架"
    case account = "账户"

    var id: String { rawValue }
}

enum MacSidebarItem: String, CaseIterable, Identifiable, Codable, Hashable {
    case categories
    case ranking
    case search
    case favourites
    case history
    case profile
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .categories: "分类"
        case .ranking: "排行榜"
        case .search: "搜索"
        case .favourites: "收藏"
        case .history: "历史"
        case .profile: "我的"
        case .settings: "设置"
        }
    }

    var systemImage: String {
        switch self {
        case .categories: "square.grid.2x2"
        case .ranking: "chart.bar"
        case .search: "magnifyingglass"
        case .favourites: "star"
        case .history: "clock.arrow.circlepath"
        case .profile: "person.crop.circle"
        case .settings: "gearshape"
        }
    }

    var group: MacSidebarGroup {
        switch self {
        case .categories, .ranking, .search:
            return .discover
        case .favourites, .history:
            return .shelf
        case .profile, .settings:
            return .account
        }
    }
}

enum MacThemeMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "跟随系统"
        case .light: "浅色"
        case .dark: "深色"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

enum MacReaderMode: String, CaseIterable, Codable, Identifiable {
    case waterfall
    case horizontal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .waterfall: "瀑布"
        case .horizontal: "横向"
        }
    }
}

enum MacListRoute: Hashable {
    case category(String)
    case author(String)
    case tag(String)
}

struct MacComicSummary: Identifiable, Hashable {
    let id: String
    let title: String
    let author: String?
    let thumbPath: String?
    let thumbServer: String?
    let categories: [String]
    let views: Int?
    let likes: Int?
    let episodeCount: Int?
    let lastReadDescription: String?

    var thumbURL: URL? {
        guard let thumbPath else { return nil }
        return Media(originalName: nil, path: thumbPath, fileServer: thumbServer).imageURL
    }

    init(comic: Comic) {
        id = comic.id
        title = comic.title
        author = comic.author
        thumbPath = comic.thumb?.path
        thumbServer = comic.thumb?.fileServer
        categories = comic.categories ?? []
        views = comic.displayViews
        likes = comic.displayLikes
        episodeCount = comic.epsCount
        lastReadDescription = nil
    }

    init(history: MacHistoryItem) {
        id = history.comicId
        title = history.title
        author = history.author
        thumbPath = history.thumbPath
        thumbServer = history.thumbServer
        categories = []
        views = nil
        likes = nil
        episodeCount = nil
        lastReadDescription = "\(history.episodeTitle) · 第 \(history.pageIndex + 1) 页"
    }
}

struct MacHistoryItem: Codable, Identifiable, Hashable {
    let comicId: String
    var title: String
    var author: String?
    var thumbPath: String?
    var thumbServer: String?
    var episodeOrder: Int
    var episodeTitle: String
    var pageIndex: Int
    var updatedAt: Date

    var id: String { comicId }
}

struct MacReadingProgress: Codable, Hashable {
    let episodeOrder: Int
    let episodeTitle: String
    let pageIndex: Int
}

func macClampedPage(_ page: Int, totalPages: Int) -> Int {
    min(max(page, 1), max(totalPages, 1))
}

struct MacReaderEpisode: Codable, Hashable, Identifiable {
    let id: String
    let title: String
    let order: Int

    init(episode: Episode) {
        id = episode.id
        title = episode.title
        order = episode.order
    }
}

struct MacReaderLaunchRequest: Codable, Hashable, Identifiable {
    let id: String
    let comicId: String
    let comicTitle: String
    let author: String?
    let thumbPath: String?
    let thumbServer: String?
    let episodes: [MacReaderEpisode]
    let startEpisodeIndex: Int
    let startPageIndex: Int
    let restoreSavedProgress: Bool

    init(
        comicId: String,
        comicTitle: String,
        author: String?,
        thumbPath: String?,
        thumbServer: String?,
        episodes: [MacReaderEpisode],
        startEpisodeIndex: Int,
        startPageIndex: Int,
        restoreSavedProgress: Bool
    ) {
        id = UUID().uuidString
        self.comicId = comicId
        self.comicTitle = comicTitle
        self.author = author
        self.thumbPath = thumbPath
        self.thumbServer = thumbServer
        self.episodes = episodes
        self.startEpisodeIndex = startEpisodeIndex
        self.startPageIndex = startPageIndex
        self.restoreSavedProgress = restoreSavedProgress
    }
}

struct MacCommentsLaunchRequest: Hashable, Identifiable {
    let comicId: String
    let comicTitle: String

    var id: String { comicId }
}

extension ImageQuality {
    var macTitle: String {
        switch self {
        case .original: "原图"
        case .low: "低"
        case .medium: "中"
        case .high: "高"
        }
    }
}

extension SortMode {
    var macTitle: String {
        switch self {
        case .defaultSort: "默认"
        case .newest: "新到旧"
        case .oldest: "旧到新"
        case .liked: "最多爱心"
        case .views: "最多观看"
        }
    }
}

extension LeaderboardType: CaseIterable, Identifiable {
    static var allCases: [LeaderboardType] { [.hour24, .day7, .day30] }

    var id: String { rawValue }

    var macTitle: String {
        switch self {
        case .hour24: "24 小时"
        case .day7: "7 天"
        case .day30: "30 天"
        }
    }
}
