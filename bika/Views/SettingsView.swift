import SwiftUI

struct SettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var viewModel: SettingsViewModel

    init(viewModel: SettingsViewModel = SettingsViewModel()) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        List {
            // Theme
            Section("外观") {
                ForEach(ThemeMode.allCases, id: \.self) { mode in
                    Button {
                        viewModel.setThemeMode(mode)
                    } label: {
                        HStack {
                            Text(mode.displayName)
                                .foregroundStyle(.primary)
                            Spacer()
                            if viewModel.themeManager.themeMode == mode {
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
                        viewModel.setImageQuality(quality)
                    } label: {
                        HStack {
                            Text(quality.displayName)
                                .foregroundStyle(.primary)
                            Spacer()
                            if viewModel.imageQuality == quality {
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
                        let count = viewModel.blockedCategoryCount
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

            Section {
                Toggle("启用云端历史同步", isOn: cloudHistoryBinding(\.cloudHistoryEnabled))

                if viewModel.cloudHistoryEnabled {
                    TextField("https://公网IP:8443", text: cloudHistoryBinding(\.cloudHistoryBaseURL))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    SecureField("同步 Token", text: cloudHistoryBinding(\.cloudHistoryBearerToken))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    TextField("证书 SHA256 pin", text: cloudHistoryBinding(\.cloudHistoryCertificatePins), axis: .vertical)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .lineLimit(2...4)

                    Button("保存云同步设置") {
                        viewModel.saveCloudHistorySettings()
                    }

                    if let message = viewModel.cloudHistorySettingsMessage {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(Color.secondaryText(for: colorScheme))
                    }
                }
            } header: {
                Text("云端历史")
            } footer: {
                Text("留空或关闭时只使用本地历史。服务地址、Token 和证书 pin 只保存在本机，不会写入仓库。")
            }

            // About
            Section("关于") {
                HStack {
                    Text("版本")
                    Spacer()
                    Text("v\(viewModel.appVersion)")
                        .foregroundStyle(.secondary)
                }
            }

            if viewModel.isUITesting {
                Section("测试诊断") {
                    HStack {
                        Text("最近请求图片质量")
                        Spacer()
                        Text(viewModel.lastRecordedImageQuality)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("settings.lastMockImageQualityValue")
                    }
                }
            }
        }
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            viewModel.refreshDiagnostics()
        }
    }

    private func cloudHistoryBinding<Value>(_ keyPath: ReferenceWritableKeyPath<SettingsViewModel, Value>) -> Binding<Value> {
        Binding {
            viewModel[keyPath: keyPath]
        } set: { value in
            viewModel[keyPath: keyPath] = value
        }
    }
}

// MARK: - Blocked Categories Management View

struct BlockedCategoriesView: View {
    @State private var viewModel: BlockedCategoriesViewModel

    init(viewModel: BlockedCategoriesViewModel = BlockedCategoriesViewModel()) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        List {
            if viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
            } else if let errorMessage = viewModel.errorMessage, viewModel.categories.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("加载失败")
                        .font(.headline)
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            } else {
                ForEach(viewModel.categories) { category in
                    Button {
                        viewModel.toggleCategory(category.title)
                    } label: {
                        HStack {
                            Text(category.title)
                                .foregroundStyle(.primary)
                            Spacer()
                            if viewModel.isBlocked(category.title) {
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
            await viewModel.loadCategories()
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
