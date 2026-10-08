import Foundation

// MARK: - 账户写操作请求体（对应 Go AccountCreateRequest / AccountModifyRequest）

/// 新增账户。`icon` 后端为 `json:",string"` → 字符串。
struct AccountCreateRequest: Codable {
    let name: String
    let category: Int
    let type: Int
    let icon: String
    let color: String
    let currency: String
    let balance: Int64
    let balanceTime: Int64
    let comment: String
    let creditCardStatementDate: Int
    let clientSessionId: String

    init(name: String, category: Int, type: Int = AccountType.single.rawValue,
         icon: String, color: String, currency: String,
         balance: Int64 = 0, balanceTime: Int64 = 0,
         comment: String = "", creditCardStatementDate: Int = 0) {
        self.name = name
        self.category = category
        self.type = type
        self.icon = icon
        self.color = color
        self.currency = currency
        self.balance = balance
        self.balanceTime = balanceTime
        self.comment = comment
        self.creditCardStatementDate = creditCardStatementDate
        self.clientSessionId = UUID().uuidString
    }
}

/// 修改账户。`id` 为 `json:",string"`；currency/balance/balanceTime 可空（不修改则不传）。
struct AccountModifyRequest: Codable {
    let id: String
    let name: String
    let category: Int
    let icon: String
    let color: String
    let currency: String?
    let balance: Int64?
    let balanceTime: Int64?
    let comment: String
    let creditCardStatementDate: Int
    let hidden: Bool
    let clientSessionId: String

    init(id: String, name: String, category: Int, icon: String, color: String,
         currency: String?, balance: Int64?, balanceTime: Int64?,
         comment: String, creditCardStatementDate: Int, hidden: Bool) {
        self.id = id
        self.name = name
        self.category = category
        self.icon = icon
        self.color = color
        self.currency = currency
        self.balance = balance
        self.balanceTime = balanceTime
        self.comment = comment
        self.creditCardStatementDate = creditCardStatementDate
        self.hidden = hidden
        self.clientSessionId = UUID().uuidString
    }
}

/// 账户删除 / 隐藏
struct AccountIdRequest: Codable { let id: String }
struct AccountHideRequest: Codable { let id: String; let hidden: Bool }

/// 账户类型（对应 Go AccountType）
enum AccountType: Int {
    case single = 1              // 单账户
    case multiSubAccounts = 2    // 多子账户
}

/// 账户类别常量（对应 Go AccountCategory，1~9）
enum AccountCategoryConst {
    static let all: [(Int, String)] = [
        (1, "现金"),
        (2, "储蓄账户"),
        (3, "信用卡"),
        (4, "虚拟账户"),
        (5, "债务"),
        (6, "应收款"),
        (7, "投资"),
        (8, "储蓄"),
        (9, "定期存单")
    ]

    /// 该类别是否计入资产（用于净资产汇总，对应后端 IsAsset）
    static func isAsset(_ category: Int) -> Bool {
        [1, 2, 4, 6, 7, 8, 9].contains(category)
    }

    /// 该类别是否计入负债
    static func isLiability(_ category: Int) -> Bool {
        [3, 5].contains(category)
    }

    static func name(_ category: Int) -> String {
        all.first { $0.0 == category }?.1 ?? "其他"
    }
}

/// 账户可选的图标编号（后端 icon 是图标字体编号 1~n，原生用 SF Symbols 近似映射）
enum AccountIconCatalog {
    /// 可选图标（编号 -> SF Symbol）
    static let options: [(Int, String, String)] = [
        (1, "banknote", "现金"),
        (2, "wallet.pass", "钱包"),
        (3, "creditcard", "银行卡"),
        (4, "cpu", "虚拟"),
        (5, "exclamationmark.circle", "债务"),
        (6, "person.2", "应收"),
        (7, "chart.line.uptrend.xyaxis", "投资"),
        (8, "piggybank", "储蓄"),
        (9, "doc.text", "存单"),
        (10, "building.columns", "银行"),
        (11, "cart", "消费"),
        (12, "gift", "红包"),
        (13, "house", "住房"),
        (14, "car", "交通"),
        (15, "airplane", "旅行")
    ]

    static func symbol(_ icon: String?) -> String {
        guard let n = Int(icon ?? "") else { return "wallet.pass" }
        return options.first { $0.0 == n }?.1 ?? "wallet.pass"
    }
}

/// 常用颜色板（对应 Web 的账户颜色选择）
enum AccountColorCatalog {
    static let all: [String] = [
        "26A69A", "4DB6AC", "66BB6A", "9CCC65", "FFCA28",
        "FFA726", "EF5350", "EC407A", "AB47BC", "7E57C2",
        "5C6BC0", "42A5F5", "29B6F6", "26C6DA", "78909C"
    ]
}
