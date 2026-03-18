import SwiftUI

struct MediaImageView: View {
    let media: Media?
    var cornerRadius: CGFloat = 8

    var body: some View {
        CachedAsyncImage(url: media?.imageURL) {
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
