import Foundation
import Combine

/// APIClient 检测到 token 失效（HTTP 401 + 错误码 202001~202003）时广播，
/// AuthManager 统一登出并回到登录页
extension Notification.Name {
    static let sessionExpired = Notification.Name("nestkeep.sessionExpired")
}

struct LoginRequest: Codable {
    let loginName: String
    let password: String
}

/// 登录结果：要么直接成功（已注入 token），要么 need2FA（返回临时 token 待二次验证）
enum LoginResult {
    case success
    case need2FA(tempToken: String)
}

/// 2FA 验证请求体（对应 Web authorize2FA / authorize2FAByBackupCode）
struct TwoFactorAuthorizeRequest: Codable {
    let passcode: String?
    let recoveryCode: String?
}

struct AuthResponse: Codable {
    let token: String
    let need2FA: Bool
    let user: UserBasicInfo?
}

/// 认证管理：登录、token 存储（Keychain）、登出
/// 注意：不要给整个类加 @MainActor，否则 APIClient（非隔离）读取 token 会触发跨 actor 隔离错误。
/// 仅把会修改 @Published 的 UI 状态的方法标 @MainActor。
final class AuthManager: ObservableObject {
    static let shared = AuthManager()

    @Published private(set) var isLoggedIn = false
    private(set) var token: String?
    /// @Published：设置页/个人资料页据此实时刷新头像与昵称（头像上传后即时生效）
    @Published private(set) var currentUser: UserBasicInfo?

    /// token 持久化在 Keychain（设备解锁才可读、不进 iCloud/备份）
    private let tokenKeychainAccount = "nestkeep.auth.token"
    /// 历史版本曾明文存 UserDefaults，启动时一次性迁移
    private let legacyTokenKey = "nestkeep.token"
    private let userKey = "nestkeep.user"
    private var cancellables: Set<AnyCancellable> = []

    private func loadPersistedToken() -> String? {
        if let token = KeychainStore.load(account: tokenKeychainAccount) { return token }
        if let legacy = UserDefaults.standard.string(forKey: legacyTokenKey) {
            KeychainStore.save(legacy, account: tokenKeychainAccount)
            UserDefaults.standard.removeObject(forKey: legacyTokenKey)
            return legacy
        }
        return nil
    }

    private func persistToken(_ token: String) {
        KeychainStore.save(token, account: tokenKeychainAccount)
    }

    private func deletePersistedToken() {
        KeychainStore.delete(account: tokenKeychainAccount)
        UserDefaults.standard.removeObject(forKey: legacyTokenKey)
    }

    init() {
        // token 过期/失效由服务端 401 广播，统一登出（幂等，多次通知只登出一次）
        NotificationCenter.default.publisher(for: .sessionExpired)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor in
                    guard let self = self, self.isLoggedIn else { return }
                    self.logout()
                }
            }
            .store(in: &cancellables)

        if let token = loadPersistedToken() {
            self.token = token
            self.isLoggedIn = true
        } else if AppLockManager.hasStoredCredential {
            // 开启了应用锁：持久层只有密文，明文 token 需解锁后才回到内存。
            // 这里把登录态视为「已登录但未解锁」，交给 RootView 展示解锁页。
            self.isLoggedIn = true
        }
        if let data = UserDefaults.standard.data(forKey: userKey),
           let user = try? JSONDecoder().decode(UserBasicInfo.self, from: data) {
            self.currentUser = user
        }
    }

    @MainActor
    func login(loginName: String, password: String) async throws -> LoginResult {
        let resp: AuthResponse = try await APIClient.shared.request(
            "/api/authorize.json",
            method: .POST,
            body: LoginRequest(loginName: loginName, password: password)
        )
        if resp.need2FA {
            // 后端返回的是临时 token，需二次验证后才换成正式 token
            return .need2FA(tempToken: resp.token)
        }
        guard !resp.token.isEmpty else { throw APIError.invalidResponse }
        applyAuthResponse(resp)
        return .success
    }

    /// 2FA 二次验证：用临时 token + 动态码 / 备份码换取正式 token。
    /// - Parameters:
    ///   - tempToken: 登录时后端下发的临时 token
    ///   - passcode: 认证器 App 的 6 位动态码（与 recoveryCode 二选一）
    ///   - recoveryCode: 备份码（与 passcode 二选一）
    @MainActor
    func verify2FA(tempToken: String, passcode: String?, recoveryCode: String?) async throws {
        let path = recoveryCode != nil ? "/api/2fa/recovery.json" : "/api/2fa/authorize.json"
        let body = TwoFactorAuthorizeRequest(passcode: passcode, recoveryCode: recoveryCode)
        // 2fa 接口用临时 token 鉴权，且 noAuth（不注入当前 token）
        let resp: AuthResponse = try await APIClient.shared.request(
            path,
            method: .POST,
            body: body,
            overrideToken: tempToken
        )
        guard !resp.token.isEmpty else { throw APIError.invalidResponse }
        applyAuthResponse(resp)
    }

    /// 应用登录响应（注入 token 与用户信息）
    @MainActor
    private func applyAuthResponse(_ resp: AuthResponse) {
        self.token = resp.token
        self.currentUser = resp.user
        self.isLoggedIn = true
        persistToken(resp.token)
        if let user = resp.user, let data = try? JSONEncoder().encode(user) {
            UserDefaults.standard.set(data, forKey: userKey)
        }
    }

    /// 刷新 token（按需调用，后端有最小刷新间隔）
    @MainActor
    func refreshToken() async throws {
        // POST /api/v1/tokens/refresh.json，成功返回 newToken
        // MVP 暂未启用自动刷新；登录态长期有效，过期后登录页会重新登录
    }

    @MainActor
    func logout() {
        // 可选：调用 GET /api/logout.json 吊销当前 token
        token = nil
        currentUser = nil
        isLoggedIn = false
        deletePersistedToken()
        UserDefaults.standard.removeObject(forKey: userKey)
        // 登出时一并清掉应用锁的凭证密文，避免残留无法解密的 token
        UserDefaults.standard.removeObject(forKey: "nestkeep.appLock.encryptedToken")
        UserDefaults.standard.removeObject(forKey: "nestkeep.appLock.salt")
    }

    /// 应用锁解锁后：把明文 token 交回内存并回写 Keychain
    /// （进程在解锁状态下被杀，重启后无需重解密即可恢复登录态，UI 仍受应用锁门控）
    @MainActor
    func restoreToken(_ newToken: String) {
        self.token = newToken
        self.isLoggedIn = true
        persistToken(newToken)
    }

    /// 重新锁定：只清内存里的 token，持久层凭证（应用锁密文）保持不变
    @MainActor
    func clearInMemoryTokenPreservingStorage() {
        self.token = nil
        self.isLoggedIn = false
    }

    /// 应用锁开启后：删掉持久层的明文 token（Keychain），只留 PIN 加密后的密文
    func removePersistedToken() {
        deletePersistedToken()
    }

    /// 应用锁关闭后：把明文 token 写回 Keychain
    func persistTokenToStorage(_ token: String) {
        persistToken(token)
    }

    /// 资料更新后同步本地用户信息（后端可能下发新 token，需一并替换）
    @MainActor
    func updateCurrentUser(_ user: UserBasicInfo, newToken: String?) async {
        if let newToken = newToken, !newToken.isEmpty {
            self.token = newToken
            persistToken(newToken)
        }
        self.currentUser = user
        if let data = try? JSONEncoder().encode(user) {
            UserDefaults.standard.set(data, forKey: userKey)
        }
    }
}
