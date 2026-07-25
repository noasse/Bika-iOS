import SwiftUI

struct MediaImageView: View {
    let media: Media?
    var cornerRadius: CGFloat = 8
    var targetSize: CGSize? = nil
    var contentMode: ContentMode = .fill
    var imageLoader: any ImageDataLoading = AppDependencies.shared.imageDataLoader
    var imageCache: ImageCache = .shared

    var body: some View {
        CachedAsyncImage(
            url: media?.imageURL,
            targetSize: targetSize,
            contentMode: contentMode,
            imageLoader: imageLoader,
            imageCache: imageCache,
            purpose: .cover
        ) {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color.gray.opacity(0.3))
                .overlay {
                    Image(systemName: "photo")
                        .foregroundStyle(.gray)
                }
        }
        .frame(width: targetSize?.width, height: targetSize?.height)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}
