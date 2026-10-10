import Foundation
import Combine

/// 全局设置：服务器地址（可离线修改，类似 Web 壳的诊断页设置），持久化到 UserDefaults
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var serverURL: URL

    private let serverKey = "nestkeep.serverURL"

    init() {
        if let saved = UserDefaults.standard.string(forKey: serverKey),
           let url = Self.normalizeServerURL(saved) {
            // 顺手修复历史脏数据（如 "https://https://..."）
            self.serverURL = url
            if url.absoluteString != saved {
                UserDefaults.standard.set(url.absoluteString, forKey: serverKey)
            }
        } else {
            // 默认外网入口（ddnsto 隧道）
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
        guard let url = URL(string: s), let host = url.host, !host.isEmpty else { return nil }
        return url
    }
}
