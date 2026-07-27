import SwiftUI

struct SettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var viewModel: SettingsViewModel
    @State private var showClearImageCacheConfirmation = false
    @State private var showImageDiagnosticsExportConfirmation = false
    @State private var showClearImageDiagnosticsConfirmation = false
    @State private var diagnosticsExportItem: DiagnosticsExportItem?

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
                HStack {
                    Label("图片缓存", systemImage: "photo.stack")
                    Spacer()
                    if viewModel.isRefreshingImageCache {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text(viewModel.imageCacheSizeDescription)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("settings.imageCacheSize")
                    }
                }

                Button(role: .destructive) {
                    showClearImageCacheConfirmation = true
                } label: {
                    Label("清理图片缓存", systemImage: "trash")
                }
                .disabled(viewModel.isClearingImageCache)
                .accessibilityIdentifier("settings.clearImageCache")

                if let message = viewModel.imageCacheMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(Color.secondaryText(for: colorScheme))
                        .accessibilityIdentifier("settings.imageCacheMessage")
                }
            } header: {
                Text("存储")
            } footer: {
                Text("缓存用于减少重复下载。清理后不会删除账号、设置和阅读记录。")
            }

            Section {
                HStack {
                    Label("已记录事件", systemImage: "waveform.path.ecg")
                    Spacer()
                    if viewModel.isRefreshingImageDiagnostics {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text(viewModel.imageDiagnosticsCountDescription)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier(
                                "settings.imageDiagnostics.count"
                            )
                    }
                }

                HStack {
                    Text("最近错误")
                    Spacer()
                    Text(viewModel.imageDiagnosticsLastErrorDescription)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier(
                            "settings.imageDiagnostics.lastError"
                        )
                }

                Button {
                    showImageDiagnosticsExportConfirmation = true
                } label: {
                    Label("导出图片诊断日志", systemImage: "square.and.arrow.up")
                }
                .disabled(viewModel.isExportingImageDiagnostics)
                .accessibilityIdentifier("settings.imageDiagnostics.export")

                Button(role: .destructive) {
                    showClearImageDiagnosticsConfirmation = true
                } label: {
                    Label("清空图片诊断日志", systemImage: "trash")
                }
                .disabled(viewModel.isClearingImageDiagnostics)
                .accessibilityIdentifier("settings.imageDiagnostics.clear")

                if let message = viewModel.imageDiagnosticsMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(Color.secondaryText(for: colorScheme))
                        .accessibilityIdentifier(
                            "settings.imageDiagnostics.message"
                        )
                }
            } header: {
                Text("图片诊断")
            } footer: {
                Text("用于定位封面或阅读页空白。导出文件包含完整图片 URL，请只发送给可信对象。")
            }

            Section {
                Toggle("启用云端历史同步", isOn: cloudHistoryBinding(\.cloudHistoryEnabled))

                if viewModel.cloudHistoryEnabled {
                    TextField("https://your-name.duckdns.org", text: cloudHistoryBinding(\.cloudHistoryBaseURL))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    SecureField("同步 Token", text: cloudHistoryBinding(\.cloudHistoryBearerToken))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    TextField("证书 SHA256 pin（可选）", text: cloudHistoryBinding(\.cloudHistoryCertificatePins), axis: .vertical)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .lineLimit(2...4)

                    HStack {
                        Button("保存云同步设置") {
                            viewModel.saveCloudHistorySettings()
                        }

                        Button {
                            Task {
                                await viewModel.testCloudHistoryConnection()
                            }
                        } label: {
                            Text(viewModel.isTestingCloudHistoryConnection ? "正在测试..." : "测试云端连接")
                        }
                        .disabled(viewModel.isTestingCloudHistoryConnection)
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
                Text("留空或关闭时只使用本地历史。DuckDNS/Let's Encrypt 可不填证书 pin；自签名证书才需要填写。服务地址、Token 和证书 pin 只保存在本机，不会写入仓库。")
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
        .task {
            async let imageCacheRefresh: Void = viewModel.refreshImageCacheUsage()
            async let imageDiagnosticsRefresh: Void = viewModel.refreshImageDiagnostics()
            _ = await (imageCacheRefresh, imageDiagnosticsRefresh)
        }
        .confirmationDialog(
            "清理图片缓存？",
            isPresented: $showClearImageCacheConfirmation,
            titleVisibility: .visible
        ) {
            Button("清理", role: .destructive) {
                Task { await viewModel.clearImageCache() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("已缓存的图片会被删除，之后浏览时需要重新下载。")
        }
        .confirmationDialog(
            "清空图片诊断日志？",
            isPresented: $showClearImageDiagnosticsConfirmation,
            titleVisibility: .visible
        ) {
            Button("清空", role: .destructive) {
                Task { await viewModel.clearImageDiagnostics() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("已记录的图片加载诊断事件会被删除，且无法恢复。")
        }
        .alert(
            "导出图片诊断日志？",
            isPresented: $showImageDiagnosticsExportConfirmation
        ) {
            Button("取消", role: .cancel) {}
            Button("继续导出") {
                Task {
                    if let url = await viewModel.exportImageDiagnostics() {
                        diagnosticsExportItem = DiagnosticsExportItem(url: url)
                    }
                }
            }
        } message: {
            Text("导出文件包含完整图片 URL，请只发送给可信对象。")
        }
        .sheet(item: $diagnosticsExportItem) { item in
            ActivityShareSheet(fileURL: item.url)
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
