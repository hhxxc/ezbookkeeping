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
    /// - releaseURL: Release 页面（含说明）
    /// - ipaURL: IPA 文件直链（供 TrollStore「从 URL 安装」）
    case updateAvailable(current: String, latest: String, releaseURL: URL?, ipaURL: URL?)
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

    /// 本机 App 变体（channel）。
    ///
    /// dev 与 stable 是两个 Bundle ID 不同、可同时安装的变体，**必须各查各的清单**：
    /// 否则 dev 会拿到 stable 的版本号并提示更新，用户「一键更新」后会被装成另一个
    /// 变体（或因为 Bundle ID 不符而装上第二个 App）。判定依据是 Bundle ID 后缀。
    static var channel: String {
        let bid = Bundle.main.bundleIdentifier ?? ""
        if bid.hasSuffix(".stable") { return "stable" }
        return "dev"
    }

    /// 本机 App 版本号
    static var currentAppVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    /// 本机 App 构建号
    static var currentBuildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
    }

    // MARK: - App 更新检测

    /// 查询最新版本并比对。优先读用户自己后端的中转清单（走自己的域名，国内可达），
    /// 失败再回退 GitHub API（需能访问 github.com）。
    static func checkAppUpdate() async -> UpdateCheckResult {
        let current = currentAppVersion

        // 1) 优先：后端中转清单 /api/nestkeep/latest.json
        if let r = await checkViaBackend(current: current) {
            return r
        }
        // 2) 回退：GitHub Releases API
        return await checkViaGitHub(current: current)
    }

    /// 后端中转清单结构（由发版脚本写入 NAS）：{ version, ipaUrl, releaseUrl?, notes?, variant? }
    /// variant 为可选：区分 dev / stable 变体，缺省表示通用（不带变体语义）。
    private struct BackendManifest: Decodable {
        let version: String
        let ipaUrl: String?
        let releaseUrl: String?
        let notes: String?
        let variant: String?
    }

    private static func checkViaBackend(current: String) async -> UpdateCheckResult? {
        // 后端目前只有一个清单 latest.json（用 variant 字段区分变体，见 NestKeepLatestHandler）。
        // 直接读它即可；不存在的变体专属清单（latest-dev.json 等）后端没有对应路由，
        // 请求只会命中 :name 通配返回 404，属于无意义的往返。
        let path = "api/nestkeep/latest.json"
        guard var comp = URLComponents(url: AppSettings.shared.serverURL.appendingPathComponent(path),
                                       resolvingAgainstBaseURL: false) else {
            return nil
        }
        comp.query = nil
        guard let url = comp.url else { return nil }

        var req = URLRequest(url: url)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 10

        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse, http.statusCode == 200,
              let manifest = try? JSONDecoder().decode(BackendManifest.self, from: data) else {
            return nil
        }

        // 清单若带 variant 字段，则必须与本机变体一致才采用（防跨变体误报）。
        // 不带 variant 的旧清单视为通用，但此时 ipaUrl 可能指向任一变体，仍按版本号比对。
        if let variant = manifest.variant, !variant.isEmpty, variant != channel {
            return nil
        }

        let latest = normalizeVersion(manifest.version)
        guard isSemanticVersion(latest) else { return nil }

        if compareVersion(latest, current) > 0 {
            return .updateAvailable(
                current: current,
                latest: latest,
                releaseURL: manifest.releaseUrl.flatMap { URL(string: $0) },
                ipaURL: manifest.ipaUrl.flatMap { URL(string: $0) }
            )
        }
        return .upToDate(current: current)
    }

    /// 通过 GitHub Releases API 查询最新版本并比对（回退路径）。
    ///
    /// 注意变体语义：stable 变体的语义版本 tag 是 `vX.Y.Z-stable`（见 build-native-ios.yml 的
    /// `Publish semantic version release` 步骤），dev 是 `vX.Y.Z`。这里必须**只认本变体的 tag**，
    /// 否则 stable 用户会拿到 dev 的 `vX.Y.Z` 当成自己的最新版，一键安装后被装成 dev 变体。
    private static func checkViaGitHub(current: String) async -> UpdateCheckResult {
        do {
            // per_page 给到 100：历史 Release 里有大量环境 tag（nestkeep-ipa-N / 巢记 v1.6.01.0x），
            // 若只取前 10 且版本号与 created_at 顺序不一致，会把真正的最新语义版本截断掉。
            let url = URL(string: "https://api.github.com/repos/\(repo)/releases?per_page=100")!
            var req = URLRequest(url: url)
            req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            req.setValue("NestKeep-iOS", forHTTPHeaderField: "User-Agent")
            req.timeoutInterval = 15

            let (data, _) = try await URLSession.shared.data(for: req)
            guard let releases = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                return .failed(message: "无法解析版本信息")
            }

            // 只保留非 draft / 非 prerelease 的正式版本，取版本号最大者
            var best: (tag: String, releaseURL: URL?, ipaURL: URL?)?
            for r in releases {
                if (r["draft"] as? Bool) == true { continue }
                if (r["prerelease"] as? Bool) == true { continue }
                guard let tag = r["tag_name"] as? String, !tag.isEmpty else { continue }
                // 解析出「核心版本号 + 变体后缀」，只认本 channel 的 tag；
                // 忽略 nestkeep-ipa-N / 巢记 v1.6.01.0x 等环境 tag。
                guard let parsed = parseVersionTag(tag), parsed.variant == channel else { continue }
                let releaseURL = (r["html_url"] as? String).flatMap { URL(string: $0) }
                let ipaURL = ipaAssetURL(from: r)
                if let cur = best {
                    if compareVersion(parsed.version, cur.tag) > 0 {
                        best = (parsed.version, releaseURL, ipaURL)
                    }
                } else {
                    best = (parsed.version, releaseURL, ipaURL)
                }
            }

            guard let latest = best else {
                return .failed(message: "暂无可用的正式版本")
            }

            if compareVersion(latest.tag, current) > 0 {
                return .updateAvailable(
                    current: current,
                    latest: latest.tag,
                    releaseURL: latest.releaseURL ?? releasesPageURL,
                    ipaURL: latest.ipaURL
                )
            }
            return .upToDate(current: current)
        } catch {
            return .failed(message: error.localizedDescription)
        }
    }

    /// 从 release 的 assets 里找 .ipa 的浏览器直链
    private static func ipaAssetURL(from release: [String: Any]) -> URL? {
        guard let assets = release["assets"] as? [[String: Any]] else { return nil }
        for a in assets {
            if let name = a["name"] as? String, name.lowercased().hasSuffix(".ipa"),
               let urlStr = a["browser_download_url"] as? String, let u = URL(string: urlStr) {
                return u
            }
        }
        return nil
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

    /// 是否形如 `x.y.z` 的标准语义版本（三段纯数字点分），用于过滤环境 tag。
    ///
    /// 严格限制：**必须恰好三段**、每段**无前导零**（除非该段就是 `0`）。
    /// 这样能排除历史遗留的 `1.6.01.09`（四段、含前导零）这类旧 Web 壳 tag——它们会被
    /// 误当成合法版本并污染「取最大版本号」的比较（`Int("01")` 会解析成 `1`）。
    static func isSemanticVersion(_ s: String) -> Bool {
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return false }
        for p in parts {
            // 非空、全数字、且（长度 == 1 或 首字符非 '0'）
            if p.isEmpty || !p.allSatisfy({ $0.isNumber }) { return false }
            if p.count > 1 && p.first == "0" { return false }
        }
        return true
    }

    /// 从 release tag 解析出「核心版本号 + 变体」。
    ///
    /// 支持：`v1.6.5`（dev）、`1.6.5`（dev）、`v1.6.5-stable` / `1.6.5-stable`（stable）。
    /// 返回 nil 表示不是本 App 的语义版本 tag（环境 tag、旧四段 tag 等）。
    private struct ParsedTag {
        let version: String   // 纯 x.y.z
        let variant: String   // "dev" / "stable"
    }

    private static func parseVersionTag(_ raw: String) -> ParsedTag? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("v") || s.hasPrefix("V") { s.removeFirst() }

        // 拆分变体后缀：-stable / -dev / 无后缀（缺省 dev）
        var variant = "dev"
        if s.hasSuffix("-stable") {
            variant = "stable"
            s = String(s.dropLast("-stable".count))
        } else if s.hasSuffix("-dev") {
            variant = "dev"
            s = String(s.dropLast("-dev".count))
        }

        guard isSemanticVersion(s) else { return nil }
        return ParsedTag(version: s, variant: variant)
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

    /// 上次自动检查时间（仅用于记录展示，不再做长节流）
    private let lastAutoCheckKey = "nestkeep.lastAutoUpdateCheck"

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

    /// 启动时检查：每次启动都查（有新版才提示，失败静默）。
    /// 加一层 1 小时的最小间隔兜底，避免用户疯狂切前后台时反复打 GitHub API。
    func autoCheckIfNeeded(force: Bool = false) async {
        let last = UserDefaults.standard.double(forKey: lastAutoCheckKey)
        let now = Date().timeIntervalSince1970
        if !force && now - last < 60 * 60 { return }
        UserDefaults.standard.set(now, forKey: lastAutoCheckKey)
        // 静默刷新后端版本
        self.serverVersion = await UpdateChecker.fetchServerVersion()
        let r = await UpdateChecker.checkAppUpdate()
        // 每次启动都拿结果：有新版提示，无新版/失败不打扰
        if case .updateAvailable = r { self.result = r }
    }
}
