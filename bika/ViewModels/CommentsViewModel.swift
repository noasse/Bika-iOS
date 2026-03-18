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

    let comicId: String
    private let client = APIClient.shared

    init(comicId: String) {
        self.comicId = comicId
    }

    func loadPage(_ page: Int) async {
        guard page >= 1, !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let response: APIResponse<CommentsData> = try await client.send(
                .comments(comicId: comicId, page: page)
            )
            if let data = response.data {
                comments = data.docs
                currentPage = data.page
                totalPages = data.pages
                if page == 1 {
                    topComments = data.topComments
                }
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

    func nextPage() async {
        guard currentPage < totalPages else { return }
        await loadPage(currentPage + 1)
    }

    func prevPage() async {
        guard currentPage > 1 else { return }
        await loadPage(currentPage - 1)
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
            await loadPage(1)
        } catch {}
    }

    func likeComment(id: String) async {
        do {
            let _: APIResponse<LikeActionData> = try await client.send(.likeComment(id: id))
            if currentPage > 0 {
                await loadPage(currentPage)
            }
        } catch {}
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

    let commentId: String
    private let client = APIClient.shared

    init(commentId: String) {
        self.commentId = commentId
    }

    func loadPage(_ page: Int) async {
        guard page >= 1, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let response: APIResponse<ChildCommentsData> = try await client.send(
                .childComments(commentId: commentId, page: page)
            )
            if let data = response.data {
                comments = data.docs
                currentPage = data.page
                totalPages = data.pages
            }
        } catch {}
    }

    func nextPage() async {
        guard currentPage < totalPages else { return }
        await loadPage(currentPage + 1)
    }

    func prevPage() async {
        guard currentPage > 1 else { return }
        await loadPage(currentPage - 1)
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
            await loadPage(currentPage > 0 ? currentPage : 1)
        } catch {}
    }

    func likeComment(id: String) async {
        do {
            let _: APIResponse<LikeActionData> = try await client.send(.likeComment(id: id))
            if currentPage > 0 {
                await loadPage(currentPage)
            }
        } catch {}
    }
}
