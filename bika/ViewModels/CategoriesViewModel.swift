import SwiftUI

@Observable
final class CategoriesViewModel {
    var categories: [Category] = []
    var isLoading = false
    var errorMessage: String?

    private let client: any APIClientProtocol

    init(client: any APIClientProtocol = APIClient.shared) {
        self.client = client
    }

    func loadCategories(forceReload: Bool = false) async {
        guard forceReload || categories.isEmpty else { return }
        isLoading = true
        errorMessage = nil
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
