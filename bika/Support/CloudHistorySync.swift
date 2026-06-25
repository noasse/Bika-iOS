import CryptoKit
import Foundation
import Security

nonisolated struct CloudHistoryConfig: Equatable, Sendable {
    nonisolated enum StorageKeys {
        static let isEnabled = "cloudHistory.isEnabled"
        static let baseURL = "cloudHistory.baseURL"
        static let bearerToken = "cloudHistory.bearerToken"
        static let certificateSHA256Pins = "cloudHistory.certificateSHA256Pins"
    }

    let baseURL: URL
    let bearerToken: String
    let certificateSHA256Pins: [String]
    let isEnabled: Bool

    init(
        baseURL: URL,
        bearerToken: String,
        certificateSHA256Pins: [String],
        isEnabled: Bool = true
    ) {
        self.baseURL = baseURL
        self.bearerToken = bearerToken
        self.certificateSHA256Pins = certificateSHA256Pins
        self.isEnabled = isEnabled
    }

    var isUsable: Bool {
        isEnabled &&
        baseURL.scheme?.lowercased() == "https" &&
        !bearerToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !certificateSHA256Pins.isEmpty
    }
}

extension KeyValueStore {
    nonisolated func cloudHistoryConfig() -> CloudHistoryConfig? {
        let enabledValue = string(forKey: CloudHistoryConfig.StorageKeys.isEnabled)
        guard enabledValue == "1" || enabledValue?.lowercased() == "true" else { return nil }
        guard
            let baseURLString = string(forKey: CloudHistoryConfig.StorageKeys.baseURL),
            let baseURL = URL(string: baseURLString),
            let bearerToken = string(forKey: CloudHistoryConfig.StorageKeys.bearerToken),
            let pins = stringArray(forKey: CloudHistoryConfig.StorageKeys.certificateSHA256Pins)
        else {
            return nil
        }

        let config = CloudHistoryConfig(baseURL: baseURL, bearerToken: bearerToken, certificateSHA256Pins: pins)
        return config.isUsable ? config : nil
    }

    nonisolated func setCloudHistoryConfig(_ config: CloudHistoryConfig) {
        set(config.isEnabled ? "1" : "0", forKey: CloudHistoryConfig.StorageKeys.isEnabled)
        set(config.baseURL.absoluteString, forKey: CloudHistoryConfig.StorageKeys.baseURL)
        set(config.bearerToken, forKey: CloudHistoryConfig.StorageKeys.bearerToken)
        set(config.certificateSHA256Pins, forKey: CloudHistoryConfig.StorageKeys.certificateSHA256Pins)
    }

    nonisolated func setCloudHistoryEnabled(_ isEnabled: Bool) {
        set(isEnabled ? "1" : "0", forKey: CloudHistoryConfig.StorageKeys.isEnabled)
    }

    nonisolated func clearCloudHistoryConfig() {
        removeObject(forKey: CloudHistoryConfig.StorageKeys.isEnabled)
        removeObject(forKey: CloudHistoryConfig.StorageKeys.baseURL)
        removeObject(forKey: CloudHistoryConfig.StorageKeys.bearerToken)
        removeObject(forKey: CloudHistoryConfig.StorageKeys.certificateSHA256Pins)
    }
}

nonisolated enum CloudHistoryJSON {
    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    static var decoder: JSONDecoder {
        JSONDecoder()
    }

    private static var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        return formatter
    }

    static func string(from date: Date) -> String {
        dateFormatter.string(from: date)
    }

    static func date(from string: String) -> Date? {
        dateFormatter.date(from: string)
    }
}

nonisolated struct CloudHistoryItem: Codable, Equatable, Identifiable, Sendable {
    let comicID: String
    var title: String
    var author: String?
    var thumbPath: String?
    var thumbServer: String?
    var lastReadAt: Date
    var episodeOrder: Int?
    var episodeTitle: String?
    var pageIndex: Int?

    var id: String { comicID }

    enum CodingKeys: String, CodingKey {
        case comicID = "comicId"
        case title
        case author
        case thumbPath
        case thumbServer
        case lastReadAt
        case episodeOrder
        case episodeTitle
        case pageIndex
    }

    init(
        comicID: String,
        title: String,
        author: String? = nil,
        thumbPath: String? = nil,
        thumbServer: String? = nil,
        lastReadAt: Date,
        episodeOrder: Int? = nil,
        episodeTitle: String? = nil,
        pageIndex: Int? = nil
    ) {
        self.comicID = comicID
        self.title = title
        self.author = author
        self.thumbPath = thumbPath
        self.thumbServer = thumbServer
        self.lastReadAt = lastReadAt
        self.episodeOrder = episodeOrder
        self.episodeTitle = episodeTitle
        self.pageIndex = pageIndex
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        comicID = try container.decode(String.self, forKey: .comicID)
        title = try container.decode(String.self, forKey: .title)
        author = try container.decodeIfPresent(String.self, forKey: .author)
        thumbPath = try container.decodeIfPresent(String.self, forKey: .thumbPath)
        thumbServer = try container.decodeIfPresent(String.self, forKey: .thumbServer)
        let dateString = try container.decode(String.self, forKey: .lastReadAt)
        guard let decodedDate = CloudHistoryJSON.date(from: dateString) else {
            throw DecodingError.dataCorruptedError(
                forKey: .lastReadAt,
                in: container,
                debugDescription: "Expected UTC ISO-8601 date formatted as yyyy-MM-dd'T'HH:mm:ss'Z'"
            )
        }
        lastReadAt = decodedDate
        episodeOrder = try container.decodeIfPresent(Int.self, forKey: .episodeOrder)
        episodeTitle = try container.decodeIfPresent(String.self, forKey: .episodeTitle)
        pageIndex = try container.decodeIfPresent(Int.self, forKey: .pageIndex)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(comicID, forKey: .comicID)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(author, forKey: .author)
        try container.encodeIfPresent(thumbPath, forKey: .thumbPath)
        try container.encodeIfPresent(thumbServer, forKey: .thumbServer)
        try container.encode(CloudHistoryJSON.string(from: lastReadAt), forKey: .lastReadAt)
        try container.encodeIfPresent(episodeOrder, forKey: .episodeOrder)
        try container.encodeIfPresent(episodeTitle, forKey: .episodeTitle)
        try container.encodeIfPresent(pageIndex, forKey: .pageIndex)
    }
}

private nonisolated struct CloudHistoryListResponse: Decodable, Sendable {
    let items: [CloudHistoryItem]
}

private nonisolated struct CloudHistoryBatchRequest: Encodable, Sendable {
    let items: [CloudHistoryItem]
}

nonisolated enum CloudHistoryClientError: LocalizedError, Sendable {
    case invalidEndpoint
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            return "云端历史同步地址无效"
        case .httpStatus(let statusCode):
            return "云端历史同步请求失败：HTTP \(statusCode)"
        }
    }
}

final nonisolated class CloudHistoryClient {
    private let config: CloudHistoryConfig
    private let session: URLSession

    init(config: CloudHistoryConfig, session: URLSession? = nil) {
        self.config = config
        if let session {
            self.session = session
        } else {
            let delegate = CloudHistoryPinnedCertificateDelegate(pins: config.certificateSHA256Pins)
            self.session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
        }
    }

    func fetchHistory(limit: Int = 200) async throws -> [CloudHistoryItem] {
        var request = URLRequest(url: try endpoint("v1/history"))
        request.httpMethod = "GET"
        request.setValue("Bearer \(config.bearerToken)", forHTTPHeaderField: "Authorization")

        if var components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false) {
            components.queryItems = [URLQueryItem(name: "limit", value: "\(limit)")]
            request.url = components.url
        }

        let data = try await send(request)
        return try CloudHistoryJSON.decoder.decode(CloudHistoryListResponse.self, from: data).items
    }

    func testConnection() async throws {
        _ = try await fetchHistory(limit: 1)
    }

    func uploadHistory(_ items: [CloudHistoryItem]) async throws {
        guard !items.isEmpty else { return }
        var request = URLRequest(url: try endpoint("v1/history/batch"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(config.bearerToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = try CloudHistoryJSON.encoder.encode(CloudHistoryBatchRequest(items: items))
        _ = try await send(request)
    }

    func deleteHistory(comicID: String) async throws {
        var request = URLRequest(url: try endpoint("v1/history/\(urlPathComponent(comicID))"))
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(config.bearerToken)", forHTTPHeaderField: "Authorization")
        _ = try await send(request)
    }

    func clearHistory() async throws {
        var request = URLRequest(url: try endpoint("v1/history/clear"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(config.bearerToken)", forHTTPHeaderField: "Authorization")
        _ = try await send(request)
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CloudHistoryClientError.httpStatus(-1)
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw CloudHistoryClientError.httpStatus(httpResponse.statusCode)
        }
        return data
    }

    private func endpoint(_ relativePath: String) throws -> URL {
        guard var components = URLComponents(url: config.baseURL, resolvingAgainstBaseURL: false) else {
            throw CloudHistoryClientError.invalidEndpoint
        }
        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let path = relativePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = "/" + [basePath, path].filter { !$0.isEmpty }.joined(separator: "/")
        guard let url = components.url else {
            throw CloudHistoryClientError.invalidEndpoint
        }
        return url
    }

    private func urlPathComponent(_ value: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}

final nonisolated class CloudHistoryPinnedCertificateDelegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate {
    private let pins: Set<String>

    init(pins: [String]) {
        self.pins = Set(pins.map(Self.normalizedPin(_:)).filter { !$0.isEmpty })
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        handleServerTrustChallenge(challenge, completionHandler: completionHandler)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        handleServerTrustChallenge(challenge, completionHandler: completionHandler)
    }

    private func handleServerTrustChallenge(
        _ challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard
            challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
            let trust = challenge.protectionSpace.serverTrust,
            let certificates = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
            let certificate = certificates.first
        else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        let certificateData = SecCertificateCopyData(certificate) as Data
        let digest = SHA256.hash(data: certificateData)
        let digestData = Data(digest)
        let base64 = digestData.base64EncodedString()
        let hex = digest.map { String(format: "%02x", $0) }.joined()

        if pins.contains(Self.normalizedPin(base64)) || pins.contains(Self.normalizedPin(hex)) {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }

    private static func normalizedPin(_ pin: String) -> String {
        pin.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

@MainActor
final class CloudHistorySyncService {
    static let shared = CloudHistorySyncService()

    private let keyValueStore: any KeyValueStore

    init(keyValueStore: any KeyValueStore = AppDependencies.shared.keyValueStore) {
        self.keyValueStore = keyValueStore
    }

    var isConfigured: Bool {
        keyValueStore.cloudHistoryConfig() != nil
    }

    func upload(_ item: CloudHistoryItem) {
        upload([item])
    }

    func upload(_ items: [CloudHistoryItem]) {
        guard let client = makeClient(), !items.isEmpty else { return }
        Task {
            try? await client.uploadHistory(items)
        }
    }

    func delete(comicID: String) {
        guard let client = makeClient() else { return }
        Task {
            try? await client.deleteHistory(comicID: comicID)
        }
    }

    func clear() {
        guard let client = makeClient() else { return }
        Task {
            try? await client.clearHistory()
        }
    }

    func fetchHistory(limit: Int = 200) async -> [CloudHistoryItem] {
        guard let client = makeClient() else { return [] }
        return (try? await client.fetchHistory(limit: limit)) ?? []
    }

    func testConnection() async throws {
        guard let client = makeClient() else {
            throw CloudHistoryClientError.invalidEndpoint
        }
        try await client.testConnection()
    }

    private func makeClient() -> CloudHistoryClient? {
        guard let config = keyValueStore.cloudHistoryConfig() else { return nil }
        return CloudHistoryClient(config: config)
    }
}
