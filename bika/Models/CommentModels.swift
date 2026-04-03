import Foundation

private extension KeyedDecodingContainer {
    nonisolated func decodeLossyIfPresent<T: Decodable>(_ type: T.Type, forKey key: Key) -> T? {
        try? decodeIfPresent(type, forKey: key)
    }
}

// MARK: - Comment

nonisolated struct Comment: Decodable, Sendable, Identifiable, Hashable {
    static func == (lhs: Comment, rhs: Comment) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    let id: String
    let content: String?
    let user: Creator?
    let comic: String?
    let totalComments: Int?
    let isTop: Bool?
    let hide: Bool?
    let created_at: String?
    var likesCount: Int?
    let commentsCount: Int?
    var isLiked: Bool?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case content
        case user = "_user"
        case comic = "_comic"
        case totalComments
        case isTop, hide, created_at
        case likesCount, commentsCount, isLiked
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        content = container.decodeLossyIfPresent(String.self, forKey: .content)
        user = container.decodeLossyIfPresent(Creator.self, forKey: .user)
        comic = container.decodeLossyIfPresent(String.self, forKey: .comic)
        totalComments = container.decodeLossyIfPresent(Int.self, forKey: .totalComments)
        isTop = container.decodeLossyIfPresent(Bool.self, forKey: .isTop)
        hide = container.decodeLossyIfPresent(Bool.self, forKey: .hide)
        created_at = container.decodeLossyIfPresent(String.self, forKey: .created_at)
        likesCount = container.decodeLossyIfPresent(Int.self, forKey: .likesCount)
        commentsCount = container.decodeLossyIfPresent(Int.self, forKey: .commentsCount)
        isLiked = container.decodeLossyIfPresent(Bool.self, forKey: .isLiked)
    }
}

nonisolated struct CommentsData: Decodable, Sendable {
    let docs: [Comment]
    let topComments: [Comment]
    let page: Int
    let pages: Int
    let total: Int

    enum CodingKeys: String, CodingKey {
        case comments, topComments
    }

    enum PaginationKeys: String, CodingKey {
        case docs, total, limit, page, pages
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let pg = try container.nestedContainer(keyedBy: PaginationKeys.self, forKey: .comments)
        docs = try pg.decode([Comment].self, forKey: .docs)
        page = try pg.decode(Int.self, forKey: .page)
        pages = try pg.decode(Int.self, forKey: .pages)
        total = try pg.decode(Int.self, forKey: .total)
        topComments = try container.decodeIfPresent([Comment].self, forKey: .topComments) ?? []
    }
}

extension CommentsData {
    var pinnedCommentIDs: Set<String> {
        Set(topComments.map(\.id))
    }

    var containsPinnedCommentsInDocs: Bool {
        !pinnedCommentIDs.isDisjoint(with: Set(docs.map(\.id)))
    }

    var topLevelCommentDisplayCount: Int {
        if pinnedCommentIDs.isEmpty {
            return total
        }

        if containsPinnedCommentsInDocs {
            return total
        }

        return total + pinnedCommentIDs.count
    }

    func regularComments(excluding existingIDs: Set<String> = []) -> [Comment] {
        let excludedIDs = pinnedCommentIDs.union(existingIDs)
        return docs.filter { !excludedIDs.contains($0.id) }
    }
}

nonisolated struct ChildCommentsData: Decodable, Sendable {
    let docs: [Comment]
    let page: Int
    let pages: Int

    enum CodingKeys: String, CodingKey {
        case comments
    }

    enum PaginationKeys: String, CodingKey {
        case docs, total, limit, page, pages
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let pg = try container.nestedContainer(keyedBy: PaginationKeys.self, forKey: .comments)
        docs = try pg.decode([Comment].self, forKey: .docs)
        page = try pg.decode(Int.self, forKey: .page)
        pages = try pg.decode(Int.self, forKey: .pages)
    }
}

// MARK: - Post Comment

nonisolated struct PostCommentRequest: Encodable, Sendable {
    let content: String
}
