import SwiftUI

struct ContentView: View {
    @Environment(AuthViewModel.self) private var authVM

    var body: some View {
        Group {
            if authVM.isAuthenticated {
                MainTabView()
            } else if authVM.isCheckingToken {
                // Brief splash while checking saved token
                ZStack {
                    Color(.systemBackground).ignoresSafeArea()
                    VStack(spacing: 12) {
                        Image(systemName: "book.pages")
                            .font(.system(size: 60))
                            .foregroundStyle(Color.accentPink)
                        ProgressView()
                    }
                }
            } else {
                LoginView()
            }
        }
        .task { await authVM.checkToken() }
    }
}
