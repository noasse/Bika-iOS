import SwiftUI

@Observable
final class CommentsViewModel {
    var comments: [Comment] = []
    var topComments: [Comment] = []
    var currentPage = 0
    var totalPages = 1
    var totalVisibleComments = 0
    var isLoading = false
    var commentText = ""
    var isSending = false
    var errorMessage: String?
    var actionErrorMessage: String?

    var hasMore: Bool { currentPage < totalPages }

    let comicId: String
    private let client: any APIClientProtocol
    private var activeRequestID = 0
    private var lastPaginationTriggerCommentID: String?

    init(comicId: String, client: any APIClientProtocol = APIClient.shared) {
        self.comicId = comicId
        self.client = client
    }

    func loadInitialPageIfNeeded() async {
        guard currentPage == 0, comments.isEmpty, topComments.isEmpty else { return }
        await loadFirstPage()
    }

    func loadFirstPage(replacingContent: Bool = false) async {
        guard replacingContent || !isLoading else { return }
        activeRequestID += 1
        let requestID = activeRequestID

        if replacingContent {
            comments = []
            topComments = []
            currentPage = 0
            totalPages = 1
            totalVisibleComments = 0
        }

        isLoading = true
        errorMessage = nil
        lastPaginationTriggerCommentID = nil
        defer {
            if requestID == activeRequestID {
                isLoading = false
            }
        }

        do {
            let response: APIResponse<CommentsData> = try await client.send(
                .comments(comicId: comicId, page: 1)
            )
            guard requestID == activeRequestID else { return }
            if let data = response.data {
                topComments = uniqueComments(in: data.topComments)
                comments = data.regularComments()
                currentPage = data.page
                totalPages = max(data.pages, data.page)
                totalVisibleComments = data.topLevelCommentDisplayCount
            } else {
                comments = []
                topComments = []
                currentPage = 1
                totalPages = 1
                totalVisibleComments = 0
            }
        } catch let error as APIError {
            guard requestID == activeRequestID else { return }
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
            guard requestID == activeRequestID else { return }
            errorMessage = error.localizedDescription
        }
    }

    func loadMoreIfNeeded(currentItemID: String) async {
        guard hasMore, !isLoading else { return }
        guard currentItemID == comments.last?.id else { return }
        guard lastPaginationTriggerCommentID != currentItemID else { return }

        lastPaginationTriggerCommentID = currentItemID
        await loadMore()
    }

    func loadMore() async {
        guard hasMore, !isLoading else { return }
        activeRequestID += 1
        let requestID = activeRequestID
        isLoading = true
        defer {
            if requestID == activeRequestID {
                isLoading = false
            }
        }

        let nextPage = currentPage + 1
        do {
            let response: APIResponse<CommentsData> = try await client.send(
                .comments(comicId: comicId, page: nextPage)
            )
            guard requestID == activeRequestID else { return }
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

            if !data.topComments.isEmpty {
                topComments = uniqueComments(in: topComments + data.topComments)
            }

            let excludedCommentIDs = Set(comments.map(\.id)).union(topComments.map(\.id))
            let newComments = data.docs.filter { !excludedCommentIDs.contains($0.id) }
            guard !newComments.isEmpty else {
                currentPage = resolvedTotalPages
                return
            }

            comments.append(contentsOf: newComments)
            currentPage = data.page
        } catch {
            guard requestID == activeRequestID else { return }
            errorMessage = error.localizedDescription
        }
    }

    func postComment() async {
        let text = commentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }
        isSending = true
        actionErrorMessage = nil
        defer { isSending = false }

        do {
            let _: APIResponse<EmptyData> = try await client.send(
                .postComment(comicId: comicId, content: text)
            )
            commentText = ""
            await loadFirstPage(replacingContent: true)
        } catch {
            actionErrorMessage = error.localizedDescription
        }
    }

    func likeComment(id: String) async {
        do {
            let response: APIResponse<LikeActionData> = try await client.send(.likeComment(id: id))
            guard let action = response.data?.action else { return }
            CommentLikeReducer.apply(action: action, commentID: id, to: &comments)
            CommentLikeReducer.apply(action: action, commentID: id, to: &topComments)
        } catch {
            actionErrorMessage = error.localizedDescription
        }
    }

    private func uniqueComments(in comments: [Comment]) -> [Comment] {
        var seenIDs = Set<String>()
        return comments.filter { comment in
            seenIDs.insert(comment.id).inserted
        }
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
    var errorMessage: String?
    var actionErrorMessage: String?

    var hasMore: Bool { currentPage < totalPages }

    let commentId: String
    private let client: any APIClientProtocol
    private var activeRequestID = 0
    private var lastPaginationTriggerCommentID: String?

    init(commentId: String, client: any APIClientProtocol = APIClient.shared) {
        self.commentId = commentId
        self.client = client
    }

    func loadFirstPage(replacingContent: Bool = false) async {
        guard replacingContent || !isLoading else { return }
        activeRequestID += 1
        let requestID = activeRequestID

        if replacingContent {
            comments = []
            currentPage = 0
            totalPages = 1
        }

        isLoading = true
        errorMessage = nil
        lastPaginationTriggerCommentID = nil
        defer {
            if requestID == activeRequestID {
                isLoading = false
            }
        }

        do {
            let response: APIResponse<ChildCommentsData> = try await client.send(
                .childComments(commentId: commentId, page: 1)
            )
            guard requestID == activeRequestID else { return }
            if let data = response.data {
                comments = data.docs
                currentPage = data.page
                totalPages = max(data.pages, data.page)
            } else {
                comments = []
                currentPage = 1
                totalPages = 1
            }
        } catch {
            guard requestID == activeRequestID else { return }
            errorMessage = error.localizedDescription
        }
    }

    func loadMoreIfNeeded(currentItemID: String) async {
        guard hasMore, !isLoading else { return }
        guard currentItemID == comments.last?.id else { return }
        guard lastPaginationTriggerCommentID != currentItemID else { return }

        lastPaginationTriggerCommentID = currentItemID
        await loadMore()
    }

    func loadMore() async {
        guard hasMore, !isLoading else { return }
        activeRequestID += 1
        let requestID = activeRequestID
        isLoading = true
        defer {
            if requestID == activeRequestID {
                isLoading = false
            }
        }

        let nextPage = currentPage + 1
        let existingCommentIDs = Set(comments.map(\.id))
        do {
            let response: APIResponse<ChildCommentsData> = try await client.send(
                .childComments(commentId: commentId, page: nextPage)
            )
            guard requestID == activeRequestID else { return }
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
            guard requestID == activeRequestID else { return }
            errorMessage = error.localizedDescription
        }
    }

    func postReply() async {
        let text = replyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }
        isSending = true
        actionErrorMessage = nil
        defer { isSending = false }

        do {
            let _: APIResponse<EmptyData> = try await client.send(
                .postChildComment(commentId: commentId, content: text)
            )
            replyText = ""
            await loadFirstPage(replacingContent: true)
        } catch {
            actionErrorMessage = error.localizedDescription
        }
    }

    func likeComment(id: String) async {
        do {
            let response: APIResponse<LikeActionData> = try await client.send(.likeComment(id: id))
            guard let action = response.data?.action else { return }
            CommentLikeReducer.apply(action: action, commentID: id, to: &comments)
        } catch {
            actionErrorMessage = error.localizedDescription
        }
    }
}
