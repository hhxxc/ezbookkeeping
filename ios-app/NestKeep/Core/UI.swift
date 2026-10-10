import SwiftUI
import UIKit

/// 主题色与金额格式化（NestKeep Pro 设计方案：系统蓝 #2F7CF6 主色，
/// 中国市场惯例「红收绿支」语义色 —— 收入红 #E0342C、支出绿 #1D9E62）
enum Theme {
    static let brand = Color(hex: "#2F7CF6")                                // 系统蓝
    static let income = Color(hex: "#E0342C")                               // 收入红
    static let expense = Color(hex: "#1D9E62")                              // 支出绿
    static let warn = Color(hex: "#F59E0B")
    static let pageBackground = Color(.systemGroupedBackground)

    /// AI 功能渐变（蓝→紫，识图/语音入口与中央加号共用）
    static let aiGradient = LinearGradient(
        colors: [Color(hex: "#2F7CF6"), Color(hex: "#6A5CF0")],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
}

/// 首页（Web `HomePage.vue`）专属调色板 —— 与 Web 的 `--hp-*` 设计令牌逐项对齐。
/// 注意：这里刻意不复用 `Theme.expense/income`，因为 Web 首页用的是低饱和的
/// `#D0443F` / `#1E9F6F`，而非全局的鲜红/鲜绿，差异肉眼可见。
enum HomePalette {
    // 亮色（红收绿支：收入红、支出绿）
    static let cardLight = Color(hex: "#FFFFFF")
    static let inkLight = Color(hex: "#1C1C1E")
    static let expenseLight = Color(hex: "#1D9E62")
    static let expenseBgLight = Color(hex: "#E7F5EE")
    static let incomeLight = Color(hex: "#E0342C")
    // 深色
    static let cardDark = Color(hex: "#252530")
    static let inkDark = Color(hex: "#E8EAED")
    static let expenseDark = Color(hex: "#34D399")
    static let expenseBgDark = Color(hex: "#22352B")
    static let incomeDark = Color(hex: "#FF6B62")

    static var card: Color { adaptive(cardLight, cardDark) }
    static var ink: Color { adaptive(inkLight, inkDark) }
    static var expense: Color { adaptive(expenseLight, expenseDark) }
    static var expenseBg: Color { adaptive(expenseBgLight, expenseBgDark) }
    static var income: Color { adaptive(incomeLight, incomeDark) }
    static var secondary: Color { Color(.secondaryLabel) }
    static var divider: Color { Color(.separator) }

    /// 页面上是否处于深色（用于给背景图叠加压暗蒙层）
    static var isDark: Bool {
        UITraitCollection.current.userInterfaceStyle == .dark
    }

    private static func adaptive(_ light: Color, _ dark: Color) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light) })
    }
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
