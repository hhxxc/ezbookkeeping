import Foundation
import Combine
import LocalAuthentication
import CryptoKit

/// 应用锁：用 6 位 PIN（或生物识别）保护本地已保存的登录态。
///
/// 实现思路与 Web 端一致——**不把 PIN 本身存下来**，而是用
///     key = SHA256("EBK_LOCK_SECRET_" + PIN)
/// 派生一把密钥，用它对 token 做 AES 加密后落盘；
/// token 的明文只放在内存里（解锁后才有）。这样即便设备被拿到，
/// 没有 PIN 也无法还原 token。生物识别则是在已配置 PIN 的前提下，
/// 用 Face ID / Touch ID 通过验证后**临时放开**对 PIN 的使用
/// （PIN 密文存 Keychain，由系统在生物识别通过后授权读取）。
///
/// 说明：这是本地应用锁，属于「防顺手翻看」的隐私保护层，
/// 不等同于服务端鉴权——真正的权限仍在后端按 token 校验。
@MainActor
final class AppLockManager: ObservableObject {
    static let shared = AppLockManager()

    /// 用户是否开启了应用锁
    @Published private(set) var isEnabled: Bool
    /// 本次运行是否已解锁（启动后未解锁时不展示主界面）
    @Published private(set) var isUnlocked: Bool
    /// 是否允许生物识别解锁
    @Published var biometricEnabled: Bool

    private let enabledKey = "nestkeep.appLock.enabled"
    private let biometricKey = "nestkeep.appLock.biometric"
    /// PIN 派生密钥的密文（AES 加密后的 token）落盘位置
    private let encryptedTokenKey = "nestkeep.appLock.encryptedToken"
    /// PIN 本身不落盘；生物识别需要一把「系统保护」的 PIN 副本（Keychain，生物识别访问控制）
    private let pinKeychainAccount = "nestkeep.appLock.pin"
    private let saltKey = "nestkeep.appLock.salt"

    var biometryType: LABiometryType {
        let ctx = LAContext()
        _ = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        return ctx.biometryType
    }

    var canUseBiometrics: Bool {
        var err: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err)
    }

    var biometryName: String {
        switch biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        default: return "生物识别"
        }
    }

    private init() {
        let enabled = UserDefaults.standard.bool(forKey: enabledKey)
        isEnabled = enabled
        // 未开启应用锁 → 直接视为已解锁
        isUnlocked = !enabled
        biometricEnabled = UserDefaults.standard.bool(forKey: biometricKey)
    }

    /// 是否存有「应用锁加密过的凭证」（供 AuthManager 在非隔离上下文中判断启动时是否算已登录）。
    /// 只读 UserDefaults，不碰实例状态，故标记 nonisolated。
    nonisolated static var hasStoredCredential: Bool {
        let encrypted = UserDefaults.standard.string(forKey: "nestkeep.appLock.encryptedToken")
        return UserDefaults.standard.bool(forKey: "nestkeep.appLock.enabled")
            && !(encrypted ?? "").isEmpty
    }

    // MARK: - 开关

    /// 开启应用锁（同时用 PIN 加密当前 token）
    func enable(pin: String) throws {
        guard pin.count == 6, pin.allSatisfy({ $0.isNumber }) else {
            throw AppLockError.invalidPin
        }
        guard let token = AuthManager.shared.token, !token.isEmpty else {
            throw AppLockError.noToken
        }
        let salt = randomSalt()
        let newKey = deriveKey(pin: pin, salt: salt)
        let encrypted = try Self.encrypt(token, key: newKey)

        UserDefaults.standard.set(salt, forKey: saltKey)
        UserDefaults.standard.set(encrypted, forKey: encryptedTokenKey)
        UserDefaults.standard.set(true, forKey: enabledKey)
        KeychainStore.save(pin, account: pinKeychainAccount)   // 供生物识别解锁使用
        // 持久层只保留密文；明文 token 仅留在内存（下次启动需先解锁）
        AuthManager.shared.removePlaintextTokenFromStorage()
        isEnabled = true
        isUnlocked = true
    }

    /// 关闭应用锁（清掉密文与 PIN 副本，把明文 token 写回持久层）
    func disable() {
        // 先把明文 token 写回，避免关闭后重启直接掉登录态
        if let token = AuthManager.shared.token, !token.isEmpty {
            AuthManager.shared.persistPlaintextTokenToStorage(token)
        }
        UserDefaults.standard.removeObject(forKey: encryptedTokenKey)
        UserDefaults.standard.removeObject(forKey: saltKey)
        UserDefaults.standard.set(false, forKey: enabledKey)
        UserDefaults.standard.set(false, forKey: biometricKey)
        KeychainStore.delete(account: pinKeychainAccount)
        isEnabled = false
        biometricEnabled = false
        isUnlocked = true
    }

    /// 修改 PIN（需已解锁，重加密 token）
    func changePin(newPin: String) throws {
        guard let token = AuthManager.shared.token, !token.isEmpty else {
            throw AppLockError.noToken
        }
        guard newPin.count == 6, newPin.allSatisfy({ $0.isNumber }) else {
            throw AppLockError.invalidPin
        }
        let salt = randomSalt()
        let encrypted = try Self.encrypt(token, key: deriveKey(pin: newPin, salt: salt))
        UserDefaults.standard.set(salt, forKey: saltKey)
        UserDefaults.standard.set(encrypted, forKey: encryptedTokenKey)
        KeychainStore.save(newPin, account: pinKeychainAccount)
    }

    // MARK: - 解锁

    /// 用 PIN 校验并解密 token；成功后把明文 token 交回 AuthManager
    @discardableResult
    func unlock(pin: String) -> Bool {
        guard let salt = UserDefaults.standard.string(forKey: saltKey),
              let encrypted = UserDefaults.standard.string(forKey: encryptedTokenKey) else {
            return false
        }
        let key = deriveKey(pin: pin, salt: salt)
        guard let token = try? Self.decrypt(encrypted, key: key), !token.isEmpty else {
            return false
        }
        AuthManager.shared.restoreToken(token)
        isUnlocked = true
        return true
    }

    /// 用生物识别解锁（先用 LAContext 校验生物识别，通过后读取 PIN 副本并解密 token）
    func unlockWithBiometrics() async -> Bool {
        guard isEnabled, biometricEnabled, canUseBiometrics,
              let pin = KeychainStore.load(account: pinKeychainAccount) else {
            return false
        }
        // 先做一次生物识别校验；失败/取消则不继续
        let ok = await evaluateBiometrics()
        guard ok else { return false }
        return unlock(pin: pin)
    }

    /// 触发系统生物识别校验（Face ID / Touch ID）
    private func evaluateBiometrics() async -> Bool {
        await withCheckedContinuation { cont in
            let ctx = LAContext()
            ctx.localizedReason = "解锁巢记"
            var err: NSError?
            guard ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err) else {
                cont.resume(returning: false)
                return
            }
            ctx.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,
                               localizedReason: "解锁巢记") { success, _ in
                cont.resume(returning: success)
            }
        }
    }

    /// 手动锁定（回到解锁页）
    func lock() {
        guard isEnabled else { return }
        isUnlocked = false
        AuthManager.shared.clearInMemoryTokenPreservingStorage()
    }

    // MARK: - 加解密

    private func randomSalt() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
    }

    /// 与 Web 端同口径：SHA256(前缀 + PIN + salt)，取 32 字节作 AES-256 密钥
    private func deriveKey(pin: String, salt: String) -> SymmetricKey {
        let material = "EBK_LOCK_SECRET_" + pin + "|" + salt
        let digest = SHA256.hash(data: Data(material.utf8))
        return SymmetricKey(data: Data(digest))
    }

    private static func encrypt(_ plaintext: String, key: SymmetricKey) throws -> String {
        let sealed = try AES.GCM.seal(Data(plaintext.utf8), using: key)
        guard let combined = sealed.combined else { throw AppLockError.cryptoFailed }
        return combined.base64EncodedString()
    }

    private static func decrypt(_ ciphertext: String, key: SymmetricKey) throws -> String {
        guard let data = Data(base64Encoded: ciphertext) else { throw AppLockError.cryptoFailed }
        let box = try AES.GCM.SealedBox(combined: data)
        let opened = try AES.GCM.open(box, using: key)
        guard let text = String(data: opened, encoding: .utf8) else { throw AppLockError.cryptoFailed }
        return text
    }
}

enum AppLockError: LocalizedError {
    case invalidPin
    case noToken
    case cryptoFailed
    case pinMismatch

    var errorDescription: String? {
        switch self {
        case .invalidPin: return "PIN 必须是 6 位数字"
        case .noToken: return "当前没有可加密的登录凭证，请重新登录后再开启"
        case .cryptoFailed: return "凭证加解密失败"
        case .pinMismatch: return "两次输入的 PIN 不一致"
        }
    }
}

/// 最小化的 Keychain 封装：只在需要「生物识别保护」的 PIN 副本上使用。
/// 普通场景（token）继续走 UserDefaults，避免影响既有逻辑。
enum KeychainStore {
    private static let service = "com.hhxxc.nestkeep.applock"

    /// 普通写入（无访问控制）
    @discardableResult
    static func save(_ value: String, account: String) -> Bool {
        delete(account: account)
        guard let data = value.data(using: .utf8) else { return false }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    /// 普通读取
    static func load(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
