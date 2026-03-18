import Foundation

nonisolated struct APIResponse<T: Decodable & Sendable>: Decodable, Sendable {
    let code: Int
    let message: String
    let data: T?

    enum CodingKeys: String, CodingKey {
        case code
        case message
        case data
    }
}

nonisolated struct PaginatedResponse<T: Decodable & Sendable>: Decodable, Sendable {
    let docs: [T]
    let total: Int
    let limit: Int
    let page: Int
    let pages: Int
}

nonisolated struct EmptyData: Decodable, Sendable {}
