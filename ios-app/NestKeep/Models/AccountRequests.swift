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

/// 账户排序（`POST /api/v1/accounts/move.json`，对齐 Web 拖拽排序）
struct AccountMoveRequest: Codable {
    let newDisplayOrders: [AccountNewDisplayOrderRequest]
}
struct AccountNewDisplayOrderRequest: Codable {
    let id: String
    let displayOrder: Int
}

/// 移动某账户下的全部账单到另一账户。
/// `POST /api/v1/transactions/move/all.json`，两个 id 均为 `json:",string"`。
struct MoveAllTransactionsRequest: Codable {
    let fromAccountId: String
    let toAccountId: String
}

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

/// 账户图标映射（后端 icon 为图标字体编号，与 Web `src/consts/icon.ts` ALL_ACCOUNT_ICONS 同一编号体系：
/// 1~99 现金、100~199 银行、500~999 其他、1000+ 货币、5000+ 卡品牌、8000+ 支付品牌。
/// SF Symbols 取 iOS 15 可用的近似图形）。
enum AccountIconCatalog {
    /// 全量编号 -> SF Symbol（未知编号回退 "wallet.pass"）
    private static let map: [Int: String] = [
        // 现金类
        1: "wallet.pass", 10: "dollarsign.circle", 20: "banknote", 30: "banknote.fill",
        // 银行类
        100: "creditcard", 110: "doc.text",
        // 其他
        500: "gauge", 510: "ticket", 520: "envelope", 530: "shippingbox", 540: "hand.thumbsup",
        560: "shield", 600: "calendar.badge.minus", 601: "calendar.badge.plus",
        700: "doc.text.fill", 701: "receipt", 800: "chart.bar.fill", 801: "chart.line.uptrend.xyaxis",
        900: "person.2", 901: "person.3", 910: "house", 911: "building.2", 912: "building.2.fill", 990: "globe",
        // 货币
        1000: "dollarsign.circle", 1001: "eurosign.circle", 1002: "sterlingsign.circle",
        1003: "yensign.circle", 1004: "rublesign.circle", 1005: "rupeesign.circle",
        1006: "wonsign.circle", 1007: "shekelsign.circle", 1008: "banknote", 1009: "banknote",
        1500: "bitcoinsign.circle", 1501: "hexagon",
        // 卡品牌
        5000: "creditcard", 5001: "creditcard.fill", 5002: "creditcard", 5100: "creditcard.fill",
        5200: "creditcard", 5300: "creditcard.fill",
        // 支付品牌
        8000: "globe", 8100: "applelogo", 8101: "wallet.pass.fill", 8200: "cart", 8201: "creditcard",
        8300: "character.textbox", 8301: "message", 8302: "message.fill", 8303: "bubble.left",
        // 旧原生版自造编号（1~15，Web 无此编号）按旧含义保留别名，避免已建账户图标突变
        2: "wallet.pass", 3: "creditcard", 4: "cpu", 5: "exclamationmark.circle",
        6: "person.2", 7: "chart.line.uptrend.xyaxis", 8: "banknote.fill",
        9: "doc.text", 11: "cart", 12: "gift", 13: "house", 14: "car", 15: "airplane"
    ]

    /// 新建/编辑账户时的可选图标（真实编号，对齐 Web 语义）
    static let options: [(Int, String, String)] = [
        (1, "wallet.pass", "钱包"),
        (20, "banknote", "现金"),
        (30, "banknote.fill", "储蓄"),
        (100, "creditcard", "银行卡"),
        (110, "doc.text", "支票"),
        (510, "ticket", "票券"),
        (530, "shippingbox", "储物"),
        (560, "shield", "保障"),
        (600, "calendar.badge.minus", "负债"),
        (601, "calendar.badge.plus", "应收"),
        (701, "receipt", "收据"),
        (801, "chart.line.uptrend.xyaxis", "投资"),
        (900, "person.2", "人情"),
        (910, "house", "房产"),
        (990, "globe", "全球"),
        (1000, "dollarsign.circle", "美元"),
        (1001, "eurosign.circle", "欧元"),
        (1002, "sterlingsign.circle", "英镑"),
        (1003, "yensign.circle", "日元"),
        (1500, "bitcoinsign.circle", "比特币"),
        (5000, "creditcard", "Visa"),
        (5001, "creditcard.fill", "万事达"),
        (8100, "applelogo", "Apple Pay"),
        (8300, "character.textbox", "支付宝"),
        (8302, "message.fill", "微信")
    ]

    static func symbol(_ icon: String?) -> String {
        guard let n = Int(icon ?? "") else { return "wallet.pass" }
        return map[n] ?? "wallet.pass"
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
