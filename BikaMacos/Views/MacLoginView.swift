import SwiftUI

struct MacLoginView: View {
    @Bindable var model: MacLibraryModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var email = ""
    @State private var password = ""
    @FocusState private var focusedField: Field?

    private enum Field {
        case email
        case password
    }

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 16) {
                Image(systemName: "books.vertical")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(MacUI.accentPink)
                    .frame(width: 62, height: 62)
                    .background(MacUI.accentWash(for: colorScheme), in: RoundedRectangle(cornerRadius: MacUI.cornerRadius))

                VStack(spacing: 7) {
                    Text("Bika")
                        .font(.largeTitle.weight(.semibold))
                    Text("登录后开始浏览和阅读")
                        .foregroundStyle(MacUI.secondaryText(for: colorScheme))
                }

                VStack(spacing: 10) {
                    TextField("邮箱", text: $email)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .email)
                        .onSubmit { focusedField = .password }

                    SecureField("密码", text: $password)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .password)
                        .onSubmit { submit() }
                }

                if let authError = model.authError {
                    Text(authError)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }

                Button {
                    submit()
                } label: {
                    if model.isAuthenticating {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 88)
                    } else {
                        Text("登录")
                            .frame(width: 88)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(MacUI.accentPink)
                .disabled(model.isAuthenticating || email.isEmpty || password.isEmpty)
            }
            .padding(26)
            .frame(width: 380)
            .macSurface(colorScheme)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
        .background(MacUI.appBackground(for: colorScheme))
        .onAppear {
            focusedField = .email
        }
    }

    private func submit() {
        guard !email.isEmpty, !password.isEmpty else { return }
        Task {
            await model.login(email: email, password: password)
        }
    }
}
