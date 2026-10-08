import SwiftUI

/// 底部导航的 5 个位置（与手机端 Web 的 `main-tabbar` 一一对应）
enum MainTab: Int, CaseIterable {
    case list        // 详情（Web 的 Details）
    case accounts    // 账户
    case add         // 中央加号（非页面，点击弹新增交易）
    case statistics  // 统计
    case settings    // 设置

    var title: String {
        switch self {
        case .list: return "详情"
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

/// 跨 Tab 的账单筛选请求（统计页「查看账单明细」/ 点图表项 → 跳账单列表应用筛选）
struct TransactionFilterRequest: Equatable {
    var type: Int = 0
    var categoryIds: [String] = []
    var accountIds: [String] = []
    var startDate: Date?
    var endDate: Date?
    var keyword: String = ""
}

/// 跨 Tab 路由：持有当前选中 Tab 与「待应用到账单列表的筛选」。
/// 统计页发起「查看账单明细」时写入 pending 请求并切到账单 Tab，账单页监听后应用筛选。
final class TabRouter: ObservableObject {
    @Published var selection: MainTab = .list
    /// 待应用筛选（每次写一个新的 struct，账单页 onChange 检测到非 nil 就应用并清空）
    @Published var pendingTransactionFilter: TransactionFilterRequest?

    /// 发起「切换到账单列表并应用筛选」
    func routeToTransactionList(_ request: TransactionFilterRequest) {
        pendingTransactionFilter = request
        selection = .list
    }
}

/// 主界面：底部 5 位导航（详情 / 账户 / 中央加号 / 统计 / 设置）。
/// 结构与手机端 Web 的 `HomePage.vue` 底部 tabbar 完全对齐：
/// 启动落在「详情」页（Web 的首页内容并入该页顶部），中央加号是记账主入口，
/// 短按新增交易、长按弹出模板快捷菜单。
struct MainTabView: View {
    @StateObject private var router = TabRouter()
    @State private var showAdd = false
    /// 长按中央加号弹出的模板菜单
    @State private var showAddMenu = false
    @State private var showTemplates = false
    /// AI 识图记账
    @State private var showAI = false
    @ObservedObject private var serverSettings = ServerSettings.shared

    /// 各页面底部需要避让的高度 = 导航条内容 52pt + 条下方 8pt 内边距 + 额外 12pt 呼吸位。
    /// 通过环境值下发；同时在 `MainTabView` 层统一给**整页容器**加同高的 `safeAreaInset`，
    /// 这样无论页面是否包在 `NavigationView` 里，滚动内容都不会被浮层导航条遮住。
    static let barContentHeight: CGFloat = 72

    var body: some View {
        ZStack(alignment: .bottom) {
            // 页面容器：用 ZStack 保活所有页面，切 Tab 不丢状态（贴近 F7 页面栈行为）
            ZStack {
                TransactionsView(showAdd: $showAdd)
                    .environmentObject(router)
                    .opacity(router.selection == .list ? 1 : 0)
                    .allowsHitTesting(router.selection == .list)

                AccountsView()
                    .opacity(router.selection == .accounts ? 1 : 0)
                    .allowsHitTesting(router.selection == .accounts)

                StatisticsView()
                    .environmentObject(router)
                    .opacity(router.selection == .statistics ? 1 : 0)
                    .allowsHitTesting(router.selection == .statistics)

                SettingsView()
                    .opacity(router.selection == .settings ? 1 : 0)
                    .allowsHitTesting(router.selection == .settings)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // 关键：在**整页容器**上加底部安全区避让（而不是各页内层 List），
            // 这样无论页面是否包在 NavigationView 里，滚动内容都不会被浮层导航条遮住。
            // 同时把高度下发为环境值，供各页内部（如 sheet 内的列表）复用。
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: Self.barContentHeight)
            }
            .environment(\.mainTabBarInset, Self.barContentHeight)

            // 底部导航浮层：自身撑满底部安全区，中央加号上探不被裁切
            MainTabBar(selection: $router.selection) {
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
            if serverSettings.enableImageRecognition {
                Button("AI 识图记账") { showAI = true }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("选择记账方式")
        }
        .sheet(isPresented: $showAI) {
            AIReceiptView()
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
        .task {
            await ServerSettings.shared.loadIfNeeded()
            await UpdateStore.shared.autoCheckIfNeeded()
        }
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

/// 底部 5 位导航栏。毛玻璃胶囊浮层（现代理财 App 风格）：
/// 圆角胶囊容器 + `.ultraThinMaterial` 毛玻璃 + 选中项高亮胶囊；
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
        .frame(height: 54)
        .padding(.horizontal, 6)
        // 毛玻璃胶囊底：圆角胶囊 + 材质 + 细描边 + 柔阴影
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
                )
                .shadow(color: Color.black.opacity(0.14), radius: 16, x: 0, y: 6)
        )
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private func tabButton(_ tab: MainTab) -> some View {
        Button {
            selection = tab
        } label: {
            VStack(spacing: 3) {
                Image(systemName: tab.icon)
                    .font(.system(size: 20, weight: .medium))
                Text(tab.title)
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundColor(selection == tab ? Theme.brand : Color.secondary)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            // 选中项高亮胶囊
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(selection == tab ? Theme.brand.opacity(0.13) : Color.clear)
            )
            .padding(.horizontal, 3)
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
                        .fill(
                            LinearGradient(colors: [Theme.brand, Theme.brand.opacity(0.82)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .shadow(color: Theme.brand.opacity(0.38), radius: 8, x: 0, y: 4)
                )
                .offset(y: -20)
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
