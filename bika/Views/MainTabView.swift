import SwiftUI

struct MainTabView: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        TabView {
            Tab("分类", systemImage: "folder") {
                NavigationStack {
                    CategoriesView()
                }
            }
            Tab("排行榜", systemImage: "trophy") {
                NavigationStack {
                    LeaderboardView()
                }
            }
            Tab("搜索", systemImage: "magnifyingglass") {
                NavigationStack {
                    SearchView()
                }
            }
            Tab("我的", systemImage: "person") {
                NavigationStack {
                    ProfileView()
                }
            }
        }
        .tint(Color.accentPink)
    }
}
