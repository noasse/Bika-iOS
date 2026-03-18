import SwiftUI

struct LoginView: View {
    @Environment(AuthViewModel.self) private var authVM
    @Environment(\.colorScheme) private var colorScheme

    @State private var email = ""
    @State private var password = ""

    var body: some View {
        ZStack {
            Color.mainBg(for: colorScheme)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                // Logo area
                VStack(spacing: 12) {
                    Image(systemName: "book.pages")
                        .font(.system(size: 60))
                        .foregroundStyle(Color.accentPink)
                    Text("Bika")
                        .font(.largeTitle.bold())
                        .foregroundStyle(Color.accentPink)
                }

                Spacer()

                // Form
                VStack(spacing: 16) {
                    TextField("邮箱", text: $email)
                        .textContentType(.emailAddress)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .padding()
                        .background(Color.cardBg(for: colorScheme))
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                    SecureField("密码", text: $password)
                        .textContentType(.password)
                        .padding()
                        .background(Color.cardBg(for: colorScheme))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal)

                if let error = authVM.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                }

                // Login button
                Button {
                    Task { await authVM.login(email: email, password: password) }
                } label: {
                    Group {
                        if authVM.isLoading {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("登录")
                                .fontWeight(.semibold)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentPink)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(email.isEmpty || password.isEmpty || authVM.isLoading)
                .padding(.horizontal)

                Spacer()
            }
        }
    }
}
