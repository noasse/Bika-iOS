import SwiftUI

struct CategoriesView: View {
    @State private var viewModel = CategoriesViewModel()
    @Environment(\.colorScheme) private var colorScheme

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)

    var body: some View {
        ScrollView {
            if viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 300)
            } else {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(viewModel.categories) { category in
                        NavigationLink(value: category) {
                            VStack(spacing: 6) {
                                MediaImageView(media: category.thumb, cornerRadius: 12)
                                    .aspectRatio(1, contentMode: .fit)
                                Text(category.title)
                                    .font(.caption)
                                    .lineLimit(1)
                                    .foregroundStyle(.primary)
                            }
                        }
                    }
                }
                .padding()
            }
        }
        .background(Color.mainBg(for: colorScheme))
        .navigationTitle("分类")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: Category.self) { category in
            ComicListView(category: category.title)
        }
        .task { await viewModel.loadCategories() }
    }
}
