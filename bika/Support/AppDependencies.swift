import Foundation

final nonisolated class AppDependencies: @unchecked Sendable {
    static let shared = AppDependencies()

    private let lock = NSLock()
    private var _keyValueStore: any KeyValueStore = UserDefaultsKeyValueStore.standard
    private var _imageDataLoader: any ImageDataLoading = URLSessionImageDataLoader()
    private var _launchConfig = UITestLaunchConfig.disabled

    private init() {}

    var keyValueStore: any KeyValueStore {
        lock.withLock { _keyValueStore }
    }

    var imageDataLoader: any ImageDataLoading {
        lock.withLock { _imageDataLoader }
    }

    var launchConfig: UITestLaunchConfig {
        lock.withLock { _launchConfig }
    }

    var isUITesting: Bool {
        launchConfig.isEnabled
    }

    func configureForLaunch() {
        let launchConfig = UITestLaunchConfig.current
        let keyValueStore = configuredKeyValueStore(for: launchConfig)

        if launchConfig.preloadAuthenticatedSession {
            keyValueStore.set("ui-test-token", forKey: TokenStore.tokenKey)
        } else if launchConfig.isEnabled {
            keyValueStore.removeObject(forKey: TokenStore.tokenKey)
        }

        if let initialImageQuality = launchConfig.initialImageQuality {
            keyValueStore.set(initialImageQuality.rawValue, forKey: APIConfig.imageQualityKey)
        }

        let imageDataLoader: any ImageDataLoading = launchConfig.isEnabled
            ? FixtureImageDataLoader()
            : URLSessionImageDataLoader()

        let apiClient = makeAPIClient(using: keyValueStore, launchConfig: launchConfig)
        APIClient.shared = apiClient

        lock.withLock {
            _keyValueStore = keyValueStore
            _imageDataLoader = imageDataLoader
            _launchConfig = launchConfig
        }
    }

    func installForTesting(
        apiClient: APIClient? = nil,
        keyValueStore: any KeyValueStore,
        imageDataLoader: any ImageDataLoading = FixtureImageDataLoader(),
        launchConfig: UITestLaunchConfig = .disabled
    ) {
        let resolvedAPIClient = apiClient ?? makeAPIClient(using: keyValueStore, launchConfig: launchConfig)
        APIClient.shared = resolvedAPIClient

        lock.withLock {
            _keyValueStore = keyValueStore
            _imageDataLoader = imageDataLoader
            _launchConfig = launchConfig
        }
    }

    private func configuredKeyValueStore(for launchConfig: UITestLaunchConfig) -> any KeyValueStore {
        guard launchConfig.isEnabled,
              let uiTestStore = UserDefaultsKeyValueStore(suiteName: launchConfig.storeSuiteName) else {
            return UserDefaultsKeyValueStore.standard
        }

        if launchConfig.resetPersistentState {
            uiTestStore.resetPersistentState()
        }

        return uiTestStore
    }

    private func makeAPIClient(using keyValueStore: any KeyValueStore, launchConfig: UITestLaunchConfig) -> APIClient {
        let tokenStore = TokenStore(store: keyValueStore)

        if launchConfig.isEnabled {
            let sessionConfiguration = URLSessionConfiguration.ephemeral
            sessionConfiguration.protocolClasses = [MockURLProtocol.self]
            let session = URLSession(configuration: sessionConfiguration)

            MockURLProtocol.requestHandler = nil
            MockURLProtocol.activeScenario = launchConfig.scenario
            MockURLProtocol.keyValueStore = keyValueStore

            return APIClient(session: session, tokenStore: tokenStore)
        }

        MockURLProtocol.reset()
        MockURLProtocol.keyValueStore = keyValueStore

        return APIClient(session: .shared, tokenStore: tokenStore)
    }
}
