import Foundation

/// 对外用户信息视图（对应 Go UserBasicInfo）。
/// 枚举类字段（transactionEditScope / firstDayOfWeek / fiscalYearStart / 各格式字段）
/// 后端以**数字**序列化，因此这里统一用 `Int?` 解码，避免类型不匹配导致整个响应解析失败。
struct UserBasicInfo: Codable {
    let username: String?
    let email: String?
    let nickname: String?
    let avatar: String?
    let defaultAccountId: String?
    let language: String?
    let defaultCurrency: String?
    let emailVerified: Bool?

    // 以下字段来自 UserBasicInfo 的枚举/格式化配置（后端发数字）
    let transactionEditScope: Int?
    let firstDayOfWeek: Int?
    let fiscalYearStart: Int?
    let calendarDisplayType: Int?
    let dateDisplayType: Int?
    let longDateFormat: Int?
    let shortDateFormat: Int?
    let longTimeFormat: Int?
    let shortTimeFormat: Int?
    let fiscalYearFormat: Int?
    let currencyDisplayType: Int?
    let numeralSystem: Int?
    let decimalSeparator: Int?
    let digitGroupingSymbol: Int?
    let digitGrouping: Int?
    let coordinateDisplayType: Int?
    let expenseAmountColor: Int?
    let incomeAmountColor: Int?

    var displayName: String { nickname ?? username ?? "用户" }

    /// 显式 memberwise init（Codable 合成的 init(from:) 会占位，导致外部无法逐字段构造）
    init(username: String?, email: String?, nickname: String?, avatar: String?,
         defaultAccountId: String?, language: String?, defaultCurrency: String?, emailVerified: Bool?,
         transactionEditScope: Int?, firstDayOfWeek: Int?, fiscalYearStart: Int?,
         calendarDisplayType: Int?, dateDisplayType: Int?, longDateFormat: Int?,
         shortDateFormat: Int?, longTimeFormat: Int?, shortTimeFormat: Int?,
         fiscalYearFormat: Int?, currencyDisplayType: Int?, numeralSystem: Int?,
         decimalSeparator: Int?, digitGroupingSymbol: Int?, digitGrouping: Int?,
         coordinateDisplayType: Int?, expenseAmountColor: Int?, incomeAmountColor: Int?) {
        self.username = username
        self.email = email
        self.nickname = nickname
        self.avatar = avatar
        self.defaultAccountId = defaultAccountId
        self.language = language
        self.defaultCurrency = defaultCurrency
        self.emailVerified = emailVerified
        self.transactionEditScope = transactionEditScope
        self.firstDayOfWeek = firstDayOfWeek
        self.fiscalYearStart = fiscalYearStart
        self.calendarDisplayType = calendarDisplayType
        self.dateDisplayType = dateDisplayType
        self.longDateFormat = longDateFormat
        self.shortDateFormat = shortDateFormat
        self.longTimeFormat = longTimeFormat
        self.shortTimeFormat = shortTimeFormat
        self.fiscalYearFormat = fiscalYearFormat
        self.currencyDisplayType = currencyDisplayType
        self.numeralSystem = numeralSystem
        self.decimalSeparator = decimalSeparator
        self.digitGroupingSymbol = digitGroupingSymbol
        self.digitGrouping = digitGrouping
        self.coordinateDisplayType = coordinateDisplayType
        self.expenseAmountColor = expenseAmountColor
        self.incomeAmountColor = incomeAmountColor
    }
}

/// 用户资料详情（对应 Go UserProfileResponse）。
/// 后端 **内嵌** `*UserBasicInfo` → JSON 是**扁平**的（username/email 在顶层），
/// 不是 `{"user": {...}}`；另有 noPassword / lastLoginAt 两个附加字段。
struct UserProfileResponse: Codable {
    // 内嵌 UserBasicInfo 的全部字段（与 UserBasicInfo 保持一致）
    let username: String?
    let email: String?
    let nickname: String?
    let avatar: String?
    let defaultAccountId: String?
    let language: String?
    let defaultCurrency: String?
    let emailVerified: Bool?
    let transactionEditScope: Int?
    let firstDayOfWeek: Int?
    let fiscalYearStart: Int?
    let calendarDisplayType: Int?
    let dateDisplayType: Int?
    let longDateFormat: Int?
    let shortDateFormat: Int?
    let longTimeFormat: Int?
    let shortTimeFormat: Int?
    let fiscalYearFormat: Int?
    let currencyDisplayType: Int?
    let numeralSystem: Int?
    let decimalSeparator: Int?
    let digitGroupingSymbol: Int?
    let digitGrouping: Int?
    let coordinateDisplayType: Int?
    let expenseAmountColor: Int?
    let incomeAmountColor: Int?

    // UserProfileResponse 专有字段
    let noPassword: Bool?
    let lastLoginAt: Int64?

    /// 转成 UserBasicInfo（供本地缓存复用）
    var asBasicInfo: UserBasicInfo {
        UserBasicInfo(
            username: username, email: email, nickname: nickname, avatar: avatar,
            defaultAccountId: defaultAccountId, language: language,
            defaultCurrency: defaultCurrency, emailVerified: emailVerified,
            transactionEditScope: transactionEditScope, firstDayOfWeek: firstDayOfWeek,
            fiscalYearStart: fiscalYearStart, calendarDisplayType: calendarDisplayType,
            dateDisplayType: dateDisplayType, longDateFormat: longDateFormat,
            shortDateFormat: shortDateFormat, longTimeFormat: longTimeFormat,
            shortTimeFormat: shortTimeFormat, fiscalYearFormat: fiscalYearFormat,
            currencyDisplayType: currencyDisplayType, numeralSystem: numeralSystem,
            decimalSeparator: decimalSeparator, digitGroupingSymbol: digitGroupingSymbol,
            digitGrouping: digitGrouping, coordinateDisplayType: coordinateDisplayType,
            expenseAmountColor: expenseAmountColor, incomeAmountColor: incomeAmountColor
        )
    }
}

/// 资料更新请求（后端全部字段可选 omitempty，只传要改的）
struct UserProfileUpdateRequest: Codable {
    var email: String?
    var nickname: String?
    var password: String?
    var oldPassword: String?
    var defaultAccountId: String?
    var defaultCurrency: String?
    var firstDayOfWeek: Int?
    var fiscalYearStart: Int?
    var expenseAmountColor: Int?
    var incomeAmountColor: Int?
}

/// 资料更新响应（可能返回新 token）
struct UserProfileUpdateResponse: Codable {
    let user: UserBasicInfo?
    let newToken: String?
}

// MARK: - 可选项常量

enum UserProfileOptions {
    /// 周首日（对应 Go core.WeekDay：0=周日 … 6=周六）
    static let weekDays: [(Int, String)] = [
        (0, "周日"), (1, "周一"), (2, "周二"), (3, "周三"),
        (4, "周四"), (5, "周五"), (6, "周六")
    ]

    /// 财年起始月（对应 Go core.FiscalYearStart）
    static let fiscalYearStarts: [(Int, String)] = (1...12).map { ($0, "\($0) 月") }

    /// 金额颜色（对应 Go AmountColorType：0=默认 1=红 2=绿 3=黑 4=白）
    static let amountColors: [(Int, String)] = [
        (0, "默认"), (1, "红色"), (2, "绿色"), (3, "黑色"), (4, "白色")
    ]

    /// 常用货币
    static let currencies: [String] = ["CNY", "USD", "EUR", "JPY", "HKD", "GBP", "AUD", "CAD", "SGD"]
}
