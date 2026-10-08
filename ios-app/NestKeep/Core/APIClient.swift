import Foundation

enum HTTPMethod: String {
    case GET, POST, PUT, DELETE
}

/// 后端统一响应信封：{ success, result, errorCode, errorMessage, path }
struct APIEnvelope<T: Decodable>: Decodable {
    let success: Bool
    let result: T?
    let errorCode: Int?
    let errorMessage: String?
    let path: String?
}

/// 让任意 Encodable 可作为请求体
struct AnyEncodable: Encodable {
    private let encodeFunc: (Encoder) throws -> Void
    init(_ wrapped: Encodable) { self.encodeFunc = wrapped.encode }
    func encode(to encoder: Encoder) throws { try encodeFunc(encoder) }
}

/// 统一网络层：自动注入 JWT、时区头，解析统一信封
struct APIClient {
    static let shared = APIClient()
    private let session = URLSession.shared

    private var baseURL: URL { AppSettings.shared.serverURL }

    func request<T: Decodable>(
        _ path: String,
        method: HTTPMethod = .GET,
        query: [URLQueryItem] = [],
        body: Encodable? = nil
    ) async throws -> T {
        guard var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false) else {
            throw APIError.invalidURL
        }
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw APIError.invalidURL }

        var req = URLRequest(url: url)
        req.httpMethod = method.rawValue
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = AuthManager.shared.token {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        // 每个请求都带客户端时区（后端绝大多数接口依赖它解释交易时间/统计区间）
        let tz = TimeZone.current
        req.setValue("\(tz.secondsFromGMT() / 60)", forHTTPHeaderField: "X-Timezone-Offset")
        req.setValue(tz.identifier, forHTTPHeaderField: "X-Timezone-Name")

        if let body = body {
            req.httpBody = try JSONEncoder().encode(AnyEncodable(body))
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, _) = try await session.data(for: req)

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .useDefaultKeys

        guard let envelope = try? decoder.decode(APIEnvelope<T>.self, from: data) else {
            throw APIError.invalidResponse
        }
        if envelope.success, let result = envelope.result {
            return result
        }
        throw APIError.server(
            code: envelope.errorCode ?? -1,
            message: envelope.errorMessage ?? "请求失败"
        )
    }

    /// 请求并返回原始 `result`（可能是数组、false、字符串等），用于 result 类型不固定的接口
    /// （如 `users/settings/cloud/get.json` 可能返回 `false` 或数组）。
    func requestRaw(
        _ path: String,
        method: HTTPMethod = .GET,
        query: [URLQueryItem] = [],
        body: Encodable? = nil
    ) async throws -> Any? {
        guard var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false) else {
            throw APIError.invalidURL
        }
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw APIError.invalidURL }

        var req = URLRequest(url: url)
        req.httpMethod = method.rawValue
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = AuthManager.shared.token {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let tz = TimeZone.current
        req.setValue("\(tz.secondsFromGMT() / 60)", forHTTPHeaderField: "X-Timezone-Offset")
        req.setValue(tz.identifier, forHTTPHeaderField: "X-Timezone-Name")

        if let body = body {
            req.httpBody = try JSONEncoder().encode(AnyEncodable(body))
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, _) = try await session.data(for: req)
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.invalidResponse
        }
        let success = root["success"] as? Bool ?? false
        if !success {
            throw APIError.server(
                code: root["errorCode"] as? Int ?? -1,
                message: root["errorMessage"] as? String ?? "请求失败"
            )
        }
        // result 可能是 false / null
        return root["result"] ?? false
    }
}
