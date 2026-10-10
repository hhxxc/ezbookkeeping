import Foundation
import UIKit

/// AI 识图记账：把票据/截图交给后端 LLM 识别，返回可直接落库的交易草稿。
///
/// 接口：`POST /api/v1/llm/transactions/recognize_receipt_image.json`
/// - multipart/form-data，表单字段名固定为 **`image`**（注意不是 `picture`）
/// - 需后端开启 `TransactionFromAIImageRecognition` 且配置了识图 LLM，否则路由不注册（404）
/// - 返回 `RecognizedReceiptImageResponse[]`（新版为数组，旧版可能只返回单个对象，两者都兼容）
enum ReceiptRecognizer {

    /// 后端返回的单条识别结果。字段语义与 Go 侧同名结构体一致：
    /// type/time/categoryId/sourceAccountId/destinationAccountId/sourceAmount/destinationAmount/tagIds/comment
    struct Recognized: Codable, Identifiable {
        var id = UUID()
        let type: Int
        let time: Int64?
        /// 后端 `,string` 序列化为字符串
        let categoryId: String?
        let sourceAccountId: String?
        let destinationAccountId: String?
        /// 金额为 int64 分
        let sourceAmount: Int64?
        let destinationAmount: Int64?
        let tagIds: [String]?
        let comment: String?

        var transactionType: TransactionType { TransactionType(rawValue: type) ?? .expense }

        enum CodingKeys: String, CodingKey {
            case type, time, categoryId, sourceAccountId, destinationAccountId
            case sourceAmount, destinationAmount, tagIds, comment
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            type = (try? c.decode(Int.self, forKey: .type)) ?? TransactionType.expense.rawValue
            time = try? c.decode(Int64.self, forKey: .time)
            // 容错：后端可能给字符串或数字
            categoryId = Self.flexString(c, .categoryId)
            sourceAccountId = Self.flexString(c, .sourceAccountId)
            destinationAccountId = Self.flexString(c, .destinationAccountId)
            sourceAmount = Self.flexInt64(c, .sourceAmount)
            destinationAmount = Self.flexInt64(c, .destinationAmount)
            tagIds = try? c.decode([String].self, forKey: .tagIds)
            comment = try? c.decode(String.self, forKey: .comment)
        }

        init(type: Int, time: Int64?, categoryId: String?, sourceAccountId: String?,
             destinationAccountId: String?, sourceAmount: Int64?, destinationAmount: Int64?,
             tagIds: [String]?, comment: String?) {
            self.type = type; self.time = time; self.categoryId = categoryId
            self.sourceAccountId = sourceAccountId; self.destinationAccountId = destinationAccountId
            self.sourceAmount = sourceAmount; self.destinationAmount = destinationAmount
            self.tagIds = tagIds; self.comment = comment
        }

        private static func flexString(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> String? {
            if let s = try? c.decode(String.self, forKey: key) { return s.isEmpty ? nil : s }
            if let i = try? c.decode(Int64.self, forKey: key), i != 0 { return "\(i)" }
            return nil
        }

        private static func flexInt64(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Int64? {
            if let i = try? c.decode(Int64.self, forKey: key) { return i }
            if let s = try? c.decode(String.self, forKey: key) { return Int64(s) }
            return nil
        }
    }

    /// 上传图片并识别。失败时抛 `APIError`（含后端中文错误信息，如「图片中没有交易信息」）。
    static func recognize(imageData: Data, fileName: String = "receipt.jpg") async throws -> [Recognized] {
        let boundary = "----NestKeepAIBoundary\(UUID().uuidString)"
        let url = AppSettings.shared.serverURL.appendingPathComponent("/api/v1/llm/transactions/recognize_receipt_image.json")

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = AuthManager.shared.token {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let tz = TimeZone.current
        req.setValue("\(tz.secondsFromGMT() / 60)", forHTTPHeaderField: "X-Timezone-Offset")
        req.setValue(tz.identifier, forHTTPHeaderField: "X-Timezone-Name")

        var body = Data()
        let ext = (fileName as NSString).pathExtension.lowercased()
        let contentType = ext == "png" ? "image/png" : "image/jpeg"

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        // 字段名必须是 image（后端 form.File["image"]）
        body.append("Content-Disposition: form-data; name=\"image\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(contentType)\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        req.httpBody = body

        // 识图较慢，单独放宽超时（与 Web 的 DEFAULT_LLM_API_TIMEOUT 对齐）。
        // ⚠️ 必须用这个 config 建 session：URLSession.shared 不吃 configuration（默认 60s，
        // 之前一直用它导致 120s 配置形同虚设，弱网大图必超时）
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 200
        config.timeoutIntervalForResource = 300
        let session = URLSession(configuration: config)
        let (data, _) = try await session.data(for: req)

        let decoder = JSONDecoder()
        if let envelope = try? decoder.decode(APIEnvelope<[Recognized]>.self, from: data) {
            if envelope.success { return envelope.result ?? [] }
            throw APIError.server(code: envelope.errorCode ?? -1,
                                  message: envelope.errorMessage ?? "识别失败")
        }
        // 兼容旧版只返回单对象
        if let envelope = try? decoder.decode(APIEnvelope<Recognized>.self, from: data) {
            if envelope.success, let one = envelope.result { return [one] }
            throw APIError.server(code: envelope.errorCode ?? -1,
                                  message: envelope.errorMessage ?? "识别失败")
        }
        throw APIError.invalidResponse
    }
}
