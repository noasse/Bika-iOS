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
    private var lastPaginationTriggerCommentID: String?

    init(comicId: String, client: any APIClientProtocol = APIClient.shared) {
        self.comicId = comicId
        self.client = client
    }

    var hasMore: Bool {
        currentPage < totalPages
    }

    func loadFirstPage() async {
        activeRequestID += 1
        let requestID = activeRequestID
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
        do {
            let response: APIResponse<CommentsData> = try await client.send(.comments(comicId: comicId, page: nextPage))
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
            comments = []
            topComments = []
            currentPage = 0
            totalPages = 1
            totalVisibleComments = 0
            lastPaginationTriggerCommentID = nil
            await loadFirstPage()
        } catch {
            actionErrorMessage = error.localizedDescription
        }
    }

    func likeComment(id: String) async {
        do {
            let _: APIResponse<LikeActionData> = try await client.send(.likeComment(id: id))
            toggleLike(id: id, in: &comments)
            toggleLike(id: id, in: &topComments)
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

    private func toggleLike(id: String, in list: inout [Comment]) {
        guard let index = list.firstIndex(where: { $0.id == id }) else { return }
        let wasLiked = list[index].isLiked ?? false
        list[index].isLiked = !wasLiked
        list[index].likesCount = max((list[index].likesCount ?? 0) + (wasLiked ? -1 : 1), 0)
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
    private var lastPaginationTriggerCommentID: String?

    init(commentId: String, client: any APIClientProtocol = APIClient.shared) {
        self.commentId = commentId
        self.client = client
    }

    var hasMore: Bool {
        currentPage < totalPages
    }

    func loadFirstPage() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        lastPaginationTriggerCommentID = nil
        defer { isLoading = false }

        do {
            let response: APIResponse<ChildCommentsData> = try await client.send(.childComments(commentId: commentId, page: 1))
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
        let existingIDs = Set(comments.map(\.id))
        do {
            let response: APIResponse<ChildCommentsData> = try await client.send(.childComments(commentId: commentId, page: nextPage))
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
            comments = []
            currentPage = 0
            totalPages = 1
            lastPaginationTriggerCommentID = nil
            await loadFirstPage()
        } catch {
            actionErrorMessage = error.localizedDescription
        }
    }

    func likeComment(id: String) async {
        do {
            let _: APIResponse<LikeActionData> = try await client.send(.likeComment(id: id))
            guard let index = comments.firstIndex(where: { $0.id == id }) else { return }
            let wasLiked = comments[index].isLiked ?? false
            comments[index].isLiked = !wasLiked
            comments[index].likesCount = max((comments[index].likesCount ?? 0) + (wasLiked ? -1 : 1), 0)
        } catch {
            actionErrorMessage = error.localizedDescription
        }
    }
}
