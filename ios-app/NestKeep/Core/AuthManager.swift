import Foundation
import Combine

struct LoginRequest: Codable {
    let loginName: String
    let password: String
}

struct AuthResponse: Codable {
    let token: String
    let need2FA: Bool
    let user: UserBasicInfo?
}

/// 认证管理：登录、token 存储（UserDefaults）、登出
/// 注意：不要给整个类加 @MainActor，否则 APIClient（非隔离）读取 token 会触发跨 actor 隔离错误。
/// 仅把会修改 @Published 的 UI 状态的方法标 @MainActor。
final class AuthManager: ObservableObject {
    static let shared = AuthManager()

    @Published private(set) var isLoggedIn = false
    private(set) var token: String?
    private(set) var currentUser: UserBasicInfo?

    private let tokenKey = "nestkeep.token"
    private let userKey = "nestkeep.user"

    init() {
        if let token = UserDefaults.standard.string(forKey: tokenKey) {
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
    func login(loginName: String, password: String) async throws {
        let resp: AuthResponse = try await APIClient.shared.request(
            "/api/authorize.json",
            method: .POST,
            body: LoginRequest(loginName: loginName, password: password)
        )
        if resp.need2FA {
            throw APIError.twoFactorRequired
        }
        guard !resp.token.isEmpty else { throw APIError.invalidResponse }
        self.token = resp.token
        self.currentUser = resp.user
        self.isLoggedIn = true
        UserDefaults.standard.set(token, forKey: tokenKey)
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
        UserDefaults.standard.removeObject(forKey: tokenKey)
        UserDefaults.standard.removeObject(forKey: userKey)
        // 登出时一并清掉应用锁的凭证密文，避免残留无法解密的 token
        UserDefaults.standard.removeObject(forKey: "nestkeep.appLock.encryptedToken")
        UserDefaults.standard.removeObject(forKey: "nestkeep.appLock.salt")
    }

    /// 应用锁解锁后：把明文 token 交回内存（不改动落盘的密文）
    @MainActor
    func restoreToken(_ newToken: String) {
        self.token = newToken
        self.isLoggedIn = true
    }

    /// 重新锁定：只清内存里的 token，UserDefaults 中的凭证保持不变
    /// （应用锁开启时落盘的是密文，明文 token 不应留在持久层）
    @MainActor
    func clearInMemoryTokenPreservingStorage() {
        self.token = nil
        self.isLoggedIn = false
    }

    /// 应用锁开启后：把 UserDefaults 里的明文 token 换成密文（由 AppLockManager 提供）
    func removePlaintextTokenFromStorage() {
        UserDefaults.standard.removeObject(forKey: tokenKey)
    }

    /// 应用锁关闭后：把明文 token 写回 UserDefaults
    func persistPlaintextTokenToStorage(_ token: String) {
        UserDefaults.standard.set(token, forKey: tokenKey)
    }

    /// 资料更新后同步本地用户信息（后端可能下发新 token，需一并替换）
    @MainActor
    func updateCurrentUser(_ user: UserBasicInfo, newToken: String?) async {
        if let newToken = newToken, !newToken.isEmpty {
            self.token = newToken
            UserDefaults.standard.set(newToken, forKey: tokenKey)
        }
        self.currentUser = user
        if let data = try? JSONEncoder().encode(user) {
            UserDefaults.standard.set(data, forKey: userKey)
        }
    }
}
