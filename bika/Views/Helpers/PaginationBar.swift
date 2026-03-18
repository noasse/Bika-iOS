import SwiftUI

// Floating pagination buttons overlay at the bottom of the screen
struct PaginationButtons: View {
    let currentPage: Int
    let totalPages: Int
    let isLoading: Bool
    let onPrev: () -> Void
    let onNext: () -> Void

    var body: some View {
        HStack {
            // Previous — circular button
            Button(action: onPrev) {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(currentPage <= 1 ? .tertiary : .primary)
                    .frame(width: 48, height: 48)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
            }
            .disabled(currentPage <= 1 || isLoading)

            Spacer()

            if isLoading {
                ProgressView()
                    .frame(width: 48, height: 48)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
            }

            Spacer()

            // Next — circular button
            Button(action: onNext) {
                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(currentPage >= totalPages ? .tertiary : .primary)
                    .frame(width: 48, height: 48)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
            }
            .disabled(currentPage >= totalPages || isLoading)
        }
        .padding(.horizontal, 40)
        .padding(.bottom, 16)
    }
}

// Tappable page indicator for toolbar — tap to input page and jump
struct PageJumpToolbarItem: View {
    let currentPage: Int
    let totalPages: Int
    let lastVisitedPage: Int
    let isLoading: Bool
    let onGoToPage: (Int) -> Void
    let onRestoreLast: () -> Void

    @State private var showPageInput = false
    @State private var pageInputText = ""

    var body: some View {
        HStack(spacing: 6) {
            // Restore button
            if lastVisitedPage > 0 && lastVisitedPage != currentPage {
                Button(action: onRestoreLast) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.caption2)
                }
                .disabled(isLoading)
            }

            // Tappable page number
            Button {
                pageInputText = "\(currentPage)"
                showPageInput = true
            } label: {
                Text("\(currentPage)/\(totalPages)")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .alert("跳转到页面", isPresented: $showPageInput) {
            TextField("页码 (1-\(totalPages))", text: $pageInputText)
                .keyboardType(.numberPad)
            Button("跳转") {
                if let page = Int(pageInputText), page >= 1, page <= totalPages {
                    onGoToPage(page)
                }
            }
            Button("取消", role: .cancel) {}
        }
    }
}
