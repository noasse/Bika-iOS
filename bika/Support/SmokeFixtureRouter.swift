import Foundation

enum SmokeFixtureRouter {
    static func response(for request: URLRequest) throws -> MockHTTPResponse {
        guard let url = request.url else { throw URLError(.badURL) }

        let method = request.httpMethod ?? "GET"
        let path = url.path
        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let page = Int(queryItems.first(where: { $0.name == "page" })?.value ?? "1") ?? 1

        switch (method, path) {
        case ("GET", "/categories"):
            return jsonResponse(data: ["categories": categories()])

        case ("GET", "/users/profile"):
            return jsonResponse(data: ["user": profile()])

        case ("POST", "/users/punch-in"):
            return jsonResponse(data: [:])

        case ("PUT", "/users/profile"):
            return jsonResponse(data: [:])

        case ("POST", "/comics/advanced-search"):
            let requestBody = decodeSearchRequest(from: request.resolvedHTTPBodyData())
            let sort = requestBody?.sort ?? SortMode.defaultSort.rawValue
            return jsonResponse(data: ["comics": searchResults(page: page, sort: sort)])

        case ("GET", let detailPath) where detailPath.hasPrefix("/comics/") && !detailPath.contains("/eps") && !detailPath.contains("/comments") && !detailPath.contains("/recommendation"):
            return jsonResponse(data: ["comic": comicDetail(id: comicIdentifier(from: detailPath))])

        case ("GET", let episodesPath) where episodesPath.hasSuffix("/eps"):
            let comicId = episodesPath
                .replacingOccurrences(of: "/comics/", with: "")
                .replacingOccurrences(of: "/eps", with: "")
            return jsonResponse(data: ["eps": episodes(comicId: comicId, page: page)])

        case ("GET", let pagesPath) where pagesPath.contains("/pages"):
            let (comicId, order) = parseComicPagesPath(pagesPath)
            return jsonResponse(data: ["pages": comicPages(comicId: comicId, order: order, page: page), "ep": ["_id": "episode-\(order)", "title": "第\(order)话"]])

        case ("GET", let commentsPath) where commentsPath.hasSuffix("/comments"):
            return jsonResponse(data: comments(page: page))

        case ("GET", let childCommentsPath) where childCommentsPath.contains("/childrens"):
            return jsonResponse(data: ["comments": childComments(page: page)])

        case ("GET", let recommendationPath) where recommendationPath.hasSuffix("/recommendation"):
            return jsonResponse(data: ["comics": recommended()])

        default:
            return jsonResponse(statusCode: 404, code: 404, message: "Fixture not found", data: [:])
        }
    }

    private static func jsonResponse(
        statusCode: Int = 200,
        code: Int = 200,
        message: String = "success",
        data: Any
    ) -> MockHTTPResponse {
        let body = try? JSONSerialization.data(withJSONObject: [
            "code": code,
            "message": message,
            "data": data,
        ])

        return MockHTTPResponse(
            statusCode: statusCode,
            headers: ["Content-Type": "application/json"],
            data: body ?? Data()
        )
    }

    private static func decodeSearchRequest(from body: Data?) -> SearchRequestBody? {
        guard let body else { return nil }
        return try? JSONDecoder().decode(SearchRequestBody.self, from: body)
    }

    private static func comicIdentifier(from detailPath: String) -> String {
        detailPath.replacingOccurrences(of: "/comics/", with: "")
    }

    private static func parseComicPagesPath(_ path: String) -> (String, Int) {
        let components = path.split(separator: "/")
        let comicId = components.dropFirst().first.map(String.init) ?? "comic-search-1"
        let order = Int(components.last(where: { $0 != "pages" }) ?? "1") ?? 1
        return (comicId, order)
    }

    private static func categories() -> [[String: Any]] {
        [
            [
                "_id": "category-1",
                "title": "嗶咔漢化",
                "description": "测试分类",
                "thumb": media(path: "category/1.png"),
                "isWeb": false,
                "active": true,
                "link": "",
            ],
            [
                "_id": "category-2",
                "title": "全彩",
                "description": "测试分类",
                "thumb": media(path: "category/2.png"),
                "isWeb": false,
                "active": true,
                "link": "",
            ],
        ]
    }

    private static func profile() -> [String: Any] {
        [
            "_id": "user-1",
            "email": "tester@example.com",
            "name": "UI Tester",
            "birthday": "2000-01-01",
            "gender": "bot",
            "title": "测试用户",
            "verified": true,
            "exp": 1200,
            "level": 7,
            "characters": ["测试"],
            "avatar": media(path: "avatars/tester.png"),
            "isPunched": false,
            "slogan": "只做冒烟，不接真网",
            "role": "user",
            "created_at": "2024-01-01T00:00:00.000Z",
        ]
    }

    private static func searchResults(page: Int, sort: String) -> [String: Any] {
        let pageOneDocs: [[String: Any]]
        if sort == SortMode.liked.rawValue {
            pageOneDocs = [
                comic(id: "comic-search-2", title: "爱心榜首"),
                comic(id: "comic-search-1", title: "冒烟漫画 Alpha"),
            ]
        } else {
            pageOneDocs = [
                comic(id: "comic-search-1", title: "冒烟漫画 Alpha"),
                comic(id: "comic-search-2", title: "冒烟漫画 Beta"),
            ]
        }

        let docs = page == 1
            ? pageOneDocs
            : [comic(id: "comic-search-3", title: "冒烟漫画 Gamma")]

        return [
            "docs": docs,
            "total": 3,
            "limit": 2,
            "page": page,
            "pages": 2,
        ]
    }

    private static func comicDetail(id: String) -> [String: Any] {
        let titleMap = [
            "comic-search-1": "冒烟漫画 Alpha",
            "comic-search-2": "爱心榜首",
            "comic-search-3": "冒烟漫画 Gamma",
        ]

        return [
            "_id": id,
            "title": titleMap[id] ?? "测试漫画",
            "author": "测试作者",
            "description": "用于 UI Smoke 的漫画详情",
            "chineseTeam": "测试汉化组",
            "categories": ["嗶咔漢化", "全彩"],
            "tags": ["测试", "冒烟"],
            "pagesCount": 6,
            "epsCount": 2,
            "finished": false,
            "updated_at": "2024-01-01T00:00:00.000Z",
            "created_at": "2024-01-01T00:00:00.000Z",
            "thumb": media(path: "comics/\(id)/thumb.png"),
            "creator": profile(),
            "totalViews": 100,
            "totalLikes": 50,
            "totalComments": 3,
            "viewsCount": 100,
            "likesCount": 50,
            "commentsCount": 3,
            "isFavourite": false,
            "isLiked": false,
            "allowDownload": false,
            "allowComment": true,
        ]
    }

    private static func episodes(comicId: String, page: Int) -> [String: Any] {
        let docs: [[String: Any]]
        if page == 1 {
            docs = [
                episode(id: "episode-2", title: "第2话", order: 2),
            ]
        } else {
            docs = [
                episode(id: "episode-1", title: "第1话", order: 1),
            ]
        }

        return [
            "docs": docs,
            "total": 2,
            "limit": 1,
            "page": page,
            "pages": 2,
        ]
    }

    private static func comicPages(comicId: String, order: Int, page: Int) -> [String: Any] {
        let docs: [[String: Any]]
        switch (order, page) {
        case (1, 1):
            docs = [
                comicPage(id: "page-\(comicId)-1-1", path: "reader/\(comicId)/1-1.png"),
                comicPage(id: "page-\(comicId)-1-2", path: "reader/\(comicId)/1-2.png"),
            ]
        case (2, 1):
            docs = [
                comicPage(id: "page-\(comicId)-2-1", path: "reader/\(comicId)/2-1.png"),
                comicPage(id: "page-\(comicId)-2-2", path: "reader/\(comicId)/2-2.png"),
            ]
        default:
            docs = []
        }

        return [
            "docs": docs,
            "total": docs.count,
            "limit": 2,
            "page": page,
            "pages": 1,
        ]
    }

    private static func comments(page: Int) -> [String: Any] {
        let docs: [[String: Any]]
        if page == 1 {
            docs = [
                comment(id: "comment-1", content: "第一页第一条评论", commentsCount: 1),
                comment(id: "comment-2", content: "第一页第二条评论", commentsCount: 0),
            ]
        } else {
            docs = [
                comment(id: "comment-3", content: "第二页评论", commentsCount: 0),
            ]
        }

        return [
            "comments": [
                "docs": docs,
                "total": 3,
                "limit": 2,
                "page": page,
                "pages": 2,
            ],
            "topComments": [
                comment(id: "comment-top", content: "置顶评论", commentsCount: 0, isTop: true),
            ],
        ]
    }

    private static func childComments(page: Int) -> [String: Any] {
        let docs: [[String: Any]] = page == 1
            ? [comment(id: "child-comment-1", content: "子评论内容", commentsCount: 0)]
            : []

        return [
            "docs": docs,
            "total": 1,
            "limit": 10,
            "page": page,
            "pages": 1,
        ]
    }

    private static func recommended() -> [[String: Any]] {
        [
            comic(id: "comic-recommend-1", title: "相关推荐"),
        ]
    }

    private static func comic(id: String, title: String) -> [String: Any] {
        [
            "_id": id,
            "title": title,
            "author": "测试作者",
            "totalViews": 100,
            "totalLikes": 50,
            "pagesCount": 120,
            "epsCount": 2,
            "finished": false,
            "categories": ["嗶咔漢化", "测试"],
            "thumb": media(path: "comics/\(id)/thumb.png"),
            "likesCount": 50,
        ]
    }

    private static func episode(id: String, title: String, order: Int) -> [String: Any] {
        [
            "_id": id,
            "title": title,
            "order": order,
            "updated_at": "2024-01-01T00:00:00.000Z",
        ]
    }

    private static func comicPage(id: String, path: String) -> [String: Any] {
        [
            "_id": id,
            "media": media(path: path),
        ]
    }

    private static func comment(id: String, content: String, commentsCount: Int, isTop: Bool = false) -> [String: Any] {
        [
            "_id": id,
            "content": content,
            "_user": [
                "_id": "creator-\(id)",
                "name": "评论用户",
                "level": 3,
                "avatar": media(path: "avatars/\(id).png"),
            ],
            "totalComments": commentsCount,
            "commentsCount": commentsCount,
            "isTop": isTop,
            "hide": false,
            "created_at": "2024-01-01T00:00:00.000Z",
            "likesCount": 3,
            "isLiked": false,
        ]
    }

    private static func media(path: String) -> [String: Any] {
        [
            "originalName": (path as NSString).lastPathComponent,
            "path": path,
            "fileServer": "https://fixtures.bika.test",
        ]
    }
}

private struct SearchRequestBody: Decodable {
    let keyword: String
    let sort: String?
    let categories: [String]?
}
