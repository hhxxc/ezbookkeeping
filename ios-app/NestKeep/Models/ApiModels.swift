import Foundation

// MARK: - 统计相关

struct AmountItem: Codable {
    let currency: String?
    let incomeAmount: Int64?
    let expenseAmount: Int64?
}

/// GET /transactions/amounts.json 的返回项
struct TransactionAmountsResponseItem: Codable {
    let startTime: Int64?
    let endTime: Int64?
    let amounts: [AmountItem]?
}

/// GET /transactions/list/by_month.json 的返回包装
struct TransactionPage2: Codable {
    let items: [Transaction]
    let totalCount: Int?
}

// MARK: - 写操作请求体

/// 地理位置（对应 Go TransactionGeoLocationRequest）
struct TransactionGeoLocation: Codable, Hashable {
    let latitude: Double
    let longitude: Double
}

/// POST /transactions/add.json 的请求体
struct TransactionCreateRequest: Codable {
    let type: Int
    let categoryId: String
    let time: Int64
    let utcOffset: Int
    let sourceAccountId: String
    let destinationAccountId: String?
    let sourceAmount: Int64
    let destinationAmount: Int64?
    let comment: String?
    let tagIds: [String]
    let pictureIds: [String]
    let geoLocation: TransactionGeoLocation?
    /// 幂等去重用的客户端会话 id（后端 EnableDuplicateSubmissionsCheck 时生效）
    let clientSessionId: String
    /// 交易来源（后端血缘标记，2026-10 起支持：ai_image / ai_speech，不传视为手动）
    var source: String? = nil
}

/// 无返回体的成功响应占位
struct EmptyResult: Decodable {}
