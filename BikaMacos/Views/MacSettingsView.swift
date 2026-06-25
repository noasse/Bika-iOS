import SwiftUI

struct MacSettingsView: View {
    @Binding var themeModeRawValue: String
    @AppStorage(APIConfig.imageQualityKey) private var imageQualityRawValue = APIConfig.imageQualityDefault
    let blockedCategoriesStore: MacBlockedCategoriesStore

    @State private var categories: [Category] = []
    @State private var isLoadingCategories = false
    @State private var categoriesError: String?
    @State private var cloudHistoryEnabled = false
    @State private var cloudHistoryBaseURL = ""
    @State private var cloudHistoryBearerToken = ""
    @State private var cloudHistoryCertificatePins = ""
    @State private var cloudHistoryMessage: String?
    @Environment(\.colorScheme) private var colorScheme

    init(themeModeRawValue: Binding<String>, blockedCategoriesStore: MacBlockedCategoriesStore) {
        _themeModeRawValue = themeModeRawValue
        self.blockedCategoriesStore = blockedCategoriesStore
    }

    var body: some View {
        TabView {
            generalSettings
                .tabItem {
                    Label("通用", systemImage: "gearshape")
                }

            blockedCategoriesSettings
                .tabItem {
                    Label("屏蔽", systemImage: "eye.slash")
                }
        }
        .frame(width: 520, height: 430)
        .tint(MacUI.accentPink)
        .background(MacUI.appBackground(for: colorScheme))
        .task {
            loadCloudHistorySettings()
            await loadCategoriesIfNeeded()
        }
    }

    private var generalSettings: some View {
        Form {
            Picker("主题", selection: themeBinding) {
                ForEach(MacThemeMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }

            Picker("图片质量", selection: imageQualityBinding) {
                ForEach(ImageQuality.allCases, id: \.self) { quality in
                    Text(quality.macTitle).tag(quality)
                }
            }

            Divider()

            Toggle("启用云端历史同步", isOn: $cloudHistoryEnabled)

            if cloudHistoryEnabled {
                TextField("服务地址", text: $cloudHistoryBaseURL, prompt: Text("https://公网IP:8443"))
                    .textFieldStyle(.roundedBorder)

                SecureField("同步 Token", text: $cloudHistoryBearerToken)
                    .textFieldStyle(.roundedBorder)

                TextField("证书 SHA256 pin", text: $cloudHistoryCertificatePins, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...4)

                HStack {
                    Button("保存云同步设置") {
                        saveCloudHistorySettings()
                    }

                    if let cloudHistoryMessage {
                        Text(cloudHistoryMessage)
                            .font(.caption)
                            .foregroundStyle(MacUI.secondaryText(for: colorScheme))
                    }
                }
            }
        }
        .padding(20)
        .background(MacUI.appBackground(for: colorScheme))
    }

    private var blockedCategoriesSettings: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("已屏蔽 \(blockedCategoriesStore.blockedCategories.count) 个分类")
                    .font(.headline)
                Spacer()
                Button {
                    Task { await loadCategories(force: true) }
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                .labelStyle(.iconOnly)
                .help("刷新分类")
            }
            .padding([.horizontal, .top], 20)
            .padding(.bottom, 10)
            .background(MacUI.surface(for: colorScheme))

            if isLoadingCategories && categories.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let categoriesError, categories.isEmpty {
                ContentUnavailableView("分类载入失败", systemImage: "exclamationmark.triangle", description: Text(categoriesError))
            } else {
                List(categories, id: \.title) { category in
                    Toggle(isOn: blockedBinding(for: category.title)) {
                        HStack(spacing: 10) {
                            MacCachedAsyncImage(url: category.thumb?.imageURL, contentMode: .fill)
                                .frame(width: 36, height: 36)
                                .clipShape(RoundedRectangle(cornerRadius: 6))

                            VStack(alignment: .leading, spacing: 2) {
                                    Text(category.title)
                                        .font(.body)
                                if let description = category.description, !description.isEmpty {
                                    Text(description)
                                        .font(.caption)
                                        .foregroundStyle(MacUI.secondaryText(for: colorScheme))
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
                .background(MacUI.appBackground(for: colorScheme))
            }
        }
        .background(MacUI.appBackground(for: colorScheme))
    }

    private var themeBinding: Binding<MacThemeMode> {
        Binding {
            MacThemeMode(rawValue: themeModeRawValue) ?? .system
        } set: { mode in
            themeModeRawValue = mode.rawValue
        }
    }

    private var imageQualityBinding: Binding<ImageQuality> {
        Binding {
            ImageQuality(rawValue: imageQualityRawValue) ?? .original
        } set: { quality in
            imageQualityRawValue = quality.rawValue
            APIConfig.setCurrentImageQuality(quality)
        }
    }

    private func blockedBinding(for category: String) -> Binding<Bool> {
        Binding {
            blockedCategoriesStore.isBlocked(category)
        } set: { isBlocked in
            if blockedCategoriesStore.isBlocked(category) != isBlocked {
                blockedCategoriesStore.toggle(category)
            }
        }
    }

    private func loadCategoriesIfNeeded() async {
        guard categories.isEmpty else { return }
        await loadCategories(force: false)
    }

    private func loadCategories(force: Bool) async {
        guard force || categories.isEmpty else { return }
        isLoadingCategories = true
        categoriesError = nil
        defer { isLoadingCategories = false }

        do {
            let response: APIResponse<CategoriesData> = try await APIClient.shared.send(.categories())
            categories = response.data?.categories.filter { $0.isWeb != true } ?? []
        } catch {
            categoriesError = error.localizedDescription
        }
    }

    private func loadCloudHistorySettings() {
        let store = AppDependencies.shared.keyValueStore
        cloudHistoryEnabled = store.string(forKey: CloudHistoryConfig.StorageKeys.isEnabled) == "1"
        cloudHistoryBaseURL = store.string(forKey: CloudHistoryConfig.StorageKeys.baseURL) ?? ""
        cloudHistoryBearerToken = store.string(forKey: CloudHistoryConfig.StorageKeys.bearerToken) ?? ""
        cloudHistoryCertificatePins = (store.stringArray(forKey: CloudHistoryConfig.StorageKeys.certificateSHA256Pins) ?? [])
            .joined(separator: "\n")
    }

    private func saveCloudHistorySettings() {
        let store = AppDependencies.shared.keyValueStore
        let pins = parsedCloudHistoryPins()
        let trimmedURL = cloudHistoryBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedToken = cloudHistoryBearerToken.trimmingCharacters(in: .whitespacesAndNewlines)

        guard cloudHistoryEnabled else {
            store.setCloudHistoryEnabled(false)
            store.set(trimmedURL, forKey: CloudHistoryConfig.StorageKeys.baseURL)
            store.set(trimmedToken, forKey: CloudHistoryConfig.StorageKeys.bearerToken)
            store.set(pins, forKey: CloudHistoryConfig.StorageKeys.certificateSHA256Pins)
            cloudHistoryMessage = "云端历史同步已关闭"
            return
        }

        guard let baseURL = URL(string: trimmedURL), baseURL.scheme?.lowercased() == "https" else {
            cloudHistoryMessage = "服务地址必须是 https:// 开头"
            return
        }
        guard !trimmedToken.isEmpty else {
            cloudHistoryMessage = "同步 Token 不能为空"
            return
        }
        guard !pins.isEmpty else {
            cloudHistoryMessage = "证书 SHA256 pin 不能为空"
            return
        }

        store.setCloudHistoryConfig(
            CloudHistoryConfig(
                baseURL: baseURL,
                bearerToken: trimmedToken,
                certificateSHA256Pins: pins
            )
        )
        cloudHistoryBaseURL = trimmedURL
        cloudHistoryBearerToken = trimmedToken
        cloudHistoryCertificatePins = pins.joined(separator: "\n")
        cloudHistoryMessage = "云端历史同步已保存"
    }

    private func parsedCloudHistoryPins() -> [String] {
        cloudHistoryCertificatePins
            .components(separatedBy: CharacterSet(charactersIn: ",\n "))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
