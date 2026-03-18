import SwiftUI

struct LeaderboardView: View {
    @State private var viewModel = LeaderboardViewModel()
    @State private var previewImageURL: URL?
    @Environment(\.colorScheme) private var colorScheme

    private let blockedManager = BlockedCategoriesManager.shared

    private var filteredComics: [Comic] {
        blockedManager.filterComics(viewModel.comics)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Time range picker
            Picker("排行榜", selection: Binding(
                get: { viewModel.selectedType },
                set: { type in Task { await viewModel.switchType(type) } }
            )) {
                Text("24小时").tag(LeaderboardType.hour24)
                Text("7天").tag(LeaderboardType.day7)
                Text("30天").tag(LeaderboardType.day30)
            }
            .pickerStyle(.segmented)
            .padding()

            if viewModel.isLoading {
                Spacer()
                ProgressView()
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(Array(filteredComics.enumerated()), id: \.element.id) { index, comic in
                            NavigationLink(value: comic) {
                                HStack(spacing: 0) {
                                    Text("\(index + 1)")
                                        .font(.headline)
                                        .foregroundStyle(index < 3 ? Color.accentPink : Color.secondaryText(for: colorScheme))
                                        .frame(width: 32)

                                    ComicCardView(comic: comic, previewImageURL: $previewImageURL)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
        .background(Color.mainBg(for: colorScheme))
        .navigationTitle("排行榜")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: Comic.self) { comic in
            ComicDetailView(comicId: comic.id)
        }
        .imagePreviewSheet(url: $previewImageURL)
        .task { await viewModel.load() }
    }
}
