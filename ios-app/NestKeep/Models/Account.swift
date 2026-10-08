import Foundation

/// 账户分类枚举（对应 Go AccountCategory）
enum AccountCategory: Int, Codable {
    case cash = 1
    case checking = 2
    case creditCard = 3
    case virtual = 4
    case debt = 5
    case receivables = 6
    case investment = 7
    case savings = 8
    case certOfDeposit = 9
}

/// 账户（对应 Go AccountInfoResponse）。金额 balance 为 Int64 分
struct Account: Codable, Identifiable {
    let id: String
    let name: String
    let parentId: String?
    let category: Int?
    let type: Int?
    let icon: String?
    let color: String?
    let currency: String?
    let balance: Int64
    let comment: String?
    let creditCardStatementDate: Int?
    let displayOrder: Int?
    let isAsset: Bool?
    let isLiability: Bool?
    let hidden: Bool?
    let subAccounts: [Account]?

    /// 分 -> 元（Decimal 避免浮点误差）
    var decimalBalance: Decimal { Decimal(balance) / 100 }
}
