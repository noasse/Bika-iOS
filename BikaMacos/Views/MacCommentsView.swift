import SwiftUI

struct MacCommentsWindowView: View {
    @Bindable var store: MacCommentsWindowStore

    var body: some View {
        Group {
            if let request = store.request {
                MacCommentsView(comicId: request.comicId, comicTitle: request.comicTitle)
                    .id(request.id)
            } else {
                ContentUnavailableView("没有打开的评论", systemImage: "text.bubble")
            }
        }
    }
}

struct MacCommentsView: View {
    let comicId: String
    let comicTitle: String

    @State private var model: MacCommentsModel
    @State private var selectedRootComment: Comment?
    @Environment(\.colorScheme) private var colorScheme

    init(comicId: String, comicTitle: String) {
        self.comicId = comicId
        self.comicTitle = comicTitle
        _model = State(initialValue: MacCommentsModel(comicId: comicId))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            composer
        }
        .frame(minWidth: 520, minHeight: 560)
        .task {
            if model.currentPage == 0 {
                await model.loadFirstPage()
            }
        }
        .sheet(item: $selectedRootComment) { comment in
            MacChildCommentsView(rootComment: comment)
        }
        .tint(MacUI.accentPink)
        .background(MacUI.appBackground(for: colorScheme))
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("评论")
                    .font(.title3.weight(.semibold))
                Text(comicTitle)
                    .font(.caption)
                    .foregroundStyle(MacUI.secondaryText(for: colorScheme))
                    .lineLimit(1)
            }
            Spacer()
            if model.totalVisibleComments > 0 {
                Text("\(model.totalVisibleComments)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(MacUI.accentPink)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(MacUI.accentWash(for: colorScheme), in: Capsule())
            }
        }
        .padding(18)
        .background(MacUI.surface(for: colorScheme))
    }

    @ViewBuilder
    private var content: some View {
        if model.isLoading && model.currentPage == 0 {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = model.errorMessage, model.comments.isEmpty && model.topComments.isEmpty {
            ContentUnavailableView("评论载入失败", systemImage: "text.bubble", description: Text(error))
        } else if model.comments.isEmpty && model.topComments.isEmpty {
            ContentUnavailableView("暂无评论", systemImage: "text.bubble")
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(model.topComments) { comment in
                        MacCommentCard(
                            comment: comment,
                            isPinned: true,
                            onLike: {
                                Task { await model.likeComment(id: comment.id) }
                            },
                            onReplies: {
                                selectedRootComment = comment
                            }
                        )
                    }

                    ForEach(model.comments) { comment in
                        MacCommentCard(
                            comment: comment,
                            isPinned: false,
                            onLike: {
                                Task { await model.likeComment(id: comment.id) }
                            },
                            onReplies: {
                                selectedRootComment = comment
                            }
                        )
                        .task {
                            await model.loadMoreIfNeeded(currentItemID: comment.id)
                        }
                    }

                    if model.isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                }
                .padding(16)
            }
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let actionError = model.actionErrorMessage {
                Text(actionError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack(spacing: 10) {
                TextField("发表评论...", text: $model.commentText)
                    .textFieldStyle(.roundedBorder)

                Button {
                    Task { await model.postComment() }
                } label: {
                    if model.isSending {
                        ProgressView()
                            .frame(width: 18, height: 18)
                    } else {
                        Label("发送", systemImage: "paperplane.fill")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(MacUI.accentPink)
                .disabled(model.commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isSending)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(MacUI.surface(for: colorScheme))
    }
}

private struct MacChildCommentsView: View {
    let rootComment: Comment
    @State private var model: MacChildCommentsModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    init(rootComment: Comment) {
        self.rootComment = rootComment
        _model = State(initialValue: MacChildCommentsModel(commentId: rootComment.id))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("回复")
                    .font(.title3.weight(.semibold))
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Label("关闭", systemImage: "xmark")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("关闭回复")
            }
            .padding(18)
            .background(MacUI.surface(for: colorScheme))

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    MacCommentCard(
                        comment: rootComment,
                        isPinned: false,
                        showsRepliesButton: false,
                        onLike: {},
                        onReplies: {}
                    )

                    Divider()

                    ForEach(model.comments) { comment in
                        MacCommentCard(
                            comment: comment,
                            isPinned: false,
                            showsRepliesButton: false,
                            onLike: {
                                Task { await model.likeComment(id: comment.id) }
                            },
                            onReplies: {}
                        )
                        .task {
                            await model.loadMoreIfNeeded(currentItemID: comment.id)
                        }
                    }

                    if model.isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    } else if model.comments.isEmpty {
                        ContentUnavailableView("暂无回复", systemImage: "arrowshape.turn.up.left")
                            .frame(maxWidth: .infinity, minHeight: 140)
                    }
                }
                .padding(16)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                if let actionError = model.actionErrorMessage {
                    Text(actionError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                HStack(spacing: 10) {
                    TextField("发表回复...", text: $model.replyText)
                        .textFieldStyle(.roundedBorder)

                    Button {
                        Task { await model.postReply() }
                    } label: {
                        if model.isSending {
                            ProgressView()
                                .frame(width: 18, height: 18)
                        } else {
                            Label("回复", systemImage: "arrowshape.turn.up.left.fill")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(MacUI.accentPink)
                    .disabled(model.replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isSending)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .frame(minWidth: 500, minHeight: 540)
        .tint(MacUI.accentPink)
        .background(MacUI.appBackground(for: colorScheme))
        .task {
            if model.currentPage == 0 {
                await model.loadFirstPage()
            }
        }
    }
}

private struct MacCommentCard: View {
    let comment: Comment
    var isPinned = false
    var showsRepliesButton = true
    let onLike: () -> Void
    let onReplies: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                MacCachedAsyncImage(url: comment.user?.avatar?.imageURL, contentMode: .fill)
                    .frame(width: 36, height: 36)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(comment.user?.name ?? "匿名")
                            .font(.subheadline.weight(.semibold))
                        if let level = comment.user?.level {
                            Text("Lv.\(level)")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(MacUI.secondaryText(for: colorScheme))
                        }
                        if isPinned {
                            Text("置顶")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(MacUI.accentPink)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(MacUI.accentWash(for: colorScheme), in: Capsule())
                        }
                    }

                    if let createdAt = comment.created_at {
                        Text(createdAt)
                            .font(.caption2)
                            .foregroundStyle(MacUI.secondaryText(for: colorScheme))
                    }
                }

                Spacer()
            }

            Text(comment.content?.isEmpty == false ? comment.content! : "无内容")
                .font(.body)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                Button(action: onLike) {
                    Label("\(comment.likesCount ?? 0)", systemImage: comment.isLiked == true ? "heart.fill" : "heart")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(comment.isLiked == true ? MacUI.accentPink : .secondary)

                if showsRepliesButton {
                    Button(action: onReplies) {
                        Label("\(comment.commentsCount ?? comment.totalComments ?? 0)", systemImage: "text.bubble")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(MacUI.secondaryText(for: colorScheme))
                }

                Spacer()
            }
            .font(.caption)
        }
        .padding(12)
        .macSurface(colorScheme)
    }
}
