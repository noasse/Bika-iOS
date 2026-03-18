import SwiftUI

struct NetworkTestView: View {
    @State private var results: [TestResult] = []
    @State private var email = ""
    @State private var password = ""
    @State private var isRunning = false

    var body: some View {
        NavigationStack {
            List {
                Section("Credentials") {
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                    SecureField("Password", text: $password)
                }

                Section {
                    Button("1. Test Signature") {
                        runTest(testSignature)
                    }
                    Button("2. Test Sign In") {
                        runTest(testSignIn)
                    }
                    Button("3. Test Categories") {
                        runTest(testCategories)
                    }
                    Button("4. Test Comics") {
                        runTest(testComics)
                    }
                    Button("Run All Tests") {
                        runAllTests()
                    }
                }
                .disabled(isRunning)

                Section("Results") {
                    if results.isEmpty {
                        Text("No tests run yet").foregroundStyle(.secondary)
                    }
                    ForEach(results) { result in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: result.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundStyle(result.passed ? .green : .red)
                                Text(result.name).bold()
                            }
                            Text(result.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(5)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .navigationTitle("Network Tests")
        }
    }

    // MARK: - Test Runner

    private func runTest(_ test: @escaping () async -> TestResult) {
        Task {
            isRunning = true
            let result = await test()
            results.append(result)
            isRunning = false
        }
    }

    private func runAllTests() {
        Task {
            isRunning = true
            results.removeAll()

            results.append(await testSignature())
            results.append(await testSignIn())

            // Only run authenticated tests if sign-in succeeded
            if results.last?.passed == true {
                results.append(await testCategories())
                results.append(await testComics())
            }

            isRunning = false
        }
    }

    // MARK: - Individual Tests

    private func testSignature() async -> TestResult {
        let sig = APISignature.sign(
            path: "auth/sign-in",
            method: "POST",
            timestamp: "1234567890",
            nonce: APIConfig.nonce
        )
        let passed = sig.count == 64 && sig.allSatisfy({ $0.isHexDigit })
        return TestResult(
            name: "Signature",
            passed: passed,
            detail: passed ? "Generated valid 64-char hex: \(sig.prefix(16))..." : "Invalid signature: \(sig)"
        )
    }

    private func testSignIn() async -> TestResult {
        guard !email.isEmpty, !password.isEmpty else {
            return TestResult(name: "Sign In", passed: false, detail: "Enter email and password first")
        }
        do {
            let token = try await APIClient.shared.signIn(email: email, password: password)
            let preview = String(token.prefix(20))
            return TestResult(name: "Sign In", passed: true, detail: "Token: \(preview)...")
        } catch {
            return TestResult(name: "Sign In", passed: false, detail: error.localizedDescription)
        }
    }

    private func testCategories() async -> TestResult {
        do {
            let response: APIResponse<CategoriesData> = try await APIClient.shared.send(.categories())
            let count = response.data?.categories.count ?? 0
            return TestResult(
                name: "Categories",
                passed: count > 0,
                detail: "Fetched \(count) categories"
            )
        } catch {
            return TestResult(name: "Categories", passed: false, detail: error.localizedDescription)
        }
    }

    private func testComics() async -> TestResult {
        do {
            // Use a common category
            let response: APIResponse<ComicsData> = try await APIClient.shared.send(
                .comics(category: "嗶咔漢化", page: 1, sort: .newest)
            )
            let total = response.data?.comics.total ?? 0
            let count = response.data?.comics.docs.count ?? 0
            return TestResult(
                name: "Comics",
                passed: count > 0,
                detail: "Page has \(count) comics, total: \(total)"
            )
        } catch {
            return TestResult(name: "Comics", passed: false, detail: error.localizedDescription)
        }
    }
}

// MARK: - Test Result Model

private struct TestResult: Identifiable {
    let id = UUID()
    let name: String
    let passed: Bool
    let detail: String
}

#Preview {
    NetworkTestView()
}
