import SwiftUI

struct ComicCardView: View {
    let comic: Comic
    @Binding var previewImageURL: URL?

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 12) {
            // Cover image — tap for large preview
            MediaImageView(media: comic.thumb, cornerRadius: 6, targetSize: CGSize(width: 80, height: 110))
                .frame(width: 80, height: 110)
                .highPriorityGesture(
                    TapGesture().onEnded {
                        previewImageURL = comic.thumb?.imageURL
                    }
                )

            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(comic.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)

                if let author = comic.author {
                    Text(author)
                        .font(.caption)
                        .foregroundStyle(Color.secondaryText(for: colorScheme))
                }

                Spacer()

                HStack(spacing: 12) {
                    if let views = comic.displayViews {
                        Label("\(views)", systemImage: "eye")
                    }
                    if let likes = comic.displayLikes {
                        Label("\(likes)", systemImage: "heart")
                    }
                    if let pages = comic.pagesCount {
                        Label("\(pages)P", systemImage: "doc")
                    }
                }
                .font(.caption2)
                .foregroundStyle(Color.secondaryText(for: colorScheme))

                if let categories = comic.categories, !categories.isEmpty {
                    Text(categories.prefix(3).joined(separator: " · "))
                        .font(.caption2)
                        .foregroundStyle(Color.accentPink)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background(Color.cardBg(for: colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Fullscreen Image Preview Overlay (zoom animation)

struct ImagePreviewOverlay: ViewModifier {
    @Binding var previewImageURL: URL?

    private var isPresented: Bool { previewImageURL != nil }

    func body(content: Content) -> some View {
        content.overlay {
            if let url = previewImageURL {
                ZStack {
                    // Material background — fades in fast
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .ignoresSafeArea()
                        .transition(.opacity)
                        .onTapGesture { dismiss() }

                    // Image — scales up from center
                    CachedAsyncImage(url: url) {
                        ProgressView()
                    }
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(radius: 20)
                    .padding(30)
                    .transition(.scale(scale: 0.3, anchor: .center))
                    .onTapGesture { dismiss() }
                }
            }
        }
        .animation(.easeOut(duration: 0.2), value: isPresented)
    }

    private func dismiss() {
        previewImageURL = nil
    }
}

extension View {
    func imagePreviewSheet(url: Binding<URL?>) -> some View {
        modifier(ImagePreviewOverlay(previewImageURL: url))
    }
}

struct IdentifiableURL: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}
