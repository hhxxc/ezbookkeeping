import Foundation
import Combine

/// 全局设置：服务器地址（可离线修改，类似 Web 壳的诊断页设置），持久化到 UserDefaults
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var serverURL: URL

    private let serverKey = "nestkeep.serverURL"

    init() {
        if let saved = UserDefaults.standard.string(forKey: serverKey),
           let url = URL(string: saved), url.scheme == "http" || url.scheme == "https" {
            self.serverURL = url
        } else {
            // 默认外网入口（ddnsto 隧道）
            self.serverURL = URL(string: "https://example-server.invalid")!
        }
    }

    @MainActor
    func setServerURL(_ string: String) {
        guard let url = URL(string: string.trimmingCharacters(in: .whitespaces)),
              url.scheme == "http" || url.scheme == "https" else { return }
        serverURL = url
        UserDefaults.standard.set(url.absoluteString, forKey: serverKey)
    }
}
