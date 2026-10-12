import SwiftUI
import UIKit

/// 一套主题：主色（按钮/高亮/选中态）+ 渐变深色端
struct AppTheme: Identifiable {
    let id: String
    let name: String
    let brand: Color
    let deep: Color
}

/// 主题管理器：全局品牌色动态化。`Theme.brand` 等静态属性实时取当前主题，
/// 调用点零改动；RootView 观察本对象，切主题时整树重建换色。
/// 本地 UserDefaults + 云设置（appTheme）双存储，跨设备跟随。
/// 注意：不加 @MainActor——Theme.brand 在非隔离上下文也有调用；写入只在主线程发生。
final class ThemeManager: ObservableObject {
    static let shared = ThemeManager()

    static let themes: [AppTheme] = [
        AppTheme(id: "teal",     name: "松石", brand: Color(hex: "#26A69A"), deep: Color(hex: "#00695C")),
        AppTheme(id: "ocean",    name: "深海", brand: Color(hex: "#1E88E5"), deep: Color(hex: "#0052D4")),
        AppTheme(id: "violet",   name: "暮紫", brand: Color(hex: "#7C4DFF"), deep: Color(hex: "#4A00E0")),
        AppTheme(id: "sunset",   name: "落日", brand: Color(hex: "#F4511E"), deep: Color(hex: "#D84315")),
        AppTheme(id: "mint",     name: "薄荷", brand: Color(hex: "#10B981"), deep: Color(hex: "#047857")),
        AppTheme(id: "graphite", name: "石墨", brand: Color(hex: "#4B5563"), deep: Color(hex: "#1F2937")),
    ]

    private static let key = "nestkeep.appTheme"

    @Published private(set) var currentID: String =
        UserDefaults.standard.string(forKey: "nestkeep.appTheme") ?? "teal"

    var current: AppTheme {
        Self.themes.first { $0.id == currentID } ?? Self.themes[0]
    }

    /// 切换主题：本地立即生效，并异步推送到云设置
    func select(_ id: String) {
        guard Self.themes.contains(where: { $0.id == id }), id != currentID else { return }
        currentID = id
        UserDefaults.standard.set(id, forKey: Self.key)
        Task { await CloudSettingsStore.shared.set("appTheme", id) }
    }

    /// 登录/启动后从云设置拉取（云优先；云值为空或非法时保持本地）。
    /// CloudSettingsStore 是 @MainActor，本方法单独标注（调用方 .task 均在主线程）
    @MainActor
    func syncFromCloud() async {
        let store = CloudSettingsStore.shared
        if !store.loaded { await store.load() }
        guard store.enabled else { return }
        let cloud = store.string("appTheme")
        if !cloud.isEmpty, cloud != currentID,
           Self.themes.contains(where: { $0.id == cloud }) {
            currentID = cloud
            UserDefaults.standard.set(cloud, forKey: Self.key)
        }
    }
}

/// 主题色与金额格式化（沿用 Web 端设计令牌：支出浅红、收入绿）
/// brand / deep / aiGradient 动态取当前主题（ThemeManager）；收支语义色固定不变
enum Theme {
    static var brand: Color { ThemeManager.shared.current.brand }
    static var deep: Color { ThemeManager.shared.current.deep }
    static var expense = Color(red: 0.90, green: 0.30, blue: 0.30)
    static var income = Color(red: 0.20, green: 0.70, blue: 0.42)
    static var pageBackground = Color(.systemGroupedBackground)

    /// 登录页头部 Logo / 登录按钮渐变（跟随主题）
    static var aiGradient: LinearGradient {
        LinearGradient(colors: [brand, deep],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
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

/// 屏幕度量辅助
enum ScreenMetrics {
    /// 底部安全区高度（Home 指示条区域；非全面屏设备为 0）。
    /// iOS 15 上 MainTabView 的 safeAreaInset 穿不透 NavigationView，
    /// 页面自行留底栏避让时除栏高外还须补上这段，否则末尾内容仍会被底栏盖住
    static var bottomSafeInset: CGFloat {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let windows = scenes.flatMap { $0.windows }
        let window = windows.first { $0.isKeyWindow } ?? windows.first
        return window?.safeAreaInsets.bottom ?? 0
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

/// 首次进入页面的数据加载指示（首页 / 统计页共用）：
/// 居中小 spinner + 说明文案。只在「从未加载成功过」时显示（配合 VM 的 hasLoadedOnce），
/// 下拉刷新 / 切月等后续刷新不再出现，避免已展示内容闪烁。
struct LoadingHint: View {
    var text: String = "正在加载数据…"

    var body: some View {
        VStack(spacing: 10) {
            ProgressView()
                .tint(Theme.brand)
                .scaleEffect(1.1)
            Text(text)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }
}

/// 金额数字滚动动画：数值变化时从当前值平滑滚到目标值（easeOut ~0.55s）。
/// iOS 15 无 `contentTransition(.numericText())`（iOS 16+），用 Animatable View
/// 让 SwiftUI 逐帧插值重算文本实现同款效果。隐藏金额时直接显示掩码不滚动。
struct TweenAmountText: View {
    var cents: Int64
    var currency: String? = "CNY"
    /// 隐藏金额（眼睛开关）：显示掩码
    var hidden: Bool = false
    var mask: String = "＊＊＊"
    var duration: Double = 0.55

    @State private var shown: Double = 0

    var body: some View {
        if hidden {
            Text(verbatim: mask)
        } else {
            AmountTweenLabel(value: shown, currency: currency)
                .onAppear {
                    // 首次挂载（骨架接替真实卡片时）也从 0 滚到目标值
                    withAnimation(.easeOut(duration: duration)) { shown = Double(cents) }
                }
                .onChange(of: cents) { target in
                    withAnimation(.easeOut(duration: duration)) { shown = Double(target) }
                }
        }
    }
}

/// 可动画金额文本：Animatable 使 SwiftUI 在 value 插值期间逐帧重算 body
struct AmountTweenLabel: View, Animatable {
    var value: Double
    var currency: String?

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Text(verbatim: AmountFormat.format(Int64(value), currency: currency))
    }
}
