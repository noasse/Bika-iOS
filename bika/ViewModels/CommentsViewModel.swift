import SwiftUI

@Observable
final class CommentsViewModel {
    var comments: [Comment] = []
    var topComments: [Comment] = []
    var currentPage = 0
    var totalPages = 1
    var isLoading = false
    var commentText = ""
    var isSending = false
    var errorMessage: String?

    var hasMore: Bool { currentPage < totalPages }

    let comicId: String
    private let client: any APIClientProtocol
    private var lastPaginationTriggerCommentID: String?

    init(comicId: String, client: any APIClientProtocol = APIClient.shared) {
        self.comicId = comicId
        self.client = client
    }

    func loadFirstPage() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        lastPaginationTriggerCommentID = nil
        defer { isLoading = false }

        do {
            let response: APIResponse<CommentsData> = try await client.send(
                .comments(comicId: comicId, page: 1)
            )
            if let data = response.data {
                comments = data.docs
                currentPage = data.page
                totalPages = max(data.pages, data.page)
                topComments = data.topComments
            } else {
                comments = []
                topComments = []
                currentPage = 1
                totalPages = 1
            }
        } catch let error as APIError {
            switch error {
            case .decodingError(let inner):
                if let de = inner as? DecodingError {
                    switch de {
                    case .keyNotFound(let key, let ctx):
                        errorMessage = "缺少字段: \(key.stringValue) (路径: \(ctx.codingPath.map(\.stringValue).joined(separator: ".")))"
                    case .typeMismatch(let type, let ctx):
                        errorMessage = "类型错误: \(type) (路径: \(ctx.codingPath.map(\.stringValue).joined(separator: ".")))"
                    case .valueNotFound(let type, let ctx):
                        errorMessage = "空值: \(type) (路径: \(ctx.codingPath.map(\.stringValue).joined(separator: ".")))"
                    case .dataCorrupted(let ctx):
                        errorMessage = "数据损坏 (路径: \(ctx.codingPath.map(\.stringValue).joined(separator: ".")))"
                    @unknown default:
                        errorMessage = de.localizedDescription
                    }
                } else {
                    errorMessage = inner.localizedDescription
                }
            default:
                errorMessage = error.localizedDescription
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadMoreIfNeeded(currentItemID: String) async {
        guard currentItemID == comments.last?.id else { return }
        guard lastPaginationTriggerCommentID != currentItemID else { return }

        lastPaginationTriggerCommentID = currentItemID
        await loadMore()
    }

    func loadMore() async {
        guard hasMore, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        let nextPage = currentPage + 1
        let existingCommentIDs = Set(comments.map(\.id))
        do {
            let response: APIResponse<CommentsData> = try await client.send(
                .comments(comicId: comicId, page: nextPage)
            )
            guard let data = response.data else {
                currentPage = totalPages
                return
            }

            let resolvedTotalPages = max(data.pages, data.page)
            totalPages = resolvedTotalPages

            guard data.page >= nextPage else {
                currentPage = resolvedTotalPages
                return
            }

            let newComments = data.docs.filter { !existingCommentIDs.contains($0.id) }
            guard !newComments.isEmpty else {
                currentPage = resolvedTotalPages
                return
            }

            comments.append(contentsOf: newComments)
            currentPage = data.page
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func postComment() async {
        let text = commentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }
        isSending = true
        defer { isSending = false }

        do {
            let _: APIResponse<EmptyData> = try await client.send(
                .postComment(comicId: comicId, content: text)
            )
            commentText = ""
            // Reset and reload from page 1 to show new comment
            comments = []
            topComments = []
            currentPage = 0
            totalPages = 1
            lastPaginationTriggerCommentID = nil
            await loadFirstPage()
        } catch {}
    }

    func likeComment(id: String) async {
        do {
            let _: APIResponse<LikeActionData> = try await client.send(.likeComment(id: id))
            toggleLike(id: id, in: &comments)
            toggleLike(id: id, in: &topComments)
        } catch {}
    }

    private func toggleLike(id: String, in list: inout [Comment]) {
        guard let idx = list.firstIndex(where: { $0.id == id }) else { return }
        let wasLiked = list[idx].isLiked ?? false
        list[idx].isLiked = !wasLiked
        list[idx].likesCount = (list[idx].likesCount ?? 0) + (wasLiked ? -1 : 1)
    }
}

// MARK: - Child Comments ViewModel

@Observable
final class ChildCommentsViewModel {
    var comments: [Comment] = []
    var currentPage = 0
    var totalPages = 1
    var isLoading = false
    var replyText = ""
    var isSending = false

    var hasMore: Bool { currentPage < totalPages }

    let commentId: String
    private let client: any APIClientProtocol
    private var lastPaginationTriggerCommentID: String?

    init(commentId: String, client: any APIClientProtocol = APIClient.shared) {
        self.commentId = commentId
        self.client = client
    }

    func loadFirstPage() async {
        guard !isLoading else { return }
        isLoading = true
        lastPaginationTriggerCommentID = nil
        defer { isLoading = false }

        do {
            let response: APIResponse<ChildCommentsData> = try await client.send(
                .childComments(commentId: commentId, page: 1)
            )
            if let data = response.data {
                comments = data.docs
                currentPage = data.page
                totalPages = max(data.pages, data.page)
            } else {
                comments = []
                currentPage = 1
                totalPages = 1
            }
        } catch {}
    }

    func loadMoreIfNeeded(currentItemID: String) async {
        guard currentItemID == comments.last?.id else { return }
        guard lastPaginationTriggerCommentID != currentItemID else { return }

        lastPaginationTriggerCommentID = currentItemID
        await loadMore()
    }

    func loadMore() async {
        guard hasMore, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        let nextPage = currentPage + 1
        let existingCommentIDs = Set(comments.map(\.id))
        do {
            let response: APIResponse<ChildCommentsData> = try await client.send(
                .childComments(commentId: commentId, page: nextPage)
            )
            guard let data = response.data else {
                currentPage = totalPages
                return
            }

            let resolvedTotalPages = max(data.pages, data.page)
            totalPages = resolvedTotalPages

            guard data.page >= nextPage else {
                currentPage = resolvedTotalPages
                return
            }

            let newComments = data.docs.filter { !existingCommentIDs.contains($0.id) }
            guard !newComments.isEmpty else {
                currentPage = resolvedTotalPages
                return
            }

            comments.append(contentsOf: newComments)
            currentPage = data.page
        } catch {}
    }

    func postReply() async {
        let text = replyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }
        isSending = true
        defer { isSending = false }

        do {
            let _: APIResponse<EmptyData> = try await client.send(
                .postChildComment(commentId: commentId, content: text)
            )
            replyText = ""
            comments = []
            currentPage = 0
            totalPages = 1
            lastPaginationTriggerCommentID = nil
            await loadFirstPage()
        } catch {}
    }

    func likeComment(id: String) async {
        do {
            let _: APIResponse<LikeActionData> = try await client.send(.likeComment(id: id))
            guard let idx = comments.firstIndex(where: { $0.id == id }) else { return }
            let wasLiked = comments[idx].isLiked ?? false
            comments[idx].isLiked = !wasLiked
            comments[idx].likesCount = (comments[idx].likesCount ?? 0) + (wasLiked ? -1 : 1)
        } catch {}
    }
}
