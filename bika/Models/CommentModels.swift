import Foundation

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
    let likesCount: Int?
    let commentsCount: Int?
    let isLiked: Bool?

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
        content = try? container.decode(String.self, forKey: .content)
        user = try? container.decode(Creator.self, forKey: .user)
        comic = try? container.decode(String.self, forKey: .comic)
        totalComments = try? container.decode(Int.self, forKey: .totalComments)
        isTop = try? container.decode(Bool.self, forKey: .isTop)
        hide = try? container.decode(Bool.self, forKey: .hide)
        created_at = try? container.decode(String.self, forKey: .created_at)
        likesCount = try? container.decode(Int.self, forKey: .likesCount)
        commentsCount = try? container.decode(Int.self, forKey: .commentsCount)
        isLiked = try? container.decode(Bool.self, forKey: .isLiked)
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
        docs = (try? pg.decode([Comment].self, forKey: .docs)) ?? []
        page = (try? pg.decode(Int.self, forKey: .page)) ?? 1
        pages = (try? pg.decode(Int.self, forKey: .pages)) ?? 1
        total = (try? pg.decode(Int.self, forKey: .total)) ?? 0
        topComments = (try? container.decode([Comment].self, forKey: .topComments)) ?? []
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
        docs = (try? pg.decode([Comment].self, forKey: .docs)) ?? []
        page = (try? pg.decode(Int.self, forKey: .page)) ?? 1
        pages = (try? pg.decode(Int.self, forKey: .pages)) ?? 1
    }
}

// MARK: - Post Comment

nonisolated struct PostCommentRequest: Encodable, Sendable {
    let content: String
}
