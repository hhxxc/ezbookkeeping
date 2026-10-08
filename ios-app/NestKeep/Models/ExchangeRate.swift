import Foundation

/// 汇率数据（对应 Go `LatestExchangeRateResponse`）
struct LatestExchangeRateResponse: Codable {
    let dataSource: String?
    let referenceUrl: String?
    let updateTime: Int64?
    let baseCurrency: String?
    let exchangeRates: [LatestExchangeRate]?
}

/// 单条汇率（rate 为字符串，避免浮点精度丢失）
struct LatestExchangeRate: Codable, Identifiable {
    let currency: String
    let rate: String

    var id: String { currency }
    /// 展示用数值（1 基准货币 = rate 该货币）
    var rateValue: Double { Double(rate) ?? 0 }
}

/// 自定义汇率更新请求（对应 Go `UserCustomExchangeRateUpdateRequest`）
/// - currency: 3 位货币代码
/// - rate: 字符串（后端按字符串接收）
struct UserCustomExchangeRateUpdateRequest: Codable {
    let currency: String
    let rate: String
}

/// 自定义汇率删除请求
struct UserCustomExchangeRateDeleteRequest: Codable {
    let currency: String
}

/// 自定义汇率更新响应（对应 Go `UserCustomExchangeRateUpdateResponse`）
struct UserCustomExchangeRateUpdateResponse: Codable {
    let currency: String?
    let rate: String?
    let updateTime: Int64?
}
