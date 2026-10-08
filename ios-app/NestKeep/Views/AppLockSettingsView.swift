import SwiftUI

/// 应用锁设置页：开启/关闭应用锁、修改 PIN、生物识别开关。
/// 与手机端 Web 的「应用锁」设置项对齐（Web 为 `applicationLock` / `applicationLockWebAuthn`）。
struct AppLockSettingsView: View {
    @ObservedObject private var lock = AppLockManager.shared
    @Environment(\.mainTabBarInset) private var tabBarInset
    @Environment(\.dismiss) private var dismiss

    /// 开启流程：设置 PIN → 再输入一次确认
    @State private var settingPin = ""
    @State private var confirmPin = ""
    @State private var showPinSheet = false
    @State private var pinSheetMode: PinSheetMode = .enable
    @State private var errorText: String?
    @State private var showDisableConfirm = false

    private enum PinSheetMode { case enable, change }

    var body: some View {
        List {
            Section {
                Toggle("应用锁", isOn: Binding(
                    get: { lock.isEnabled },
                    set: { on in
                        if on {
                            pinSheetMode = .enable
                            settingPin = ""; confirmPin = ""; errorText = nil
                            showPinSheet = true
                        } else {
                            showDisableConfirm = true
                        }
                    }
                ))
            } footer: {
                Text("开启后，每次启动或从后台返回都需要输入 6 位 PIN 解锁。PIN 仅保存在本机，不上传服务器。")
            }

            if lock.isEnabled {
                Section {
                    Button("修改 PIN") {
                        pinSheetMode = .change
                        settingPin = ""; confirmPin = ""; errorText = nil
                        showPinSheet = true
                    }
                } header: {
                    Text("安全")
                }

                if lock.canUseBiometrics {
                    Section {
                        Toggle("使用 \(lock.biometryName)", isOn: Binding(
                            get: { lock.biometricEnabled },
                            set: { lock.biometricEnabled = $0
                                   UserDefaults.standard.set($0, forKey: "nestkeep.appLock.biometric") }
                        ))
                    } footer: {
                        Text("开启后可用 \(lock.biometryName) 快速解锁，无需每次输入 PIN。")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .safeAreaInset(edge: .bottom) { Color.clear.frame(height: tabBarInset) }
        .navigationTitle("应用锁")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPinSheet) {
            pinSheet
        }
        .confirmationDialog("关闭应用锁？", isPresented: $showDisableConfirm, titleVisibility: .visible) {
            Button("关闭", role: .destructive) { lock.disable() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("关闭后启动应用将不再需要 PIN。")
        }
    }

    private var pinSheet: some View {
        NavigationView {
            Form {
                Section(header: Text("输入 6 位数字 PIN")) {
                    SecureField("新 PIN", text: $settingPin)
                        .keyboardType(.numberPad)
                    SecureField("再次输入", text: $confirmPin)
                        .keyboardType(.numberPad)
                }
                if let errorText = errorText {
                    Section { Text(errorText).font(.footnote).foregroundColor(Theme.expense) }
                }
            }
            .navigationTitle(pinSheetMode == .enable ? "设置 PIN" : "修改 PIN")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { showPinSheet = false }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { commitPin() }
                        .font(.body.weight(.semibold))
                }
            }
        }
    }

    private func commitPin() {
        errorText = nil
        guard settingPin.count == 6, settingPin.allSatisfy({ $0.isNumber }) else {
            errorText = "PIN 必须是 6 位数字"
            return
        }
        guard settingPin == confirmPin else {
            errorText = "两次输入的 PIN 不一致"
            return
        }
        do {
            switch pinSheetMode {
            case .enable: try lock.enable(pin: settingPin)
            case .change: try lock.changePin(newPin: settingPin)
            }
            showPinSheet = false
        } catch {
            errorText = (error as? AppLockError)?.errorDescription ?? error.localizedDescription
        }
    }
}
