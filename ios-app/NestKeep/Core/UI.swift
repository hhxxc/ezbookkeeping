import SwiftUI
import UIKit

/// 主题色与金额格式化（沿用 Web 端设计令牌：主色 #26A69A，支出浅红、收入绿）
enum Theme {
    static let brand = Color(red: 38/255, green: 166/255, blue: 154/255)   // #26A69A
    static let expense = Color(red: 0.90, green: 0.30, blue: 0.30)
    static let income = Color(red: 0.20, green: 0.70, blue: 0.42)
    static let pageBackground = Color(.systemGroupedBackground)

    /// 登录页头部 Logo / 登录按钮渐变（青绿系，与品牌色同族）
    static let aiGradient = LinearGradient(
        colors: [Color(hex: "#26A69A"), Color(hex: "#4DB6AC")],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
}

/// 首页（Web `HomePage.vue`）专属调色板 —— 与 Web 的 `--hp-*` 设计令牌逐项对齐。
/// 注意：这里刻意不复用 `Theme.expense/income`，因为 Web 首页用的是低饱和的
/// `#D0443F` / `#1E9F6F`，而非全局的鲜红/鲜绿，差异肉眼可见。
enum HomePalette {
    // 亮色
    static let cardLight = Color(hex: "#FFFFFF")
    static let inkLight = Color(hex: "#1F2937")
    static let expenseLight = Color(hex: "#D0443F")
    static let expenseBgLight = Color(hex: "#FCEBEA")
    static let incomeLight = Color(hex: "#1E9F6F")
    // 深色
    static let cardDark = Color(hex: "#252530")
    static let inkDark = Color(hex: "#E8EAED")
    static let expenseDark = Color(hex: "#F87171")
    static let expenseBgDark = Color(hex: "#3A2426")
    static let incomeDark = Color(hex: "#34D399")

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
