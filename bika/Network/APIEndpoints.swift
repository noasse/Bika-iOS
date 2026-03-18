import Foundation

// MARK: - HTTP Method

nonisolated enum HTTPMethod: String, Sendable {
    case GET
    case POST
    case PUT
    case DELETE
}

// MARK: - API Endpoint

nonisolated struct APIEndpoint<Response: Decodable & Sendable>: Sendable {
    let path: String
    let method: HTTPMethod
    let bodyData: @Sendable () throws -> Data?
    let requiresAuth: Bool

    init(path: String, method: HTTPMethod = .GET, requiresAuth: Bool = true) {
        self.path = path
        self.method = method
        self.bodyData = { nil }
        self.requiresAuth = requiresAuth
    }

    init<Body: Encodable & Sendable>(path: String, method: HTTPMethod, body: Body, requiresAuth: Bool = true) {
        self.path = path
        self.method = method
        self.bodyData = { try JSONEncoder().encode(body) }
        self.requiresAuth = requiresAuth
    }
}

// MARK: - Auth Endpoints

extension APIEndpoint where Response == APIResponse<SignInData> {
    static func signIn(email: String, password: String) -> Self {
        APIEndpoint(
            path: "auth/sign-in",
            method: .POST,
            body: SignInRequest(email: email, password: password),
            requiresAuth: false
        )
    }
}

extension APIEndpoint where Response == APIResponse<EmptyData> {
    static func register(_ request: RegisterRequest) -> Self {
        APIEndpoint(
            path: "auth/register",
            method: .POST,
            body: request,
            requiresAuth: false
        )
    }

    static func punchIn() -> Self {
        APIEndpoint(path: "users/punch-in", method: .POST)
    }

    static func setSlogan(_ slogan: String) -> Self {
        APIEndpoint(
            path: "users/profile",
            method: .PUT,
            body: UpdateSloganRequest(slogan: slogan)
        )
    }

    static func changePassword(old: String, new: String) -> Self {
        APIEndpoint(
            path: "users/password",
            method: .PUT,
            body: UpdatePasswordRequest(old_password: old, new_password: new)
        )
    }

    static func postComment(comicId: String, content: String) -> Self {
        APIEndpoint(
            path: "comics/\(comicId)/comments",
            method: .POST,
            body: PostCommentRequest(content: content)
        )
    }

    static func postChildComment(commentId: String, content: String) -> Self {
        APIEndpoint(
            path: "comments/\(commentId)/childrens",
            method: .POST,
            body: PostCommentRequest(content: content)
        )
    }
}

// MARK: - User Endpoints

extension APIEndpoint where Response == APIResponse<UserProfileData> {
    static func myProfile() -> Self {
        APIEndpoint(path: "users/profile")
    }
}

// MARK: - Categories

extension APIEndpoint where Response == APIResponse<CategoriesData> {
    static func categories() -> Self {
        APIEndpoint(path: "categories")
    }
}

// MARK: - Comics

extension APIEndpoint where Response == APIResponse<ComicsData> {
    static func comics(category: String, page: Int = 1, sort: SortMode = .defaultSort) -> Self {
        let encodedCategory = category.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? category
        return APIEndpoint(path: "comics?page=\(page)&c=\(encodedCategory)&s=\(sort.rawValue)")
    }

    static func search(keyword: String, page: Int = 1, sort: SortMode = .defaultSort, categories: [String]? = nil) -> Self {
        APIEndpoint(
            path: "comics/advanced-search?page=\(page)",
            method: .POST,
            body: SearchRequest(keyword: keyword, sort: sort.rawValue, categories: categories)
        )
    }

    static func favourites(page: Int = 1, sort: SortMode = .defaultSort) -> Self {
        APIEndpoint(path: "users/favourite?s=\(sort.rawValue)&page=\(page)")
    }
}

// MARK: - Comic Detail

extension APIEndpoint where Response == APIResponse<ComicDetailData> {
    static func comicDetail(id: String) -> Self {
        APIEndpoint(path: "comics/\(id)")
    }
}

// MARK: - Episodes

extension APIEndpoint where Response == APIResponse<EpisodesData> {
    static func episodes(comicId: String, page: Int = 1) -> Self {
        APIEndpoint(path: "comics/\(comicId)/eps?page=\(page)")
    }
}

// MARK: - Comic Pages

extension APIEndpoint where Response == APIResponse<ComicPagesData> {
    static func comicPages(comicId: String, epsOrder: Int, page: Int = 1) -> Self {
        APIEndpoint(path: "comics/\(comicId)/order/\(epsOrder)/pages?page=\(page)")
    }
}

// MARK: - Like / Favourite Actions

extension APIEndpoint where Response == APIResponse<LikeActionData> {
    static func likeComic(id: String) -> Self {
        APIEndpoint(path: "comics/\(id)/like", method: .POST)
    }

    static func likeComment(id: String) -> Self {
        APIEndpoint(path: "comments/\(id)/like", method: .POST)
    }
}

extension APIEndpoint where Response == APIResponse<FavouriteData> {
    static func favouriteComic(id: String) -> Self {
        APIEndpoint(path: "comics/\(id)/favourite", method: .POST)
    }
}

// MARK: - Comments

extension APIEndpoint where Response == APIResponse<CommentsData> {
    static func comments(comicId: String, page: Int = 1) -> Self {
        APIEndpoint(path: "comics/\(comicId)/comments?page=\(page)")
    }
}

extension APIEndpoint where Response == APIResponse<ChildCommentsData> {
    static func childComments(commentId: String, page: Int = 1) -> Self {
        APIEndpoint(path: "comments/\(commentId)/childrens?page=\(page)")
    }
}

// MARK: - Leaderboard

extension APIEndpoint where Response == APIResponse<LeaderboardData> {
    static func leaderboard(type: LeaderboardType) -> Self {
        APIEndpoint(path: "comics/leaderboard?tt=\(type.rawValue)&ct=VC")
    }
}

// MARK: - Recommended

extension APIEndpoint where Response == APIResponse<RecommendedData> {
    static func recommended(comicId: String) -> Self {
        APIEndpoint(path: "comics/\(comicId)/recommendation")
    }
}
