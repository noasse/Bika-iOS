import Foundation

// MARK: - Token Store (persisted to UserDefaults)

actor TokenStore {
    private static let tokenKey = "com.bika.authToken"
    private var token: String? = UserDefaults.standard.string(forKey: tokenKey)

    func setToken(_ token: String?) {
        self.token = token
        if let token {
            UserDefaults.standard.set(token, forKey: Self.tokenKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.tokenKey)
        }
    }

    func getToken() -> String? {
        token
    }

    func clear() {
        token = nil
        UserDefaults.standard.removeObject(forKey: Self.tokenKey)
    }
}

// MARK: - Protocol

nonisolated protocol APIClientProtocol: Sendable {
    func send<T: Decodable & Sendable>(_ endpoint: APIEndpoint<T>) async throws -> T
}

// MARK: - API Client

final nonisolated class APIClient: APIClientProtocol, Sendable {
    static let shared = APIClient()

    let tokenStore = TokenStore()
    private let session: URLSession
    private let decoder: JSONDecoder

    init(session: URLSession = .shared) {
        self.session = session
        let decoder = JSONDecoder()
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
        request.setValue(APIConfig.imageQualityDefault, forHTTPHeaderField: "image-quality")
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

        // Decode
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decodingError(error)
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
