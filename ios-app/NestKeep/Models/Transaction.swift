import Foundation

/// 交易类型（对应 Go TransactionType）
enum TransactionType: Int, Codable, Hashable {
    case modifyBalance = 1
    case income = 2
    case expense = 3
    case transfer = 4
}

/// 交易内嵌的账号摘要（对应 Go AccountInfoResponse 的常用字段）
struct TransactionAccountBrief: Codable, Hashable {
    let id: String?
    let name: String?
    let currency: String?
}

/// 交易内嵌的分类摘要（对应 Go TransactionCategoryInfoResponse 的常用字段）
struct TransactionCategoryBrief: Codable, Hashable {
    let id: String?
    let name: String?
}

/// 单条交易（对应 Go TransactionInfoResponse）。金额 sourceAmount/destinationAmount 为 Int64 分，time 为 Unix 秒
struct Transaction: Codable, Identifiable {
    let id: String
    let type: Int
    let categoryId: String?
    let category: TransactionCategoryBrief?
    let time: Int64
    let utcOffset: Int?
    let sourceAccountId: String?
    let sourceAccount: TransactionAccountBrief?
    let destinationAccountId: String?
    let destinationAccount: TransactionAccountBrief?
    let sourceAmount: Int64
    let destinationAmount: Int64?
    let hideAmount: Bool?
    let tagIds: [String]?
    let comment: String?
    let editable: Bool?

    var transactionType: TransactionType { TransactionType(rawValue: type) ?? .expense }
    var date: Date { Date(timeIntervalSince1970: TimeInterval(time)) }
    /// 分类名（无分类时回退）
    var categoryName: String? { category?.name }
    /// 币种（优先取源账户币种）
    var currency: String? { sourceAccount?.currency }
    /// 分 -> 元
    var decimalSourceAmount: Decimal { Decimal(sourceAmount) / 100 }
    var decimalDestinationAmount: Decimal? {
        guard let v = destinationAmount else { return nil }
        return Decimal(v) / 100
    }
}

/// 交易列表分页包装（对应 Go TransactionInfoPageWrapperResponse）
struct TransactionPage: Codable {
    let items: [Transaction]
    let nextTimeSequenceId: String?
    let totalCount: Int?
}
