import Foundation

// MARK: - Sign In

nonisolated struct SignInRequest: Encodable, Sendable {
    let email: String
    let password: String
}

nonisolated struct SignInData: Decodable, Sendable {
    let token: String
}

// MARK: - Register

nonisolated struct RegisterRequest: Encodable, Sendable {
    let email: String
    let password: String
    let name: String
    let birthday: String   // "2000-01-01"
    let gender: String     // "m", "f", "bot"
    let answer1: String
    let answer2: String
    let answer3: String
    let question1: String
    let question2: String
    let question3: String
}
