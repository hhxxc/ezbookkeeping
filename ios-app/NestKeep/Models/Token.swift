import Foundation

/// 会话 / 令牌信息（对应 Go TokenInfoResponse）
struct TokenInfo: Codable, Identifiable {
    let tokenId: String
    let tokenType: Int
    let userAgent: String?
    let lastSeen: Int64
    let isCurrent: Bool

    var id: String { tokenId }
}

/// POST /tokens/revoke.json 请求体
struct TokenRevokeRequest: Codable {
    let tokenId: String
}
