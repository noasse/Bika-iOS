import SwiftUI

struct MediaImageView: View {
    let media: Media?
    var cornerRadius: CGFloat = 8
    var targetSize: CGSize? = nil
    var imageLoader: any ImageDataLoading = AppDependencies.shared.imageDataLoader
    var imageCache: ImageCache = .shared

    var body: some View {
        CachedAsyncImage(
            url: media?.imageURL,
            targetSize: targetSize,
            imageLoader: imageLoader,
            imageCache: imageCache
        ) {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color.gray.opacity(0.3))
                .overlay {
                    Image(systemName: "photo")
                        .foregroundStyle(.gray)
                }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}
