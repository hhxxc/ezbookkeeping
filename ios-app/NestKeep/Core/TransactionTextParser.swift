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
            if envelope.success {
                return await applyCategoryHints(envelope.result ?? [], text: text)
            }
            throw APIError.server(code: envelope.errorCode ?? -1,
                                  message: envelope.errorMessage ?? "解析失败")
        }
        // 兼容旧版只返回单对象
        if let envelope = try? decoder.decode(APIEnvelope<ReceiptRecognizer.Recognized>.self, from: data) {
            if envelope.success, let one = envelope.result {
                return await applyCategoryHints([one], text: text)
            }
            throw APIError.server(code: envelope.errorCode ?? -1,
                                  message: envelope.errorMessage ?? "解析失败")
        }
        throw APIError.invalidResponse
    }

    /// 口语关键词 → 分类校正：LLM 对特定口语词的归类不稳定（如提到「婴儿」可能被
    /// 归到购物/日用品），命中关键词时强制归到指定名称的分类。
    /// 按用户实际分类名包含匹配（含子分类）；目标分类不存在或已在该分类则不动。
    /// 只校正支出（收入/转账的语义不同，避免误伤）。
    private static let keywordCategoryHints: [(keywords: [String], categoryName: String)] = [
        (keywords: ["婴儿"], categoryName: "育儿"),
    ]

    private static func applyCategoryHints(
        _ results: [ReceiptRecognizer.Recognized], text: String
    ) async -> [ReceiptRecognizer.Recognized] {
        // 文本未命中任何关键词直接返回，不查分类列表
        guard keywordCategoryHints.contains(where: { hint in
            hint.keywords.contains { text.contains($0) }
        }) else { return results }

        let categories = (try? await AppDataStore.shared.getCategories()) ?? []
        var flat: [(id: String, name: String)] = []
        for c in categories {
            flat.append((c.id, c.name))
            for sub in c.subCategories ?? [] { flat.append((sub.id, sub.name)) }
        }

        var mapped = results
        for (idx, var item) in mapped.enumerated() where item.transactionType == .expense {
            for hint in keywordCategoryHints where hint.keywords.contains(where: { text.contains($0) }) {
                // 已在目标分类（含子分类名带目标词的）则不动
                if let current = flat.first(where: { $0.id == item.categoryId }),
                   current.name.contains(hint.categoryName) { continue }
                guard let target = flat.first(where: { $0.name.contains(hint.categoryName) }) else { continue }
                item.categoryId = target.id
                mapped[idx] = item
            }
        }
        return mapped
    }
}
