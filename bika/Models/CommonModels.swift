import Foundation

nonisolated struct Media: Decodable, Sendable, Hashable {
    let originalName: String?
    let path: String
    let fileServer: String?

    var imageURL: URL? {
        let server = fileServer ?? "https://storage1.picacomic.com"
        let base = server.hasSuffix("/") ? server : server + "/"
        return URL(string: "\(base)static/\(path)")
    }
}

nonisolated struct Creator: Decodable, Sendable {
    let id: String?
    let gender: String?
    let name: String?
    let title: String?
    let verified: Bool?
    let exp: Int?
    let level: Int?
    let characters: [String]?
    let role: String?
    let avatar: Media?
    let slogan: String?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case gender, name, title, verified, exp, level
        case characters, role, avatar, slogan
    }
}
