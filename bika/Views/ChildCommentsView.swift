import SwiftUI

struct ChildCommentsView: View {
    let parentComment: Comment
    @State private var viewModel: ChildCommentsViewModel
    @State private var showPagination = false
    @State private var scrollPosition = ScrollPosition(edge: .top)
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
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 80)
            }
            .scrollPosition($scrollPosition)
            .onScrollGeometryChange(for: Bool.self) { geo in
                geo.contentOffset.y + geo.visibleRect.height >= geo.contentSize.height - 100
            } action: { _, isAtBottom in
                showPagination = isAtBottom
            }
            .overlay(alignment: .bottom) {
                if showPagination && viewModel.totalPages > 1 {
                    PaginationButtons(
                        currentPage: viewModel.currentPage,
                        totalPages: viewModel.totalPages,
                        isLoading: viewModel.isLoading,
                        onPrev: { Task {
                            await viewModel.prevPage()
                            scrollPosition.scrollTo(edge: .top)
                        }},
                        onNext: { Task {
                            await viewModel.nextPage()
                            scrollPosition.scrollTo(edge: .top)
                        }}
                    )
                    .padding(.bottom, 56)
                }
            }

            // Reply input bar
            inputBar
        }
        .background(Color.mainBg(for: colorScheme))
        .navigationTitle("回复")
        .navigationBarTitleDisplayMode(.inline)
        .userProfileOverlay(user: $selectedUser)
        .task { await viewModel.loadPage(1) }
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
}
