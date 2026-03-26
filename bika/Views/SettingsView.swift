import SwiftUI

struct SettingsView: View {
    @State private var themeManager = ThemeManager.shared
    @State private var imageQuality = APIConfig.currentImageQuality
    @State private var lastRecordedImageQuality = "未记录"
    @Environment(\.colorScheme) private var colorScheme
    private let keyValueStore = AppDependencies.shared.keyValueStore
    private let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "未知版本"

    var body: some View {
        List {
            // Theme
            Section("外观") {
                ForEach(ThemeMode.allCases, id: \.self) { mode in
                    Button {
                        themeManager.themeMode = mode
                    } label: {
                        HStack {
                            Text(mode.displayName)
                                .foregroundStyle(.primary)
                            Spacer()
                            if themeManager.themeMode == mode {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentPink)
                            }
                        }
                    }
                }
            }

            // Image quality
            Section("图片质量") {
                ForEach(ImageQuality.allCases, id: \.self) { quality in
                    Button {
                        imageQuality = quality
                        APIConfig.setCurrentImageQuality(quality)
                    } label: {
                        HStack {
                            Text(quality.displayName)
                                .foregroundStyle(.primary)
                            Spacer()
                            if imageQuality == quality {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentPink)
                            }
                        }
                    }
                    .accessibilityIdentifier("settings.imageQuality.\(quality.rawValue)")
                }
            }

            // Blocked categories
            Section {
                NavigationLink {
                    BlockedCategoriesView()
                } label: {
                    HStack {
                        Text("屏蔽分类")
                        Spacer()
                        let count = BlockedCategoriesManager.shared.blockedCategories.count
                        if count > 0 {
                            Text("\(count)个已屏蔽")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("内容过滤")
            } footer: {
                Text("已屏蔽分类的漫画不会出现在任何列表中")
            }

            // About
            Section("关于") {
                HStack {
                    Text("版本")
                    Spacer()
                    Text("v\(appVersion)")
                        .foregroundStyle(.secondary)
                }
            }

            if AppDependencies.shared.isUITesting {
                Section("测试诊断") {
                    HStack {
                        Text("最近请求图片质量")
                        Spacer()
                        Text(lastRecordedImageQuality)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("settings.lastMockImageQualityValue")
                    }
                }
            }
        }
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            refreshDiagnostics()
        }
    }

    private func refreshDiagnostics() {
        lastRecordedImageQuality = keyValueStore.string(forKey: MockURLProtocol.lastImageQualityHeaderKey) ?? "未记录"
    }
}

// MARK: - Blocked Categories Management View

struct BlockedCategoriesView: View {
    @State private var categories: [Category] = []
    @State private var isLoading = false
    @State private var blockedManager = BlockedCategoriesManager.shared

    private let client = APIClient.shared

    var body: some View {
        List {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
            } else {
                ForEach(categories) { category in
                    Button {
                        blockedManager.toggle(category.title)
                    } label: {
                        HStack {
                            Text(category.title)
                                .foregroundStyle(.primary)
                            Spacer()
                            if blockedManager.isBlocked(category.title) {
                                Image(systemName: "eye.slash.fill")
                                    .foregroundStyle(.red)
                            } else {
                                Image(systemName: "eye")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("屏蔽分类")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard categories.isEmpty else { return }
            isLoading = true
            defer { isLoading = false }
            do {
                let response: APIResponse<CategoriesData> = try await client.send(.categories())
                if let data = response.data {
                    categories = data.categories.filter { $0.isWeb != true }
                }
            } catch {}
        }
    }
}

extension ImageQuality {
    var displayName: String {
        switch self {
        case .original: "原图"
        case .low: "低"
        case .medium: "中"
        case .high: "高"
        }
    }
}
