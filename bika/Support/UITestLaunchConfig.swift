import Foundation

struct UITestLaunchConfig: Sendable {
    enum Scenario: String, Sendable {
        case smoke
    }

    static let enabledArgument = "-ui-testing"
    static let authenticatedArgument = "-ui-authenticated"
    static let resetStateArgument = "-ui-reset-state"

    static let enabledEnvironmentKey = "UI_TESTING"
    static let authenticatedEnvironmentKey = "UI_TEST_AUTHENTICATED"
    static let resetStateEnvironmentKey = "UI_TEST_RESET_STATE"
    static let scenarioEnvironmentKey = "UI_TEST_SCENARIO"
    static let storeSuiteEnvironmentKey = "UI_TEST_STORE_SUITE"
    static let currentImageQualityEnvironmentKey = "UI_TEST_IMAGE_QUALITY"

    static let defaultStoreSuiteName = "com.noasse.bika.ui-tests"

    let isEnabled: Bool
    let preloadAuthenticatedSession: Bool
    let resetPersistentState: Bool
    let scenario: Scenario
    let storeSuiteName: String
    let initialImageQuality: ImageQuality?

    init(
        isEnabled: Bool,
        preloadAuthenticatedSession: Bool,
        resetPersistentState: Bool,
        scenario: Scenario,
        storeSuiteName: String,
        initialImageQuality: ImageQuality?
    ) {
        self.isEnabled = isEnabled
        self.preloadAuthenticatedSession = preloadAuthenticatedSession
        self.resetPersistentState = resetPersistentState
        self.scenario = scenario
        self.storeSuiteName = storeSuiteName
        self.initialImageQuality = initialImageQuality
    }

    static let disabled = UITestLaunchConfig(
        isEnabled: false,
        preloadAuthenticatedSession: false,
        resetPersistentState: false,
        scenario: .smoke,
        storeSuiteName: defaultStoreSuiteName,
        initialImageQuality: nil
    )

    static var current: UITestLaunchConfig {
        let processInfo = ProcessInfo.processInfo
        let arguments = Set(processInfo.arguments)
        let environment = processInfo.environment

        let isEnabled = arguments.contains(enabledArgument) || environment[enabledEnvironmentKey] == "1"
        let preloadAuthenticatedSession = arguments.contains(authenticatedArgument) || environment[authenticatedEnvironmentKey] == "1"
        let resetPersistentState = arguments.contains(resetStateArgument) || environment[resetStateEnvironmentKey] == "1"

        let scenario = Scenario(rawValue: environment[scenarioEnvironmentKey] ?? "") ?? .smoke
        let storeSuiteName = environment[storeSuiteEnvironmentKey] ?? defaultStoreSuiteName
        let initialImageQuality = ImageQuality(rawValue: environment[currentImageQualityEnvironmentKey] ?? "")

        return UITestLaunchConfig(
            isEnabled: isEnabled,
            preloadAuthenticatedSession: preloadAuthenticatedSession,
            resetPersistentState: resetPersistentState,
            scenario: scenario,
            storeSuiteName: storeSuiteName,
            initialImageQuality: initialImageQuality
        )
    }
}
