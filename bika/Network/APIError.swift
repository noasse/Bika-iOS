import Foundation

nonisolated enum APIError: LocalizedError, Sendable {
    case invalidURL
    case httpError(statusCode: Int, data: Data?)
    case apiError(code: Int, message: String)
    case unauthorized
    case decodingError(Error)
    case networkError(Error)
    case noToken

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .httpError(let statusCode, _):
            return "HTTP error: \(statusCode)"
        case .apiError(let code, let message):
            return "API error (\(code)): \(message)"
        case .unauthorized:
            return "Unauthorized – please sign in again"
        case .decodingError(let error):
            return "Decoding error: \(error.localizedDescription)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .noToken:
            return "No auth token available"
        }
    }
}
