import Foundation

/// 分期计划（对应 Go TransactionInstallmentPlanInfoResponse）。
/// 创建时一次性生成全部期次交易；paidPeriods = 交易时间已过的期数。
struct InstallmentPlan: Codable, Identifiable {
    let id: String
    let name: String
    let type: Int
    let categoryId: String
    let sourceAccountId: String
    let periodAmount: Int64
    let lastPeriodAmount: Int64
    let totalAmount: Int64
    let totalPeriods: Int
    let paidPeriods: Int
    let startTime: Int64
    let endTime: Int64
    let nextTime: Int64?
    let hideAmount: Bool?
    let tagIds: [String]?
    let comment: String?

    var transactionType: TransactionType { TransactionType(rawValue: type) ?? .expense }
    var startDate: Date { Date(timeIntervalSince1970: TimeInterval(startTime)) }
    var endDate: Date { Date(timeIntervalSince1970: TimeInterval(endTime)) }
    /// 下一期待入账时间
    var nextDate: Date? { nextTime.map { Date(timeIntervalSince1970: TimeInterval($0)) } }
    var isFinished: Bool { paidPeriods >= totalPeriods }
}

/// GET /transactions/installments/get.json 的返回（计划 + 全部期次交易）
struct InstallmentPlanDetail: Codable {
    let plan: InstallmentPlan
    let transactions: [Transaction]
}

/// POST /transactions/installments/add.json 的请求体。
/// sourceAmount 为全部期次总金额（分），后端均摊（余数放最后一期）。
struct InstallmentCreateRequest: Codable {
    let name: String
    let type: Int
    let categoryId: String
    let time: Int64
    let utcOffset: Int
    let sourceAccountId: String
    let sourceAmount: Int64
    let totalPeriods: Int
    let hideAmount: Bool
    let tagIds: [String]
    let comment: String
}

/// POST /transactions/installments/delete.json 的请求体。
/// deleteTransactions = 是否连同全部期次交易一起删除（false = 仅删计划，保留交易记录）
struct InstallmentDeleteRequest: Codable {
    let id: String
    let deleteTransactions: Bool
}
