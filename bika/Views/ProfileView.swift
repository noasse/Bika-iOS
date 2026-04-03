import SwiftUI

struct ProfileView: View {
    @Environment(AuthViewModel.self) private var authVM
    @Environment(\.colorScheme) private var colorScheme

    @State private var viewModel: ProfileViewModel
    @State private var showSloganEditor = false
    @State private var sloganText = ""

    init(viewModel: ProfileViewModel = ProfileViewModel()) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                profileHeader

                VStack(spacing: 2) {
                    NavigationLink {
                        FavouritesView()
                    } label: {
                        menuContent(icon: "star", title: "我的收藏")
                    }

                    NavigationLink {
                        ReadingHistoryView()
                    } label: {
                        menuContent(icon: "clock.arrow.circlepath", title: "阅读记录")
                    }

                    Button(action: openSloganEditor) {
                        menuContent(icon: "pencil", title: "编辑签名")
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        SettingsView()
                    } label: {
                        menuContent(icon: "gearshape", title: "设置")
                    }
                    .accessibilityIdentifier("profile.openSettings")
                }
                .background(Color.cardBg(for: colorScheme))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)

                Button(role: .destructive, action: logout) {
                    Text("退出登录")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.cardBg(for: colorScheme))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .background(Color.mainBg(for: colorScheme))
        .navigationTitle("我的")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await viewModel.loadProfile()
        }
        .alert("编辑签名", isPresented: $showSloganEditor) {
            TextField("输入签名", text: $sloganText)
            Button("保存", action: saveSlogan)
            Button("取消", role: .cancel) {}
        }
        .task {
            await viewModel.loadProfile()
        }
    }

    @ViewBuilder
    private var profileHeader: some View {
        if viewModel.isLoading && viewModel.profile == nil {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 220)
        } else if let errorMessage = viewModel.errorMessage, viewModel.profile == nil {
            VStack(spacing: 12) {
                Text("资料加载失败")
                    .font(.headline)
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(Color.secondaryText(for: colorScheme))
                    .multilineTextAlignment(.center)
                Button("重试") {
                    Task { await viewModel.loadProfile() }
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.accentPink)
            }
            .frame(maxWidth: .infinity, minHeight: 220)
            .padding(.horizontal, 24)
        } else if let profile = viewModel.profile {
            VStack(spacing: 12) {
                MediaImageView(media: profile.avatar, cornerRadius: 40)
                    .frame(width: 80, height: 80)

                Text(profile.name)
                    .font(.title2.bold())

                if let title = profile.title, !title.isEmpty {
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(Color.accentPink)
                }

                HStack(spacing: 20) {
                    VStack {
                        Text("Lv.\(profile.level ?? 0)")
                            .font(.headline)
                        Text("等级")
                            .font(.caption2)
                            .foregroundStyle(Color.secondaryText(for: colorScheme))
                    }

                    VStack {
                        Text("\(profile.exp ?? 0)")
                            .font(.headline)
                        Text("经验")
                            .font(.caption2)
                            .foregroundStyle(Color.secondaryText(for: colorScheme))
                    }
                }

                if let slogan = profile.slogan, !slogan.isEmpty {
                    Text(slogan)
                        .font(.callout)
                        .foregroundStyle(Color.secondaryText(for: colorScheme))
                }

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.cardBg(for: colorScheme))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal)

            Button(action: punchIn) {
                HStack {
                    Image(systemName: profile.isPunched == true ? "checkmark.circle.fill" : "hand.tap")
                    Text(profile.isPunched == true ? "已打卡" : "每日打卡")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(profile.isPunched == true ? Color.gray.opacity(0.3) : Color.accentPink)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(profile.isPunched == true || viewModel.isPunching)
            .padding(.horizontal)
        } else {
            Text("暂无资料")
                .foregroundStyle(Color.secondaryText(for: colorScheme))
                .frame(maxWidth: .infinity, minHeight: 220)
        }
    }

    private func menuContent(icon: String, title: String) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(Color.accentPink)
                .frame(width: 24)
            Text(title)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.gray)
        }
        .padding()
    }

    private func openSloganEditor() {
        sloganText = viewModel.profile?.slogan ?? ""
        showSloganEditor = true
    }

    private func punchIn() {
        Task { await viewModel.punchIn() }
    }

    private func saveSlogan() {
        Task { await viewModel.updateSlogan(sloganText) }
    }

    private func logout() {
        Task { await authVM.logout() }
    }
}
