import SwiftUI

/// 登录页：服务器地址 + 用户名/密码 + 两步验证 + 忘记密码。
/// 自定义卡片式设计（渐变 Logo 头部 + 圆角输入卡 + 品牌渐变登录按钮）。
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

    // 服务器地址输入（本地缓冲，失焦/提交时归一化保存）
    @State private var serverText = ""

    enum TwoFAVerifyType {
        case passcode
        case backupCode
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 0) {
                    header
                    loginCard
                    if let error = error {
                        errorBanner(error)
                    }
                    loginButton
                    forgetPasswordButton
                }
                .padding(.horizontal, 24)
            }
            .background(Theme.pageBackground.ignoresSafeArea())
            .navigationBarHidden(true)
            .onAppear {
                if serverText.isEmpty {
                    serverText = settings.serverURL.absoluteString
                }
            }
        }
        .navigationViewStyle(.stack)
        .sheet(isPresented: $show2FASheet) { twoFASheetContent }
        .sheet(isPresented: $showForgetSheet) { forgetSheetContent }
    }

    // MARK: - 子视图

    /// 顶部品牌区：渐变圆形 Logo + 应用名 + 副标题
    private var header: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Theme.aiGradient)
                    .frame(width: 84, height: 84)
                    .shadow(color: Theme.brand.opacity(0.3), radius: 12, y: 6)
                Image(systemName: "bird.fill")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundColor(.white)
            }
            .padding(.top, 24)

            Text("巢记")
                .font(.system(size: 30, weight: .bold))
                .foregroundColor(HomePalette.ink)

            Text("轻量记账，安全同步")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.bottom, 36)
    }

    /// 卡片式输入区：服务器地址 / 用户名 / 密码
    private var loginCard: some View {
        VStack(spacing: 0) {
            fieldRow(icon: "globe", placeholder: "服务器地址 https://…", text: $serverText, isFirst: true, isLast: false)
                .keyboardType(.URL)
                .textContentType(.URL)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .onSubmit { commitServerURL() }

            divider

            fieldRow(icon: "person", placeholder: "用户名或邮箱", text: $loginName, isFirst: false, isLast: false)
                .textContentType(.username)
                .autocapitalization(.none)

            divider

            fieldRow(icon: "lock", placeholder: "密码", text: $password, isFirst: false, isLast: true, isSecure: true)
                .textContentType(.password)
                .submitLabel(.go)
                .onSubmit { doLogin() }
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(HomePalette.card)
                .shadow(color: Color.black.opacity(0.06), radius: 10, y: 4)
        )
    }

    private var divider: some View {
        Rectangle()
            .fill(HomePalette.divider.opacity(0.5))
            .frame(height: 0.5)
            .padding(.leading, 48)
    }

    private func fieldRow(icon: String, placeholder: String, text: Binding<String>, isFirst: Bool, isLast: Bool, isSecure: Bool = false) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(Theme.brand)
                .frame(width: 22)

            Group {
                if isSecure {
                    SecureField(placeholder, text: text)
                } else {
                    TextField(placeholder, text: text)
                }
            }
            .font(.body)
            .foregroundColor(HomePalette.ink)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, (isFirst || isLast) ? 14 : 12)
        .frame(minHeight: 48)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(message)
                .font(.footnote)
                .multilineTextAlignment(.leading)
        }
        .foregroundColor(Theme.income)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Theme.income.opacity(0.1))
        )
        .padding(.top, 14)
    }

    private var loginButton: some View {
        Button {
            commitServerURL()
            doLogin()
        } label: {
            HStack {
                Spacer()
                if isLoading {
                    ProgressView().tint(.white)
                } else {
                    Text("登录")
                        .font(.system(size: 17, weight: .semibold))
                }
                Spacer()
            }
            .frame(height: 50)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(canLogin ? AnyShapeStyle(Theme.aiGradient) : AnyShapeStyle(Color(.systemFill)))
            )
            .foregroundColor(canLogin ? .white : .secondary)
        }
        .disabled(!canLogin || isLoading)
        .padding(.top, 24)
    }

    private var canLogin: Bool {
        !loginName.isEmpty && !password.isEmpty
    }

    private var forgetPasswordButton: some View {
        Button("忘记密码？") {
            forgetEmail = ""
            forgetMessage = nil
            showForgetSheet = true
        }
        .font(.footnote)
        .foregroundColor(Theme.brand)
        .padding(.top, 16)
        .padding(.bottom, 24)
    }

    /// 服务器地址归一化后保存（修重复 scheme / 补 https://）
    private func commitServerURL() {
        if let url = AppSettings.normalizeServerURL(serverText) {
            settings.setServerURL(url.absoluteString)
            serverText = url.absoluteString
        }
    }

    private var twoFASheetContent: some View {
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

    private var forgetSheetContent: some View {
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
