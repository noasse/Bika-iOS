import Foundation

// MARK: - Category

nonisolated struct Category: Decodable, Sendable, Identifiable, Hashable {
    let id: String?
    let title: String
    let description: String?
    let thumb: Media?
    let isWeb: Bool?
    let active: Bool?
    let link: String?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case title, description, thumb, isWeb, active, link
    }
}

nonisolated struct CategoriesData: Decodable, Sendable {
    let categories: [Category]
}

// MARK: - Comic (list item)

nonisolated struct Comic: Decodable, Sendable, Identifiable, Hashable {
    let id: String
    let title: String
    let author: String?
    let totalViews: Int?
    let viewsCount: Int?
    let totalLikes: Int?
    let pagesCount: Int?
    let epsCount: Int?
    let finished: Bool?
    let categories: [String]?
    let thumb: Media?
    let likesCount: Int?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case title, author, totalViews, viewsCount, totalLikes, pagesCount
        case epsCount, finished, categories, thumb, likesCount
    }
}

nonisolated struct ComicsData: Decodable, Sendable {
    let comics: PaginatedResponse<Comic>
}

// MARK: - Comic Detail

nonisolated struct ComicDetail: Decodable, Sendable {
    let id: String
    let title: String
    let author: String?
    let description: String?
    let chineseTeam: String?
    let categories: [String]?
    let tags: [String]?
    let pagesCount: Int?
    let epsCount: Int?
    let finished: Bool?
    let updated_at: String?
    let created_at: String?
    let thumb: Media?
    let creator: Creator?
    let totalViews: Int?
    let totalLikes: Int?
    let totalComments: Int?
    let viewsCount: Int?
    let likesCount: Int?
    let commentsCount: Int?
    let isFavourite: Bool?
    let isLiked: Bool?
    let allowDownload: Bool?
    let allowComment: Bool?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case title, author, description, chineseTeam
        case categories, tags, pagesCount, epsCount, finished
        case updated_at, created_at, thumb, creator
        case totalViews, totalLikes, totalComments
        case viewsCount, likesCount, commentsCount
        case isFavourite, isLiked, allowDownload, allowComment
    }
}

nonisolated struct ComicDetailData: Decodable, Sendable {
    let comic: ComicDetail
}

// MARK: - Episode

nonisolated struct Episode: Decodable, Sendable, Identifiable {
    let id: String
    let title: String
    let order: Int
    let updated_at: String?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case title, order, updated_at
    }
}

nonisolated struct EpisodesData: Decodable, Sendable {
    let eps: PaginatedResponse<Episode>
}

// MARK: - Comic Page (image)

nonisolated struct ComicPage: Decodable, Sendable {
    let id: String?
    let media: Media

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case media
    }
}

nonisolated struct ComicPagesData: Decodable, Sendable {
    let pages: PaginatedResponse<ComicPage>
    let ep: EpisodeRef?
}

nonisolated struct EpisodeRef: Decodable, Sendable {
    let id: String?
    let title: String?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case title
    }
}

// MARK: - Search

nonisolated struct SearchRequest: Encodable, Sendable {
    let keyword: String
    let sort: String?
    let categories: [String]?
}

// MARK: - Like Action

nonisolated struct LikeActionData: Decodable, Sendable {
    let action: String  // "like" or "unlike"
}

// MARK: - Leaderboard

nonisolated struct LeaderboardData: Decodable, Sendable {
    let comics: [Comic]
}

// MARK: - Recommended

nonisolated struct RecommendedData: Decodable, Sendable {
    let comics: [Comic]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Decode each comic individually, skipping any that fail
        var comicsContainer = try container.nestedUnkeyedContainer(forKey: .comics)
        var result: [Comic] = []
        while !comicsContainer.isAtEnd {
            if let comic = try? comicsContainer.decode(Comic.self) {
                result.append(comic)
            } else {
                // Skip the broken element
                _ = try? comicsContainer.decode(AnyCodable.self)
            }
        }
        comics = result
    }

    private enum CodingKeys: String, CodingKey {
        case comics
    }
}

// Helper to skip broken elements in arrays
private nonisolated struct AnyCodable: Decodable, Sendable {
    init(from decoder: Decoder) throws {
        _ = try? decoder.singleValueContainer()
    }
}
