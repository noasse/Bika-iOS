import SwiftUI

struct CommentsView: View {
    @State private var viewModel: CommentsViewModel
    @State private var selectedComment: Comment?
    @State private var selectedUser: Creator?
    @Environment(\.colorScheme) private var colorScheme

    init(comicId: String) {
        _viewModel = State(initialValue: CommentsViewModel(comicId: comicId))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                if viewModel.isLoading && viewModel.comments.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 300)
                } else if let error = viewModel.errorMessage {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.title)
                            .foregroundStyle(.orange)
                        Text("加载失败")
                            .font(.headline)
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(Color.secondaryText(for: colorScheme))
                            .multilineTextAlignment(.center)
                        Button("重试") {
                            Task { await viewModel.loadFirstPage() }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.accentPink)
                    }
                    .frame(maxWidth: .infinity, minHeight: 200)
                    .padding()
                } else if viewModel.comments.isEmpty && viewModel.topComments.isEmpty && viewModel.currentPage > 0 {
                    Text("暂无评论")
                        .foregroundStyle(Color.secondaryText(for: colorScheme))
                        .frame(maxWidth: .infinity, minHeight: 200)
                } else {
                    LazyVStack(spacing: 10) {
                        // Top (pinned) comments
                        if !viewModel.topComments.isEmpty {
                            Section {
                                ForEach(viewModel.topComments) { comment in
                                    commentCard(comment)
                                }
                            } header: {
                                Text("置顶评论")
                                    .font(.caption.bold())
                                    .foregroundStyle(Color.secondaryText(for: colorScheme))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }

                        // Regular comments
                        ForEach(viewModel.comments) { comment in
                            commentCard(comment)
                                .onAppear {
                                    if comment.id == viewModel.comments.last?.id {
                                        Task { await viewModel.loadMore() }
                                    }
                                }
                        }

                        // Loading indicator at bottom
                        if viewModel.isLoading && !viewModel.comments.isEmpty {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding()
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 80)
                }
            }

            // Input bar
            inputBar
        }
        .background(Color.mainBg(for: colorScheme))
        .navigationTitle("评论")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $selectedComment) { comment in
            ChildCommentsView(parentComment: comment)
        }
        .userProfileOverlay(user: $selectedUser)
        .task { await viewModel.loadFirstPage() }
    }

    private func commentCard(_ comment: Comment) -> some View {
        CommentCardView(
            comment: comment,
            onLike: {
                Task { await viewModel.likeComment(id: comment.id) }
            },
            onTap: {
                selectedComment = comment
            },
            onAvatarTap: {
                selectedUser = comment.user
            }
        )
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("发表评论...", text: $viewModel.commentText)
                .textFieldStyle(.roundedBorder)

            Button {
                Task { await viewModel.postComment() }
            } label: {
                if viewModel.isSending {
                    ProgressView()
                        .frame(width: 20, height: 20)
                } else {
                    Image(systemName: "paperplane.fill")
                        .foregroundStyle(Color.accentPink)
                }
            }
            .disabled(viewModel.commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isSending)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }
}
