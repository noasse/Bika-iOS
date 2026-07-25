import SwiftUI

@main
struct bikaApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var authVM: AuthViewModel
    @State private var themeManager: ThemeManager

    init() {
        AppDependencies.shared.configureForLaunch()
        _authVM = State(initialValue: AuthViewModel())
        _themeManager = State(initialValue: ThemeManager.shared)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(authVM)
                .preferredColorScheme(themeManager.colorScheme)
                .onChange(of: scenePhase) { _, newPhase in
                    guard newPhase != .active else { return }
                    Task { await ImageDiagnosticsService.shared.flush() }
                }
        }
    }
}
