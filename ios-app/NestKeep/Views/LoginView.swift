import SwiftUI

/// 登录页：服务器地址 + 用户名/密码。完全原生 iOS 风格（NavigationView + Form）
struct LoginView: View {
    @EnvironmentObject var auth: AuthManager
    @EnvironmentObject var settings: AppSettings

    @State private var loginName = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var error: String?

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("服务器")) {
                    TextField("https://...", text: Binding(
                        get: { settings.serverURL.absoluteString },
                        set: { settings.setServerURL($0) }
                    ))
                    .textContentType(.URL)
                    .keyboardType(.URL)
                    .autocapitalization(.none)
                }

                Section(header: Text("登录")) {
                    TextField("用户名或邮箱", text: $loginName)
                        .textContentType(.username)
                        .autocapitalization(.none)
                    SecureField("密码", text: $password)
                        .textContentType(.password)
                }

                if let error = error {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.footnote)
                    }
                }

                Section {
                    Button {
                        doLogin()
                    } label: {
                        HStack {
                            Spacer()
                            if isLoading {
                                ProgressView()
                            } else {
                                Text("登录")
                            }
                            Spacer()
                        }
                    }
                    .disabled(isLoading || loginName.isEmpty || password.isEmpty)
                }
            }
            .navigationTitle("巢记")
        }
    }

    private func doLogin() {
        isLoading = true
        error = nil
        Task {
            do {
                try await auth.login(loginName: loginName, password: password)
                await MainActor.run { isLoading = false }
            } catch {
                await MainActor.run {
                    isLoading = false
                    self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
                }
            }
        }
    }
}
