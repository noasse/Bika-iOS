import SwiftUI

struct CommentCardView: View {
    let comment: Comment
    var showReplyCount: Bool = true
    var onLike: (() -> Void)?
    var onTap: (() -> Void)?
    var onAvatarTap: (() -> Void)?

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Top badge
            if comment.isTop == true {
                Text("置顶")
                    .font(.caption2.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentPink)
                    .clipShape(Capsule())
            }

            // User row
            HStack(spacing: 8) {
                Button {
                    onAvatarTap?()
                } label: {
                    if let avatar = comment.user?.avatar {
                        MediaImageView(media: avatar, cornerRadius: 16)
                            .frame(width: 32, height: 32)
                    } else {
                        Circle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 32, height: 32)
                            .overlay {
                                Image(systemName: "person.fill")
                                    .font(.caption)
                                    .foregroundStyle(.gray)
                            }
                    }
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 2) {
                    Text(comment.user?.name ?? "匿名")
                        .font(.subheadline.weight(.medium))

                    HStack(spacing: 4) {
                        if let level = comment.user?.level {
                            Text("Lv.\(level)")
                                .font(.caption2)
                                .foregroundStyle(Color.accentPink)
                        }
                        if let time = comment.created_at {
                            Text(formatTime(time))
                                .font(.caption2)
                                .foregroundStyle(Color.secondaryText(for: colorScheme))
                        }
                    }
                }

                Spacer()
            }

            // Content
            Text(comment.content ?? "")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)

            // Bottom actions
            HStack(spacing: 16) {
                Button {
                    onLike?()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: comment.isLiked == true ? "heart.fill" : "heart")
                        Text("\(comment.likesCount ?? 0)")
                    }
                    .foregroundStyle(comment.isLiked == true ? Color.red : Color.secondaryText(for: colorScheme))
                }
                .buttonStyle(.plain)

                if showReplyCount, let count = comment.commentsCount ?? comment.totalComments, count > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "bubble.right")
                        Text("\(count)")
                    }
                    .foregroundStyle(Color.secondaryText(for: colorScheme))
                }

                Spacer()
            }
            .font(.caption)
        }
        .padding(12)
        .background(Color.cardBg(for: colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(comment.content ?? "")
        .accessibilityIdentifier("comment.card.\(comment.id)")
        .onTapGesture { onTap?() }
    }

    private func formatTime(_ isoString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: isoString) else {
            formatter.formatOptions = [.withInternetDateTime]
            guard let date = formatter.date(from: isoString) else { return isoString }
            return relativeString(from: date)
        }
        return relativeString(from: date)
    }

    private func relativeString(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "刚刚" }
        if interval < 3600 { return "\(Int(interval / 60))分钟前" }
        if interval < 86400 { return "\(Int(interval / 3600))小时前" }
        if interval < 2592000 { return "\(Int(interval / 86400))天前" }
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        return df.string(from: date)
    }
}

// MARK: - User Profile Overlay

struct UserProfileOverlay: ViewModifier {
    @Binding var user: Creator?
    @Environment(\.colorScheme) private var colorScheme

    private var isPresented: Bool { user != nil }

    func body(content: Content) -> some View {
        content.overlay {
            if let user = user {
                ZStack {
                    Color.black.opacity(0.5)
                        .ignoresSafeArea()
                        .onTapGesture { dismiss() }

                    VStack(spacing: 12) {
                        if let avatar = user.avatar {
                            MediaImageView(media: avatar, cornerRadius: 40)
                                .frame(width: 80, height: 80)
                        } else {
                            Circle()
                                .fill(Color.gray.opacity(0.3))
                                .frame(width: 80, height: 80)
                                .overlay {
                                    Image(systemName: "person.fill")
                                        .font(.title)
                                        .foregroundStyle(.gray)
                                }
                        }

                        Text(user.name ?? "匿名")
                            .font(.title3.bold())

                        if let title = user.title, !title.isEmpty {
                            Text(title)
                                .font(.caption)
                                .foregroundStyle(Color.accentPink)
                        }

                        HStack(spacing: 20) {
                            if let level = user.level {
                                VStack {
                                    Text("Lv.\(level)")
                                        .font(.headline)
                                    Text("等级")
                                        .font(.caption2)
                                        .foregroundStyle(Color.secondaryText(for: colorScheme))
                                }
                            }
                            if let exp = user.exp {
                                VStack {
                                    Text("\(exp)")
                                        .font(.headline)
                                    Text("经验")
                                        .font(.caption2)
                                        .foregroundStyle(Color.secondaryText(for: colorScheme))
                                }
                            }
                        }

                        if let slogan = user.slogan, !slogan.isEmpty {
                            Text(slogan)
                                .font(.callout)
                                .foregroundStyle(Color.secondaryText(for: colorScheme))
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: 280)
                    .background(Color.cardBg(for: colorScheme))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(radius: 20)
                    .transition(.scale(scale: 0.3, anchor: .center))
                    .onTapGesture { dismiss() }
                }
            }
        }
        .animation(.easeOut(duration: 0.2), value: isPresented)
    }

    private func dismiss() {
        user = nil
    }
}

extension View {
    func userProfileOverlay(user: Binding<Creator?>) -> some View {
        modifier(UserProfileOverlay(user: user))
    }
}
