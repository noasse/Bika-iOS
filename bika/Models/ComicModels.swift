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

nonisolated enum SearchKeywordExpander {
    private static let defaultMaximumKeywordCount = 5
    private static let bracketPairs: [(String, String)] = [
        ("（", "）"),
        ("(", ")"),
        ("【", "】"),
        ("[", "]"),
        ("［", "］"),
        ("「", "」"),
        ("『", "』"),
        ("《", "》"),
        ("〈", "〉"),
        ("{", "}"),
        ("｛", "｝"),
    ]
    private static let separatorCharacters = CharacterSet(charactersIn: "，,、/／|｜;；:：·・+＋&＆")

    static func keywords(for rawKeyword: String, maximumCount: Int = defaultMaximumKeywordCount) -> [String] {
        let trimmed = cleanedKeyword(rawKeyword)
        guard !trimmed.isEmpty, maximumCount > 0 else { return [] }

        var result: [String] = []
        var seenKeys = Set<String>()
        var expansionQueue: [String] = []
        var expandedKeys = Set<String>()

        @discardableResult
        func append(_ keyword: String) -> Bool {
            let cleaned = cleanedKeyword(keyword)
            guard !cleaned.isEmpty else { return false }
            let key = normalizedKey(cleaned)
            guard seenKeys.insert(key).inserted else { return false }
            result.append(cleaned)
            expansionQueue.append(cleaned)
            return true
        }

        append(trimmed)

        var queueIndex = 0
        while queueIndex < expansionQueue.count, result.count < maximumCount {
            let keyword = expansionQueue[queueIndex]
            queueIndex += 1

            let expansionKey = normalizedKey(keyword)
            guard expandedKeys.insert(expansionKey).inserted else { continue }

            for variant in bracketVariants(for: keyword) + separatorVariants(for: keyword) {
                append(variant)
                if result.count >= maximumCount {
                    break
                }
            }
        }

        return result
    }

    static func matchesExpandedName(_ candidate: String?, query: String) -> Bool {
        let candidateAliases = aliases(for: candidate)
        guard !candidateAliases.isEmpty else { return false }
        let queryAliases = aliases(for: query)
        guard !queryAliases.isEmpty else { return false }
        return !candidateAliases.isDisjoint(with: queryAliases)
    }

    private static func aliases(for rawName: String?) -> Set<String> {
        guard let rawName else { return [] }
        return Set(
            keywords(for: rawName, maximumCount: 12)
                .map(normalizedKey)
                .filter { !$0.isEmpty }
        )
    }

    private static func bracketVariants(for keyword: String) -> [String] {
        var variants: [String] = []

        for (opening, closing) in bracketPairs {
            var searchStart = keyword.startIndex
            while
                searchStart < keyword.endIndex,
                let openingRange = keyword.range(of: opening, range: searchStart..<keyword.endIndex),
                let closingRange = keyword.range(of: closing, range: openingRange.upperBound..<keyword.endIndex)
            {
                let prefix = String(keyword[..<openingRange.lowerBound])
                let inner = String(keyword[openingRange.upperBound..<closingRange.lowerBound])
                let suffix = closingRange.upperBound < keyword.endIndex
                    ? String(keyword[closingRange.upperBound..<keyword.endIndex])
                    : ""
                variants.append(prefix + suffix)
                variants.append(inner)
                searchStart = closingRange.upperBound
            }
        }

        return variants
    }

    private static func separatorVariants(for keyword: String) -> [String] {
        let separators = separatorCharacters.union(.whitespacesAndNewlines)
        return keyword.components(separatedBy: separators)
    }

    private static func cleanedKeyword(_ keyword: String) -> String {
        keyword.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizedKey(_ keyword: String) -> String {
        cleanedKeyword(keyword)
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
    }
}

nonisolated enum SearchResultMerger {
    static func mergedPage(from pages: [PaginatedResponse<Comic>]) -> PaginatedResponse<Comic>? {
        guard let firstPage = pages.first else { return nil }

        var mergedDocs: [Comic] = []
        var seenComicIDs = Set<String>()
        var total = 0
        var limit = 0
        var pageCount = max(firstPage.pages, firstPage.page, 1)

        for page in pages {
            total += page.total
            limit = max(limit, page.limit)
            pageCount = max(pageCount, page.pages, page.page)

            for comic in page.docs where seenComicIDs.insert(comic.id).inserted {
                mergedDocs.append(comic)
            }
        }

        return PaginatedResponse(
            docs: mergedDocs,
            total: max(total, mergedDocs.count),
            limit: max(limit, mergedDocs.count, 1),
            page: max(firstPage.page, 1),
            pages: pageCount
        )
    }
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
