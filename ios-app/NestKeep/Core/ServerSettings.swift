import Foundation
import Combine

/// 服务端能力探测。后端把「功能开关」以一段 JS 变量的形式下发：
///     GET {serverURL}/mobile/server_settings.js
///     window.EZBOOKKEEPING_SERVER_SETTINGS = window.EZBOOKKEEPING_SERVER_SETTINGS || {};
///     window.EZBOOKKEEPING_SERVER_SETTINGS["llmt"] = 1;
///     ...
/// 原生端不便执行 JS，改为直接抓取文本并按行解析 `["key"] = value;`。
/// 用途：控制「AI 识图」「图片上传」「数据导出」等入口是否展示，
/// 避免在未开启该能力的后端上出现点了就报 404 的死入口。
///
/// 注意：该接口**无鉴权**，可在登录前拉取；失败时按「全部关闭」兜底，
/// 不影响其余功能。
@MainActor
final class ServerSettings: ObservableObject {
    static let shared = ServerSettings()

    /// 是否开启「AI 识图记账」（对应后端 TransactionFromAIImageRecognition）
    @Published private(set) var enableImageRecognition = false
    /// 是否开启交易图片上传（对应 EnableTransactionPictures，背景图共用此开关）
    @Published private(set) var enableTransactionPictures = false
    /// 是否开启数据导出（对应 EnableDataExport）
    @Published private(set) var enableDataExport = false
    /// 是否开启数据导入（对应 EnableDataImport）
    @Published private(set) var enableDataImport = false
    /// 是否开启定时交易（对应 EnableScheduledTransaction）
    @Published private(set) var enableScheduledTransaction = false

    /// 原始键值对，便于后续扩展
    private(set) var raw: [String: String] = [:]

    private var loaded = false
    private var lastLoadedAt = Date.distantPast

    /// 拉取并解析服务端设置（成功后本会话内不再重复请求；失败不置 loaded，可重试）
    func loadIfNeeded(force: Bool = false) async {
        if loaded && !force { return }
        await fetchAndParse()
    }

    /// 前台/页面回显时的补拉：从未成功、解析结果为空（上次拉到空壳/失败）、
    /// 或距上次成功超过 10 分钟时重拉一次。用于冷启动拉取失败后自愈，
    /// 避免「AI 识图入口」等整个会话消失。
    func refreshIfNeeded() async {
        if !loaded || raw.isEmpty || Date().timeIntervalSince(lastLoadedAt) > 600 {
            await fetchAndParse()
        }
    }

    /// 最多重试 3 次（间隔 1s/2s），短超时（请求 8s / 资源 10s），
    /// 避免隧道未就绪时默认 60s 超时把启动流程拖死。
    private func fetchAndParse() async {
        let url = AppSettings.shared.serverURL.appendingPathComponent("/mobile/server_settings.js")
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 10
        let session = URLSession(configuration: config)
        defer { session.finishTasksAndInvalidate() }

        for attempt in 0..<3 {
            if let (data, resp) = try? await session.data(from: url),
               let http = resp as? HTTPURLResponse, http.statusCode == 200,
               let text = String(data: data, encoding: .utf8),
               text.contains("EZBOOKKEEPING_SERVER_SETTINGS") {
                parse(text)
                loaded = true
                lastLoadedAt = Date()
                return
            }
            if attempt < 2 {
                try? await Task.sleep(nanoseconds: UInt64(1_000_000_000 * (attempt + 1)))
            }
        }
    }

    /// 解析 `EZBOOKKEEPING_SERVER_SETTINGS['key']=value;` 形式的多行文本。
    /// 注意后端用的是**单引号**包裹键名（见 `appendEncodedString`）。
    private func parse(_ text: String) {
        var dict: [String: String] = [:]
        for line in text.split(separator: "\n") {
            guard let open = line.range(of: "['"),
                  let close = line.range(of: "']", range: open.upperBound..<line.endIndex),
                  let eq = line.range(of: "=", range: close.upperBound..<line.endIndex) else {
                continue
            }
            let key = String(line[open.upperBound..<close.lowerBound])
            // 取等号后到分号前的部分，去掉引号与空白
            var value = String(line[eq.upperBound..<line.endIndex])
            if let semi = value.firstIndex(of: ";") { value = String(value[..<semi]) }
            value = value.trimmingCharacters(in: .whitespacesAndNewlines)
            value = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            dict[key] = value
        }
        raw = dict
        enableImageRecognition = isOn("llmt")
        enableTransactionPictures = isOn("p")
        enableDataExport = isOn("e")
        enableDataImport = isOn("i")
        enableScheduledTransaction = isOn("s")
    }

    /// 后端布尔设置为 true 时下发 `1`
    private func isOn(_ key: String) -> Bool {
        raw[key] == "1" || raw[key]?.lowercased() == "true"
    }
}
