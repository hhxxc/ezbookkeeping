import SwiftUI

/// 登录页：服务器地址 + 用户名/密码 + 两步验证 + 忘记密码。
/// 完全原生 iOS 风格（NavigationView + Form）。
struct LoginView: View {
    @EnvironmentObject var auth: AuthManager
    @EnvironmentObject var settings: AppSettings

    @State private var loginName = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var error: String?

    // 两步验证
    @State private var show2FASheet = false
    @State private var tempToken = ""
    @State private var twoFAVerifyType: TwoFAVerifyType = .passcode
    @State private var passcode = ""
    @State private var backupCode = ""
    @State private var verifying = false

    // 忘记密码
    @State private var showForgetSheet = false
    @State private var forgetEmail = ""
    @State private var requestingReset = false
    @State private var forgetMessage: String?

    enum TwoFAVerifyType {
        case passcode
        case backupCode
    }

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

                    Button("忘记密码？") {
                        forgetEmail = ""
                        forgetMessage = nil
                        showForgetSheet = true
                    }
                    .font(.footnote)
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("巢记")
        }
        .sheet(isPresented: $show2FASheet) {
            NavigationView {
                Form {
                    Section(footer: Text("该账号开启了两步验证，请输入认证器 App 的 6 位动态码，或切换到备份码。")) {
                        if twoFAVerifyType == .passcode {
                            TextField("6 位动态码", text: $passcode)
                                .keyboardType(.numberPad)
                                .textContentType(.oneTimeCode)
                        } else {
                            TextField("备份码", text: $backupCode)
                                .autocapitalization(.allCharacters)
                                .disableAutocorrection(true)
                        }
                    }

                    if let error = error {
                        Section { Text(error).foregroundColor(.red).font(.footnote) }
                    }

                    Section {
                        Button {
                            doVerify2FA()
                        } label: {
                            HStack {
                                Spacer()
                                if verifying { ProgressView() } else { Text("验证") }
                                Spacer()
                            }
                        }
                        .disabled(verifying || twoFAInputIsEmpty)

                        Button(twoFAVerifyType == .passcode ? "使用备份码" : "使用动态码") {
                            twoFAVerifyType = twoFAVerifyType == .passcode ? .backupCode : .passcode
                            error = nil
                        }
                        .font(.footnote)
                        .frame(maxWidth: .infinity)
                    }
                }
                .navigationTitle("两步验证")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("取消") { show2FASheet = false }.disabled(verifying)
                    }
                }
            }
        }
        .sheet(isPresented: $showForgetSheet) {
            NavigationView {
                Form {
                    Section(footer: Text("请输入注册时使用的邮箱，我们会发送一封含重置密码链接的邮件。")) {
                        TextField("邮箱地址", text: $forgetEmail)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .autocapitalization(.none)
                    }

                    if let message = forgetMessage {
                        Section { Text(message).font(.footnote).foregroundColor(Theme.income) }
                    }

                    Section {
                        Button {
                            doRequestReset()
                        } label: {
                            HStack {
                                Spacer()
                                if requestingReset { ProgressView() } else { Text("发送重置链接") }
                                Spacer()
                            }
                        }
                        .disabled(requestingReset || forgetEmail.isEmpty)
                    }
                }
                .navigationTitle("忘记密码")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("取消") { showForgetSheet = false }.disabled(requestingReset)
                    }
                }
            }
        }
    }

    private var twoFAInputIsEmpty: Bool {
        twoFAVerifyType == .passcode ? passcode.isEmpty : backupCode.isEmpty
    }

    private func doLogin() {
        isLoading = true
        error = nil
        Task {
            do {
                let result = try await auth.login(loginName: loginName, password: password)
                await MainActor.run {
                    isLoading = false
                    switch result {
                    case .success:
                        break
                    case .need2FA(let token):
                        tempToken = token
                        passcode = ""
                        backupCode = ""
                        twoFAVerifyType = .passcode
                        show2FASheet = true
                    }
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
                }
            }
        }
    }

    private func doVerify2FA() {
        verifying = true
        error = nil
        let code = twoFAVerifyType == .passcode ? passcode : backupCode
        Task {
            do {
                try await auth.verify2FA(
                    tempToken: tempToken,
                    passcode: twoFAVerifyType == .passcode ? code : nil,
                    recoveryCode: twoFAVerifyType == .backupCode ? code : nil
                )
                await MainActor.run {
                    verifying = false
                    show2FASheet = false
                }
            } catch {
                await MainActor.run {
                    verifying = false
                    self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
                }
            }
        }
    }

    private func doRequestReset() {
        requestingReset = true
        forgetMessage = nil
        Task {
            do {
                let _: EmptyResult = try await APIClient.shared.request(
                    "/api/forget_password/request.json",
                    method: .POST,
                    body: ForgetPasswordRequest(email: forgetEmail)
                )
                await MainActor.run {
                    requestingReset = false
                    forgetMessage = "重置密码邮件已发送，请查收。"
                }
            } catch {
                await MainActor.run {
                    requestingReset = false
                    forgetMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
                }
            }
        }
    }
}

/// 忘记密码请求体（对应 Go ForgetPasswordRequest）
struct ForgetPasswordRequest: Codable {
    let email: String
}
