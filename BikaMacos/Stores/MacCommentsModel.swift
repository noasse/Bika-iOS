import Foundation
import SwiftUI

@MainActor
@Observable
final class MacCommentsModel {
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

    let comicId: String

    private let client: any APIClientProtocol
    private var activeRequestID = 0
    private var inFlightLikeCommentIDs: Set<String> = []
    private var lastPaginationTriggerCommentID: String?

    init(comicId: String, client: any APIClientProtocol = APIClient.shared) {
        self.comicId = comicId
        self.client = client
    }

    var hasMore: Bool {
        currentPage < totalPages
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
            let response: APIResponse<CommentsData> = try await client.send(.comments(comicId: comicId, page: 1))
            guard requestID == activeRequestID else { return }
            applyFirstPage(response.data)
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
            let response: APIResponse<CommentsData> = try await client.send(.comments(comicId: comicId, page: nextPage))
            guard requestID == activeRequestID else { return }
            guard let data = response.data else {
                currentPage = totalPages
                return
            }

            totalPages = max(data.pages, data.page)
            guard data.page >= nextPage else {
                currentPage = totalPages
                return
            }

            if !data.topComments.isEmpty {
                topComments = uniqueComments(topComments + data.topComments)
            }

            let excludedCommentIDs = Set(comments.map(\.id)).union(topComments.map(\.id))
            let newComments = data.docs.filter { !excludedCommentIDs.contains($0.id) }
            guard !newComments.isEmpty else {
                currentPage = totalPages
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
            let _: APIResponse<EmptyData> = try await client.send(.postComment(comicId: comicId, content: text))
            commentText = ""
            await loadFirstPage(replacingContent: true)
        } catch {
            actionErrorMessage = error.localizedDescription
        }
    }

    func likeComment(id: String) async {
        guard inFlightLikeCommentIDs.insert(id).inserted else { return }
        defer { inFlightLikeCommentIDs.remove(id) }

        do {
            let response: APIResponse<LikeActionData> = try await client.send(.likeComment(id: id))
            guard let action = response.data?.action else { return }
            CommentLikeReducer.apply(action: action, commentID: id, to: &comments)
            CommentLikeReducer.apply(action: action, commentID: id, to: &topComments)
        } catch {
            actionErrorMessage = error.localizedDescription
        }
    }

    private func applyFirstPage(_ data: CommentsData?) {
        guard let data else {
            comments = []
            topComments = []
            currentPage = 1
            totalPages = 1
            totalVisibleComments = 0
            return
        }

        topComments = uniqueComments(data.topComments)
        comments = data.regularComments()
        currentPage = data.page
        totalPages = max(data.pages, data.page)
        totalVisibleComments = data.topLevelCommentDisplayCount
    }

    private func uniqueComments(_ comments: [Comment]) -> [Comment] {
        var seenIDs = Set<String>()
        return comments.filter { seenIDs.insert($0.id).inserted }
    }
}

@MainActor
@Observable
final class MacChildCommentsModel {
    var comments: [Comment] = []
    var currentPage = 0
    var totalPages = 1
    var isLoading = false
    var replyText = ""
    var isSending = false
    var errorMessage: String?
    var actionErrorMessage: String?

    let commentId: String

    private let client: any APIClientProtocol
    private var activeRequestID = 0
    private var inFlightLikeCommentIDs: Set<String> = []
    private var lastPaginationTriggerCommentID: String?

    init(commentId: String, client: any APIClientProtocol = APIClient.shared) {
        self.commentId = commentId
        self.client = client
    }

    var hasMore: Bool {
        currentPage < totalPages
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
            let response: APIResponse<ChildCommentsData> = try await client.send(.childComments(commentId: commentId, page: 1))
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
        let existingIDs = Set(comments.map(\.id))
        do {
            let response: APIResponse<ChildCommentsData> = try await client.send(.childComments(commentId: commentId, page: nextPage))
            guard requestID == activeRequestID else { return }
            guard let data = response.data else {
                currentPage = totalPages
                return
            }

            totalPages = max(data.pages, data.page)
            guard data.page >= nextPage else {
                currentPage = totalPages
                return
            }

            let newComments = data.docs.filter { !existingIDs.contains($0.id) }
            guard !newComments.isEmpty else {
                currentPage = totalPages
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
            let _: APIResponse<EmptyData> = try await client.send(.postChildComment(commentId: commentId, content: text))
            replyText = ""
            await loadFirstPage(replacingContent: true)
        } catch {
            actionErrorMessage = error.localizedDescription
        }
    }

    func likeComment(id: String) async {
        guard inFlightLikeCommentIDs.insert(id).inserted else { return }
        defer { inFlightLikeCommentIDs.remove(id) }

        do {
            let response: APIResponse<LikeActionData> = try await client.send(.likeComment(id: id))
            guard let action = response.data?.action else { return }
            CommentLikeReducer.apply(action: action, commentID: id, to: &comments)
        } catch {
            actionErrorMessage = error.localizedDescription
        }
    }
}
