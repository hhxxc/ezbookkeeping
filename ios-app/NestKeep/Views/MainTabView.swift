import SwiftUI

/// 底部导航的 5 个位置（与手机端 Web 的 `main-tabbar` 一一对应）
enum MainTab: Int, CaseIterable {
    case list        // 账单
    case accounts    // 账户
    case add         // 中央加号（非页面，点击弹新增交易）
    case statistics  // 统计
    case settings    // 设置

    var title: String {
        switch self {
        case .list: return "账单"
        case .accounts: return "账户"
        case .add: return ""
        case .statistics: return "统计"
        case .settings: return "设置"
        }
    }

    /// 手机端 Web 的图标（Framework7 iOS 图标 → SF Symbols 近似映射）
    var icon: String {
        switch self {
        case .list: return "list.bullet"          // f7: square_list
        case .accounts: return "creditcard"       // f7: creditcard
        case .add: return "plus"                  // f7: plus
        case .statistics: return "chart.pie"      // f7: chart_pie
        case .settings: return "gearshape"        // f7: gear_alt
        }
    }
}

/// 主界面：底部 5 位导航（账单 / 账户 / 中央加号 / 统计 / 设置）。
/// 结构与手机端 Web 的 `HomePage.vue` 底部 tabbar 完全对齐：
/// 启动落在「账单」页（Web 的首页内容并入账单页顶部），中央加号是记账主入口，
/// 短按新增交易、长按弹出模板快捷菜单。
struct MainTabView: View {
    @State private var selection: MainTab = .list
    @State private var showAdd = false
    /// 长按中央加号弹出的模板菜单
    @State private var showAddMenu = false
    @State private var showTemplates = false

    /// 各页面底部需要避让的高度（不含安全区），通过环境值下发，避免列表被浮层导航盖住
    static let barContentHeight: CGFloat = 52

    var body: some View {
        ZStack(alignment: .bottom) {
            // 页面容器：用 ZStack 保活所有页面，切 Tab 不丢状态（贴近 F7 页面栈行为）
            ZStack {
                TransactionsView(showAdd: $showAdd)
                    .opacity(selection == .list ? 1 : 0)
                    .allowsHitTesting(selection == .list)

                AccountsView()
                    .opacity(selection == .accounts ? 1 : 0)
                    .allowsHitTesting(selection == .accounts)

                StatisticsView()
                    .opacity(selection == .statistics ? 1 : 0)
                    .allowsHitTesting(selection == .statistics)

                SettingsView()
                    .opacity(selection == .settings ? 1 : 0)
                    .allowsHitTesting(selection == .settings)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // 各页内容底部留出浮层导航的高度（导航行本身；安全区由各页 safeAreaInset 自动叠加）
            .environment(\.mainTabBarInset, Self.barContentHeight)

            // 底部导航浮层：自身撑满底部安全区，中央加号上探不被裁切
            MainTabBar(selection: $selection) {
                showAdd = true
            } onAddLongPress: {
                showAddMenu = true
            }
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        // 新增交易（短按加号 / 各页里的新增入口共用）
        .sheet(isPresented: $showAdd) {
            TransactionEditView(transaction: nil)
        }
        // 长按加号：模板快捷菜单（对齐 Web 的 template-popover-menu）
        .confirmationDialog("快捷记账", isPresented: $showAddMenu, titleVisibility: .visible) {
            Button("记一笔") { showAdd = true }
            Button("模板与计划账单") { showTemplates = true }
            Button("取消", role: .cancel) {}
        } message: {
            Text("选择记账方式")
        }
        .sheet(isPresented: $showTemplates) {
            NavigationView {
                TemplatesView()
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("完成") { showTemplates = false }
                        }
                    }
            }
        }
        // 启动时静默检查更新（有间隔节流，失败不打扰）
        .task { await UpdateStore.shared.autoCheckIfNeeded() }
    }
}

// MARK: - 底部导航避让（环境值）

private struct MainTabBarInsetKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    /// 浮层底部导航占用的高度；页面用它给滚动内容留出底部空白
    var mainTabBarInset: CGFloat {
        get { self[MainTabBarInsetKey.self] }
        set { self[MainTabBarInsetKey.self] = newValue }
    }
}

/// 底部 5 位导航栏。完全透明背景、无顶部分隔线，与手机端 Web 一致；
/// 中央加号是上探 28pt 的主色圆钮（56×56）。
struct MainTabBar: View {
    @Binding var selection: MainTab
    let onAddTap: () -> Void
    let onAddLongPress: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(MainTab.allCases, id: \.rawValue) { tab in
                if tab == .add {
                    addButton
                } else {
                    tabButton(tab)
                }
            }
        }
        .frame(height: 52)
        .padding(.horizontal, 4)
        // 与 Web 一致：完全透明背景、无顶部分隔线。
        // 用 safeAreaInset 把导航行抬到 Home Indicator 之上；加号上探部分由下方 padding 兜住。
        .padding(.bottom, 8)
        .background(
            // 透明但撑满底部安全区，避免上探的加号被裁切，同时保持视觉透明
            Color.clear
                .ignoresSafeArea(edges: .bottom)
                .allowsHitTesting(false)
        )
    }

    private func tabButton(_ tab: MainTab) -> some View {
        Button {
            selection = tab
        } label: {
            VStack(spacing: 3) {
                Image(systemName: tab.icon)
                    .font(.system(size: 22, weight: .regular))
                Text(tab.title)
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundColor(selection == tab ? Theme.brand : Color.secondary)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// 中央加号：主色圆钮，上探 28pt（对应 Web 的 `margin-top: -28px`）
    private var addButton: some View {
        Button {
            onAddTap()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 26, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 56, height: 56)
                .background(
                    Circle()
                        .fill(Theme.brand)
                        .shadow(color: Theme.brand.opacity(0.35), radius: 6, x: 0, y: 3)
                )
                .offset(y: -28)
        }
        .buttonStyle(.plain)
        .frame(width: 64)
        // 长按弹出模板快捷菜单（对应 Web 的 @taphold）
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.4)
                .onEnded { _ in onAddLongPress() }
        )
    }
}
