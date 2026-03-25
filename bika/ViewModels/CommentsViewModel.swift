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
    private let client = APIClient.shared

    init(comicId: String) {
        self.comicId = comicId
    }

    func loadFirstPage() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let response: APIResponse<CommentsData> = try await client.send(
                .comments(comicId: comicId, page: 1)
            )
            if let data = response.data {
                comments = data.docs
                currentPage = data.page
                totalPages = data.pages
                topComments = data.topComments
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

    func loadMore() async {
        guard hasMore, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        let nextPage = currentPage + 1
        do {
            let response: APIResponse<CommentsData> = try await client.send(
                .comments(comicId: comicId, page: nextPage)
            )
            if let data = response.data {
                comments.append(contentsOf: data.docs)
                currentPage = data.page
                totalPages = data.pages
            }
        } catch {}
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
    private let client = APIClient.shared

    init(commentId: String) {
        self.commentId = commentId
    }

    func loadFirstPage() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let response: APIResponse<ChildCommentsData> = try await client.send(
                .childComments(commentId: commentId, page: 1)
            )
            if let data = response.data {
                comments = data.docs
                currentPage = data.page
                totalPages = data.pages
            }
        } catch {}
    }

    func loadMore() async {
        guard hasMore, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        let nextPage = currentPage + 1
        do {
            let response: APIResponse<ChildCommentsData> = try await client.send(
                .childComments(commentId: commentId, page: nextPage)
            )
            if let data = response.data {
                comments.append(contentsOf: data.docs)
                currentPage = data.page
                totalPages = data.pages
            }
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
