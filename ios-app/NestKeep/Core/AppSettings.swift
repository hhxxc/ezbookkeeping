import Foundation
import Combine

/// 全局设置：服务器地址（可离线修改，类似 Web 壳的诊断页设置），持久化到 UserDefaults
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var serverURL: URL

    private let serverKey = "nestkeep.serverURL"

    /// 历史遗留的占位/本地测试地址的 host。
    /// 命中即丢弃本地保存值、回落到构建期注入的默认入口——避免用户很久以前手填过
    /// 一次测试地址后被 UserDefaults 长期"锁死"，明明换了正式包还是连旧地址上。
    ///
    /// 只列绝不该出现在生产配置里的几项；**局域网地址（192.168./10./172.16-31）
    /// 故意不列**——用户完全可能真在用内网直连，不能一刀切清掉。
    private static let placeholderHosts: Set<String> = [
        "example-server.invalid",
        "localhost",
        "127.0.0.1",
        "0.0.0.0",
    ]

    init() {
        let saved = UserDefaults.standard.string(forKey: serverKey)

        func isPlaceholder(_ url: URL) -> Bool {
            guard let host = url.host?.lowercased(), !host.isEmpty else { return true }
            return Self.placeholderHosts.contains(host)
        }

        if let saved, let url = Self.normalizeServerURL(saved), !isPlaceholder(url) {
            // 顺手修复历史脏数据（如 "https://https://..."）
            self.serverURL = url
            if url.absoluteString != saved {
                UserDefaults.standard.set(url.absoluteString, forKey: serverKey)
            }
        } else if let saved,
                  let rescued = Self.normalizeServerURL(Self.stripNonASCII(saved)),
                  !isPlaceholder(rescued) {
            // 抢救：粘贴带入的全角符号/中文标点等非 ASCII 脏字符剥掉后地址可用，
            // 直接自动修复并写回（2026-10-20 实例：地址尾部粘了全角 ），
            // 所有请求 DNS 解析失败，而检查更新页因 GitHub 源兜底显示「已是最新」，
            // 极具迷惑性，排查成本很高）
            self.serverURL = rescued
            UserDefaults.standard.set(rescued.absoluteString, forKey: serverKey)
        } else {
            // 本地存的是占位符/测试地址，或根本没存过 → 清掉脏值，用默认外网入口
            if saved != nil {
                UserDefaults.standard.removeObject(forKey: serverKey)
            }
            self.serverURL = URL(string: "https://example-server.invalid")!
        }
    }

    @MainActor
    func setServerURL(_ string: String) {
        guard let url = Self.normalizeServerURL(string) else { return }
        serverURL = url
        UserDefaults.standard.set(url.absoluteString, forKey: serverKey)
    }

    /// 归一化用户输入的服务器地址：
    /// - 去首尾空白
    /// - 重复 scheme（如 "https://https://x"）折叠为一个
    /// - 无 scheme 时自动补 "https://"
    /// - 必须能解析出 host 才接受
    static func normalizeServerURL(_ raw: String) -> URL? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        // 折叠重复 scheme：只要开头连续出现 http(s):// 就剥到只剩一个
        while true {
            let lower = s.lowercased()
            if lower.hasPrefix("https://https://") {
                s = String(s.dropFirst("https://".count))
            } else if lower.hasPrefix("http://http://") {
                s = String(s.dropFirst("http://".count))
            } else {
                break
            }
        }
        if !s.lowercased().hasPrefix("http://") && !s.lowercased().hasPrefix("https://") {
            s = "https://" + s
        }
        // 强制 HTTPS：用户填 http:// 时统一升级为 https://。
        // 明文 HTTP 会被 ATS 拦截（Info.plist 未开 NSAllowsArbitraryLoads），
        // 与其请求必然失败，不如在入口处直接升级，避免用户困惑。
        if s.lowercased().hasPrefix("http://") {
            s = "https://" + s.dropFirst("http://".count)
        }
        // 服务器地址必须是纯 ASCII：URL(string:) 对 host 里的全角括号/中文标点等
        // 脏字符会 percent-encode 后放行（host 非空、校验全过、absoluteString 也
        // 变成纯 ASCII），但 DNS 永远解析不出来（hostname could not be found）。
        // 因此必须校验归一化后的原始串 s（而非 url.absoluteString），在入口处拒绝，
        // 避免存进一个永远连不上的地址
        guard s.unicodeScalars.allSatisfy(\.isASCII) else { return nil }
        guard let url = URL(string: s), let host = url.host, !host.isEmpty else { return nil }
        return url
    }

    /// 剥掉字符串里的非 ASCII 字符（用于抢救粘贴带入脏字符的历史地址）
    private static func stripNonASCII(_ s: String) -> String {
        String(s.filter { $0.isASCII })
    }
}
