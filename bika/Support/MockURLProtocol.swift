import Foundation

struct MockHTTPResponse: Sendable {
    let statusCode: Int
    let headers: [String: String]
    let data: Data
}

enum MockURLProtocolError: Error {
    case missingResponse
    case unsupportedScenario
}

typealias MockURLProtocolHandler = @Sendable (URLRequest) async throws -> MockHTTPResponse

extension URLRequest {
    func resolvedHTTPBodyData() -> Data? {
        if let httpBody {
            return httpBody
        }

        guard let stream = httpBodyStream else {
            return nil
        }

        stream.open()
        defer { stream.close() }

        var data = Data()
        let bufferSize = 1024
        var buffer = [UInt8](repeating: 0, count: bufferSize)

        while stream.hasBytesAvailable {
            let bytesRead = stream.read(&buffer, maxLength: bufferSize)
            guard bytesRead >= 0 else {
                return nil
            }

            if bytesRead == 0 {
                break
            }

            data.append(buffer, count: bytesRead)
        }

        return data
    }
}

final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    static let lastImageQualityHeaderKey = "uiTest.lastImageQualityHeader"

    nonisolated(unsafe) static var requestHandler: MockURLProtocolHandler?
    nonisolated(unsafe) static var activeScenario: UITestLaunchConfig.Scenario?
    nonisolated(unsafe) static var keyValueStore: any KeyValueStore = UserDefaultsKeyValueStore.standard

    override class func canInit(with request: URLRequest) -> Bool {
        guard let scheme = request.url?.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Task {
            do {
                let response = try await Self.resolveResponse(for: request)
                Self.recordHeaders(from: request)

                guard let url = request.url,
                      let client else {
                    throw URLError(.badURL)
                }

                let httpResponse = HTTPURLResponse(
                    url: url,
                    statusCode: response.statusCode,
                    httpVersion: nil,
                    headerFields: response.headers
                )!

                client.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
                client.urlProtocol(self, didLoad: response.data)
                client.urlProtocolDidFinishLoading(self)
            } catch {
                client?.urlProtocol(self, didFailWithError: error)
            }
        }
    }

    override func stopLoading() {}

    static func reset() {
        requestHandler = nil
        activeScenario = nil
        keyValueStore = UserDefaultsKeyValueStore.standard
    }

    private static func resolveResponse(for request: URLRequest) async throws -> MockHTTPResponse {
        if let requestHandler {
            return try await requestHandler(request)
        }

        guard let scenario = activeScenario else {
            throw MockURLProtocolError.missingResponse
        }

        switch scenario {
        case .smoke:
            return try SmokeFixtureRouter.response(for: request)
        }
    }

    private static func recordHeaders(from request: URLRequest) {
        if let imageQuality = request.value(forHTTPHeaderField: "image-quality") {
            keyValueStore.set(imageQuality, forKey: lastImageQualityHeaderKey)
        }
    }
}
