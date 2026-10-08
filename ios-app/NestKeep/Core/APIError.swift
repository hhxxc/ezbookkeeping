import Foundation

/// 统一的客户端错误模型，对应后端 { success:false, errorCode, errorMessage }
enum APIError: LocalizedError {
    case notAuthenticated
    case server(code: Int, message: String)
    case decoding(Error)
    case invalidResponse
    case twoFactorRequired
    case invalidURL

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
            return "该账号开启了两步验证，当前版本暂不支持，请在网页端操作"
        case .invalidURL:
            return "请求地址无效"
        }
    }
}
