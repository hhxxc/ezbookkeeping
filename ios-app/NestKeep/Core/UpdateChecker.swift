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
        /// URLSession 提供的断点续传数据（仅网络中断类失败会有；HTTP 状态错误没有）。
        /// 供调用方在同一源上续传，而不是从头重下。
        var resumeData: Data? = nil
        var errorDescription: String? { message }
    }

    /// 下载目标路径：Caches/NestKeepUpdate/NestKeep-<version>.ipa。
    ///
    /// 用 Caches 而不是 tmp：闲时自动下载的安装包需要**跨启动保留**（下次打开 App
    /// 直接「点此安装」），tmp 随时可能被系统清空；Caches 同样不占用户可见空间、
    /// 存储紧张时系统也可回收，语义正合适。
    static func destinationURL(version: String) -> URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = caches.appendingPathComponent("NestKeepUpdate", isDirectory: true)
        return dir.appendingPathComponent("NestKeep-\(version).ipa")
    }

    /// 取已下载完成的安装包（文件存在、大小合理、且为合法 zip 头），没有则返回 nil。
    ///
    /// 供闲时自动下载复用：检测到新版本时先看本地是否已有上次下好的包，
    /// 有就直接进入「点此安装」状态，不重新下载。
    static func existingDownload(version: String) -> URL? {
        let url = destinationURL(version: version)
        let fm = FileManager.default
        guard let attrs = try? fm.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int64, size > 1024,
              let fh = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? fh.close() }
        let head = (try? fh.read(upToCount: 2)) ?? Data()
        return head == Data([0x50, 0x4B]) ? url : nil
    }

    /// 清理除保留版本以外的旧安装包与断点数据（换新版本下载时防 Caches 堆积）。
    static func cleanStaleDownloads(keeping keepVersion: String) {
        let dir = destinationURL(version: keepVersion).deletingLastPathComponent()
        let keepName = "NestKeep-\(keepVersion).ipa"
        guard let items = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        for item in items {
            let name = item.lastPathComponent
            guard name != keepName else { continue }
            let isIPA = name.lowercased().hasSuffix(".ipa")
            let isResume = name.lowercased().hasSuffix(".resumedata.plist")
            if isIPA || isResume {
                try? FileManager.default.removeItem(at: item)
            }
        }
    }

    /// 取消当前下载（无进行中的任务时无副作用）。
    func cancel() {
        task?.cancel()
    }

    // MARK: 断点续传（resumeData 持久化）

    /// resumeData 落盘路径：Caches/NestKeepUpdate/NestKeep-<version>.resumedata.plist
    /// 内容为 {url, data}：data 是 URLSession 的续传数据，url 是它对应的下载源——
    /// 续传只能对同一个源进行（里面记录了已下载的字节偏移），换源必须从头下。
    private static func resumeDataURL(version: String) -> URL {
        destinationURL(version: version).deletingPathExtension().appendingPathExtension("resumedata.plist")
    }

    /// 保存断点数据（换新版本下载时会随 cleanStaleDownloads 一起清理）。
    static func saveResumeData(_ data: Data, sourceURL: URL, version: String) {
        let payload: [String: Any] = ["url": sourceURL.absoluteString, "data": data]
        let url = resumeDataURL(version: version)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        (payload as NSDictionary).write(to: url)
    }

    /// 读取断点数据（无或损坏返回 nil）。
    static func loadResumeData(version: String) -> (data: Data, sourceURL: URL)? {
        let url = resumeDataURL(version: version)
        guard let dict = NSDictionary(contentsOf: url),
              let data = dict["data"] as? Data, !data.isEmpty,
              let urlStr = dict["url"] as? String,
              let source = URL(string: urlStr) else { return nil }
        return (data, source)
    }

    /// 清除断点数据（下载成功或确认要从头重下时调用）。
    static func clearResumeData(version: String) {
        try? FileManager.default.removeItem(at: resumeDataURL(version: version))
    }

    /// 从 url 下载并写入 destination（覆盖已有文件），返回 destination。
    ///
    /// - resumeData 非空时从断点续传（同一 URL 的中断点继续），失败或校验不过由调用方换策略。
    /// - HTTP 非 2xx、内容不是 zip（IPA 实为 zip 包，防反代返回 200 的 HTML 错误页）
    ///   都按失败抛出，由调用方换下一个候选源。
    func download(from url: URL, to destination: URL, resumeData: Data? = nil) async throws -> URL {
        self.destination = destination

        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 60     // 无数据进展的最大间隔
        cfg.timeoutIntervalForResource = 300   // 单次尝试的整体上限（续传重试各自计时）
        let session = URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
        self.session = session
        defer {
            session.finishTasksAndInvalidate()
            self.session = nil
            self.task = nil
        }

        // 优先续传；resumeData 无效（如源已变更）会立即报错，调用方回退为全新下载
        let task: URLSessionDownloadTask
        if let resumeData {
            task = try session.downloadTask(withResumeData: resumeData)
        } else {
            task = session.downloadTask(with: url)
        }
        self.task = task

        _ = try await withTaskCancellationHandler(operation: {
            // 显式标注续体类型：body 内不走 resume(returning:)，泛型 T 推不出来
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<URL, Error>) in
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
        // 网络中断类失败携带 resumeData（HTTP 状态错误等没有），供调用方续传；
        // 用户取消（NSURLErrorCancelled）也会走到这里，但调用方靠 Task.isCancelled 先行拦截
        let nsError = (task.error ?? error) as NSError
        let rd = nsError.userInfo[NSURLSessionDownloadTaskResumeData] as? Data
        resumeContinuation(with: .failure(DownloadError(message: error.localizedDescription, resumeData: rd)))
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

    /// 当前下载对应的目标版本（取消记忆用）
    private var currentDownloadVersion: String?

    /// 用户手动取消下载过的版本（避免闲时自动下载与用户意图打架）
    private static let cancelledAutoDownloadKey = "nestkeep.autoDownloadCancelledVersion"

    /// 手动检查（用户点按）：同时刷新后端版本
    func checkNow() async {
        // 内部重置（非用户取消）：不记取消记忆，否则下面的闲时安排会被挡掉
        cancelDownload(rememberCancel: false)
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

        // 手动检查发现新版也立即自动下载：用户不开弹层、不点下载，包也会提前下好
        if case .updateAvailable(_, let latest, _, let ipaURL) = appResult, let url = ipaURL {
            scheduleAutoDownload(latest: latest, ipaURL: url)
        }
    }

    /// 启动时检查：每次启动都查（有新版才提示，失败静默）。
    /// 加一层 5 分钟的最小间隔兜底，避免用户疯狂切前后台时反复打 GitHub API；
    /// IPA 仅 ~2MB 且下载无感，检测本身够便宜，不必再用长节流。
    ///
    /// 发现新版本后立即自动下载：后台静默把 IPA 下到 Caches（自动换源，NAS 优先）；
    /// 本地已有完整包则直接标记为已下载。用户下次打开更新弹层，看到的直接是「点此安装」。
    func autoCheckIfNeeded(force: Bool = false) async {
        let last = UserDefaults.standard.double(forKey: lastAutoCheckKey)
        let now = Date().timeIntervalSince1970
        if !force && now - last < 5 * 60 { return }
        UserDefaults.standard.set(now, forKey: lastAutoCheckKey)
        // 静默刷新后端版本
        self.serverVersion = await UpdateChecker.fetchServerVersion()
        let r = await UpdateChecker.checkAppUpdate()
        // 每次启动都拿结果：有新版提示，无新版/失败不打扰
        if case .updateAvailable(let current, let latest, let releaseURL, let ipaURL) = r {
            self.result = r
            if let url = ipaURL {
                scheduleAutoDownload(latest: latest, ipaURL: url)
            }
        }
    }

    // MARK: - 自动下载

    /// 发现新版本后立即自动下载（后台静默，IPA 仅 ~2MB，不抢首屏带宽，
    /// 无需再做闲时延迟）：
    ///
    /// 1. 本地已有完整安装包（上次会话下好的）→ 直接进入「点此安装」，零等待；
    /// 2. 用户明确取消过该版本的下载 → 不再自动下载（尊重用户意图）；
    /// 3. 否则立刻后台静默下载（自动换源，NAS 优先）。
    func scheduleAutoDownload(latest: String, ipaURL: URL) {
        // 1. 本地已有完整包：直接复用，免重新下载
        if let existing = IPAFileDownloader.existingDownload(version: latest) {
            currentDownloadVersion = latest
            IPAFileDownloader.cleanStaleDownloads(keeping: latest)
            downloadState = .downloaded(fileURL: existing)
            return
        }
        // 2. 该版本被用户取消过自动下载
        let cancelled = UserDefaults.standard.string(forKey: Self.cancelledAutoDownloadKey)
        if cancelled == latest { return }
        // 内存态已在下载/已下载就不重复安排
        if case .downloading = downloadState { return }
        if case .downloaded = downloadState { return }

        startDownload(latest: latest, ipaURL: ipaURL)
    }

    // MARK: - IPA 下载（App 内下载 → 系统面板交给 TrollStore）

    /// App 内下载 IPA：按候选顺序尝试（自有域名 → 后端反代 → GitHub），自动换源；
    /// 同一源内网络中断优先**断点续传**（resumeData，跨启动也能续），反复失败才换源。
    ///
    /// 下载与 TrollStore 解耦：TrollStore 下载器无法换源、失败无提示，
    /// 由 App 自己下载可以把进度、续传、重试、换源都做进 UI 里。
    func startDownload(latest: String, ipaURL: URL) {
        cancelDownload(rememberCancel: false)
        // 用户主动发起（或闲时任务启动）即清除该版本的取消记忆
        UserDefaults.standard.removeObject(forKey: Self.cancelledAutoDownloadKey)
        currentDownloadVersion = latest
        IPAFileDownloader.cleanStaleDownloads(keeping: latest)
        downloadState = .downloading(received: 0, total: nil)

        let candidates = UpdateChecker.downloadCandidates(ipaURL: ipaURL, version: latest)
        let destination = IPAFileDownloader.destinationURL(version: latest)
        // 上次（可能是上个启动会话）留下的断点：仅当源一致才能续传
        let savedResume = IPAFileDownloader.loadResumeData(version: latest)
        let downloader = IPAFileDownloader { received, total in
            // 进度回调来自 URLSession 委托队列，跳回主线程刷新状态
            Task { @MainActor [weak self] in
                guard let self, !Task.isCancelled else { return }
                if case .downloading = self.downloadState {
                    self.downloadState = .downloading(received: received, total: total)
                }
            }
        }
        self.downloader = downloader

        downloadTaskRef = Task { [weak self] in
            var lastError: Error = IPAFileDownloader.DownloadError(message: "未知错误", resumeData: nil)
            for candidate in candidates {
                if Task.isCancelled { return }
                var resumeData: Data?
                if let saved = savedResume, saved.sourceURL == candidate {
                    resumeData = saved.data   // 跨启动续传
                }
                // 单个源最多 5 次尝试：1 次全新（或跨启动续传）+ 至多 4 次会话内续传重试
                var attempts = 0
                while attempts < 5 {
                    attempts += 1
                    if Task.isCancelled { return }
                    do {
                        let fileURL = try await downloader.download(from: candidate, to: destination, resumeData: resumeData)
                        guard !Task.isCancelled else { return }
                        IPAFileDownloader.clearResumeData(version: latest)
                        self?.downloadState = .downloaded(fileURL: fileURL)
                        return
                    } catch {
                        // 任务被取消时 URLSession 报的是 NSURLErrorCancelled（非 CancellationError），
                        // 统一靠 Task.isCancelled 识别，避免取消后被当成普通失败换源续传。
                        if Task.isCancelled { return }
                        lastError = error
                        // 有断点数据 → 落盘（下次启动也能续）并原地续传重试
                        if let de = error as? IPAFileDownloader.DownloadError,
                           let rd = de.resumeData, !rd.isEmpty {
                            resumeData = rd
                            IPAFileDownloader.saveResumeData(rd, sourceURL: candidate, version: latest)
                            continue
                        }
                        // 无断点（HTTP 错误页 / 内容不合法）：清掉残留断点，换下一个源
                        IPAFileDownloader.clearResumeData(version: latest)
                        break
                    }
                }
            }
            guard !Task.isCancelled else { return }
            self?.downloadState = .failed(
                message: "\(lastError.localizedDescription)（已尝试全部 \(candidates.count) 个下载源）")
        }
    }

    /// 取消下载（下载完成后调用即回到待下载状态）。
    ///
    /// 若取消的是进行中的下载且 rememberCancel 为真，会记住版本号：
    /// 自动下载不再对该版本重启，直到用户下次手动点「下载并安装」才清除。
    /// 内部重置（检查更新 / 重新下载前的清理）传 false，避免误记用户意图。
    func cancelDownload(rememberCancel: Bool = true) {
        downloadTaskRef?.cancel()
        downloadTaskRef = nil
        downloader?.cancel()
        downloader = nil
        if case .downloading = downloadState {
            if rememberCancel, let version = currentDownloadVersion {
                UserDefaults.standard.set(version, forKey: Self.cancelledAutoDownloadKey)
            }
            downloadState = .idle
        }
    }
}
