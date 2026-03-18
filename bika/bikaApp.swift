import SwiftUI

@main
struct bikaApp: App {
    @State private var authVM = AuthViewModel()
    @State private var themeManager = ThemeManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(authVM)
                .preferredColorScheme(themeManager.colorScheme)
        }
    }
}
