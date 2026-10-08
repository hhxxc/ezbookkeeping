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
}

/// 无返回体的成功响应占位
struct EmptyResult: Decodable {}
