import SwiftUI

struct PaginatedComicResultsView<Header: View, LeadingContent: View>: View {
    let comics: [Comic]
    let isLoading: Bool
    let errorMessage: String?
    let emptyMessage: String
    let currentPage: Int
    let totalPages: Int
    let lastVisitedPage: Int
    let pendingRestoreComicID: String?
    let identifierPrefix: String
    let onConsumePendingRestoreComicID: () -> Void
    let onRememberNavigationAnchor: (String) -> Void
    let onLoadPage: (Int) async -> Void
    let onPrevPage: () async -> Void
    let onNextPage: () async -> Void
    let onRestoreLastPage: () async -> Void
    let onRetry: (() async -> Void)?
    @Binding var previewImageURL: URL?
    @ViewBuilder let header: () -> Header
    @ViewBuilder let leadingContent: (Int, Comic) -> LeadingContent

    @Environment(\.colorScheme) private var colorScheme
    @State private var showPagination = false

    private let topAnchorID = "paginatedComicResults.top"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Color.clear
                    .frame(height: 0)
                    .id(topAnchorID)

                header()

                if isLoading && comics.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 300)
                } else if let errorMessage, comics.isEmpty {
                    VStack(spacing: 12) {
                        Text("加载失败")
                            .font(.headline)
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(Color.secondaryText(for: colorScheme))
                            .multilineTextAlignment(.center)

                        if let onRetry {
                            Button("重试") {
                                Task { await onRetry() }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Color.accentPink)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 300)
                    .padding(.horizontal, 24)
                } else if comics.isEmpty && currentPage > 0 {
                    Text(emptyMessage)
                        .foregroundStyle(Color.secondaryText(for: colorScheme))
                        .frame(maxWidth: .infinity, minHeight: 300)
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(Array(comics.enumerated()), id: \.element.id) { index, comic in
                            NavigationLink(value: comic) {
                                HStack(spacing: 0) {
                                    leadingContent(index, comic)
                                    ComicCardView(comic: comic, previewImageURL: $previewImageURL)
                                }
                            }
                            .id(comic.id)
                            .simultaneousGesture(
                                TapGesture().onEnded {
                                    onRememberNavigationAnchor(comic.id)
                                }
                            )
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("\(identifierPrefix).\(comic.id)")
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .onScrollGeometryChange(for: Bool.self) { geo in
                geo.contentOffset.y + geo.visibleRect.height >= geo.contentSize.height - 100
            } action: { _, isAtBottom in
                showPagination = isAtBottom
            }
            .overlay(alignment: .bottom) {
                if showPagination && totalPages > 1 {
                    PaginationButtons(
                        currentPage: currentPage,
                        totalPages: totalPages,
                        isLoading: isLoading,
                        onPrev: { Task {
                            await onPrevPage()
                            scrollToTop(using: proxy)
                        }},
                        onNext: { Task {
                            await onNextPage()
                            scrollToTop(using: proxy)
                        }}
                    )
                }
            }
            .toolbar {
                if totalPages > 0 && currentPage > 0 {
                    ToolbarItem(placement: .topBarTrailing) {
                        PageJumpToolbarItem(
                            currentPage: currentPage,
                            totalPages: totalPages,
                            lastVisitedPage: lastVisitedPage,
                            isLoading: isLoading,
                            onGoToPage: { page in Task {
                                await onLoadPage(page)
                                scrollToTop(using: proxy)
                            }},
                            onRestoreLast: { Task {
                                await onRestoreLastPage()
                                scrollToTop(using: proxy)
                            }}
                        )
                    }
                }
            }
            .navigationDestination(for: Comic.self) { comic in
                ComicDetailView(comicId: comic.id)
            }
            .imagePreviewSheet(url: $previewImageURL)
            .onChange(of: comics.map(\.id)) { _, _ in
                restoreSavedPosition(using: proxy)
            }
        }
    }

    private func restoreSavedPosition(using proxy: ScrollViewProxy) {
        guard let comicID = pendingRestoreComicID else { return }
        guard comics.contains(where: { $0.id == comicID }) else { return }

        DispatchQueue.main.async {
            proxy.scrollTo(comicID, anchor: .top)
            onConsumePendingRestoreComicID()
        }
    }

    private func scrollToTop(using proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            proxy.scrollTo(topAnchorID, anchor: .top)
        }
    }
}
