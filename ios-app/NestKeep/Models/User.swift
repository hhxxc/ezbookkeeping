import Foundation

/// 对外用户信息视图（对应 Go UserBasicInfo）。
/// 仅保留 MVP 需要且类型确定安全的字段；其余格式化/枚举字段（如 fiscalYearFormat、
/// decimalSeparator 等后端以「数字」序列化）暂不解码，避免类型不匹配导致整个登录响应解析失败。
struct UserBasicInfo: Codable {
    let username: String?
    let email: String?
    let nickname: String?
    let avatar: String?
    let defaultAccountId: String?
    let language: String?
    let defaultCurrency: String?
    let emailVerified: Bool?

    var displayName: String { nickname ?? username ?? "用户" }
}
