import SwiftUI
import Combine

/// 统计页：收支总览 + 分类占比饼图 + 日收支统计（柱状/折线 × 支出/收入/全部）+ 日报表。
/// iOS 15 没有原生 Charts 框架，图表全部用 SwiftUI Path / 几何图形自绘。
@MainActor
final class StatisticsViewModel: ObservableObject {
    @Published var year: Int
    @Published var month: Int
    @Published var isLoading = false
    @Published var error: String?
    /// 本 Tab 是否已成功加载过（供「首次选中才加载」门控）
    @Published var hasLoadedOnce = false

    @Published var totalExpenseCents: Int64 = 0
    @Published var totalIncomeCents: Int64 = 0
    /// 分类聚合（支出，按金额降序）
    @Published var expenseByCategory: [CategoryStat] = []
    @Published var incomeByCategory: [CategoryStat] = []
    /// 每日支出/收入（按日）
    @Published var dailyExpense: [Int64] = []
    @Published var dailyIncome: [Int64] = []
    @Published var daysInMonth: Int = 30
    /// 周期：false=按月，true=按年（对齐 Web 统计页导航栏的「月/年」分段切换）
    @Published var isYearMode = false

    private var categories: [TransactionCategory] = []
    /// 账户列表（用于账户过滤）
    @Published var accounts: [Account] = []
    /// 标签列表（用于标签过滤）
    @Published var tagList: [TransactionTag] = []

    /// 多条件筛选（对齐 Web 统计页「更多」菜单）：
    /// - 账户/分类：本地过滤（统计响应里的 accountId/categoryId）
    /// - 标签/关键词：走后端 tag_filter / keyword 参数
    @Published var filterAccountIds: Set<String> = []
    @Published var filterCategoryIds: Set<String> = []
    /// 标签过滤（Web 的 tagFilter，形如 "include:1,2|exclude:3" 之类；这里简化为「包含的标签 id 集合」）
    @Published var filterTagIds: Set<String> = []
    @Published var filterKeyword = ""

    struct CategoryStat: Identifiable {
        let id: String
        let name: String
        let icon: String?
        let color: Color
        let amount: Int64
        var ratio: Double = 0
    }

    init() {
        let comps = Calendar.current.dateComponents([.year, .month], from: Date())
        year = comps.year!
        month = comps.month!
    }

    var netCents: Int64 { totalIncomeCents - totalExpenseCents }

    /// 是否处于筛选态（账户/分类/标签/关键词任一非空）
    var hasFilter: Bool {
        !filterAccountIds.isEmpty || !filterCategoryIds.isEmpty ||
        !filterTagIds.isEmpty || !filterKeyword.isEmpty
    }

    /// 当前周期的自然日天数（月模式=当月天数，年模式=全年天数），用于日均支出
    private var periodDayCount: Int {
        let cal = Calendar.current
        if isYearMode {
            let start = cal.date(from: DateComponents(year: year, month: 1, day: 1))!
            return cal.range(of: .day, in: .year, for: start)?.count ?? 365
        }
        let start = cal.date(from: DateComponents(year: year, month: month))!
        return cal.range(of: .day, in: .month, for: start)?.count ?? 30
    }

    /// 周期起点（月模式=当月 1 日，年模式=1 月 1 日）
    var periodStart: Date {
        Calendar.current.date(from: DateComponents(year: year, month: isYearMode ? 1 : month, day: 1))!
    }

    /// 周期终点（开区间，不含当天）
    var periodEnd: Date {
        Calendar.current.date(byAdding: isYearMode ? .year : .month, value: 1, to: periodStart)!
    }

    /// 已流逝的天数（截止今天，用于「日均」——对齐 Web `elapsedDaysInRange`，
    /// 而不是整个周期的自然日天数；未到月底时按已过天数均摊）
    var elapsedDaysInPeriod: Int {
        let todayStart = Calendar.current.startOfDay(for: Date())
        let end = min(periodEnd, todayStart)
        let days = Calendar.current.dateComponents([.day], from: periodStart, to: end).day ?? 0
        return max(days + 1, 0)
    }

    /// 日均支出（对齐 Web：总支出 / 已流逝天数）
    var dailyAverageExpenseCents: Int64 {
        let days = elapsedDaysInPeriod
        guard days > 0 else { return 0 }
        return totalExpenseCents / Int64(days)
    }

    var periodLabel: String { isYearMode ? "\(year)年" : "\(year)年\(month)月" }

    /// 柱状图末位标签（月模式「31日」/ 年模式「12月」）
    var bucketEndLabel: String { isYearMode ? "12月" : "\(daysInMonth)日" }

    func setYearMode(_ value: Bool) {
        guard value != isYearMode else { return }
        isYearMode = value
        Task { await load() }
    }

    func load() async {
        isLoading = true
        error = nil
        do {
            // 引用数据走共享缓存（冷启动只拉一次）
            categories = (try? await AppDataStore.shared.getCategories()) ?? []
            accounts = (try? await AppDataStore.shared.getAccounts()) ?? []
            guard let start = Calendar.current.date(from: DateComponents(
                      year: year,
                      month: isYearMode ? 1 : month,
                      day: 1)),
                  let end = Calendar.current.date(byAdding: isYearMode ? .year : .month,
                                                  value: 1, to: start) else {
                isLoading = false
                return
            }
            let startTs = Int(start.timeIntervalSince1970)
            let endTs = Int(end.timeIntervalSince1970)

            // 构造后端筛选参数（tag_filter / keyword）
            var statQuery: [URLQueryItem] = [
                URLQueryItem(name: "start_time", value: "\(startTs)"),
                URLQueryItem(name: "end_time", value: "\(endTs)"),
                URLQueryItem(name: "use_transaction_timezone", value: "true")
            ]
            var dailyQuery: [URLQueryItem] = [
                URLQueryItem(name: "start_time", value: "\(startTs)"),
                URLQueryItem(name: "end_time", value: "\(endTs)"),
                URLQueryItem(name: "use_transaction_timezone", value: "true")
            ]
            if !filterTagIds.isEmpty {
                // tag_filter 形如 "0:id1,id2"（0=HAS_ANY 包含任一标签，对齐 Web「包含」语义）
                let tf = "0:\(filterTagIds.sorted().joined(separator: ","))"
                statQuery.append(URLQueryItem(name: "tag_filter", value: tf))
                dailyQuery.append(URLQueryItem(name: "tag_filter", value: tf))
            }
            if !filterKeyword.isEmpty {
                statQuery.append(URLQueryItem(name: "keyword", value: filterKeyword))
                dailyQuery.append(URLQueryItem(name: "keyword", value: filterKeyword))
            }

            async let statResp: StatisticResponse = APIClient.shared.request(
                "/api/v1/transactions/statistics.json",
                query: statQuery
            )
            async let dailyResp: [StatisticDailyItem] = APIClient.shared.request(
                "/api/v1/transactions/statistics/daily.json",
                query: dailyQuery
            )

            let stats = try await statResp
            let daily = (try? await dailyResp) ?? []

            buildCategoryStats(stats.items)
            buildDaily(daily)
            hasLoadedOnce = true
            isLoading = false
        } catch {
            isLoading = false
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// 把统计项聚合成分类维度（支出 / 收入分开），并应用本地账户/分类过滤
    private func buildCategoryStats(_ items: [StatisticResponseItem]) {
        var expMap: [String: Int64] = [:]
        var incMap: [String: Int64] = [:]
        for item in items {
            // 本地账户过滤
            if !filterAccountIds.isEmpty,
               let accountId = item.accountId, filterAccountIds.contains(accountId) {
                continue
            }
            // 本地分类过滤
            let key = item.categoryId ?? "0"
            if !filterCategoryIds.isEmpty, filterCategoryIds.contains(key) {
                continue
            }
            // 后端统计接口的 amount 恒为正数，收支方向由分类类型决定
            //（对齐 Web：category.type 1=收入→收入桶、2=支出→支出桶、3=转账→跳过）
            let amount = abs(item.amount)
            switch categoryType(forKey: key) {
            case .some(2): expMap[key, default: 0] += amount
            case .some(1): incMap[key, default: 0] += amount
            default: break
            }
        }
        totalExpenseCents = expMap.values.reduce(0, +)
        totalIncomeCents = incMap.values.reduce(0, +)

        expenseByCategory = makeStats(from: expMap, total: totalExpenseCents)
        incomeByCategory = makeStats(from: incMap, total: totalIncomeCents)
    }

    /// 饼图配色兜底盘：分类自身颜色撞色时依次取用（低饱和、明暗模式均可读）
    private static let chartFallbackPalette: [Color] = [
        Color(hex: "#0EA5E9"), Color(hex: "#F97316"), Color(hex: "#14B8A6"),
        Color(hex: "#8B5CF6"), Color(hex: "#F43F5E"), Color(hex: "#84CC16"),
        Color(hex: "#EAB308"), Color(hex: "#06B6D4"), Color(hex: "#EC4899"),
        Color(hex: "#6366F1"), Color(hex: "#22C55E"), Color(hex: "#A855F7")
    ]

    /// 颜色亮度（0~1）；解析失败返回 nil。近黑色在饼图/图标上不可辨，强制换兜底色
    private static func luminance(ofHex hex: String) -> Double? {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count >= 6 else { return nil }
        let r = Double(Int(s.prefix(2), radix: 16) ?? 0)
        let g = Double(Int(s.dropFirst(2).prefix(2), radix: 16) ?? 0)
        let b = Double(Int(s.dropFirst(4).prefix(2), radix: 16) ?? 0)
        return (0.299 * r + 0.587 * g + 0.114 * b) / 255.0
    }

    private func makeStats(from map: [String: Int64], total: Int64) -> [CategoryStat] {
        let sorted = map.compactMap { key, amount -> (key: String, colorHex: String?, icon: String?, amount: Int64)? in
            guard amount > 0 else { return nil }
            let cat = findCategory(key)
            return (key, cat?.color, cat?.icon, amount)
        }
        .sorted { $0.amount > $1.amount }

        // 配色规则：
        // ① 分类自身色够亮（非近黑）才用；近黑/缺失一律走兜底盘（用户要求饼图不要黑色）
        // ② 撞色消解：与已用色重复时从兜底盘取未用色
        // ③ 兜底盘扫描**有上界**——全被占用时直接轮转取色。此前无界 while 在分类数
        //    多、撞色多时存在主线程死循环风险（年视图分类多，疑似“点年卡死”的元凶之一）
        var usedColors: [Color] = []
        var fallbackIdx = 0
        func nextPaletteColor() -> Color {
            let palette = Self.chartFallbackPalette
            var pick = fallbackIdx
            while pick - fallbackIdx < palette.count,
                  usedColors.contains(palette[pick % palette.count]) {
                pick += 1
            }
            fallbackIdx = pick + 1
            return palette[pick % palette.count]
        }
        return sorted.map { item in
            var color: Color
            if let hex = item.colorHex,
               let lum = Self.luminance(ofHex: hex), lum >= 0.16 {
                color = Color(hex: hex)
            } else {
                color = nextPaletteColor()
            }
            if usedColors.contains(color) {
                color = nextPaletteColor()
            }
            usedColors.append(color)
            return CategoryStat(
                id: item.key,
                name: findCategory(item.key)?.name ?? "未分类",
                icon: item.icon,
                color: color,
                amount: item.amount,
                ratio: total > 0 ? Double(item.amount) / Double(total) : 0
            )
        }
    }

    private func findCategory(_ id: String) -> TransactionCategory? {
        for c in categories {
            if c.id == id { return c }
            if let subs = c.subCategories, let hit = subs.first(where: { $0.id == id }) {
                return hit
            }
        }
        return nil
    }

    /// 分类类型（1=收入 2=支出 3=转账）。
    /// 关键契约：统计接口的 amount 恒为**正数**，收支方向只能靠分类类型判断
    /// （后端按交易 type 分别聚合、金额不做符号化；Web 端同样按 category.type 分桶）。
    /// 找不到分类（含转账项 categoryId 为空/0）返回 nil，跳过不计入。
    private func categoryType(forKey id: String) -> Int? {
        findCategory(id)?.type
    }

    /// 汇总区间收支：月模式按「日」聚合，年模式按「月」聚合（对齐 Web 年周期柱状图）
    private func buildDaily(_ items: [StatisticDailyItem]) {
        if isYearMode {
            var exp = [Int64](repeating: 0, count: 12)
            var inc = [Int64](repeating: 0, count: 12)
            for d in items {
                let m = d.month
                guard m >= 1, m <= 12 else { continue }
                for item in d.items {
                    if shouldExclude(item) { continue }
                    let amount = abs(item.amount)
                    switch categoryType(forKey: item.categoryId ?? "0") {
                    case .some(2): exp[m - 1] += amount
                    case .some(1): inc[m - 1] += amount
                    default: break
                    }
                }
            }
            dailyExpense = exp
            dailyIncome = inc
            return
        }

        let dayCount = periodDayCount
        daysInMonth = dayCount
        var exp = [Int64](repeating: 0, count: dayCount)
        var inc = [Int64](repeating: 0, count: dayCount)

        for d in items {
            guard d.month == month, d.day >= 1, d.day <= dayCount else { continue }
            let idx = d.day - 1
            for item in d.items {
                if shouldExclude(item) { continue }
                let amount = abs(item.amount)
                switch categoryType(forKey: item.categoryId ?? "0") {
                case .some(2): exp[idx] += amount
                case .some(1): inc[idx] += amount
                default: break
                }
            }
        }
        dailyExpense = exp
        dailyIncome = inc
    }

    /// 本地账户/分类过滤（用于日报表/柱状图的逐项过滤）
    private func shouldExclude(_ item: StatisticResponseItem) -> Bool {
        if !filterAccountIds.isEmpty, let accountId = item.accountId, filterAccountIds.contains(accountId) {
            return true
        }
        let key = item.categoryId ?? "0"
        if !filterCategoryIds.isEmpty, filterCategoryIds.contains(key) {
            return true
        }
        return false
    }

    /// 切换周期时重置月份基准：进入年模式保留年份，回到月模式保留当前月
    func shiftPeriod(by delta: Int) {
        let comps = DateComponents(year: year, month: month)
        let unit: Calendar.Component = isYearMode ? .year : .month
        guard let date = Calendar.current.date(byAdding: unit, value: delta,
                                              to: Calendar.current.date(from: comps)!) else { return }
        let c = Calendar.current.dateComponents([.year, .month], from: date)
        year = c.year!
        month = c.month!
        Task { await load() }
    }

    /// 清空筛选
    func clearFilter() {
        filterAccountIds = []
        filterCategoryIds = []
        filterTagIds = []
        filterKeyword = ""
        Task { await load() }
    }

    /// 应用筛选后重载
    func applyFilter() {
        Task { await load() }
    }

    /// 供筛选面板使用的拍平分类列表
    var categoriesForFilter: [TransactionCategory] {
        categories.flatMap { c -> [TransactionCategory] in
            var arr = [c]
            if let subs = c.subCategories { arr.append(contentsOf: subs) }
            return arr
        }
    }

    /// 按需加载标签列表（筛选面板打开时调用）
    func loadTagListIfNeeded() async {
        guard tagList.isEmpty else { return }
        tagList = (try? await AppDataStore.shared.getTags())?.tags ?? []
    }
}

// MARK: - 统计接口模型

struct StatisticResponse: Codable {
    let startTime: Int64?
    let endTime: Int64?
    let items: [StatisticResponseItem]
}

struct StatisticResponseItem: Codable {
    let categoryId: String?
    let accountId: String?
    let amount: Int64
}

struct StatisticDailyItem: Codable {
    let year: Int
    let month: Int
    let day: Int
    let items: [StatisticResponseItem]
}

// MARK: - 统计页

struct StatisticsView: View {
    @StateObject private var vm = StatisticsViewModel()
    @EnvironmentObject private var router: TabRouter
    /// 排行/总览点击下钻的账单列表页用独立 VM（不与首页 VM 共享筛选态）
    @StateObject private var listVM = TransactionsViewModel()
    @State private var mode: Mode = .expense
    /// 日收支图维度（支出/收入/全部）——独立于分类饼图维度，对齐 Web `dailyChartMode`
    @State private var dailyMode: DailyMode = .expense
    /// 日收支图类型（柱状/折线）——对齐 Web `dailyChartType`
    @State private var dailyChartType: ChartType = .bar
    /// 更多菜单（筛选 / 设置）
    @State private var showMoreSheet = false
    /// 筛选面板
    @State private var showFilterSheet = false
    /// 统计设置页
    @State private var showSettings = false
    /// 下钻账单列表页（原生 push，返回即回统计页）
    @State private var showListPage = false
    @State private var editing: Transaction?
    @State private var duplicating: Transaction?
    @State private var detail: Transaction?

    enum Mode: String, CaseIterable {
        case expense = "支出"
        case income = "收入"
    }

    enum DailyMode: String, CaseIterable {
        case expense = "支出"
        case income = "收入"
        case all = "全部"
    }

    enum ChartType: String, CaseIterable {
        case bar = "柱状"
        case line = "折线"
    }

    private var stats: [StatisticsViewModel.CategoryStat] {
        mode == .expense ? vm.expenseByCategory : vm.incomeByCategory
    }

    /// 日收支图是否有数据
    private var hasDailyData: Bool {
        vm.dailyExpense.contains { $0 > 0 } || vm.dailyIncome.contains { $0 > 0 }
    }

    /// 主强调色：与 Web 统计页一致，用首页调色板（低饱和红/绿）而非全局鲜色
    private var accent: Color { mode == .expense ? HomePalette.expense : HomePalette.income }

    var body: some View {
        // 包 NavigationView 让下钻的账单列表页走系统 push：返回即回统计页
        //（旧实现跨 Tab 跳到「详情」Tab，返回落在详情首页而非统计页，与 Web 不一致）
        NavigationView {
            statisticsBody
        }
        .navigationViewStyle(.stack)
    }

    private var statisticsBody: some View {
        ScrollView {
            VStack(spacing: 16) {
                // 自绘顶栏放进滚动内容（首页同款方案）：包进 NavigationView 后 iOS 15 上
                // safeAreaInset(top) 定位不可靠（AIReceiptView 同款教训），不能再用悬浮方案
                topBar
                    .padding(.top, 4)
                periodModePicker
                overviewCard
                modePicker
                if !stats.isEmpty {
                    pieCard
                    rankCard
                }
                if hasDailyData {
                    dailyChartCard
                }
                dailyReportCard
                viewDetailsLink
                if let error = vm.error {
                    Text(error).font(.footnote).foregroundColor(.red)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        // 底部避让由 MainTabView 整页容器统一施加，此处不再重复叠加
        .background(Theme.pageBackground.ignoresSafeArea())
        .refreshable { await vm.load() }
        .confirmationDialog("更多", isPresented: $showMoreSheet, titleVisibility: .visible) {
                Button("筛选账户") { showFilterSheet = true }
                Button("筛选分类") { showFilterSheet = true }
                Button("筛选标签") { showFilterSheet = true }
                Button("筛选描述") { showFilterSheet = true }
                if vm.hasFilter {
                    Button("清除筛选", role: .destructive) { vm.clearFilter() }
                }
                Button("统计设置") { showMoreSheet = false; showSettings = true }
                Button("取消", role: .cancel) {}
            }
            .sheet(isPresented: $showFilterSheet) {
                StatisticsFilterSheet(vm: vm)
            }
            .sheet(isPresented: $showSettings) {
                NavigationView {
                    StatisticsSettingsView()
                        .toolbar {
                            ToolbarItem(placement: .navigationBarTrailing) {
                                Button("完成") { showSettings = false }
                            }
                        }
                }
            }
        // 冷启动不加载（4 Tab 全保活，屏外 .task 也会执行）：首次真正切到本 Tab 才拉统计
        .task { if router.selection == .statistics { await vm.load() } }
        .onChange(of: router.selection) { sel in
            if sel == .statistics && !vm.hasLoadedOnce { Task { await vm.load() } }
        }
        // 统计页根节点隐藏系统导航栏（自绘顶栏替代）；推入的账单列表页自动显示导航栏
        .navigationBarHidden(true)
        // 隐藏的编程式导航链接（iOS 15 手法）：排行/总览下钻账单列表页走系统 push
        .background(
            NavigationLink(
                destination: BillListPageView(vm: listVM, onEdit: { tx in
                    editing = tx
                }, onDuplicate: { tx in
                    duplicating = tx
                }, onDetail: { tx in
                    detail = tx
                }),
                isActive: $showListPage
            ) { EmptyView() }
        )
        .sheet(item: $editing, onDismiss: {
            Task { await listVM.load(); await vm.load() }
        }) { tx in
            TransactionEditView(transaction: tx, mode: .edit)
        }
        .sheet(item: $duplicating, onDismiss: {
            Task { await listVM.load(); await vm.load() }
        }) { tx in
            TransactionEditView(transaction: tx, mode: .duplicate)
        }
        .sheet(item: $detail, onDismiss: {
            Task { await listVM.load(); await vm.load() }
        }) { tx in
            TransactionDetailView(transaction: tx, onChanged: {
                Task { await listVM.load(); await vm.load() }
            })
        }
    }

    // MARK: - 顶部自绘栏：月份/年份切换胶囊 + 筛选入口（风格对齐首页顶栏胶囊）
    private var topBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 14) {
                Button { vm.shiftPeriod(by: -1) } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.plain)

                Text(verbatim: vm.periodLabel)
                    .font(.system(size: 15, weight: .semibold))
                    .monospacedDigit()
                    .frame(minWidth: 72)

                Button { vm.shiftPeriod(by: 1) } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.plain)
            }
            .foregroundColor(HomePalette.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            // 纯色底替代 ultraThinMaterial：材质在本页反复重绘时会强制离屏渲染，
            // iOS 15 上有明显卡顿风险（纯色 5% 透明度观感几乎一致）
            .background(Color.primary.opacity(0.05))
            .clipShape(Capsule())
            .overlay(
                Capsule().strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
            )

            Spacer()

            Button { showMoreSheet = true } label: {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(vm.hasFilter ? Theme.brand : HomePalette.ink)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color.primary.opacity(0.05)))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .background(
            VStack(spacing: 0) {
                Color(.systemGroupedBackground)
                Rectangle()
                    .fill(Color.primary.opacity(0.06))
                    .frame(height: 0.5)
            }
            .ignoresSafeArea(edges: .top)
        )
    }

    // MARK: - 周期切换（月 / 年，对齐 Web 导航栏 `.period-mode-segmented`）
    private var periodModePicker: some View {
        Picker("周期", selection: Binding(
            get: { vm.isYearMode },
            set: { vm.setYearMode($0) }
        )) {
            Text("月").tag(false)
            Text("年").tag(true)
        }
        .pickerStyle(.segmented)
    }

    // MARK: - 概览卡（对齐 Web `statistics/TransactionPage.vue`）
    /// Web 结构：`收支总览` 标题(17px/600) + 2×2 网格（支出/收入/结余/日均支出），
    /// 每格「标签 14px 次要色 + 数值 21px/700 主文字色」，**白底卡，不用主题色渐变**。
    private var overviewCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("收支总览")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(HomePalette.ink)
                .padding(.bottom, 16)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12),
                                GridItem(.flexible(), spacing: 12)],
                      spacing: 18) {
                overviewCell("支出", vm.totalExpenseCents, HomePalette.expense) {
                    routeToDetail(type: 3)
                }
                overviewCell("收入", vm.totalIncomeCents, HomePalette.income) {
                    routeToDetail(type: 2)
                }
                overviewCell("结余", vm.netCents,
                             vm.netCents >= 0 ? HomePalette.income : HomePalette.expense)
                overviewCell("日均支出", vm.dailyAverageExpenseCents, HomePalette.ink)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HomePalette.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: Color.black.opacity(HomePalette.isDark ? 0.5 : 0.06), radius: 10, x: 0, y: 4)
    }

    /// 概览网格单元：标签 14px 次要色 / 数值 21px-700 指定色（对齐 Web `.statistics-overview-*`）；
    /// 传入 action 时整格可点（点击跳账单 Tab 查看该类型明细）
    private func overviewCell(_ title: String, _ cents: Int64, _ color: Color, action: (() -> Void)? = nil) -> some View {
        let cell = VStack(spacing: 4) {
            Text(title).font(.system(size: 14)).foregroundColor(HomePalette.secondary)
            Text(AmountFormat.format(cents))
                .font(.system(size: 21, weight: .bold))
                .monospacedDigit()
                .foregroundColor(color)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        if let action {
            return AnyView(Button(action: action) { cell }.buttonStyle(.plain))
        }
        return AnyView(cell)
    }

    /// 点击统计数字/分类行 → 在本 Tab 内原生 push 账单列表页（返回即回统计页）。
    /// type 对齐 TransactionFilter：0=全部 2=收入 3=支出；不传 categoryId 时保留当前分类筛选。
    private func routeToDetail(type: Int, categoryId: String? = nil) {
        // periodEnd 是开区间（下月 1 日 / 次年 1 日 00:00），
        // 账单列表的筛选是闭区间（当日 23:59:59），需回退 1 秒避免多算一天
        let closedEnd = vm.periodEnd.addingTimeInterval(-1)
        listVM.applyFilterRequest(TransactionFilterRequest(
            type: type,
            categoryIds: categoryId.map { [$0] } ?? Array(vm.filterCategoryIds),
            accountIds: Array(vm.filterAccountIds),
            startDate: vm.periodStart,
            endDate: closedEnd,
            keyword: vm.filterKeyword
        ))
        showListPage = true
    }

    private var modePicker: some View {
        Picker("维度", selection: $mode) {
            ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
    }

    // MARK: - 饼图（自绘）
    private var pieCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("\(mode.rawValue)分类占比").font(.headline)
            HStack(spacing: 18) {
                PieChart(slices: stats.map { ($0.ratio, $0.color) })
                    .frame(width: 130, height: 130)
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(stats.prefix(6)) { s in
                        HStack(spacing: 7) {
                            // 分类图标徽章（色底白图标，与分类管理页一致）
                            Image(systemName: CategoryIconCatalog.symbol(s.icon))
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 18, height: 18)
                                .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(s.color))
                            Text(s.name).font(.footnote).lineLimit(1)
                            Spacer()
                            Text("\(Int((s.ratio * 100).rounded()))%")
                                .font(.footnote).foregroundColor(.secondary)
                        }
                    }
                    if stats.count > 6 {
                        Text("等 \(stats.count) 个分类")
                            .font(.footnote).foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(16)
        .background(HomePalette.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - 分类排行
    private var rankCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(mode.rawValue)排行").font(.headline).padding(.bottom, 12)
            ForEach(Array(stats.prefix(10).enumerated()), id: \.element.id) { idx, s in
                Button {
                    // 点分类行 → 跳账单 Tab 查看该分类在当前周期的明细
                    routeToDetail(type: mode == .expense ? 3 : 2, categoryId: s.id)
                } label: {
                    HStack(spacing: 12) {
                        Text("\(idx + 1)")
                            .font(.footnote.monospacedDigit())
                            .foregroundColor(.secondary)
                            .frame(width: 18, alignment: .leading)
                        // 分类图标徽章（色底白图标）
                        Image(systemName: CategoryIconCatalog.symbol(s.icon))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 24, height: 24)
                            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(s.color))
                        Text(s.name).font(.subheadline).lineLimit(1)
                        Spacer()
                        Text(AmountFormat.format(s.amount))
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundColor(accent)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(HomePalette.secondary.opacity(0.6))
                    }
                }
                .buttonStyle(.plain)
                .padding(.vertical, 7)
                if idx < min(stats.count, 10) - 1 {
                    Divider().padding(.leading, 66)
                }
            }
        }
        .padding(16)
        .background(HomePalette.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - 日收支图（柱状/折线，支出/收入/全部）：月模式按日、年模式按月
    private var dailyChartCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("日收支统计")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(HomePalette.ink)
                Spacer()
                Button {
                    dailyChartType = dailyChartType == .bar ? .line : .bar
                } label: {
                    Image(systemName: dailyChartType == .bar ? "chart.bar.fill" : "chart.line.uptrend.xyaxis")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(HomePalette.secondary)
                }
            }

            DailyTrendChart(expense: vm.dailyExpense,
                            income: vm.dailyIncome,
                            isLine: dailyChartType == .line,
                            showExpense: dailyMode != .income,
                            showIncome: dailyMode != .expense)
                .frame(height: 130)

            Picker("维度", selection: $dailyMode) {
                ForEach(DailyMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            HStack {
                Text(vm.isYearMode ? "1月" : "1日")
                    .font(.footnote).foregroundColor(.secondary)
                Spacer()
                Text(vm.bucketEndLabel).font(.footnote).foregroundColor(.secondary)
            }
        }
        .padding(16)
        .background(HomePalette.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - 日报表（日期/收入/支出/余额 + 平均行，对齐 Web `.statistics-daily-report-table`）
    private struct DailyReportRow: Identifiable {
        let id: Int
        let label: String
        let income: Int64
        let expense: Int64
        var balance: Int64 { income - expense }
    }

    private var dailyReportRows: [DailyReportRow] {
        var rows: [DailyReportRow] = []
        if vm.isYearMode {
            for m in 1...12 {
                let inc = vm.dailyIncome.indices.contains(m - 1) ? vm.dailyIncome[m - 1] : 0
                let exp = vm.dailyExpense.indices.contains(m - 1) ? vm.dailyExpense[m - 1] : 0
                if inc == 0 && exp == 0 { continue }
                rows.append(DailyReportRow(id: m, label: "\(m)月", income: inc, expense: exp))
            }
        } else {
            for d in 1...vm.daysInMonth {
                let inc = vm.dailyIncome.indices.contains(d - 1) ? vm.dailyIncome[d - 1] : 0
                let exp = vm.dailyExpense.indices.contains(d - 1) ? vm.dailyExpense[d - 1] : 0
                if inc == 0 && exp == 0 { continue }
                rows.append(DailyReportRow(id: d, label: "\(vm.month)月\(d)日", income: inc, expense: exp))
            }
        }
        // 倒序：最新的日期排最前（平均行仍固定在表格底部）
        return Array(rows.reversed())
    }

    private var reportTotalIncome: Int64 { dailyReportRows.reduce(0) { $0 + $1.income } }
    private var reportTotalExpense: Int64 { dailyReportRows.reduce(0) { $0 + $1.expense } }

    private var dailyReportCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("日报表")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(HomePalette.ink)

            if dailyReportRows.isEmpty {
                Text("没有交易数据")
                    .font(.footnote)
                    .foregroundColor(HomePalette.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
            } else {
                reportHeaderRow
                ForEach(dailyReportRows) { row in
                    reportRow(label: row.label, income: row.income,
                              expense: row.expense, balance: row.balance, isAverage: false)
                }
                if vm.elapsedDaysInPeriod > 0 {
                    Divider()
                    reportRow(label: "平均",
                              income: reportTotalIncome / Int64(vm.elapsedDaysInPeriod),
                              expense: reportTotalExpense / Int64(vm.elapsedDaysInPeriod),
                              balance: (reportTotalIncome - reportTotalExpense) / Int64(vm.elapsedDaysInPeriod),
                              isAverage: true)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HomePalette.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var reportHeaderRow: some View {
        HStack(spacing: 8) {
            reportText("日期", weight: .regular, alignment: .leading, color: HomePalette.secondary)
            reportText("收入", weight: .regular, alignment: .trailing, color: HomePalette.secondary)
            reportText("支出", weight: .regular, alignment: .trailing, color: HomePalette.secondary)
            reportText("余额", weight: .regular, alignment: .trailing, color: HomePalette.secondary)
        }
    }

    private func reportRow(label: String, income: Int64, expense: Int64, balance: Int64,
                           isAverage: Bool) -> some View {
        let weight: Font.Weight = isAverage ? .semibold : .regular
        return HStack(spacing: 8) {
            reportText(label, weight: weight, alignment: .leading, color: HomePalette.ink)
            reportText(AmountFormat.format(income), weight: weight, alignment: .trailing, color: HomePalette.ink)
            reportText(AmountFormat.format(expense), weight: weight, alignment: .trailing, color: HomePalette.ink)
            reportText(AmountFormat.format(balance), weight: weight, alignment: .trailing,
                       color: balance < 0 ? HomePalette.expense : HomePalette.ink)
        }
    }

    private func reportText(_ text: String, weight: Font.Weight, alignment: Alignment,
                            color: Color) -> some View {
        Text(text)
            .font(.system(size: 13, weight: weight))
            .monospacedDigit()
            .foregroundColor(color)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(maxWidth: .infinity, alignment: alignment)
    }

    // MARK: - 查看账单明细（本 Tab 内原生 push，对齐 Web `viewTransactionDetails`）

    /// 底部「查看账单明细」链接：把当前统计的日期区间 + 筛选条件带到账单列表。
    private var viewDetailsLink: some View {
        Button {
            routeToDetail(type: 0)
        } label: {
            HStack {
                Spacer()
                Text("查看账单明细")
                    .font(.footnote)
                    .foregroundColor(Theme.brand)
                Spacer()
            }
            .padding(.vertical, 6)
        }
    }
}

// MARK: - 统计筛选面板

/// 多条件筛选面板：账户 / 分类 / 标签 / 描述（对齐 Web 统计页「更多」菜单）。
struct StatisticsFilterSheet: View {
    @ObservedObject var vm: StatisticsViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var accountIds: Set<String> = []
    @State private var categoryIds: Set<String> = []
    @State private var tagIds: Set<String> = []
    @State private var keyword = ""

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("账户")) {
                    ForEach(vm.accounts, id: \.id) { acc in
                        checkRow(acc.name, isOn: accountIds.contains(acc.id)) {
                            toggle(&accountIds, acc.id)
                        }
                    }
                }

                Section(header: Text("分类")) {
                    ForEach(flatCategories, id: \.id) { cat in
                        checkRow(cat.name, isOn: categoryIds.contains(cat.id)) {
                            toggle(&categoryIds, cat.id)
                        }
                    }
                }

                Section(header: Text("标签")) {
                    ForEach(vm.tagList, id: \.id) { tag in
                        checkRow(tag.name, isOn: tagIds.contains(tag.id)) {
                            toggle(&tagIds, tag.id)
                        }
                    }
                }

                Section(header: Text("描述")) {
                    TextField("交易描述关键字", text: $keyword)
                }

                Section {
                    Button("重置") {
                        accountIds = []
                        categoryIds = []
                        tagIds = []
                        keyword = ""
                    }
                    .foregroundColor(Theme.expense)
                }
            }
            .navigationTitle("筛选")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("应用") {
                        vm.filterAccountIds = accountIds
                        vm.filterCategoryIds = categoryIds
                        vm.filterTagIds = tagIds
                        vm.filterKeyword = keyword
                        vm.applyFilter()
                        dismiss()
                    }
                    .font(.body.weight(.semibold))
                }
            }
            .onAppear {
                accountIds = vm.filterAccountIds
                categoryIds = vm.filterCategoryIds
                tagIds = vm.filterTagIds
                keyword = vm.filterKeyword
            }
            .task { await vm.loadTagListIfNeeded() }
        }
    }

    /// 拍平一级 + 子分类（直接复用 VM 的拍平结果）
    private var flatCategories: [TransactionCategory] {
        vm.categoriesForFilter
    }

    private func checkRow(_ title: String, isOn: Bool, tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            HStack {
                Text(title).foregroundColor(.primary)
                Spacer()
                if isOn {
                    Image(systemName: "checkmark").foregroundColor(Theme.brand)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func toggle(_ arr: inout Set<String>, _ id: String) {
        if arr.contains(id) { arr.remove(id) } else { arr.insert(id) }
    }
}

// MARK: - 自绘饼图

/// 用 Canvas 自绘的环形占比图（iOS 15 无原生 Charts）
struct PieChart: View {
    /// (占比 0~1, 颜色)
    let slices: [(Double, Color)]

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            let center = CGPoint(x: rect.midX, y: rect.midY)
            let radius = min(size.width, size.height) / 2
            let lineWidth = radius * 0.42

            var startAngle = Angle(degrees: -90)
            for slice in slices {
                let sweep = Angle(degrees: 360 * slice.0)
                var path = Path()
                path.addArc(center: center, radius: radius - lineWidth / 2,
                            startAngle: startAngle, endAngle: startAngle + sweep,
                            clockwise: false)
                context.stroke(path, with: .color(slice.1),
                               style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                startAngle += sweep
            }
        }
        .padding(4)
    }
}

// MARK: - 自绘日收支图（柱状/折线，单/双系列）

/// 折线路径：把一组值映射为折线（iOS 15 无 Charts，自绘）
struct LinePath: Shape {
    let values: [Int64]
    let maxValue: Int64

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let count = max(values.count, 1)
        let width = rect.width
        let height = rect.height
        let stepX = count > 1 ? width / CGFloat(count - 1) : 0
        let baselineY = height - 3

        for (i, v) in values.enumerated() {
            let x = count == 1 ? width / 2 : CGFloat(i) * stepX
            let y = baselineY - height * CGFloat(Double(max(v, 0)) / Double(maxValue))
            let point = CGPoint(x: x, y: max(y, 3))
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }
}

/// 日收支图：柱状（单系列/双系列并列）或折线（单/双系列），
/// 对齐 Web `DailyIncomeExpenseBarChart` 的 bar/line 与 expense/income/all 三态
struct DailyTrendChart: View {
    let expense: [Int64]
    let income: [Int64]
    let isLine: Bool
    let showExpense: Bool
    let showIncome: Bool

    var body: some View {
        GeometryReader { geo in
            let count = max(max(expense.count, income.count), 1)
            let maxValue: Int64 = max(
                max(showExpense ? expense.max() ?? 0 : 0,
                    showIncome ? income.max() ?? 0 : 0), 1)
            let width = geo.size.width
            let height = geo.size.height

            ZStack(alignment: .bottom) {
                // 基线
                Rectangle().fill(Color.secondary.opacity(0.18))
                    .frame(height: 1)
                    .frame(maxHeight: .infinity, alignment: .bottom)

                if isLine {
                    lineSeries(width: width, height: height, maxValue: maxValue)
                } else {
                    barSeries(width: width, height: height, count: count, maxValue: maxValue)
                }
            }
        }
    }

    private func value(_ arr: [Int64], _ i: Int) -> Int64 {
        arr.indices.contains(i) ? arr[i] : 0
    }

    private func barHeight(_ v: Int64, _ maxValue: Int64, _ height: CGFloat) -> CGFloat {
        guard v > 0 else { return 0 }
        return max(height * CGFloat(Double(v) / Double(maxValue)), 2)
    }

    private func barSeries(width: CGFloat, height: CGFloat, count: Int, maxValue: Int64) -> some View {
        let slot = width / CGFloat(count)
        let groupWidth = min(slot - 2, 20)
        let singleWidth: CGFloat = (showExpense && showIncome) ? max((groupWidth - 2) / 2, 2) : groupWidth

        return HStack(alignment: .bottom, spacing: 0) {
            ForEach(0..<count, id: \.self) { i in
                HStack(alignment: .bottom, spacing: 1.5) {
                    if showExpense {
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(HomePalette.expense.opacity(0.85))
                            .frame(width: singleWidth,
                                   height: barHeight(value(expense, i), maxValue, height))
                    }
                    if showIncome {
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(HomePalette.income.opacity(0.85))
                            .frame(width: singleWidth,
                                   height: barHeight(value(income, i), maxValue, height))
                    }
                }
                .frame(width: slot, alignment: .bottom)
            }
        }
        .frame(maxWidth: .infinity, alignment: .bottom)
    }

    private func lineSeries(width: CGFloat, height: CGFloat, maxValue: Int64) -> some View {
        ZStack {
            if showExpense {
                LinePath(values: expense, maxValue: maxValue)
                    .stroke(HomePalette.expense,
                            style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
            if showIncome {
                LinePath(values: income, maxValue: maxValue)
                    .stroke(HomePalette.income,
                            style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
        }
        .frame(width: width, height: height)
    }
}
