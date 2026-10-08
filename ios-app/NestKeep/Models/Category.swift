import Foundation

/// 分类类型（对应 Go TransactionCategoryType）
enum TransactionCategoryType: Int, Codable, Hashable {
    case income = 1
    case expense = 2
    case transfer = 3
}

/// 交易分类（对应 Go TransactionCategoryInfoResponse）
struct TransactionCategory: Codable, Identifiable {
    let id: String
    let name: String
    let parentId: String?
    let type: Int?
    let icon: String?
    let color: String?
    let comment: String?
    let displayOrder: Int?
    let hidden: Bool?
    let subCategories: [TransactionCategory]?
}
