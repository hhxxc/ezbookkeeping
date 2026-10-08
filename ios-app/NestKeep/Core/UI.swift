import SwiftUI

/// 主题色与金额格式化（沿用 Web 端设计令牌：主色 #26A69A，支出浅红、收入绿）
enum Theme {
    static let brand = Color(red: 38/255, green: 166/255, blue: 154/255)   // #26A69A
    static let expense = Color(red: 0.90, green: 0.30, blue: 0.30)
    static let income = Color(red: 0.20, green: 0.70, blue: 0.42)
    static let pageBackground = Color(.systemGroupedBackground)
}

enum AmountFormat {
    /// 分 -> 本地化货币字符串
    static func format(_ cents: Int64, currency: String? = "CNY") -> String {
        let decimal = Decimal(cents) / 100
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency ?? "CNY"
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: decimal as NSDecimalNumber) ?? "\(decimal)"
    }

    /// 分 -> 纯数字字符串（用于编辑回填）
    static func centsToText(_ cents: Int64) -> String {
        let decimal = Decimal(cents) / 100
        return (decimal as NSDecimalNumber).stringValue
    }
}
