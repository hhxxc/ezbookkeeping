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

    /// 单个来源报告的最新版本信息（内部用）。
    /// version 为空表示该来源不可用（网络失败 / 无本变体版本）。
    private struct LatestInfo {
        let version: String
        let releaseURL: URL?
        let ipaURL: URL?
    }

    /// 查询最新版本并比对。
    ///
    /// **同时查两个来源，取版本号较大者**：
    ///   1. 后端中转清单 latest.json（走自有域名，国内可达、快）
    ///   2. GitHub Releases API（权威，但需能访问 github.com）
    ///
    /// 之所以不采用「清单优先、失败才回退」的串行策略，是因为 latest.json 由发版脚本
    /// 手动更新、可能滞后：若清单存在但版本号偏旧，串行策略会直接返回「已是最新」，
    /// 永远不会回退到 GitHub 去发现真正的新版——这正是「查不到最新」的根因之一。
    /// 并行取最大，能保证无论哪个来源更及时，用户都能拿到真正的最大版本号。
    static func checkAppUpdate() async -> UpdateCheckResult {
        let current = currentAppVersion

        async let backend = queryBackend()
        async let github = queryGitHub()
        let b = await backend
        let g = await github

        // 取两个来源中版本号较大者
        let candidates = [b, g].compactMap { $0 }
        guard let best = candidates.max(by: { compareVersion($0.version, $1.version) < 0 }) else {
            return .failed(message: "无法获取版本信息，请稍后重试")
        }

        if compareVersion(best.version, current) > 0 {
            return .updateAvailable(
                current: current,
                latest: best.version,
                releaseURL: best.releaseURL,
                ipaURL: best.ipaURL
            )
        }
        return .upToDate(current: current)
    }

    /// 后端清单来源：返回清单报告的最新版本（不可用/无本变体版本则返回 nil）。
    ///
    /// 优先读本变体清单 `latest-<flavor>.json`（新版后端支持，见 NestKeepVariantLatestHandler）；
    /// 旧后端没有该路由（请求会被 :name 兜底路由按非 .ipa 400 拒掉）或文件缺失时，
    /// 回退通用 latest.json（用 variant 字段区分变体，见 NestKeepLatestHandler）。
    private static func queryBackend() async -> LatestInfo? {
        for path in ["api/nestkeep/latest-\(channel).json", "api/nestkeep/latest.json"] {
            if let info = await fetchBackendManifest(path: path) { return info }
        }
        return nil
    }

    /// 读取单个后端清单文件（非 200 / 解析失败 / 变体不符都按不可用处理）。
    private static func fetchBackendManifest(path: String) async -> LatestInfo? {
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
        if let variant = manifest.variant, !variant.isEmpty, variant != channel {
            return nil
        }

        let latest = normalizeVersion(manifest.version)
        guard isSemanticVersion(latest) else { return nil }

        return LatestInfo(
            version: latest,
            releaseURL: manifest.releaseUrl.flatMap { URL(string: $0) },
            ipaURL: manifest.ipaUrl.flatMap { URL(string: $0) }
        )
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

    /// GitHub Releases API 来源：返回本变体最新的语义版本（不可用/无本变体版本则返回 nil）。
    ///
    /// 注意变体语义：stable 变体的语义版本 tag 是 `vX.Y.Z-stable`（见 build-native-ios.yml 的
    /// `Publish semantic version release` 步骤），dev 是 `vX.Y.Z`。这里必须**只认本变体的 tag**，
    /// 否则 stable 用户会拿到 dev 的 `vX.Y.Z` 当成自己的最新版，一键安装后被装成 dev 变体。
    private static func queryGitHub() async -> LatestInfo? {
        // per_page 给到 100：历史 Release 里有大量环境 tag（nestkeep-ipa-N / 巢记 v1.6.01.0x），
        // 若只取前 10 且版本号与 created_at 顺序不一致，会把真正的最新语义版本截断掉。
        guard let url = URL(string: "https://api.github.com/repos/\(repo)/releases?per_page=100") else {
            return nil
        }
        var req = URLRequest(url: url)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("NestKeep-iOS", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 15

        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let releases = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return nil
        }

        // 只保留非 draft / 非 prerelease 的正式版本，取版本号最大者
        var best: LatestInfo?
        for r in releases {
            if (r["draft"] as? Bool) == true { continue }
            if (r["prerelease"] as? Bool) == true { continue }
            guard let tag = r["tag_name"] as? String, !tag.isEmpty else { continue }
            // 解析出「核心版本号 + 变体后缀」，只认本 channel 的 tag；
            // 忽略 nestkeep-ipa-N / 巢记 v1.6.01.0x 等环境 tag。
            guard let parsed = parseVersionTag(tag), parsed.variant == channel else { continue }
            let releaseURL = (r["html_url"] as? String).flatMap { URL(string: $0) }
            let ipaURL = ipaAssetURL(from: r)
            let info = LatestInfo(version: parsed.version, releaseURL: releaseURL, ipaURL: ipaURL)
            if let cur = best {
                if compareVersion(info.version, cur.version) > 0 {
                    best = info
                }
            } else {
                best = info
            }
        }
        return best
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

    // MARK: - IPA 下载候选（App 内下载，不依赖 TrollStore 直连 GitHub）

    /// 构造按优先级排序的 IPA 下载候选地址：
    ///
    /// 1. 自有域名（NAS 直链 / 后端中转）永远最优：国内可达、不经 GitHub；
    /// 2. 给定的是 GitHub 直链时（清单滞后、GitHub 来源胜出的场景），在**前面**插入
    ///    后端反代 `{serverURL}/api/proxy/github/download?url=<原始链接>`，
    ///    由 NAS 服务端代下载，手机仍然不直连 github.com；
    /// 3. 给定的是自有域名且文件是 .ipa 时（发布脚本按 GitHub 资产原名上传），
    ///    在**后面**补反代 + GitHub 原链，作为 NAS 文件缺失时的兜底。
    static func downloadCandidates(ipaURL: URL, version: String) -> [URL] {
        var candidates: [URL] = []
        func push(_ url: URL?) {
            guard let url, !candidates.contains(url) else { return }
            candidates.append(url)
        }

        push(ipaURL)
        let host = ipaURL.host?.lowercased() ?? ""
        let ownHost = AppSettings.shared.serverURL.host?.lowercased() ?? ""

        if host == "github.com" || host == "objects.githubusercontent.com" {
            push(gitHubProxyURL(ipaURL))
        } else if !ownHost.isEmpty && host == ownHost,
                  ipaURL.lastPathComponent.lowercased().hasSuffix(".ipa"),
                  let gh = URL(string: "https://github.com/\(repo)/releases/download/v\(version)/\(ipaURL.lastPathComponent)") {
            push(gitHubProxyURL(gh))
            push(gh)
        }
        return candidates
    }

    /// 把 GitHub 直链包一层后端反代（{serverURL}/api/proxy/github/download?url=…）。
    private static func gitHubProxyURL(_ githubURL: URL) -> URL? {
        let base = AppSettings.shared.serverURL.appendingPathComponent("api/proxy/github/download")
        var comp = URLComponents(url: base, resolvingAgainstBaseURL: false)
        comp?.queryItems = [URLQueryItem(name: "url", value: githubURL.absoluteString)]
        return comp?.url
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

/// IPA 下载状态（App 内下载，完成后交给系统面板 → TrollStore 安装）
enum IPADownloadState: Equatable {
    case idle
    case downloading(received: Int64, total: Int64?)
    case downloaded(fileURL: URL)
    case failed(message: String)
}

/// IPA 文件下载器：委托式 URLSession downloadTask，支持进度回调与任务取消。
///
/// 之所以不用 `URLSession.bytes` 逐字节读（MB 级文件逐字节迭代太慢），
/// 也不用 `download(for:)`（拿不到进度）：委托是唯一既高效又有进度的写法。
final class IPAFileDownloader: NSObject, URLSessionDownloadDelegate {
    private let onProgress: @Sendable (Int64, Int64?) -> Void
    private var continuation: CheckedContinuation<URL, Error>?
    private var session: URLSession?
    private var task: URLSessionDownloadTask?
    private var destination: URL?

    init(onProgress: @escaping @Sendable (Int64, Int64?) -> Void) {
        self.onProgress = onProgress
        super.init()
    }

    struct DownloadError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// 下载目标路径：tmp/NestKeepUpdate/NestKeep-<version>.ipa
    static func destinationURL(version: String) -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("NestKeepUpdate", isDirectory: true)
        return dir.appendingPathComponent("NestKeep-\(version).ipa")
    }

    /// 取消当前下载（无进行中的任务时无副作用）。
    func cancel() {
        task?.cancel()
    }

    /// 从 url 下载并写入 destination（覆盖已有文件），返回 destination。
    ///
    /// HTTP 非 2xx、内容不是 zip（IPA 实为 zip 包，防反代返回 200 的 HTML 错误页）
    /// 都按失败抛出，由调用方换下一个候选源。
    func download(from url: URL, to destination: URL) async throws -> URL {
        self.destination = destination

        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 60     // 无数据进展的最大间隔
        cfg.timeoutIntervalForResource = 300   // 单个源的整体上限
        let session = URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
        self.session = session
        defer {
            session.finishTasksAndInvalidate()
            self.session = nil
            self.task = nil
        }

        let task = session.downloadTask(with: url)
        self.task = task

        _ = try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { cont in
                if Task.isCancelled {
                    cont.resume(throwing: CancellationError())
                    return
                }
                self.continuation = cont
                task.resume()
            }
        }, onCancel: { task.cancel() })

        if let http = task.response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            try? FileManager.default.removeItem(at: destination)
            throw DownloadError(message: "HTTP \(http.statusCode)")
        }

        // 内容校验：IPA 是 zip 包，头部应为 "PK"；拦截伪装成 200 的错误页
        if let fh = try? FileHandle(forReadingFrom: destination) {
            defer { try? fh.close() }
            let head = (try? fh.read(upToCount: 2)) ?? Data()
            if head != Data([0x50, 0x4B]) {
                try? FileManager.default.removeItem(at: destination)
                throw DownloadError(message: "下载内容不是有效的 IPA")
            }
        }
        return destination
    }

    // MARK: URLSessionDownloadDelegate

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        let total: Int64? = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : nil
        onProgress(totalBytesWritten, total)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        // 临时文件在本方法返回后会被系统删除，必须**同步**搬到稳定位置再恢复续体
        guard let destination else {
            resumeContinuation(with: .failure(DownloadError(message: "内部错误")))
            return
        }
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: destination.deletingLastPathComponent(),
                                   withIntermediateDirectories: true)
            if fm.fileExists(atPath: destination.path) {
                try fm.removeItem(at: destination)
            }
            try fm.moveItem(at: location, to: destination)
            resumeContinuation(with: .success(destination))
        } catch {
            resumeContinuation(with: .failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        // 成功路径已由 didFinish 处理；error == nil 的收尾无需再动续体
        guard let error else { return }
        resumeContinuation(with: .failure(error))
    }

    private func resumeContinuation(with result: Result<URL, Error>) {
        if let cont = continuation {
            continuation = nil
            cont.resume(with: result)
        }
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

    /// IPA 下载状态（供更新弹层渲染进度 / 打开安装面板）
    @Published var downloadState: IPADownloadState = .idle
    private var downloader: IPAFileDownloader?
    private var downloadTaskRef: Task<Void, Never>?

    /// 手动检查（用户点按）：同时刷新后端版本
    func checkNow() async {
        cancelDownload()
        downloadState = .idle
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

    // MARK: - IPA 下载（App 内下载 → 系统面板交给 TrollStore）

    /// App 内下载 IPA：按候选顺序尝试（自有域名 → 后端反代 → GitHub），自动换源。
    ///
    /// 下载与 TrollStore 解耦：TrollStore 下载器无法换源、失败无提示，
    /// 由 App 自己下载可以把进度、重试、换源都做进 UI 里。
    func startDownload(latest: String, ipaURL: URL) {
        cancelDownload()
        downloadState = .downloading(received: 0, total: nil)

        let candidates = UpdateChecker.downloadCandidates(ipaURL: ipaURL, version: latest)
        let destination = IPAFileDownloader.destinationURL(version: latest)
        let downloader = IPAFileDownloader()
        self.downloader = downloader

        downloadTaskRef = Task { [weak self] in
            var lastError: Error = IPAFileDownloader.DownloadError(message: "未知错误")
            for candidate in candidates {
                if Task.isCancelled { return }
                do {
                    let fileURL = try await downloader.download(from: candidate, to: destination) { received, total in
                        // 进度回调来自 URLSession 委托队列，跳回主线程刷新状态
                        Task { @MainActor [weak self] in
                            guard let self, !Task.isCancelled else { return }
                            if case .downloading = self.downloadState {
                                self.downloadState = .downloading(received: received, total: total)
                            }
                        }
                    }
                    guard !Task.isCancelled else { return }
                    self?.downloadState = .downloaded(fileURL: fileURL)
                    return
                } catch {
                    // 任务被取消时 URLSession 报的是 NSURLErrorCancelled（非 CancellationError），
                    // 统一靠 Task.isCancelled 识别，避免取消后被当成普通失败换源续传。
                    if Task.isCancelled { return }
                    lastError = error
                }
            }
            guard !Task.isCancelled else { return }
            self?.downloadState = .failed(
                message: "\(lastError.localizedDescription)（已尝试全部 \(candidates.count) 个下载源）")
        }
    }

    /// 取消下载（下载完成后调用即回到待下载状态）。
    func cancelDownload() {
        downloadTaskRef?.cancel()
        downloadTaskRef = nil
        downloader?.cancel()
        downloader = nil
        if case .downloading = downloadState {
            downloadState = .idle
        }
    }
}
