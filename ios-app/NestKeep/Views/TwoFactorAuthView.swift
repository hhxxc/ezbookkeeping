import SwiftUI
import Combine

/// 两步验证（2FA）：对齐 Web `users/TwoFactorAuthPage.vue`。
/// 流程：
///  - 状态查询 `GET /api/v1/users/2fa/status.json` → `{enable}`
///  - 启用：`POST /users/2fa/enable/request.json` → `{secret, qrcode(base64图片)}`
///          → 扫码后 `POST /users/2fa/enable/confirm.json` body `{secret, passcode}` → `{token?, recoveryCodes}`
///  - 关闭：`POST /users/2fa/disable.json` body `{password}`
///  - 重生成备份码：`POST /users/2fa/recovery/regenerate.json` body `{password}` → `{recoveryCodes}`
struct TwoFactorAuthView: View {
    @StateObject private var vm = TwoFactorViewModel()

    @State private var showEnableSheet = false
    @State private var passcode = ""
    @State private var showDisableSheet = false
    @State private var showRegenerateSheet = false
    @State private var password = ""
    @State private var showBackupCodes = false
    @State private var backupText = ""
    @State private var copied = false

    var body: some View {
        List {
            Section {
                HStack {
                    Text("状态")
                    Spacer()
                    Text(vm.enabled == nil ? "未知" : (vm.enabled! ? "已启用" : "未启用"))
                        .foregroundColor(.secondary)
                }
            }

            if vm.enabled == true {
                Section {
                    Button("重新生成备份码") {
                        password = ""
                        showRegenerateSheet = true
                    }
                    .disabled(vm.busy)
                    Button("关闭两步验证", role: .destructive) {
                        password = ""
                        showDisableSheet = true
                    }
                    .disabled(vm.busy)
                }
            } else if vm.enabled == false {
                Section {
                    Button("启用两步验证") {
                        Task {
                            if await vm.requestEnable() {
                                passcode = ""
                                showEnableSheet = true
                            }
                        }
                    }
                    .disabled(vm.busy)
                }
            }

            if let error = vm.error {
                Section { Text(error).foregroundColor(.red).font(.footnote) }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("两步验证")
        .navigationBarTitleDisplayMode(.inline)
        .task { await vm.load() }
        // 启用确认：展示二维码 + 输入 6 位动态码
        .sheet(isPresented: $showEnableSheet) {
            NavigationView {
                Form {
                    Section {
                        if let img = vm.qrImage {
                            Image(uiImage: img)
                                .resizable()
                                .interpolation(.none)
                                .frame(width: 220, height: 220)
                                .frame(maxWidth: .infinity)
                        }
                        if !vm.secret.isEmpty {
                            Text("密钥：\(vm.secret)")
                                .font(.footnote).foregroundColor(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                    Section(header: Text("请输入认证器 App 当前的 6 位动态码")) {
                        TextField("6 位动态码", text: $passcode)
                            .keyboardType(.numberPad)
                    }
                }
                .navigationTitle("启用两步验证")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("取消") { showEnableSheet = false }.disabled(vm.busy)
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            Task {
                                if await vm.confirmEnable(passcode: passcode) {
                                    showEnableSheet = false
                                    if !vm.recoveryCodes.isEmpty {
                                        backupText = vm.recoveryCodes.joined(separator: "\n")
                                        copied = false
                                        showBackupCodes = true
                                    }
                                }
                            }
                        } label: {
                            if vm.busy { ProgressView() } else { Text("确认").bold() }
                        }
                        .disabled(vm.busy || passcode.count != 6)
                    }
                }
            }
        }
        // 关闭 / 重生成：输入密码
        .sheet(isPresented: $showDisableSheet) {
            PasswordPromptSheet(title: "关闭两步验证",
                                hint: "需要输入当前密码以关闭两步验证。",
                                password: $password,
                                busy: vm.busy) {
                let pwd = password
                Task {
                    if await vm.disable(password: pwd) { showDisableSheet = false }
                }
            }
        }
        .sheet(isPresented: $showRegenerateSheet) {
            PasswordPromptSheet(title: "重新生成备份码",
                                hint: "需要输入当前密码。重新生成后旧备份码将立即失效。",
                                password: $password,
                                busy: vm.busy) {
                let pwd = password
                Task {
                    if await vm.regenerate(password: pwd) {
                        showRegenerateSheet = false
                        backupText = vm.recoveryCodes.joined(separator: "\n")
                        copied = false
                        showBackupCodes = true
                    }
                }
            }
        }
        // 备份码展示（仅展示一次）
        .sheet(isPresented: $showBackupCodes) {
            NavigationView {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("请把下面的备份码妥善保存，它们只会展示这一次。如果丢失，可随时重新生成。")
                            .font(.footnote).foregroundColor(.secondary)
                        Text(backupText)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                        Button {
                            UIPasteboard.general.string = backupText
                            copied = true
                        } label: {
                            Label(copied ? "已复制" : "复制全部", systemImage: copied ? "checkmark.circle.fill" : "doc.on.doc")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                }
                .navigationTitle("备份码")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("完成") { showBackupCodes = false }
                    }
                }
            }
        }
    }
}

@MainActor
final class TwoFactorViewModel: ObservableObject {
    @Published var enabled: Bool?
    @Published var secret = ""
    @Published var qrImage: UIImage?
    @Published var recoveryCodes: [String] = []
    @Published var busy = false
    @Published var error: String?

    func load() async {
        error = nil
        do {
            let resp: TwoFactorStatus = try await APIClient.shared.request("/api/v1/users/2fa/status.json")
            enabled = resp.enable
        } catch {
            // 后端未注册该路由（ApiNotFound）时视为未启用
            enabled = nil
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// 请求启用，拿到二维码与密钥
    func requestEnable() async -> Bool {
        busy = true
        error = nil
        do {
            let resp: TwoFactorEnableResponse = try await APIClient.shared.request(
                "/api/v1/users/2fa/enable/request.json", method: .POST
            )
            secret = resp.secret
            qrImage = Self.decodeQRCode(resp.qrcode)
            busy = false
            return true
        } catch {
            busy = false
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    func confirmEnable(passcode: String) async -> Bool {
        busy = true
        error = nil
        do {
            let resp: TwoFactorEnableConfirmResponse = try await APIClient.shared.request(
                "/api/v1/users/2fa/enable/confirm.json", method: .POST,
                body: TwoFactorEnableConfirmRequest(secret: secret, passcode: passcode)
            )
            recoveryCodes = resp.recoveryCodes ?? []
            enabled = true
            busy = false
            return true
        } catch {
            busy = false
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    func disable(password: String) async -> Bool {
        busy = true
        error = nil
        do {
            let _: EmptyResult = try await APIClient.shared.request(
                "/api/v1/users/2fa/disable.json", method: .POST,
                body: TwoFactorPasswordRequest(password: password)
            )
            enabled = false
            busy = false
            return true
        } catch {
            busy = false
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    func regenerate(password: String) async -> Bool {
        busy = true
        error = nil
        do {
            let resp: TwoFactorRecoveryResponse = try await APIClient.shared.request(
                "/api/v1/users/2fa/recovery/regenerate.json", method: .POST,
                body: TwoFactorPasswordRequest(password: password)
            )
            recoveryCodes = resp.recoveryCodes ?? []
            busy = false
            return true
        } catch {
            busy = false
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    /// 后端 qrcode 是 data URI（base64）或纯 base64，解码成 UIImage
    private static func decodeQRCode(_ raw: String) -> UIImage? {
        var s = raw
        if let range = s.range(of: "base64,") {
            s = String(s[range.upperBound...])
        }
        guard let data = Data(base64Encoded: s) else { return nil }
        return UIImage(data: data)
    }
}

// MARK: - 请求 / 响应模型

struct TwoFactorStatus: Codable { let enable: Bool }
struct TwoFactorEnableResponse: Codable { let secret: String; let qrcode: String }
struct TwoFactorEnableConfirmRequest: Codable { let secret: String; let passcode: String }
struct TwoFactorEnableConfirmResponse: Codable { let token: String?; let recoveryCodes: [String]? }
struct TwoFactorPasswordRequest: Codable { let password: String }
struct TwoFactorRecoveryResponse: Codable { let recoveryCodes: [String]? }

/// 密码输入弹层
struct PasswordPromptSheet: View {
    let title: String
    let hint: String
    @Binding var password: String
    let busy: Bool
    let onConfirm: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section {
                    SecureField("当前密码", text: $password)
                } footer: {
                    Text(hint)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { dismiss() }.disabled(busy)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        onConfirm()
                    } label: {
                        if busy { ProgressView() } else { Text("确认").bold() }
                    }
                    .disabled(busy || password.isEmpty)
                }
            }
        }
    }
}
