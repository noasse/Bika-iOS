import SwiftUI

struct MacLibraryRootView: View {
    @Bindable var model: MacLibraryModel
    let commentsWindowStore: MacCommentsWindowStore

    var body: some View {
        NavigationSplitView {
            MacSidebarView(model: model)
                .navigationSplitViewColumnWidth(min: 150, ideal: 190, max: 240)
        } content: {
            MacListPaneView(model: model)
                .navigationSplitViewColumnWidth(min: 280, ideal: 360, max: 520)
        } detail: {
            MacComicDetailPane(model: model, commentsWindowStore: commentsWindowStore)
                .navigationSplitViewColumnWidth(min: 320, ideal: 540)
        }
        .tint(MacUI.accentPink)
        .modifier(MacCompactWindowTitleModifier())
        .toolbar {
            ToolbarItemGroup {
                Button {
                    Task { await model.refreshCurrentSurface() }
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                .help("刷新当前内容")

                Button {
                    Task { await model.logout() }
                } label: {
                    Label("退出", systemImage: "rectangle.portrait.and.arrow.right")
                }
                .help("退出登录")
            }
        }
    }
}

private struct MacCompactWindowTitleModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.toolbar(removing: .title)
        } else {
            content
        }
    }
}

struct MacSidebarView: View {
    @Bindable var model: MacLibraryModel

    var body: some View {
        List(selection: sidebarSelection) {
            ForEach(MacSidebarGroup.allCases) { group in
                Section(group.rawValue) {
                    ForEach(MacSidebarItem.allCases.filter { $0.group == group }) { item in
                        Label {
                            Text(item.title)
                        } icon: {
                            Image(systemName: item.systemImage)
                                .foregroundStyle(MacUI.accentPink)
                        }
                            .tag(item)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .tint(MacUI.accentPink)
        .safeAreaInset(edge: .top, spacing: 0) {
            Text("Bika")
                .font(.title3.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 6)
        }
    }

    private var sidebarSelection: Binding<MacSidebarItem?> {
        Binding {
            model.sidebarSelection
        } set: { item in
            guard let item else { return }
            Task { await model.selectSidebar(item) }
        }
    }
}
