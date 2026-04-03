import SwiftUI

struct ChildCommentsView: View {
    let parentComment: Comment
    @State private var viewModel: ChildCommentsViewModel
    @State private var selectedUser: Creator?
    @Environment(\.colorScheme) private var colorScheme

    init(parentComment: Comment) {
        self.parentComment = parentComment
        _viewModel = State(initialValue: ChildCommentsViewModel(commentId: parentComment.id))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                LazyVStack(spacing: 10) {
                    // Parent comment at top
                    CommentCardView(
                        comment: parentComment,
                        showReplyCount: false,
                        onAvatarTap: { selectedUser = parentComment.user }
                    )

                    Divider()
                        .padding(.horizontal)

                    if viewModel.isLoading && viewModel.comments.isEmpty {
                        ProgressView()
                            .frame(maxWidth: .infinity, minHeight: 200)
                    } else if let errorMessage = viewModel.errorMessage, viewModel.comments.isEmpty {
                        VStack(spacing: 12) {
                            Text("加载失败")
                                .font(.headline)
                            Text(errorMessage)
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
                    } else if viewModel.comments.isEmpty && viewModel.currentPage > 0 {
                        Text("暂无回复")
                            .foregroundStyle(Color.secondaryText(for: colorScheme))
                            .frame(maxWidth: .infinity, minHeight: 100)
                    } else {
                        ForEach(viewModel.comments) { comment in
                            CommentCardView(
                                comment: comment,
                                showReplyCount: false,
                                onLike: {
                                    Task { await viewModel.likeComment(id: comment.id) }
                                },
                                onAvatarTap: {
                                    selectedUser = comment.user
                                }
                            )
                            .onAppear {
                                if comment.id == viewModel.comments.last?.id {
                                    Task { await viewModel.loadMoreIfNeeded(currentItemID: comment.id) }
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
                }
                .padding(.horizontal)
                .padding(.bottom, 80)
            }

            // Reply input bar
            inputBar
        }
        .background(Color.mainBg(for: colorScheme))
        .navigationTitle("回复")
        .navigationBarTitleDisplayMode(.inline)
        .userProfileOverlay(user: $selectedUser)
        .alert("操作失败", isPresented: actionErrorIsPresented) {
            Button("确定", role: .cancel) {
                viewModel.actionErrorMessage = nil
            }
        } message: {
            Text(viewModel.actionErrorMessage ?? "")
        }
        .task { await viewModel.loadFirstPage() }
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("发表回复...", text: $viewModel.replyText)
                .textFieldStyle(.roundedBorder)

            Button {
                Task { await viewModel.postReply() }
            } label: {
                if viewModel.isSending {
                    ProgressView()
                        .frame(width: 20, height: 20)
                } else {
                    Image(systemName: "paperplane.fill")
                        .foregroundStyle(Color.accentPink)
                }
            }
            .disabled(viewModel.replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isSending)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    private var actionErrorIsPresented: Binding<Bool> {
        Binding(
            get: { viewModel.actionErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    viewModel.actionErrorMessage = nil
                }
            }
        )
    }
}
