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

    /// 底部导航条内容高度（不含底部安全区）。
    /// 通过环境值下发，供从页面内推入的二级页 / sheet 复用（它们自身在 tab 层级之外）。
    /// 页面滚动内容的避让不再依赖此值：底栏本体挂在 `safeAreaInset(edge: .bottom)` 上，
    /// SwiftUI 自动为所有滚动内容留出「栏高 + 底部安全区」。
    static let barContentHeight: CGFloat = 49

    /// Tab 切换时非选中页「停靠」在屏幕右侧外的距离（统一右往左滑动动画）
    private static let parkedOffset: CGFloat = UIScreen.main.bounds.width

    var body: some View {
        ZStack {
            // 页面容器：用 ZStack 保活所有页面，切 Tab 不丢状态（贴近 F7 页面栈行为）。
            // 切换动画统一为「右往左滑动」（无淡入淡出）：非选中页停靠在屏幕右侧外，
            // 选中页滑入到 0 并置于顶层，覆盖在下方的旧页保持原位。
            ZStack {
                TransactionsView(showAdd: $showAdd)
                    .environmentObject(router)
                    .offset(x: router.selection == .list ? 0 : Self.parkedOffset)
                    .allowsHitTesting(router.selection == .list)
                    .zIndex(router.selection == .list ? 1 : 0)

                AccountsView()
                    .offset(x: router.selection == .accounts ? 0 : Self.parkedOffset)
                    .allowsHitTesting(router.selection == .accounts)
                    .zIndex(router.selection == .accounts ? 1 : 0)

                StatisticsView()
                    .environmentObject(router)
                    .offset(x: router.selection == .statistics ? 0 : Self.parkedOffset)
                    .allowsHitTesting(router.selection == .statistics)
                    .zIndex(router.selection == .statistics ? 1 : 0)

                SettingsView()
                    .offset(x: router.selection == .settings ? 0 : Self.parkedOffset)
                    .allowsHitTesting(router.selection == .settings)
                    .zIndex(router.selection == .settings ? 1 : 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeOut(duration: 0.28), value: router.selection)
            // 统一隐藏滚动指示条（上下滑动时右侧不出现滚动条），对容器内所有 List/ScrollView 生效
            .indicator(.hidden)

            // 固定式底部导航：挂在 safeAreaInset 上占据真实布局空间（非悬浮），
            // 滚动内容自动避让，背景延伸进底部安全区（Home 指示条区域同色）。
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            MainTabBar(selection: $router.selection) {
                showAdd = true
            } onAddLongPress: {
                showAddMenu = true
            }
        }
        .environment(\.mainTabBarInset, Self.barContentHeight)
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

/// 底部导航栏的固定底色（与页面背景 systemGroupedBackground 同色：亮 #F2F2F7 / 暗 #1C1C1E）
private let tabBarBackgroundColor = Color(UIColor.systemGroupedBackground)

/// 底部 5 位导航栏。**固定式**底栏（对齐系统 Tab Bar 形态，非悬浮胶囊）：
/// 全宽不透明背景 + 顶部细分隔线，5 等分布局；
/// 中央加号是内嵌的主色圆钮（42×42），长按弹模板快捷菜单。
struct MainTabBar: View {
    @Binding var selection: MainTab
    let onAddTap: () -> Void
    let onAddLongPress: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // 顶部分隔细线（与页面内容分界）
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(height: 0.5)

            HStack(spacing: 0) {
                ForEach(MainTab.allCases, id: \.rawValue) { tab in
                    if tab == .add {
                        addButton
                    } else {
                        tabButton(tab)
                    }
                }
            }
            .frame(height: 48)
            .padding(.horizontal, 4)
        }
        .background(
            tabBarBackgroundColor
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private func tabButton(_ tab: MainTab) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.28)) {
                selection = tab
            }
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
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// 中央加号：主色圆钮，内嵌在栏内（不再上探悬浮）
    private var addButton: some View {
        Button {
            onAddTap()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 42, height: 42)
                .background(
                    Circle()
                        .fill(
                            LinearGradient(colors: [Theme.brand, Theme.brand.opacity(0.82)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .shadow(color: Theme.brand.opacity(0.32), radius: 5, x: 0, y: 3)
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        // 长按弹出模板快捷菜单（对应 Web 的 @taphold）
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.4)
                .onEnded { _ in onAddLongPress() }
        )
    }
}
