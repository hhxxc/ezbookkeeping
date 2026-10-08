import Foundation

// MARK: - 分类写操作请求体（对应 Go TransactionCategory*Request）

/// 新增分类
struct CategoryCreateRequest: Codable {
    let name: String
    let type: Int
    let parentId: String
    let icon: String
    let color: String
    let comment: String
    let clientSessionId: String

    init(name: String, type: Int, parentId: String = "0", icon: String,
         color: String, comment: String = "") {
        self.name = name
        self.type = type
        self.parentId = parentId
        self.icon = icon
        self.color = color
        self.comment = comment
        self.clientSessionId = UUID().uuidString
    }
}

/// 修改分类
struct CategoryModifyRequest: Codable {
    let id: String
    let name: String
    let parentId: String
    let icon: String
    let color: String
    let comment: String
    let hidden: Bool
}

/// 分类删除 / 显隐
struct CategoryIdRequest: Codable { let id: String }
struct CategoryHideRequest: Codable { let id: String; let hidden: Bool }

/// 分类图标候选（后端 icon 为图标字体编号，原生用 SF Symbols 近似映射）
enum CategoryIconCatalog {
    static let options: [(Int, String)] = [
        (1, "fork.knife"), (2, "cart"), (3, "bus"), (4, "house"),
        (5, "bag"), (6, "cross.case"), (7, "book"), (8, "gamecontroller"),
        (9, "phone"), (10, "bolt"), (11, "gift"), (12, "pawprint"),
        (13, "airplane"), (14, "tshirt"), (15, "cup.and.saucer"),
        (16, "banknote"), (17, "chart.line.uptrend.xyaxis"), (18, "wrench.and.screwdriver"),
        (19, "heart"), (20, "graduationcap")
    ]

    static func symbol(_ icon: String?) -> String {
        guard let n = Int(icon ?? "") else { return "tag" }
        return options.first { $0.0 == n }?.1 ?? "tag"
    }
}
