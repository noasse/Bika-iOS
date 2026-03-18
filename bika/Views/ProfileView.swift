import SwiftUI

struct ProfileView: View {
    @Environment(AuthViewModel.self) private var authVM
    @State private var viewModel = ProfileViewModel()
    @State private var showSloganEditor = false
    @State private var sloganText = ""
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // User card
                if let profile = viewModel.profile {
                    VStack(spacing: 12) {
                        // Avatar
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
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.cardBg(for: colorScheme))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal)

                    // Punch in button
                    Button {
                        Task { await viewModel.punchIn() }
                    } label: {
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
                }

                // Menu items
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

                    Button {
                        sloganText = viewModel.profile?.slogan ?? ""
                        showSloganEditor = true
                    } label: {
                        menuContent(icon: "pencil", title: "编辑签名")
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        SettingsView()
                    } label: {
                        menuContent(icon: "gearshape", title: "设置")
                    }
                }
                .background(Color.cardBg(for: colorScheme))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)

                // Logout
                Button(role: .destructive) {
                    Task { await authVM.logout() }
                } label: {
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
        .alert("编辑签名", isPresented: $showSloganEditor) {
            TextField("输入签名", text: $sloganText)
            Button("保存") {
                Task { await viewModel.updateSlogan(sloganText) }
            }
            Button("取消", role: .cancel) {}
        }
        .task { await viewModel.loadProfile() }
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
}
