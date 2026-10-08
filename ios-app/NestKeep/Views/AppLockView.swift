import SwiftUI

/// 应用锁解锁页：6 位 PIN 输入 + 生物识别（可用时）。
/// 解锁失败给错误提示；也提供「重新登录」的兜底出口。
struct AppLockView: View {
    @ObservedObject private var lock = AppLockManager.shared
    @EnvironmentObject private var auth: AuthManager

    @State private var pin = ""
    @State private var errorText: String?
    @State private var isTryingBiometrics = false

    private let pinLength = 6

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 10) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 54))
                    .foregroundColor(Theme.brand)
                Text("巢记已锁定").font(.title3.bold())
                Text("输入 6 位 PIN 解锁").font(.footnote).foregroundColor(.secondary)
            }

            // PIN 圆点
            HStack(spacing: 14) {
                ForEach(0..<pinLength, id: \.self) { idx in
                    ZStack {
                        Circle().fill(idx < pin.count ? Theme.brand : Color.clear)
                        Circle().strokeBorder(Theme.brand.opacity(0.5), lineWidth: 1.5)
                    }
                    .frame(width: 14, height: 14)
                }
            }

            if let errorText = errorText {
                Text(errorText).font(.footnote).foregroundColor(Theme.expense)
            }

            // 数字键盘
            numberPad

            if lock.biometricEnabled && lock.canUseBiometrics {
                Button {
                    Task { await tryBiometrics() }
                } label: {
                    Label("使用 \(lock.biometryName) 解锁", systemImage: "faceid")
                        .font(.body.weight(.medium))
                }
                .padding(.top, 4)
            }

            Button("重新登录") {
                auth.logout()
            }
            .font(.footnote)
            .foregroundColor(.secondary)

            Spacer()
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .onAppear {
            // 进入即尝试一次生物识别（有开启时）
            if lock.biometricEnabled && lock.canUseBiometrics {
                Task { await tryBiometrics() }
            }
        }
    }

    private var numberPad: some View {
        VStack(spacing: 12) {
            ForEach([[1, 2, 3], [4, 5, 6], [7, 8, 9]], id: \.self) { row in
                HStack(spacing: 12) {
                    ForEach(row, id: \.self) { digit in
                        padButton(String(digit)) { append(String(digit)) }
                    }
                }
            }
            HStack(spacing: 12) {
                // 左下角留空，保持键盘对称
                Color.clear.frame(maxWidth: .infinity, minHeight: 56, maxHeight: 56)
                padButton("0") { append("0") }
                Button {
                    if !pin.isEmpty { pin.removeLast() }
                    errorText = nil
                } label: {
                    Image(systemName: "delete.left")
                        .font(.system(size: 20))
                        .frame(maxWidth: .infinity, minHeight: 56, maxHeight: 56)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func padButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 24, weight: .medium))
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }

    private func append(_ digit: String) {
        guard pin.count < pinLength else { return }
        pin += digit
        errorText = nil
        if pin.count == pinLength { verify() }
    }

    private func verify() {
        if lock.unlock(pin: pin) {
            errorText = nil
        } else {
            errorText = "PIN 不正确"
            pin = ""
        }
    }

    private func tryBiometrics() async {
        guard !isTryingBiometrics else { return }
        isTryingBiometrics = true
        let ok = await lock.unlockWithBiometrics()
        isTryingBiometrics = false
        if !ok { errorText = nil }
    }
}
