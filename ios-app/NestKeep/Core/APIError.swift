import Foundation

/// 统一的客户端错误模型，对应后端 { success:false, errorCode, errorMessage }
enum APIError: LocalizedError {
    case notAuthenticated
    case server(code: Int, message: String)
    case decoding(Error)
    case invalidResponse
    case twoFactorRequired
    case invalidURL
    /// HTTP 状态码异常且解不出后端信封（如隧道/反代返回 502、纯文本 500 等）
    case http(status: Int)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "未登录或登录已过期，请重新登录"
        case .server(_, let message):
            return message
        case .decoding(let e):
            return "数据解析失败：\(e.localizedDescription)"
        case .invalidResponse:
            return "服务器响应异常"
        case .twoFactorRequired:
            return "该账号开启了两步验证，请继续完成验证"
        case .invalidURL:
            return "请求地址无效"
        case .http(let status):
            return status == 401 ? "登录状态已失效，请重新登录" : "服务器错误（HTTP \(status)）"
        }
    }
}
