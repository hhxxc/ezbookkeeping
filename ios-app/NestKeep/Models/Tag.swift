import Foundation

/// 交易标签（对应 Go TransactionTagInfoResponse）
struct TransactionTag: Codable, Identifiable {
    let id: String
    let name: String
    let groupId: String?
    let displayOrder: Int?
    let hidden: Bool?
}
