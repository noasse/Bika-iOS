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

    init(
        id: String,
        title: String,
        author: String?,
        totalViews: Int?,
        viewsCount: Int?,
        totalLikes: Int?,
        pagesCount: Int?,
        epsCount: Int?,
        finished: Bool?,
        categories: [String]?,
        thumb: Media?,
        likesCount: Int?
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.totalViews = totalViews
        self.viewsCount = viewsCount
        self.totalLikes = totalLikes
        self.pagesCount = pagesCount
        self.epsCount = epsCount
        self.finished = finished
        self.categories = categories
        self.thumb = thumb
        self.likesCount = likesCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        author = container.decodeLossyIfPresent(String.self, forKey: .author)
        totalViews = container.decodeFlexibleIntIfPresent(forKey: .totalViews)
        viewsCount = container.decodeFlexibleIntIfPresent(forKey: .viewsCount)
        totalLikes = container.decodeFlexibleIntIfPresent(forKey: .totalLikes)
        pagesCount = container.decodeFlexibleIntIfPresent(forKey: .pagesCount)
        epsCount = container.decodeFlexibleIntIfPresent(forKey: .epsCount)
        finished = container.decodeLossyIfPresent(Bool.self, forKey: .finished)
        categories = container.decodeLossyIfPresent([String].self, forKey: .categories)
        thumb = container.decodeLossyIfPresent(Media.self, forKey: .thumb)
        likesCount = container.decodeFlexibleIntIfPresent(forKey: .likesCount)
    }

    var displayViews: Int? {
        totalViews ?? viewsCount
    }

    var displayLikes: Int? {
        totalLikes ?? likesCount
    }

    func replacingCanonicalStats(totalViews: Int?, totalLikes: Int?) -> Comic {
        Comic(
            id: id,
            title: title,
            author: author,
            totalViews: totalViews ?? self.totalViews,
            viewsCount: viewsCount,
            totalLikes: totalLikes ?? self.totalLikes,
            pagesCount: pagesCount,
            epsCount: epsCount,
            finished: finished,
            categories: categories,
            thumb: thumb,
            likesCount: likesCount
        )
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
        var sawSourceComic = false
        while !comicsContainer.isAtEnd {
            sawSourceComic = true
            if let comic = try? comicsContainer.decode(Comic.self) {
                result.append(comic)
            } else {
                // Skip the broken element
                _ = try? comicsContainer.decode(AnyCodable.self)
            }
        }

        if sawSourceComic && result.isEmpty {
            throw DecodingError.dataCorruptedError(
                forKey: .comics,
                in: container,
                debugDescription: "All recommended comics failed to decode"
            )
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
