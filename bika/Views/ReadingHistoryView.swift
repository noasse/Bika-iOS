import SwiftUI

struct ReadingHistoryView: View {
    private let historyManager = ReadingHistoryManager.shared
    @State private var previewImageURL: URL?
    @State private var showClearAlert = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView {
            if historyManager.items.isEmpty {
                Text("暂无阅读记录")
                    .foregroundStyle(Color.secondaryText(for: colorScheme))
                    .frame(maxWidth: .infinity, minHeight: 300)
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(historyManager.items) { item in
                        NavigationLink {
                            ComicDetailView(comicId: item.comicId)
                        } label: {
                            historyCard(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
        .background(Color.mainBg(for: colorScheme))
        .navigationTitle("阅读记录")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !historyManager.items.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("清空", role: .destructive) {
                        showClearAlert = true
                    }
                    .foregroundStyle(.red)
                }
            }
        }
        .alert("确认清空", isPresented: $showClearAlert) {
            Button("清空", role: .destructive) {
                historyManager.clearAll()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("确定要清空所有阅读记录吗？")
        }
        .imagePreviewSheet(url: $previewImageURL)
    }

    private func historyCard(item: ReadingHistoryManager.HistoryItem) -> some View {
        HStack(spacing: 12) {
            let media = Media(originalName: nil, path: item.thumbPath, fileServer: item.thumbServer)
            MediaImageView(media: media, cornerRadius: 6)
                .frame(width: 60, height: 84)
                .highPriorityGesture(
                    TapGesture().onEnded {
                        previewImageURL = media.imageURL
                    }
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)

                if let author = item.author {
                    Text(author)
                        .font(.caption)
                        .foregroundStyle(Color.secondaryText(for: colorScheme))
                }

                Spacer()

                Text(formatDate(item.lastReadDate))
                    .font(.caption2)
                    .foregroundStyle(Color.secondaryText(for: colorScheme))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background(Color.cardBg(for: colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func formatDate(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "刚刚" }
        if interval < 3600 { return "\(Int(interval / 60))分钟前" }
        if interval < 86400 { return "\(Int(interval / 3600))小时前" }
        if interval < 172800 { return "昨天" }
        let df = DateFormatter()
        df.dateFormat = "MM-dd HH:mm"
        return df.string(from: date)
    }
}
