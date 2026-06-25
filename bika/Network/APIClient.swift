import Foundation
import Security

// MARK: - Token Storage

private nonisolated enum TokenStorageKeys {
    static let authToken = "com.bika.authToken"
}

nonisolated protocol TokenPersisting: Sendable {
    func token() -> String?
    func setToken(_ token: String?)
    func clearToken()
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
    private let service: String
    private let account: String
    private let legacyStore: any KeyValueStore
    private let lock = NSLock()

    init(
        service: String = Bundle.main.bundleIdentifier ?? "com.bika.auth",
        account: String = TokenStorageKeys.authToken,
        legacyStore: any KeyValueStore = AppDependencies.shared.keyValueStore
    ) {
        self.service = service
        self.account = account
        self.legacyStore = legacyStore
    }

    func token() -> String? {
        lock.withLock {
            if let keychainToken = readTokenLocked() {
                legacyStore.removeObject(forKey: TokenStorageKeys.authToken)
                return keychainToken
            }

            guard let legacyToken = legacyStore.string(forKey: TokenStorageKeys.authToken), !legacyToken.isEmpty else {
                return nil
            }

            _ = storeTokenLocked(legacyToken)
            legacyStore.removeObject(forKey: TokenStorageKeys.authToken)
            return legacyToken
        }
    }

    func setToken(_ token: String?) {
        lock.withLock {
            if let token, !token.isEmpty {
                _ = storeTokenLocked(token)
            } else {
                deleteTokenLocked()
            }
            legacyStore.removeObject(forKey: TokenStorageKeys.authToken)
        }
    }

    func clearToken() {
        lock.withLock {
            deleteTokenLocked()
            legacyStore.removeObject(forKey: TokenStorageKeys.authToken)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private func readTokenLocked() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func storeTokenLocked(_ token: String) -> Bool {
        let data = Data(token.utf8)
        let attributes = tokenAttributes(data: data)
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)

        if updateStatus == errSecSuccess {
            return true
        }

        guard updateStatus == errSecItemNotFound else {
            return false
        }

        var addQuery = baseQuery
        addQuery.merge(attributes) { _, new in new }
        return SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess
    }

    private func deleteTokenLocked() {
        SecItemDelete(baseQuery as CFDictionary)
    }

    private func tokenAttributes(data: Data) -> [String: Any] {
        var attributes: [String: Any] = [
            kSecValueData as String: data,
        ]

        #if os(iOS) || os(tvOS) || os(watchOS)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        #endif

        return attributes
    }
}

// MARK: - Token Store

actor TokenStore {
    static let tokenKey = TokenStorageKeys.authToken

    private let secureStore: any TokenPersisting
    private var token: String?

    init(secureStore: any TokenPersisting = SecureTokenStore()) {
        self.secureStore = secureStore
        token = secureStore.token()
    }

    init(store: any KeyValueStore) {
        let secureStore = KeyValueTokenStore(store: store)
        self.secureStore = secureStore
        token = secureStore.token()
    }

    func setToken(_ token: String?) {
        self.token = token
        secureStore.setToken(token)
    }

    func getToken() -> String? {
        token
    }

    func clear() {
        token = nil
        secureStore.clearToken()
    }
}

// MARK: - Protocol

nonisolated protocol APIClientProtocol: Sendable {
    var tokenStore: TokenStore { get }
    func send<T: Decodable & Sendable>(_ endpoint: APIEndpoint<T>) async throws -> T
    func signIn(email: String, password: String) async throws -> String
}

// MARK: - API Client

final nonisolated class APIClient: APIClientProtocol, Sendable {
    static var shared = APIClient()

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
            guard let token = await tokenStore.getToken() else {
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

        return .apiError(code: code, message: message)
    }

    private func validateBusinessResponseIfNeeded<T>(_ decoded: T) throws {
        guard let response = decoded as? any APIBusinessResponse else { return }
        guard (200...299).contains(response.code) else {
            throw APIError.apiError(code: response.code, message: response.message)
        }
    }

    // MARK: - Convenience: Sign In & store token

    func signIn(email: String, password: String) async throws -> String {
        let response: APIResponse<SignInData> = try await send(.signIn(email: email, password: password))
        guard let token = response.data?.token else {
            throw APIError.apiError(code: response.code, message: response.message)
        }
        await tokenStore.setToken(token)
        return token
    }
}
