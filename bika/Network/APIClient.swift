import Foundation
import CryptoKit
import Security

// MARK: - Token Storage

private nonisolated enum TokenStorageKeys {
    static let authToken = "com.bika.authToken"
}

nonisolated protocol TokenPersisting: Sendable {
    func token() throws -> String?
    func setToken(_ token: String?) throws
    func clearToken() throws
}

nonisolated protocol KeychainAccessing: Sendable {
    func read(service: String, account: String) throws -> Data?
    func write(_ data: Data, service: String, account: String) throws
    func delete(service: String, account: String) throws
}

nonisolated enum KeychainAccessError: LocalizedError, Sendable {
    case invalidTokenData
    case unexpectedStatus(operation: String, status: OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidTokenData:
            return "Keychain token data is not valid UTF-8"
        case .unexpectedStatus(let operation, let status):
            return "Keychain \(operation) failed with status \(status)"
        }
    }
}

nonisolated struct SecurityKeychainAccess: KeychainAccessing {
    func read(service: String, account: String) throws -> Data? {
        var query = baseQuery(service: service, account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data else {
                throw KeychainAccessError.invalidTokenData
            }
            return data
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainAccessError.unexpectedStatus(operation: "read", status: status)
        }
    }

    func write(_ data: Data, service: String, account: String) throws {
        let query = baseQuery(service: service, account: account)
        let attributes = tokenAttributes(data: data)
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

        if updateStatus == errSecSuccess {
            return
        }

        guard updateStatus == errSecItemNotFound else {
            throw KeychainAccessError.unexpectedStatus(operation: "update", status: updateStatus)
        }

        var addQuery = query
        addQuery.merge(attributes) { _, new in new }
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainAccessError.unexpectedStatus(operation: "add", status: addStatus)
        }
    }

    func delete(service: String, account: String) throws {
        let status = SecItemDelete(baseQuery(service: service, account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainAccessError.unexpectedStatus(operation: "delete", status: status)
        }
    }

    private func baseQuery(service: String, account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private func tokenAttributes(data: Data) -> [String: Any] {
        var attributes: [String: Any] = [
            kSecValueData as String: data,
        ]

        // `kSecAttrAccessible` only applies to the data protection keychain. macOS would need
        // `kSecUseDataProtectionKeychain` to honour it, and that in turn requires an
        // `application-identifier` entitlement the ad-hoc signed macOS build does not carry.
        #if os(iOS) || os(tvOS) || os(watchOS)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        #endif

        return attributes
    }
}

final nonisolated class KeyValueTokenStore: @unchecked Sendable, TokenPersisting {
    private let store: any KeyValueStore

    init(store: any KeyValueStore) {
        self.store = store
    }

    func token() -> String? {
        store.string(forKey: TokenStorageKeys.authToken)
    }

    func setToken(_ token: String?) {
        store.set(token, forKey: TokenStorageKeys.authToken)
    }

    func clearToken() {
        store.removeObject(forKey: TokenStorageKeys.authToken)
    }
}

final nonisolated class SecureTokenStore: @unchecked Sendable, TokenPersisting {
    private enum SuppressionState {
        static let suppressed = "suppressed:v1"
        static let replacementPrefix = "replacement:v1:"
    }

    private let service: String
    private let account: String
    private let legacyStore: any KeyValueStore
    private let keychain: any KeychainAccessing
    private let lock = NSLock()

    private var suppressionKey: String {
        "\(TokenStorageKeys.authToken).suppressed.\(service).\(account)"
    }

    init(
        service: String = Bundle.main.bundleIdentifier ?? "com.bika.auth",
        account: String = TokenStorageKeys.authToken,
        legacyStore: any KeyValueStore = AppDependencies.shared.keyValueStore,
        keychain: any KeychainAccessing = SecurityKeychainAccess()
    ) {
        self.service = service
        self.account = account
        self.legacyStore = legacyStore
        self.keychain = keychain
    }

    func token() throws -> String? {
        try lock.withLock {
            if let suppressionState = legacyStore.string(forKey: suppressionKey) {
                let keychainData = try keychain.read(service: service, account: account)
                if let expectedDigest = replacementDigest(from: suppressionState),
                   let keychainData,
                   tokenDigest(keychainData) == expectedDigest {
                    guard let replacementToken = String(data: keychainData, encoding: .utf8) else {
                        throw KeychainAccessError.invalidTokenData
                    }
                    legacyStore.removeObject(forKey: TokenStorageKeys.authToken)
                    legacyStore.removeObject(forKey: suppressionKey)
                    return replacementToken
                }

                legacyStore.removeObject(forKey: TokenStorageKeys.authToken)
                try keychain.delete(service: service, account: account)
                legacyStore.removeObject(forKey: suppressionKey)
                return nil
            }

            if let keychainData = try keychain.read(service: service, account: account) {
                guard let keychainToken = String(data: keychainData, encoding: .utf8) else {
                    throw KeychainAccessError.invalidTokenData
                }
                legacyStore.removeObject(forKey: TokenStorageKeys.authToken)
                return keychainToken
            }

            guard let legacyToken = legacyStore.string(forKey: TokenStorageKeys.authToken), !legacyToken.isEmpty else {
                return nil
            }

            try keychain.write(Data(legacyToken.utf8), service: service, account: account)
            legacyStore.removeObject(forKey: TokenStorageKeys.authToken)
            return legacyToken
        }
    }

    func setToken(_ token: String?) throws {
        try lock.withLock {
            if let token, !token.isEmpty {
                let tokenData = Data(token.utf8)
                if legacyStore.string(forKey: suppressionKey) != nil {
                    legacyStore.set(replacementState(for: tokenData), forKey: suppressionKey)
                }
                try keychain.write(tokenData, service: service, account: account)
                legacyStore.removeObject(forKey: suppressionKey)
                legacyStore.removeObject(forKey: TokenStorageKeys.authToken)
            } else {
                try clearTokenLocked()
            }
        }
    }

    func clearToken() throws {
        try lock.withLock {
            try clearTokenLocked()
        }
    }

    private func clearTokenLocked() throws {
        legacyStore.set(SuppressionState.suppressed, forKey: suppressionKey)
        legacyStore.removeObject(forKey: TokenStorageKeys.authToken)
        try keychain.delete(service: service, account: account)
        legacyStore.removeObject(forKey: suppressionKey)
    }

    private func replacementState(for tokenData: Data) -> String {
        SuppressionState.replacementPrefix + tokenDigest(tokenData)
    }

    private func replacementDigest(from state: String) -> String? {
        guard state.hasPrefix(SuppressionState.replacementPrefix) else { return nil }
        let digest = String(state.dropFirst(SuppressionState.replacementPrefix.count))
        return digest.isEmpty ? nil : digest
    }

    private func tokenDigest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Token Store

actor TokenStore {
    static let tokenKey = TokenStorageKeys.authToken

    private let secureStore: any TokenPersisting
    private var token: String?
    private var didLoadToken = false

    init(secureStore: any TokenPersisting = SecureTokenStore()) {
        self.secureStore = secureStore
    }

    init(store: any KeyValueStore) {
        let secureStore = KeyValueTokenStore(store: store)
        self.secureStore = secureStore
    }

    func setToken(_ token: String?) throws {
        try secureStore.setToken(token)
        self.token = token
        didLoadToken = true
    }

    func getToken() throws -> String? {
        if !didLoadToken {
            token = try secureStore.token()
            didLoadToken = true
        }
        return token
    }

    func clear() throws {
        token = nil
        didLoadToken = true
        try secureStore.clearToken()
    }
}

// MARK: - Protocol

nonisolated protocol APIClientProtocol: Sendable {
    var tokenStore: TokenStore { get }
    func send<T: Decodable & Sendable>(_ endpoint: APIEndpoint<T>) async throws -> T
    func requestSignInToken(email: String, password: String) async throws -> String
    func signIn(email: String, password: String) async throws -> String
}

// MARK: - API Client

final nonisolated class APIClient: APIClientProtocol, Sendable {
    static var shared: APIClient {
        AppDependencies.shared.apiClient
    }

    let tokenStore: TokenStore
    private let session: URLSession
    private let decoder: JSONDecoder

    init(
        session: URLSession = .shared,
        tokenStore: TokenStore = TokenStore(),
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.tokenStore = tokenStore
        self.session = session
        self.decoder = decoder
    }

    func send<T: Decodable & Sendable>(_ endpoint: APIEndpoint<T>) async throws -> T {
        // Build URL
        guard let url = URL(string: APIConfig.baseURL + endpoint.path) else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method.rawValue

        // Timestamp & signature
        let timestamp = String(Int(Date().timeIntervalSince1970))
        let signature = APISignature.sign(
            path: endpoint.path,
            method: endpoint.method.rawValue,
            timestamp: timestamp
        )

        // 13 required headers
        request.setValue(APIConfig.apiKey, forHTTPHeaderField: "api-key")
        request.setValue(APIConfig.accept, forHTTPHeaderField: "accept")
        request.setValue(APIConfig.channel, forHTTPHeaderField: "app-channel")
        request.setValue(timestamp, forHTTPHeaderField: "time")
        request.setValue(APIConfig.nonce, forHTTPHeaderField: "nonce")
        request.setValue(signature, forHTTPHeaderField: "signature")
        request.setValue(APIConfig.version, forHTTPHeaderField: "app-version")
        request.setValue(APIConfig.buildVersion, forHTTPHeaderField: "app-build-version")
        request.setValue(APIConfig.platform, forHTTPHeaderField: "app-platform")
        request.setValue(APIConfig.appUUID, forHTTPHeaderField: "app-uuid")
        request.setValue(APIConfig.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(APIConfig.currentImageQuality.rawValue, forHTTPHeaderField: "image-quality")
        request.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")

        // Auth token
        if endpoint.requiresAuth {
            guard let token = try await tokenStore.getToken() else {
                throw APIError.noToken
            }
            request.setValue(token, forHTTPHeaderField: "authorization")
        }

        // Body
        if let bodyData = try endpoint.bodyData() {
            request.httpBody = bodyData
        }

        // Send
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.networkError(error)
        }

        // Check HTTP status
        if let httpResponse = response as? HTTPURLResponse {
            guard (200...299).contains(httpResponse.statusCode) else {
                if httpResponse.statusCode == 401 {
                    throw APIError.unauthorized
                }
                throw APIError.httpError(statusCode: httpResponse.statusCode, data: data)
            }
        }

        if let businessError = extractBusinessError(from: data) {
            throw businessError
        }

        // Decode
        do {
            let decoded = try decoder.decode(T.self, from: data)
            try validateBusinessResponseIfNeeded(decoded)
            return decoded
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.decodingError(error)
        }
    }

    private func extractBusinessError(from data: Data) -> APIError? {
        guard
            let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let code = jsonObject["code"] as? Int,
            let message = jsonObject["message"] as? String,
            !(200...299).contains(code)
        else {
            return nil
        }

        if code == 401 {
            return .unauthorized
        }

        return .apiError(code: code, message: message)
    }

    private func validateBusinessResponseIfNeeded<T>(_ decoded: T) throws {
        guard let response = decoded as? any APIBusinessResponse else { return }
        guard (200...299).contains(response.code) else {
            if response.code == 401 {
                throw APIError.unauthorized
            }
            throw APIError.apiError(code: response.code, message: response.message)
        }
    }

    // MARK: - Convenience: Sign In & store token

    func requestSignInToken(email: String, password: String) async throws -> String {
        let response: APIResponse<SignInData> = try await send(.signIn(email: email, password: password))
        guard let token = response.data?.token else {
            throw APIError.apiError(code: response.code, message: response.message)
        }
        return token
    }

    func signIn(email: String, password: String) async throws -> String {
        let token = try await requestSignInToken(email: email, password: password)
        try await tokenStore.setToken(token)
        return token
    }
}
