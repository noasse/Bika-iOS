import SwiftUI

struct MacComicDetailPane: View {
    @Bindable var model: MacLibraryModel
    let commentsWindowStore: MacCommentsWindowStore
    @Environment(\.openWindow) private var openWindow
    @Environment(\.colorScheme) private var colorScheme

    private let episodeColumns = [
        GridItem(.adaptive(minimum: 96), spacing: 8)
    ]

    var body: some View {
        Group {
            if model.isDetailLoading {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("正在载入详情")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let detail = model.detail {
                detailContent(detail)
            } else if let error = model.detailError {
                ContentUnavailableView("详情载入失败", systemImage: "exclamationmark.triangle", description: Text(error))
            } else {
                ContentUnavailableView("选择一本漫画", systemImage: "book")
            }
        }
        .background(MacUI.appBackground(for: colorScheme))
    }

    private func detailContent(_ detail: ComicDetail) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                heroCard(detail)

                routeSections(detail)

                if let description = detail.description, !description.isEmpty {
                    section("简介") {
                        Text(description)
                            .font(.callout)
                            .foregroundStyle(MacUI.secondaryText(for: colorScheme))
                            .textSelection(.enabled)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                episodesSection
                commentEntrySection
                recommendedSection
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private func heroCard(_ detail: ComicDetail) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 18) {
                cover(detail, width: 230, height: 326)
                heroInformation(detail)
                    .frame(width: 242, alignment: .topLeading)
            }

            VStack(alignment: .leading, spacing: 16) {
                cover(detail, width: 260, height: 368)
                    .frame(maxWidth: .infinity, alignment: .leading)
                heroInformation(detail)
            }
        }
        .padding(14)
        .macSurface(colorScheme)
    }

    private func cover(_ detail: ComicDetail, width: CGFloat, height: CGFloat) -> some View {
        MacCachedAsyncImage(url: detail.thumb?.imageURL, contentMode: .fill) {
            ZStack {
                MacUI.subtleSurface(for: colorScheme)
                Image(systemName: "photo")
                    .font(.largeTitle)
                    .foregroundStyle(MacUI.secondaryText(for: colorScheme))
            }
        }
        .frame(width: width, height: height)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: MacUI.cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: MacUI.cornerRadius)
                .stroke(MacUI.hairline(for: colorScheme))
        }
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.28 : 0.12), radius: 12, y: 6)
    }

    private func heroInformation(_ detail: ComicDetail) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            titleBlock(detail)
            metricsStrip(detail)
            primaryActions(detail)
            continueReadingSection(detail, progressRevision: model.readingProgressRevision)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func titleBlock(_ detail: ComicDetail) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(detail.title)
                .font(.title2.weight(.semibold))
                .lineLimit(4)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                if let author = detail.author, !author.isEmpty {
                    Button {
                        Task { await model.selectRoute(.author(author)) }
                    } label: {
                        Label(author, systemImage: "person.text.rectangle")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(MacUI.accentPink)
                    .help("查看作者作品")
                } else {
                    Label("未知作者", systemImage: "person")
                        .foregroundStyle(.secondary)
                }

                Text(detail.finished == true ? "已完结" : "连载中")
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(MacUI.accentWash(for: colorScheme), in: Capsule())
                    .foregroundStyle(MacUI.accentPink)
            }
            .font(.subheadline)
        }
    }

    private func metricsStrip(_ detail: ComicDetail) -> some View {
        let items = metricItems(detail)

        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    metric(item.title, item.value)
                    if index < items.count - 1 {
                        metricDivider
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(MacUI.subtleSurface(for: colorScheme), in: RoundedRectangle(cornerRadius: MacUI.cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: MacUI.cornerRadius)
                    .stroke(MacUI.hairline(for: colorScheme))
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    metricCell(item.title, item.value)
                }
            }
        }
    }

    private func metricItems(_ detail: ComicDetail) -> [(title: String, value: Int?)] {
        [
            ("浏览", detail.totalViews ?? detail.viewsCount),
            ("喜欢", detail.totalLikes ?? detail.likesCount),
            ("评论", model.commentEntryCount ?? detail.totalComments ?? detail.commentsCount),
            ("章节", detail.epsCount),
            ("页数", detail.pagesCount)
        ]
    }

    private func metric(_ title: String, _ value: Int?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value.map { compactCount($0) } ?? "-")
                .font(.callout.weight(.semibold))
                .monospacedDigit()
            Text(title)
                .font(.caption2)
                .foregroundStyle(MacUI.secondaryText(for: colorScheme))
        }
        .frame(minWidth: 52, maxWidth: .infinity, alignment: .leading)
    }

    private func metricCell(_ title: String, _ value: Int?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value.map { compactCount($0) } ?? "-")
                .font(.callout.weight(.semibold))
                .monospacedDigit()
            Text(title)
                .font(.caption2)
                .foregroundStyle(MacUI.secondaryText(for: colorScheme))
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MacUI.subtleSurface(for: colorScheme), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(MacUI.hairline(for: colorScheme))
        }
    }

    private var metricDivider: some View {
        Rectangle()
            .fill(MacUI.hairline(for: colorScheme))
            .frame(width: 1, height: 28)
            .padding(.horizontal, 9)
    }

    private func primaryActions(_ detail: ComicDetail) -> some View {
        HStack(spacing: 8) {
            iconAction(
                title: detail.isLiked == true ? "已喜欢" : "喜欢",
                systemImage: detail.isLiked == true ? "heart.fill" : "heart",
                isActive: detail.isLiked == true,
                isDisabled: model.isTogglingLike
            ) {
                Task { await model.toggleLike() }
            }

            iconAction(
                title: detail.isFavourite == true ? "已收藏" : "收藏",
                systemImage: detail.isFavourite == true ? "star.fill" : "star",
                isActive: detail.isFavourite == true,
                isDisabled: model.isTogglingFavourite
            ) {
                Task { await model.toggleFavourite() }
            }
        }
    }

    private func iconAction(
        title: String,
        systemImage: String,
        isActive: Bool,
        isDisabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.titleAndIcon)
        }
        .buttonStyle(.bordered)
        .foregroundStyle(isActive ? MacUI.accentPink : .secondary)
        .disabled(isDisabled)
        .help(title)
    }

    @ViewBuilder
    private func routeSections(_ detail: ComicDetail) -> some View {
        if let categories = detail.categories, !categories.isEmpty {
            pillScroller(categories, isAccent: true) { category in
                routeChip(title: category, isAccent: true, isBlocked: model.isBlocked(category)) {
                    Task { await model.selectRoute(.category(category)) }
                }
                .contextMenu {
                    Button {
                        model.toggleBlockedCategory(category)
                    } label: {
                        Label(
                            model.isBlocked(category) ? "取消屏蔽" : "屏蔽分类",
                            systemImage: model.isBlocked(category) ? "eye" : "eye.slash"
                        )
                    }
                }
            }
        }

        if let tags = detail.tags, !tags.isEmpty {
            pillScroller(tags, isAccent: false) { tag in
                routeChip(title: tag, isAccent: false, isBlocked: false) {
                    Task { await model.selectRoute(.tag(tag)) }
                }
            }
        }
    }

    private func pillScroller<Data: RandomAccessCollection, Content: View>(
        _ items: Data,
        isAccent: Bool,
        @ViewBuilder content: @escaping (Data.Element) -> Content
    ) -> some View where Data.Element: Hashable {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(Array(items), id: \.self) { item in
                    content(item)
                }
            }
            .padding(.vertical, 1)
        }
        .scrollIndicators(.hidden)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(MacUI.accentPink)
                    .frame(width: 3, height: 14)
                Text(title)
                    .font(.headline)
            }

            content()
        }
    }

    private var episodesSection: some View {
        section("章节") {
            if model.episodes.isEmpty {
                ContentUnavailableView("暂无章节", systemImage: "list.bullet")
                    .frame(minHeight: 120)
            } else {
                LazyVGrid(columns: episodeColumns, alignment: .leading, spacing: 8) {
                    ForEach(model.episodes) { episode in
                        Button {
                            if let request = model.makeEpisodeReaderRequest(episode: episode) {
                                openWindow(value: request)
                            }
                        } label: {
                            episodeRow(episode)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func episodeRow(_ episode: Episode) -> some View {
        Text(episode.title)
            .font(.caption)
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .padding(.horizontal, 8)
            .background(MacUI.surface(for: colorScheme), in: RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(MacUI.hairline(for: colorScheme))
            }
    }

    @ViewBuilder
    private func continueReadingSection(_ detail: ComicDetail, progressRevision: Int) -> some View {
        if let progress = model.readingProgress(for: detail) {
            Button {
                if let request = model.makeContinueReaderRequest() {
                    openWindow(value: request)
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "book.fill")
                    Text("继续阅读 \(progress.episodeTitle)")
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.right")
                }
                .font(.subheadline)
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(MacUI.accentPink, in: RoundedRectangle(cornerRadius: MacUI.cornerRadius))
            }
            .buttonStyle(.plain)
            .id(progressRevision)
        }
    }

    private var commentEntrySection: some View {
        Button {
            guard let detail = model.detail else { return }
            commentsWindowStore.open(comicId: detail.id, comicTitle: detail.title)
            openWindow(id: "comments")
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "bubble.left.and.bubble.right")
                Text(commentCountText)
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)
            .foregroundStyle(.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(MacUI.surface(for: colorScheme), in: RoundedRectangle(cornerRadius: MacUI.cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: MacUI.cornerRadius)
                    .stroke(MacUI.hairline(for: colorScheme))
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var recommendedSection: some View {
        if model.isLoadingRecommended || !model.displayedRecommended.isEmpty || model.recommendedError != nil {
            section("推荐") {
                if let error = model.recommendedError, model.displayedRecommended.isEmpty {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView(.horizontal) {
                        LazyHStack(spacing: 10) {
                            ForEach(model.displayedRecommended) { comic in
                                Button {
                                    Task { await model.selectComic(MacComicSummary(comic: comic)) }
                                } label: {
                                    recommendedCard(comic)
                                }
                                .buttonStyle(.plain)
                            }

                            if model.isLoadingRecommended {
                                ProgressView()
                                    .frame(width: 108, height: 160)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .scrollIndicators(.hidden)
                }
            }
        }
    }

    private func recommendedCard(_ comic: Comic) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            MacCachedAsyncImage(url: comic.thumb?.imageURL, contentMode: .fill)
                .frame(width: 102, height: 136)
                .clipShape(RoundedRectangle(cornerRadius: 7))

            Text(comic.title)
                .font(.caption.weight(.medium))
                .lineLimit(2)
                .frame(width: 102, alignment: .leading)

            Text(comic.author ?? "未知作者")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 102, alignment: .leading)
        }
        .padding(8)
        .macSurface(colorScheme)
    }

    private func routeChip(
        title: String,
        isAccent: Bool,
        isBlocked: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    chipBackground(isAccent: isAccent, isBlocked: isBlocked),
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
        .foregroundStyle(chipForeground(isAccent: isAccent, isBlocked: isBlocked))
    }

    private func chipBackground(isAccent: Bool, isBlocked: Bool) -> Color {
        if isBlocked {
            return MacUI.subtleSurface(for: colorScheme)
        }
        return isAccent ? MacUI.accentWash(for: colorScheme) : Color.gray.opacity(0.15)
    }

    private func chipForeground(isAccent: Bool, isBlocked: Bool) -> Color {
        if isBlocked {
            return MacUI.secondaryText(for: colorScheme)
        }
        return isAccent ? MacUI.accentPink : MacUI.secondaryText(for: colorScheme)
    }

    private func compactCount(_ value: Int) -> String {
        if value >= 10_000 {
            return String(format: "%.1f万", Double(value) / 10_000)
        }
        return "\(value)"
    }

    private var commentCountText: String {
        guard let commentEntryCount = model.commentEntryCount else { return "查看评论" }
        return "查看评论 (\(compactCount(commentEntryCount))条)"
    }
}
