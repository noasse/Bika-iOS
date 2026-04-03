import SwiftUI

struct CategoriesView: View {
    @Environment(\.colorScheme) private var colorScheme

    @State private var viewModel: CategoriesViewModel

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)

    init(viewModel: CategoriesViewModel = CategoriesViewModel()) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ScrollView {
            if viewModel.isLoading && viewModel.categories.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 300)
            } else if let errorMessage = viewModel.errorMessage, viewModel.categories.isEmpty {
                VStack(spacing: 12) {
                    Text("分类加载失败")
                        .font(.headline)
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(Color.secondaryText(for: colorScheme))
                        .multilineTextAlignment(.center)
                    Button("重试") {
                        Task { await viewModel.loadCategories(forceReload: true) }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.accentPink)
                }
                .frame(maxWidth: .infinity, minHeight: 300)
                .padding(.horizontal, 24)
            } else if viewModel.categories.isEmpty {
                Text("暂无分类")
                    .foregroundStyle(Color.secondaryText(for: colorScheme))
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
        .refreshable {
            await viewModel.loadCategories(forceReload: true)
        }
        .navigationDestination(for: Category.self) { category in
            ComicListView(category: category.title)
        }
        .task {
            await viewModel.loadCategories()
        }
    }
}
