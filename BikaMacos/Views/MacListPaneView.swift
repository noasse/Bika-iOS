import SwiftUI

struct MacListPaneView: View {
    @Bindable var model: MacLibraryModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.colorScheme) private var colorScheme
    @State private var showingPageInput = false
    @State private var pageInputText = ""
    @State private var showingSloganEditor = false
    @State private var sloganText = ""

    private let categoryColumns = [
        GridItem(.adaptive(minimum: 132, maximum: 180), spacing: 12)
    ]

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch model.sidebarSelection {
                case .categories:
                    categorySurface
                case .ranking:
                    comicListSurface(showRankingPicker: true, showSortPicker: false)
                case .search:
                    searchSurface
                case .favourites:
                    comicListSurface(showRankingPicker: false, showSortPicker: true)
                case .history:
                    historySurface
                case .profile:
                    profileSurface
                case .settings:
                    settingsSurface
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .tint(MacUI.accentPink)
        .background(MacUI.appBackground(for: colorScheme))
        .alert("跳转页数", isPresented: $showingPageInput) {
            TextField("1-\(max(model.totalPages, 1))", text: $pageInputText)
            Button("跳转") {
                submitPageInput()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("输入 1 到 \(max(model.totalPages, 1)) 之间的页数。")
        }
        .alert("编辑签名", isPresented: $showingSloganEditor) {
            TextField("签名", text: $sloganText)
            Button("保存") {
                submitSlogan()
            }
            Button("取消", role: .cancel) {}
        }
    }

    @ViewBuilder
    private var paginationControls: some View {
        if showsTopPageControls {
            HStack(spacing: 10) {
                Button {
                    openPageInput()
                } label: {
                    Text("\(model.currentPage)/\(model.totalPages)")
                        .font(.caption)
                        .monospacedDigit()
                        .lineLimit(1)
                        .foregroundStyle(MacUI.accentPink)
                }
                .buttonStyle(.plain)
                .disabled(!showsPageJump)
                .help("第 \(model.currentPage) / \(model.totalPages) 页")

                ControlGroup {
                    Button {
                        Task { await model.previousPage() }
                    } label: {
                        Label("上一页", systemImage: "chevron.left")
                    }
                    .disabled(!model.canPageBackward || model.isListLoading)
                    .help("上一页")

                    Button {
                        Task { await model.nextPage() }
                    } label: {
                        Label("下一页", systemImage: "chevron.right")
                    }
                    .disabled(!model.canPageForward || model.isListLoading)
                    .help("下一页")
                }
                .labelStyle(.iconOnly)
            }
        }
    }

    @ViewBuilder
    private var categorySurface: some View {
        if let _ = model.selectedCategoryTitle {
            VStack(spacing: 0) {
                HStack {
                    Button {
                        model.showCategoryIndex()
                    } label: {
                        Label("返回分类", systemImage: "chevron.left")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.borderless)
                    .help("返回分类")

                    Spacer()

                    sortPicker
                    paginationControls
                }
                .controlSize(.small)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)

                Divider()

                comicList
            }
        } else {
            ScrollView {
                LazyVGrid(columns: categoryColumns, spacing: 12) {
                    ForEach(model.categories, id: \.title) { category in
                        Button {
                            Task { await model.selectCategory(category) }
                        } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                MacCachedAsyncImage(url: category.thumb?.imageURL, contentMode: .fill)
                                    .frame(height: 86)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))

                                Text(category.title)
                                    .font(.headline)
                                    .lineLimit(2)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                if let description = category.description, !description.isEmpty {
                                    Text(description)
                                        .font(.caption)
                                        .foregroundStyle(MacUI.secondaryText(for: colorScheme))
                                        .lineLimit(2)
                                }
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, minHeight: 156, alignment: .topLeading)
                            .macSurface(colorScheme)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
            .overlay { loadingAndErrorOverlay }
        }
    }

    private var searchSurface: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    TextField("搜索漫画、作者或标签", text: $model.searchText)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            Task { await model.search(page: 1) }
                        }

                    Button {
                        Task { await model.search(page: 1) }
                    } label: {
                        Label("搜索", systemImage: "magnifyingglass")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(MacUI.accentPink)
                }

                HStack {
                    sortPicker
                    Spacer()
                    paginationControls
                }
            }
            .padding(16)
            .background(MacUI.surface(for: colorScheme))

            Divider()
            comicList
        }
    }

    private var historySurface: some View {
        VStack(spacing: 0) {
            HStack {
                    Text("\(model.displayedListItems.count) 条记录")
                        .font(.caption)
                        .foregroundStyle(MacUI.secondaryText(for: colorScheme))
                Spacer()
                Button(role: .destructive) {
                    model.clearHistory()
                } label: {
                    Label("清空", systemImage: "trash")
                }
                .disabled(model.displayedListItems.isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()
            historyList
        }
    }

    private func comicListSurface(showRankingPicker: Bool, showSortPicker: Bool) -> some View {
        VStack(spacing: 0) {
            if showRankingPicker || showSortPicker || showsTopPageControls {
                HStack {
                    if showRankingPicker {
                        Picker("榜单", selection: rankingBinding) {
                            ForEach(LeaderboardType.allCases) { type in
                                Text(type.macTitle).tag(type)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 240)
                    }

                    if showSortPicker {
                        sortPicker
                    }

                    Spacer()
                    paginationControls
                }
                .controlSize(.small)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                Divider()
            }

            comicList
        }
    }

    private var comicList: some View {
        List(selection: selectedComicBinding) {
            ForEach(model.displayedListItems) { item in
                MacComicRow(item: item)
                    .tag(item.id)
                    .contextMenu {
                        if model.sidebarSelection == .history {
                            Button(role: .destructive) {
                                model.removeHistory(comicId: item.id)
                            } label: {
                                Label("移除历史", systemImage: "trash")
                            }
                        }
                    }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .background(MacUI.appBackground(for: colorScheme))
        .overlay { loadingAndErrorOverlay }
    }

    private var historyList: some View {
        List(selection: selectedComicBinding) {
            ForEach(model.displayedListItems) { item in
                HStack(spacing: 10) {
                    MacComicRow(item: item)
                        .contentShape(Rectangle())

                    Spacer()

                    Button {
                        openHistoryReader(comicId: item.id)
                    } label: {
                        Label("继续", systemImage: "play.fill")
                    }
                    .labelStyle(.titleAndIcon)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("从历史进度继续阅读")
                }
                .tag(item.id)
                .contextMenu {
                    Button(role: .destructive) {
                        model.removeHistory(comicId: item.id)
                    } label: {
                        Label("移除历史", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .background(MacUI.appBackground(for: colorScheme))
        .overlay { loadingAndErrorOverlay }
    }

    private var profileSurface: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let user = model.userProfile {
                HStack(alignment: .top, spacing: 14) {
                    MacCachedAsyncImage(url: user.avatar?.imageURL, contentMode: .fill)
                        .frame(width: 68, height: 68)
                        .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 8) {
                        Text(user.name)
                            .font(.title3.weight(.semibold))
                        Text(user.email ?? "未显示邮箱")
                            .foregroundStyle(MacUI.secondaryText(for: colorScheme))

                        if let slogan = user.slogan, !slogan.isEmpty {
                            Text(slogan)
                                .font(.callout)
                                .foregroundStyle(MacUI.secondaryText(for: colorScheme))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    Spacer()
                }

                HStack(spacing: 10) {
                    profileMetric("等级", "Lv.\(user.level ?? 0)")
                    profileMetric("经验", "\(user.exp ?? 0)")
                    profileMetric("称号", user.title ?? "无")
                }

                Divider()

                HStack(spacing: 10) {
                    Button {
                        Task { await model.punchIn() }
                    } label: {
                        Label(user.isPunched == true ? "已打卡" : "每日打卡", systemImage: user.isPunched == true ? "checkmark.circle.fill" : "hand.tap")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(MacUI.accentPink)
                    .disabled(user.isPunched == true || model.isPunching)

                    Button {
                        sloganText = user.slogan ?? ""
                        showingSloganEditor = true
                    } label: {
                        Label("编辑签名", systemImage: "pencil")
                    }
                    .buttonStyle(.bordered)
                }
            } else if model.isListLoading {
                ProgressView()
            } else {
                ContentUnavailableView("无法载入账户资料", systemImage: "person.crop.circle.badge.exclamationmark")
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(MacUI.appBackground(for: colorScheme))
    }

    private func profileMetric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.headline)
                .lineLimit(1)
            Text(title)
                .font(.caption)
                .foregroundStyle(MacUI.secondaryText(for: colorScheme))
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MacUI.subtleSurface(for: colorScheme), in: RoundedRectangle(cornerRadius: MacUI.cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: MacUI.cornerRadius)
                .stroke(MacUI.hairline(for: colorScheme))
        }
    }

    private var settingsSurface: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "gearshape")
                    .font(.title3)
                    .foregroundStyle(MacUI.accentPink)
                    .frame(width: 34, height: 34)
                    .background(MacUI.accentWash(for: colorScheme), in: RoundedRectangle(cornerRadius: MacUI.cornerRadius))

                VStack(alignment: .leading, spacing: 3) {
                    Text("设置")
                        .font(.headline)
                    Text("主题、图片质量和屏蔽分类在独立设置窗口中管理")
                        .font(.caption)
                        .foregroundStyle(MacUI.secondaryText(for: colorScheme))
                }
            }

            profileMetric("屏蔽分类", "\(model.blockedCategoryCount)")

            SettingsLink {
                Label("打开设置", systemImage: "gearshape")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(MacUI.accentPink)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(MacUI.appBackground(for: colorScheme))
    }

    @ViewBuilder
    private var loadingAndErrorOverlay: some View {
        if model.isListLoading {
            ProgressView()
                .padding(12)
                .background(MacUI.surface(for: colorScheme), in: RoundedRectangle(cornerRadius: MacUI.cornerRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: MacUI.cornerRadius)
                        .stroke(MacUI.hairline(for: colorScheme))
                }
        } else if let error = model.listError {
            ContentUnavailableView("载入失败", systemImage: "exclamationmark.triangle", description: Text(error))
        } else if model.displayedListItems.isEmpty && model.sidebarSelection != .categories {
            ContentUnavailableView("暂无内容", systemImage: "tray")
        }
    }

    private var sortPicker: some View {
        Picker("排序", selection: sortBinding) {
            ForEach(SortMode.allCases, id: \.self) { mode in
                Text(mode.macTitle).tag(mode)
            }
        }
        .controlSize(.small)
        .frame(width: 118)
    }

    private var sortBinding: Binding<SortMode> {
        Binding {
            model.sortMode
        } set: { mode in
            Task { await model.changeSort(mode) }
        }
    }

    private var rankingBinding: Binding<LeaderboardType> {
        Binding {
            model.rankingType
        } set: { type in
            Task { await model.changeRanking(type) }
        }
    }

    private var showsPageJump: Bool {
        model.currentPage > 0 && model.sidebarSelection != .history && model.sidebarSelection != .ranking
    }

    private var showsTopPageControls: Bool {
        model.currentPage > 0 && (showsPageJump || model.canPageBackward || model.canPageForward)
    }

    private var selectedComicBinding: Binding<String?> {
        Binding {
            model.selectedComicID
        } set: { comicID in
            guard let comicID else { return }
            Task { await model.selectComic(id: comicID) }
        }
    }

    private func openPageInput() {
        guard showsPageJump else { return }
        pageInputText = "\(model.currentPage)"
        showingPageInput = true
    }

    private func submitPageInput() {
        guard let page = Int(pageInputText.trimmingCharacters(in: .whitespacesAndNewlines)) else { return }
        Task { await model.goToPage(page) }
    }

    private func submitSlogan() {
        Task { await model.updateSlogan(sloganText) }
    }

    private func openHistoryReader(comicId: String) {
        Task {
            if let request = await model.makeHistoryReaderRequest(for: comicId) {
                openWindow(value: request)
            }
        }
    }
}

private struct MacComicRow: View {
    let item: MacComicSummary
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 12) {
            MacCachedAsyncImage(url: item.thumbURL, contentMode: .fill)
                .frame(width: 56, height: 76)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(MacUI.hairline(for: colorScheme))
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.headline)
                    .lineLimit(2)

                Text(item.author ?? "未知作者")
                    .font(.subheadline)
                    .foregroundStyle(MacUI.secondaryText(for: colorScheme))
                    .lineLimit(1)

                if let lastReadDescription = item.lastReadDescription {
                    Text(lastReadDescription)
                        .font(.caption)
                        .foregroundStyle(MacUI.accentPink)
                        .lineLimit(1)
                } else {
                    HStack(spacing: 10) {
                        if let episodeCount = item.episodeCount {
                            Label("\(episodeCount)", systemImage: "list.bullet")
                        }
                        if let views = item.views {
                            Label(compactCount(views), systemImage: "eye")
                        }
                        if let likes = item.likes {
                            Label(compactCount(likes), systemImage: "heart")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(MacUI.secondaryText(for: colorScheme))
                    .labelStyle(.titleAndIcon)
                }
            }
        }
        .padding(.vertical, 5)
    }

    private func compactCount(_ value: Int) -> String {
        if value >= 10_000 {
            return String(format: "%.1f万", Double(value) / 10_000)
        }
        return "\(value)"
    }
}
