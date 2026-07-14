import Foundation

final nonisolated class AppDependencies: @unchecked Sendable {
    static let shared = AppDependencies()

    struct Snapshot: Sendable {
        let apiClient: APIClient
        let keyValueStore: any KeyValueStore
        let imageDataLoader: any ImageDataLoading
        let launchConfig: UITestLaunchConfig
    }

    private let lock = NSLock()
    private var state: Snapshot

    private init() {
        let keyValueStore = UserDefaultsKeyValueStore.standard
        let launchConfig = UITestLaunchConfig.disabled
        state = Snapshot(
            apiClient: Self.makeAPIClient(using: keyValueStore, launchConfig: launchConfig),
            keyValueStore: keyValueStore,
            imageDataLoader: Self.makeLiveImageDataLoader(),
            launchConfig: launchConfig
        )
    }

    var snapshot: Snapshot {
        lock.withLock { state }
    }

    var apiClient: APIClient {
        snapshot.apiClient
    }

    var keyValueStore: any KeyValueStore {
        snapshot.keyValueStore
    }

    var imageDataLoader: any ImageDataLoading {
        snapshot.imageDataLoader
    }

    var launchConfig: UITestLaunchConfig {
        snapshot.launchConfig
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
            : Self.makeLiveImageDataLoader()

        let apiClient = Self.makeAPIClient(using: keyValueStore, launchConfig: launchConfig)

        lock.withLock {
            state = Snapshot(
                apiClient: apiClient,
                keyValueStore: keyValueStore,
                imageDataLoader: imageDataLoader,
                launchConfig: launchConfig
            )
        }
    }

    func installForTesting(
        apiClient: APIClient? = nil,
        keyValueStore: any KeyValueStore,
        imageDataLoader: any ImageDataLoading = FixtureImageDataLoader(),
        launchConfig: UITestLaunchConfig = .disabled
    ) {
        let resolvedAPIClient = apiClient
            ?? Self.makeAPIClient(using: keyValueStore, launchConfig: launchConfig)

        lock.withLock {
            state = Snapshot(
                apiClient: resolvedAPIClient,
                keyValueStore: keyValueStore,
                imageDataLoader: imageDataLoader,
                launchConfig: launchConfig
            )
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

    private static func makeAPIClient(
        using keyValueStore: any KeyValueStore,
        launchConfig: UITestLaunchConfig
    ) -> APIClient {
        let tokenStore = launchConfig.isEnabled
            ? TokenStore(store: keyValueStore)
            : TokenStore(secureStore: SecureTokenStore(legacyStore: keyValueStore))

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

    private static func makeLiveImageDataLoader() -> any ImageDataLoading {
#if os(iOS)
        return URLSessionImageDataLoader(cacheController: .shared)
#else
        return URLSessionImageDataLoader()
#endif
    }
}
