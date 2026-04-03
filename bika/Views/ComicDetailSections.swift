import SwiftUI

struct ComicDetailHeaderSection: View {
    let detail: ComicDetail
    let colorScheme: ColorScheme
    let onPreviewImage: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            MediaImageView(
                media: detail.thumb,
                cornerRadius: 8,
                targetSize: CGSize(width: 120, height: 170)
            )
            .frame(width: 120, height: 170)
            .onTapGesture(perform: onPreviewImage)

            VStack(alignment: .leading, spacing: 6) {
                Text(detail.title)
                    .font(.title3.bold())

                if let author = detail.author {
                    NavigationLink {
                        AuthorSearchResultsView(author: author)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "person")
                                .font(.caption2)
                            Text(author)
                                .font(.subheadline)
                        }
                        .foregroundStyle(Color.accentPink)
                    }
                }

                if let chineseTeam = detail.chineseTeam, !chineseTeam.isEmpty {
                    Text("汉化: \(chineseTeam)")
                        .font(.caption)
                        .foregroundStyle(Color.secondaryText(for: colorScheme))
                }

                Spacer()

                HStack(spacing: 16) {
                    ComicDetailStatLabel(
                        systemImage: "eye",
                        value: detail.totalViews ?? detail.viewsCount ?? 0,
                        colorScheme: colorScheme
                    )
                    ComicDetailStatLabel(
                        systemImage: "heart",
                        value: detail.totalLikes ?? detail.likesCount ?? 0,
                        colorScheme: colorScheme
                    )
                    if let eps = detail.epsCount {
                        ComicDetailStatLabel(
                            systemImage: "book",
                            value: eps,
                            colorScheme: colorScheme
                        )
                    }
                }
            }
        }
        .padding(.horizontal)
    }
}

struct ComicDetailActionsSection: View {
    let detail: ComicDetail
    let onToggleLike: () -> Void
    let onToggleFavourite: () -> Void

    var body: some View {
        HStack(spacing: 20) {
            ComicDetailActionButton(
                title: detail.isLiked == true ? "已喜欢" : "喜欢",
                systemImage: detail.isLiked == true ? "heart.fill" : "heart",
                tint: detail.isLiked == true ? .red : .gray,
                action: onToggleLike
            )

            ComicDetailActionButton(
                title: detail.isFavourite == true ? "已收藏" : "收藏",
                systemImage: detail.isFavourite == true ? "star.fill" : "star",
                tint: detail.isFavourite == true ? .yellow : .gray,
                action: onToggleFavourite
            )
        }
        .padding(.horizontal)
    }
}

struct ComicCategoriesSection: View {
    let categories: [String]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(categories, id: \.self) { category in
                    NavigationLink {
                        ComicListView(category: category)
                    } label: {
                        Text(category)
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.accentPink.opacity(0.15))
                            .foregroundStyle(Color.accentPink)
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(.horizontal)
        }
    }
}

struct ComicTagsSection: View {
    let tags: [String]
    let colorScheme: ColorScheme

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(tags, id: \.self) { tag in
                    NavigationLink {
                        TagSearchResultsView(keyword: tag)
                    } label: {
                        Text(tag)
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.gray.opacity(0.15))
                            .foregroundStyle(Color.secondaryText(for: colorScheme))
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(.horizontal)
        }
    }
}

struct ComicDescriptionSection: View {
    let description: String
    let colorScheme: ColorScheme

    var body: some View {
        Text(description)
            .font(.callout)
            .foregroundStyle(Color.secondaryText(for: colorScheme))
            .padding(.horizontal)
    }
}

struct ComicEpisodesSection: View {
    let episodes: [Episode]
    let isLoading: Bool
    let errorMessage: String?
    let colorScheme: ColorScheme
    let onSelectEpisode: (Int) -> Void
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("章节")
                .font(.headline)
                .padding(.horizontal)

            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
            } else if let errorMessage, episodes.isEmpty {
                VStack(spacing: 8) {
                    Text("章节加载失败")
                        .font(.caption)
                        .foregroundStyle(Color.secondaryText(for: colorScheme))
                    Text(errorMessage)
                        .font(.caption2)
                        .foregroundStyle(Color.secondaryText(for: colorScheme))
                        .multilineTextAlignment(.center)
                    Button("重试", action: onRetry)
                        .font(.caption)
                        .buttonStyle(.borderedProminent)
                        .tint(Color.accentPink)
                        .accessibilityIdentifier("comicDetail.episodes.retry")
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal)
            } else if episodes.isEmpty {
                Text("暂无章节")
                    .font(.caption)
                    .foregroundStyle(Color.secondaryText(for: colorScheme))
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: 8) {
                    ForEach(Array(episodes.enumerated()), id: \.element.id) { index, episode in
                        Button {
                            onSelectEpisode(index)
                        } label: {
                            Text(episode.title)
                                .font(.caption)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(Color.cardBg(for: colorScheme))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("comicDetail.episode.\(episode.order)")
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

struct ContinueReadingSection: View {
    let progress: ReadingProgressManager.Progress
    let onContinue: () -> Void

    var body: some View {
        Button(action: onContinue) {
            HStack {
                Image(systemName: "book.fill")
                Text("继续阅读 \(progress.episodeTitle)")
                Spacer()
                Image(systemName: "chevron.right")
            }
            .font(.subheadline)
            .foregroundStyle(.white)
            .padding()
            .background(Color.accentPink)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .padding(.horizontal)
        .accessibilityIdentifier("comicDetail.continueReading")
    }
}

struct ComicCommentEntrySection: View {
    let label: String
    let colorScheme: ColorScheme
    let comicId: String

    var body: some View {
        NavigationLink {
            CommentsView(comicId: comicId)
        } label: {
            HStack {
                Image(systemName: "bubble.left.and.bubble.right")
                Text(label)
                Spacer()
                Image(systemName: "chevron.right")
            }
            .font(.subheadline)
            .foregroundStyle(.primary)
            .padding()
            .background(Color.cardBg(for: colorScheme))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .padding(.horizontal)
        .accessibilityIdentifier("comicDetail.openComments")
    }
}

struct RecommendedComicsSection: View {
    let comics: [Comic]
    let isLoading: Bool
    let errorMessage: String?
    let colorScheme: ColorScheme
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("相关推荐")
                .font(.headline)
                .padding(.horizontal)

            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding()
                    .accessibilityIdentifier("comicDetail.recommended.loading")
            } else if !comics.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(comics) { comic in
                            NavigationLink {
                                ComicDetailView(comicId: comic.id)
                            } label: {
                                VStack(spacing: 6) {
                                    MediaImageView(
                                        media: comic.thumb,
                                        cornerRadius: 6,
                                        targetSize: CGSize(width: 100, height: 140)
                                    )
                                    .frame(width: 100, height: 140)

                                    Text(comic.title)
                                        .font(.caption)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.center)
                                        .frame(width: 100)
                                }
                                .foregroundStyle(.primary)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            } else if let errorMessage {
                VStack(spacing: 8) {
                    Text("加载推荐失败")
                        .font(.caption)
                        .foregroundStyle(Color.secondaryText(for: colorScheme))
                    Text(errorMessage)
                        .font(.caption2)
                        .foregroundStyle(Color.secondaryText(for: colorScheme))
                        .multilineTextAlignment(.center)
                    Button("重试", action: onRetry)
                        .font(.caption)
                        .buttonStyle(.borderedProminent)
                        .tint(Color.accentPink)
                        .accessibilityIdentifier("comicDetail.recommended.retry")
                }
                .frame(maxWidth: .infinity)
                .padding()
            } else {
                Text("暂无相关推荐")
                    .font(.caption)
                    .foregroundStyle(Color.secondaryText(for: colorScheme))
                    .frame(maxWidth: .infinity)
                    .padding()
                    .accessibilityIdentifier("comicDetail.recommended.empty")
            }
        }
    }
}

private struct ComicDetailStatLabel: View {
    let systemImage: String
    let value: Int
    let colorScheme: ColorScheme

    var body: some View {
        Label("\(value)", systemImage: systemImage)
            .font(.caption)
            .foregroundStyle(Color.secondaryText(for: colorScheme))
    }
}

private struct ComicDetailActionButton: View {
    let title: String
    let systemImage: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.title3)
                Text(title)
                    .font(.caption)
            }
            .foregroundStyle(tint)
        }
    }
}
