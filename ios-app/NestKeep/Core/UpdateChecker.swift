import Foundation
import Combine

/// 后端版本信息（GET /api/v1/systems/version.json）
struct ServerVersionInfo: Codable {
    let version: String?
    let commitHash: String?
    let buildTime: String?
}

/// 更新检测结果
enum UpdateCheckResult: Equatable {
    case upToDate(current: String)
    case updateAvailable(current: String, latest: String, downloadURL: URL?)
    case failed(message: String)
}

/// 版本更新检测器：
/// - App 自更新：读取本机 CFBundleShortVersionString，与 GitHub Releases 最新 tag 比对
/// - 后端版本：调用后端 systems/version.json（便于确认 NAS 后端是否最新）
///
/// 纯原生实现，不依赖第三方库；GitHub 公开 API 无需 token（有速率限制，故仅在用户手动触发或低频自动检查时调用）。
enum UpdateChecker {
    /// 本 App 对应的 GitHub 仓库（Releases 里查最新 tag）
    static let repo = "hhxxc/ezbookkeeping"
    /// Releases 下载页（供「去下载」按钮打开）
    static let releasesPageURL = URL(string: "https://github.com/\(repo)/releases")!

    /// 本机 App 版本号
    static var currentAppVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    /// 本机 App 构建号
    static var currentBuildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
    }

    // MARK: - App 更新检测

    /// 通过 GitHub Releases API 查询最新版本并比对。
    /// 取「最新的、非 draft 的 release」的 tag_name，去掉前缀 v 后与当前版本做数值比较。
    static func checkAppUpdate() async -> UpdateCheckResult {
        let current = currentAppVersion
        do {
            let url = URL(string: "https://api.github.com/repos/\(repo)/releases?per_page=10")!
            var req = URLRequest(url: url)
            req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            req.setValue("NestKeep-iOS", forHTTPHeaderField: "User-Agent")
            req.timeoutInterval = 15

            let (data, _) = try await URLSession.shared.data(for: req)
            guard let releases = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                return .failed(message: "无法解析版本信息")
            }

            // 只保留非 draft / 非 prerelease 的正式版本，取版本号最大者
            var best: (tag: String, url: URL?)?
            for r in releases {
                if (r["draft"] as? Bool) == true { continue }
                if (r["prerelease"] as? Bool) == true { continue }
                guard let tag = r["tag_name"] as? String, !tag.isEmpty else { continue }
                let normalized = normalizeVersion(tag)
                // 仅考虑形如 x.y.z 的版本（忽略 nestkeep-ipa-N 这类环境 tag）
                guard isSemanticVersion(normalized) else { continue }
                if let cur = best {
                    if compareVersion(normalized, cur.tag) > 0 {
                        let u = (r["html_url"] as? String).flatMap { URL(string: $0) }
                        best = (normalized, u)
                    }
                } else {
                    let u = (r["html_url"] as? String).flatMap { URL(string: $0) }
                    best = (normalized, u)
                }
            }

            guard let latest = best else {
                return .failed(message: "暂无可用的正式版本")
            }

            if compareVersion(latest.tag, current) > 0 {
                return .updateAvailable(current: current, latest: latest.tag, downloadURL: latest.url ?? releasesPageURL)
            }
            return .upToDate(current: current)
        } catch {
            return .failed(message: error.localizedDescription)
        }
    }

    // MARK: - 后端版本

    /// 查询后端版本（需要已登录，走统一信封）
    static func fetchServerVersion() async -> ServerVersionInfo? {
        try? await APIClient.shared.request("/api/v1/systems/version.json") as ServerVersionInfo
    }

    // MARK: - 版本号工具

    /// 去掉 v 前缀（v1.6.0 -> 1.6.0）
    static func normalizeVersion(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("v") || s.hasPrefix("V") { s.removeFirst() }
        return s
    }

    /// 是否形如 1 / 1.2 / 1.2.3（纯数字点分），用于过滤环境 tag
    static func isSemanticVersion(_ s: String) -> Bool {
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        guard !parts.isEmpty else { return false }
        return parts.allSatisfy { !$0.isEmpty && $0.allSatisfy { $0.isNumber } }
    }

    /// 比较两个点分版本号：a > b 返回 1，a < b 返回 -1，相等返回 0
    static func compareVersion(_ a: String, _ b: String) -> Int {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        let n = max(pa.count, pb.count)
        for i in 0..<n {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y ? 1 : -1 }
        }
        return 0
    }
}

/// 更新检查的可观察状态（供 SwiftUI 绑定）
@MainActor
final class UpdateStore: ObservableObject {
    static let shared = UpdateStore()

    @Published var isChecking = false
    @Published var result: UpdateCheckResult?
    @Published var serverVersion: ServerVersionInfo?

    /// 上次自动检查时间（避免每次启动都打 GitHub API）
    private let lastAutoCheckKey = "nestkeep.lastAutoUpdateCheck"
    private let autoCheckInterval: TimeInterval = 60 * 60 * 12  // 12 小时

    /// 手动检查（用户点按）：同时刷新后端版本
    func checkNow() async {
        isChecking = true
        async let app = UpdateChecker.checkAppUpdate()
        async let server = UpdateChecker.fetchServerVersion()
        let appResult = await app
        let serverResult = await server
        self.result = appResult
        self.serverVersion = serverResult
        isChecking = false
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastAutoCheckKey)
    }

    /// 启动时静默检查：超过间隔才真正请求，且失败不打扰用户
    func autoCheckIfNeeded() async {
        let last = UserDefaults.standard.double(forKey: lastAutoCheckKey)
        let now = Date().timeIntervalSince1970
        guard now - last > autoCheckInterval else { return }
        UserDefaults.standard.set(now, forKey: lastAutoCheckKey)
        // 静默刷新后端版本
        self.serverVersion = await UpdateChecker.fetchServerVersion()
        let r = await UpdateChecker.checkAppUpdate()
        // 仅当有新版时才在 UI 上提示（upToDate/failed 不打扰）
        if case .updateAvailable = r { self.result = r }
    }
}
