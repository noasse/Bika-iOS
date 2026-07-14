import Foundation

nonisolated struct MockHTTPResponse: Sendable {
    let statusCode: Int
    let headers: [String: String]
    let data: Data
}

nonisolated enum MockURLProtocolError: Error {
    case missingResponse
    case unsupportedScenario
}

typealias MockURLProtocolHandler = @Sendable (URLRequest) async throws -> MockHTTPResponse

private final nonisolated class MockURLProtocolState: @unchecked Sendable {
    nonisolated struct Snapshot: Sendable {
        let requestHandler: MockURLProtocolHandler?
        let activeScenario: UITestLaunchConfig.Scenario?
        let keyValueStore: any KeyValueStore
    }

    private let lock = NSLock()
    private var _requestHandler: MockURLProtocolHandler?
    private var _activeScenario: UITestLaunchConfig.Scenario?
    private var _keyValueStore: any KeyValueStore = UserDefaultsKeyValueStore.standard

    var requestHandler: MockURLProtocolHandler? {
        get { lock.withLock { _requestHandler } }
        set { lock.withLock { _requestHandler = newValue } }
    }

    var activeScenario: UITestLaunchConfig.Scenario? {
        get { lock.withLock { _activeScenario } }
        set { lock.withLock { _activeScenario = newValue } }
    }

    var keyValueStore: any KeyValueStore {
        get { lock.withLock { _keyValueStore } }
        set { lock.withLock { _keyValueStore = newValue } }
    }

    func snapshot() -> Snapshot {
        lock.withLock {
            Snapshot(
                requestHandler: _requestHandler,
                activeScenario: _activeScenario,
                keyValueStore: _keyValueStore
            )
        }
    }

    func reset() {
        lock.withLock {
            _requestHandler = nil
            _activeScenario = nil
            _keyValueStore = UserDefaultsKeyValueStore.standard
        }
    }
}

extension URLRequest {
    nonisolated func resolvedHTTPBodyData() -> Data? {
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

final nonisolated class MockURLProtocol: URLProtocol, @unchecked Sendable {
    static let lastImageQualityHeaderKey = "uiTest.lastImageQualityHeader"

    private static let state = MockURLProtocolState()

    static var requestHandler: MockURLProtocolHandler? {
        get { state.requestHandler }
        set { state.requestHandler = newValue }
    }

    static var activeScenario: UITestLaunchConfig.Scenario? {
        get { state.activeScenario }
        set { state.activeScenario = newValue }
    }

    static var keyValueStore: any KeyValueStore {
        get { state.keyValueStore }
        set { state.keyValueStore = newValue }
    }

    private let loadingTaskLock = NSLock()
    private var loadingTask: Task<Void, Never>?
    private var isStopRequested = false
    private let clientCallbackLock = NSRecursiveLock()
    private var isStopped = false

    override class func canInit(with request: URLRequest) -> Bool {
        guard let scheme = request.url?.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        var taskToCancel: Task<Void, Never>?
        loadingTaskLock.withLock {
            let task = Task<Void, Never> { [weak self] in
                guard let self else { return }
                await self.loadRequest()
            }

            if isStopRequested {
                taskToCancel = task
            } else {
                taskToCancel = loadingTask
                loadingTask = task
            }
        }
        taskToCancel?.cancel()
    }

    override func stopLoading() {
        let task = loadingTaskLock.withLock {
            isStopRequested = true
            defer { loadingTask = nil }
            return loadingTask
        }
        task?.cancel()

        withClientCallbackLock {
            isStopped = true
        }
    }

    static func reset() {
        state.reset()
    }

    private func loadRequest() async {
        do {
            let configuration = Self.state.snapshot()
            let response = try await Self.resolveResponse(for: request, configuration: configuration)
            guard !Task.isCancelled else { return }

            Self.recordHeaders(from: request, keyValueStore: configuration.keyValueStore)
            guard !Task.isCancelled else { return }

            guard let url = request.url,
                  client != nil else {
                throw URLError(.badURL)
            }

            let httpResponse = HTTPURLResponse(
                url: url,
                statusCode: response.statusCode,
                httpVersion: nil,
                headerFields: response.headers
            )!

            notifyClient {
                $0.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
            }
            notifyClient {
                $0.urlProtocol(self, didLoad: response.data)
            }
            notifyClient {
                $0.urlProtocolDidFinishLoading(self)
            }
        } catch {
            notifyClient {
                $0.urlProtocol(self, didFailWithError: error)
            }
        }
    }

    private func notifyClient(_ callback: (any URLProtocolClient) -> Void) {
        withClientCallbackLock {
            guard !isStopped,
                  !Task.isCancelled,
                  let client else { return }
            callback(client)
        }
    }

    @discardableResult
    private func withClientCallbackLock<T>(_ action: () throws -> T) rethrows -> T {
        clientCallbackLock.lock()
        defer { clientCallbackLock.unlock() }
        return try action()
    }

    private static func resolveResponse(
        for request: URLRequest,
        configuration: MockURLProtocolState.Snapshot
    ) async throws -> MockHTTPResponse {
        if let requestHandler = configuration.requestHandler {
            return try await requestHandler(request)
        }

        guard let scenario = configuration.activeScenario else {
            throw MockURLProtocolError.missingResponse
        }

        switch scenario {
        case .smoke:
            return try SmokeFixtureRouter.response(for: request)
        }
    }

    private static func recordHeaders(from request: URLRequest, keyValueStore: any KeyValueStore) {
        if let imageQuality = request.value(forHTTPHeaderField: "image-quality") {
            keyValueStore.set(imageQuality, forKey: lastImageQualityHeaderKey)
        }
    }
}
