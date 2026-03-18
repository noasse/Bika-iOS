import Foundation

// MARK: - User Profile

nonisolated struct UserProfile: Decodable, Sendable {
    let id: String?
    let email: String?
    let name: String
    let birthday: String?
    let gender: String?
    let title: String?
    let verified: Bool?
    let exp: Int?
    let level: Int?
    let characters: [String]?
    let avatar: Media?
    let isPunched: Bool?
    let slogan: String?
    let role: String?
    let created_at: String?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case email, name, birthday, gender, title, verified
        case exp, level, characters, avatar, isPunched, slogan
        case role, created_at
    }
}

nonisolated struct UserProfileData: Decodable, Sendable {
    let user: UserProfile
}

// MARK: - Punch In

nonisolated struct PunchInData: Decodable, Sendable {
    let res: PunchInResult
}

nonisolated struct PunchInResult: Decodable, Sendable {
    let status: String      // "ok"
    let punchInLastDay: String?
}

// MARK: - Favourite

nonisolated struct FavouriteData: Decodable, Sendable {
    let comics: PaginatedResponse<Comic>
}

// MARK: - Update Requests

nonisolated struct UpdatePasswordRequest: Encodable, Sendable {
    let old_password: String
    let new_password: String
}

nonisolated struct UpdateSloganRequest: Encodable, Sendable {
    let slogan: String
}
