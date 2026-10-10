import Foundation

/// 语音/文字记账：把口述文字交给后端 LLM 解析成可落库的交易草稿。
///
/// 接口：`POST /api/v1/llm/transactions/parse_text.json`（与识图同一开关门控）
/// - JSON body：`{"text": "..."}`
/// - 返回 `RecognizedReceiptImageResponse[]`，结构与识图完全一致，直接复用
///   `ReceiptRecognizer.Recognized` 与识图的确认/落库流程
enum TransactionTextParser {

    /// 解析口述文字。失败时抛 `APIError`（含后端中文错误信息，如「没有识别到交易信息」）。
    static func parse(_ text: String) async throws -> [ReceiptRecognizer.Recognized] {
        let url = AppSettings.shared.serverURL.appendingPathComponent("/api/v1/llm/transactions/parse_text.json")

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = AuthManager.shared.token {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let tz = TimeZone.current
        req.setValue("\(tz.secondsFromGMT() / 60)", forHTTPHeaderField: "X-Timezone-Offset")
        req.setValue(tz.identifier, forHTTPHeaderField: "X-Timezone-Name")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["text": text], options: [])

        // LLM 解析较慢，放宽超时（口径同 ReceiptRecognizer）。
        // 注意：服务端主模型 + 3 个 fallback 轮换、每模型 30s，最坏 ~120s 才返回错误，
        // 客户端超时必须大于服务端最坏耗时，否则会先在客户端报 "The request timed out."
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 200
        config.timeoutIntervalForResource = 300
        let session = URLSession(configuration: config)
        let (data, _) = try await session.data(for: req)

        let decoder = JSONDecoder()
        if let envelope = try? decoder.decode(APIEnvelope<[ReceiptRecognizer.Recognized]>.self, from: data) {
            if envelope.success { return envelope.result ?? [] }
            throw APIError.server(code: envelope.errorCode ?? -1,
                                  message: envelope.errorMessage ?? "解析失败")
        }
        // 兼容旧版只返回单对象
        if let envelope = try? decoder.decode(APIEnvelope<ReceiptRecognizer.Recognized>.self, from: data) {
            if envelope.success, let one = envelope.result { return [one] }
            throw APIError.server(code: envelope.errorCode ?? -1,
                                  message: envelope.errorMessage ?? "解析失败")
        }
        throw APIError.invalidResponse
    }
}
