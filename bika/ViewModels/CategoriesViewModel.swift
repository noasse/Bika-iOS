import SwiftUI

@Observable
final class CategoriesViewModel {
    var categories: [Category] = []
    var isLoading = false
    var errorMessage: String?

    private let client = APIClient.shared

    func loadCategories() async {
        guard categories.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let response: APIResponse<CategoriesData> = try await client.send(.categories())
            if let data = response.data {
                categories = data.categories.filter { $0.isWeb != true }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
