import SwiftUI

@main
struct bikaApp: App {
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
        }
    }
}
