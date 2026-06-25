import SwiftUI

struct ContentView: View {
    @Bindable var model: MacLibraryModel
    let commentsWindowStore: MacCommentsWindowStore
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if model.isCheckingToken {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("正在检查登录状态")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.isAuthenticated {
                MacLibraryRootView(model: model, commentsWindowStore: commentsWindowStore)
            } else {
                MacLoginView(model: model)
            }
        }
        .tint(MacUI.accentPink)
        .background(MacUI.appBackground(for: colorScheme))
        .task {
            await model.checkTokenIfNeeded()
        }
    }
}

#Preview {
    ContentView(
        model: MacLibraryModel(readingStore: MacReadingStore()),
        commentsWindowStore: MacCommentsWindowStore()
    )
}
