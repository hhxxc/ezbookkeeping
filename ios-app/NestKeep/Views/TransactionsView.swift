import SwiftUI
import Combine

/// 汇总卡在背景图模式下给文字加投影（对应 Web `.has-bg` 的 `text-shadow`）
struct HomeShadow: ViewModifier {
    let active: Bool
    func body(content: Content) -> some View {
        if active {
            content.shadow(color: Color.black.opacity(0.35), radius: 2, x: 0, y: 1)
        } else {
            content
        }
    }
}

/// 账单筛选条件（对齐 Web 手机端账单筛选面板）
struct TransactionFilter: Equatable {
    /// 交易类型：0=全部，与 Go TransactionType 一致（1余额调整/2收入/3支出/4转账）
    var type: Int = 0
    var categoryIds: [String] = []
    var accountIds: [String] = []
    var startDate: Date?
    var endDate: Date?
    /// 排序字段：""=默认（数字关键词搜索时后端金额精确命中置顶），time / amount 为显式排序
    var sortBy: String = ""
    /// 排序方向：asc / desc
    var sortOrder: String = "desc"

    var isActive: Bool {
        type > 0 || !categoryIds.isEmpty || !accountIds.isEmpty || startDate != nil || endDate != nil
    }

    /// 生效条件数量（用于筛选按钮角标）
    var activeCount: Int {
        var n = 0
        if type > 0 { n += 1 }
        if !categoryIds.isEmpty { n += 1 }
        if !accountIds.isEmpty { n += 1 }
        if startDate != nil || endDate != nil { n += 1 }
        return n
    }

    mutating func reset() { self = TransactionFilter() }
}

/// 首页「日期范围」的 6 个区间（顺序与手机端 Web 的 `overview-transaction-list` 一致）。
/// `key` 即后端 `amounts.json` 的 query 类型名（见 `TransactionAmountsRequestType`）。
enum OverviewPeriod: String, CaseIterable, Identifiable {
    case today
    case yesterday
    case thisWeek
    case thisMonth
    case lastMonth
    case thisYear

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: return "今天"
        case .yesterday: return "昨天"
        case .thisWeek: return "本周"
        case .thisMonth: return "本月"
        case .lastMonth: return "上月"
        case .thisYear: return "今年"
        }
    }

    /// 图标徽章配色（取自 Web 的低饱和图表色板）
    var color: Color {
        switch self {
        case .today: return Color(hex: "#26A69A")
        case .yesterday: return Color(hex: "#8E7CC3")
        case .thisWeek: return Color(hex: "#5B8DB8")
        case .thisMonth: return Color(hex: "#DD9437")
        case .lastMonth: return Color(hex: "#879BAB")
        case .thisYear: return Color(hex: "#5DA65C")
        }
    }

    var icon: String {
        switch self {
        case .today: return "sun.max.fill"
        case .yesterday: return "moon.fill"
        case .thisWeek: return "square.grid.2x2.fill"
        case .thisMonth: return "calendar"
        case .lastMonth: return "arrow.counterclockwise.circle.fill"
        case .thisYear: return "square.stack.3d.up.fill"
        }
    }
}

/// 某个区间的起止（Unix **秒**，与 Web 的 startTime/endTime 同口径）
struct OverviewDateRange {
    let start: Int
    let end: Int
}

/// 区间详情页上下文（fullScreenCover(item:) 需要 Identifiable）
struct RangeDetailContext: Identifiable {
    let period: OverviewPeriod
    let range: OverviewDateRange
    var id: String { period.rawValue }
}

/// 账单页：顶部汇总卡（原首页内容）+ 按月分页列表，按日分组。
/// 结构对齐手机端 Web：Web 的首页内容并入本页顶部，底部不再有独立「首页」Tab。
@MainActor
final class TransactionsViewModel: ObservableObject {
    @Published var transactions: [Transaction] = []
    @Published var year: Int
    @Published var month: Int
    @Published var isLoading = false
    @Published var error: String?

    /// 汇总数据（原首页：总资产 + 本月收支）
    @Published var accounts: [Account] = []
    @Published var monthIncomeCents: Int64 = 0
    @Published var monthExpenseCents: Int64 = 0

    /// 6 个区间的日期边界（用于展示副标题 + 点击跳筛选）
    @Published var ranges: [OverviewPeriod: OverviewDateRange] = [:]
    /// 6 个区间的收支合计（元→分，与其它金额一致）
    @Published var periodIncome: [OverviewPeriod: Int64] = [:]
    @Published var periodExpense: [OverviewPeriod: Int64] = [:]
    /// 首页/账单页金额隐藏（眼睛图标切换，持久化）
    @Published var hideAmounts = UserDefaults.standard.bool(forKey: "nestkeep.hideAmounts") {
        didSet { UserDefaults.standard.set(hideAmounts, forKey: "nestkeep.hideAmounts") }
    }

    // 筛选条件（对齐 Web 的账单筛选）
    @Published var filter = TransactionFilter()
    @Published var searchKeyword = ""
    /// 是否处于筛选态（用于决定走 list.json 还是 by_month.json）
    var isFiltering: Bool { filter.isActive || !searchKeyword.isEmpty }

    private var categories: [TransactionCategory] = []
    private var searchTask: Task<Void, Never>?

    /// 供筛选面板使用的拍平分类列表
    var categoriesForFilter: [TransactionCategory] {
        categories.flatMap { c -> [TransactionCategory] in
            var arr = [c]
            if let subs = c.subCategories { arr.append(contentsOf: subs) }
            return arr
        }
    }

    init() {
        let comps = Calendar.current.dateComponents([.year, .month], from: Date())
        year = comps.year!
        month = comps.month!
    }

    /// 拍平可见账户（含子账户），与账户页 `AccountsView` 同一口径
    private func flattenAccounts(visibleOnly: Bool) -> [Account] {
        var result: [Account] = []
        for acc in accounts {
            if visibleOnly && (acc.hidden ?? false) { continue }
            if let subs = acc.subAccounts, !subs.isEmpty {
                for sub in subs where !(visibleOnly && (sub.hidden ?? false)) {
                    result.append(sub)
                }
            } else {
                result.append(acc)
            }
        }
        return result
    }

    /// 总资产（isAsset 或按类别推断，含子账户拍平，口径对齐账户页净资产卡）
    var totalAssetsCents: Int64 {
        flattenAccounts(visibleOnly: true)
            .filter { $0.category.map { AccountCategoryConst.isAsset($0) } ?? ($0.isAsset ?? false) }
            .reduce(0) { $0 + $1.balance }
    }

    /// 总负债（取绝对值累加）
    var totalLiabilitiesCents: Int64 {
        flattenAccounts(visibleOnly: true)
            .filter { $0.category.map { AccountCategoryConst.isLiability($0) } ?? ($0.isLiability ?? false) }
            .reduce(0) { $0 + abs($1.balance) }
    }

    /// 净资产 = 总资产 - 总负债
    var netAssetsCents: Int64 { totalAssetsCents - totalLiabilitiesCents }

    var monthNetCents: Int64 { monthIncomeCents - monthExpenseCents }

    /// 当前月是否就是本月（决定汇总卡是否展示「本月」）
    var isCurrentMonth: Bool {
        let comps = Calendar.current.dateComponents([.year, .month], from: Date())
        return comps.year == year && comps.month == month
    }

    var monthLabel: String { "\(month)月" }

    func load() async {
        isLoading = true
        error = nil
        do {
            // 四路并行；accounts/categories 走共享缓存（staleTime 内不发请求），
            // 下拉刷新时也就只刷账单和汇总，不再重拉账户/分类
            async let accs = AppDataStore.shared.getAccounts()
            async let cats = AppDataStore.shared.getCategories()
            async let txs = fetchTransactions()
            async let amounts: Void = loadAmounts()
            accounts = try await accs
            categories = try await cats
            transactions = try await txs
            await amounts
            isLoading = false
        } catch {
            isLoading = false
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// 按当前筛选态选择拉取方式：
    /// - 无筛选：走 by_month（按月浏览，滚动分页语义）
    /// - 有筛选/搜索：走 list.json（支持 category_ids / account_ids / type / keyword / 排序）
    private func fetchTransactions() async throws -> [Transaction] {
        if !isFiltering {
            let page: TransactionPage2 = try await APIClient.shared.request(
                "/api/v1/transactions/list/by_month.json",
                query: [
                    URLQueryItem(name: "year", value: "\(year)"),
                    URLQueryItem(name: "month", value: "\(month)"),
                    URLQueryItem(name: "count", value: "200"),
                    URLQueryItem(name: "sort_order", value: "desc")
                ]
            )
            return page.items
        }

        var query: [URLQueryItem] = [
            URLQueryItem(name: "count", value: "200"),
            URLQueryItem(name: "with_count", value: "true"),
            URLQueryItem(name: "sort_by", value: filter.sortBy),
            URLQueryItem(name: "sort_order", value: filter.sortOrder)
        ]
        if filter.type > 0 { query.append(URLQueryItem(name: "type", value: "\(filter.type)")) }
        if !filter.categoryIds.isEmpty {
            query.append(URLQueryItem(name: "category_ids", value: filter.categoryIds.joined(separator: ",")))
        }
        if !filter.accountIds.isEmpty {
            query.append(URLQueryItem(name: "account_ids", value: filter.accountIds.joined(separator: ",")))
        }
        // 日期范围：后端 max_time / min_time 是**毫秒级**时间序列 id（Unix 秒 × 1000）；
        // 结束日取当日 23:59:59.999，起始日取当日 00:00:00.000
        let cal = Calendar.current
        if let start = filter.startDate {
            let ts = Int(cal.startOfDay(for: start).timeIntervalSince1970) * 1000
            query.append(URLQueryItem(name: "min_time", value: "\(ts)"))
        }
        if let end = filter.endDate {
            let endOfDay = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: end)) ?? end
            let ts = Int(endOfDay.timeIntervalSince1970) * 1000 - 1
            query.append(URLQueryItem(name: "max_time", value: "\(ts)"))
        }
        if !searchKeyword.isEmpty {
            query.append(URLQueryItem(name: "keyword", value: searchKeyword))
        }
        let page: TransactionPage = try await APIClient.shared.request(
            "/api/v1/transactions/list.json", query: query
        )
        return page.items
    }

    /// 搜索防抖（300ms）
    func scheduleSearch() {
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled, let self = self else { return }
            await self.load()
        }
    }

    /// 应用筛选（筛选面板确认后调用）
    func applyFilter(_ newFilter: TransactionFilter) {
        filter = newFilter
        Task { await load() }
    }

    /// 应用跨 Tab 跳转带来的筛选请求（统计页「查看账单明细」等）。
    /// 与本地筛选不同：直接按请求里的日期/账户/分类/关键词构造筛选态。
    func applyFilterRequest(_ req: TransactionFilterRequest) {
        var f = TransactionFilter()
        f.type = req.type
        f.categoryIds = req.categoryIds
        f.accountIds = req.accountIds
        f.startDate = req.startDate
        f.endDate = req.endDate
        filter = f
        searchKeyword = req.keyword
        // 跳转过来的日期区间通常不是「本月」，若落在某月则同步年份月份标题
        if let start = req.startDate {
            let comps = Calendar.current.dateComponents([.year, .month], from: start)
            if let y = comps.year, let m = comps.month {
                year = y
                month = m
            }
        }
        Task { await load() }
    }

    func clearFilter() {
        filter = TransactionFilter()
        searchKeyword = ""
        Task { await load() }
    }

    /// 计算 6 个区间的 Unix 秒边界（口径完全对齐 Web 的 `initTransactionDateRange`）：
    /// - today / yesterday：本日与前一日的 00:00:00 ~ 23:59:59
    /// - thisWeek：以**周一**为一周之始（Web 用 currentUserFirstDayOfWeek，默认取 0 为周日；
    ///   此处按国内习惯固定周一，保证与用户预期一致）
    /// - thisMonth：本月 1 日 00:00 ~ 下月 1 日 00:00 前 1 秒
    /// - lastMonth：上月 1 日 00:00 ~ 本月 1 日 00:00 前 1 秒
    /// - thisYear：1 月 1 日 00:00 ~ 次年 1 月 1 日 00:00 前 1 秒
    private func buildRanges() -> [OverviewPeriod: OverviewDateRange] {
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: Date())
        guard let tomorrow = cal.date(byAdding: .day, value: 1, to: todayStart),
              let yesterdayStart = cal.date(byAdding: .day, value: -1, to: todayStart),
              let thisMonthStart = cal.date(from: cal.dateComponents([.year, .month], from: todayStart)),
              let nextMonthStart = cal.date(byAdding: .month, value: 1, to: thisMonthStart),
              let lastMonthStart = cal.date(byAdding: .month, value: -1, to: thisMonthStart),
              let thisYearStart = cal.date(from: cal.dateComponents([.year], from: todayStart)),
              let nextYearStart = cal.date(byAdding: .year, value: 1, to: thisYearStart) else { return [:] }

        // 本周起始：以周一为第一天（Calendar 的 weekday：1=周日…2=周一）
        let weekdayOffset = (cal.component(.weekday, from: todayStart) + 5) % 7   // 周一→0，周日→6
        guard let thisWeekStart = cal.date(byAdding: .day, value: -weekdayOffset, to: todayStart),
              let nextWeekStart = cal.date(byAdding: .day, value: 7, to: thisWeekStart) else { return [:] }

        func range(_ start: Date, _ exclusiveEnd: Date) -> OverviewDateRange {
            OverviewDateRange(
                start: Int(start.timeIntervalSince1970),
                end: Int(exclusiveEnd.timeIntervalSince1970) - 1
            )
        }

        return [
            .today: range(todayStart, tomorrow),
            .yesterday: range(yesterdayStart, todayStart),
            .thisWeek: range(thisWeekStart, nextWeekStart),
            .thisMonth: range(thisMonthStart, nextMonthStart),
            .lastMonth: range(lastMonthStart, thisMonthStart),
            .thisYear: range(thisYearStart, nextYearStart)
        ]
    }

    /// 一次请求拉取 6 个区间的收支合计（用于汇总卡与日期范围卡）。
    /// 请求形如：
    ///   GET /api/v1/transactions/amounts.json?use_transaction_timezone=true
    ///       &query=today_<s>_<e>|yesterday_<s>_<e>|...
    private func loadAmounts() async {
        let built = buildRanges()
        guard !built.isEmpty else { return }
        ranges = built

        // 顺序与 Web 的 ALL_TRANSACTION_AMOUNTS_REQUEST_TYPE 保持一致
        let ordered = OverviewPeriod.allCases.compactMap { p -> String? in
            guard let r = built[p] else { return nil }
            return "\(p.rawValue)_\(r.start)_\(r.end)"
        }
        guard let dict: [String: TransactionAmountsResponseItem] = try? await APIClient.shared.request(
            "/api/v1/transactions/amounts.json",
            query: [
                URLQueryItem(name: "use_transaction_timezone", value: "true"),
                URLQueryItem(name: "query", value: ordered.joined(separator: "|"))
            ]
        ) else { return }

        var income: [OverviewPeriod: Int64] = [:]
        var expense: [OverviewPeriod: Int64] = [:]
        for p in OverviewPeriod.allCases {
            guard let item = dict[p.rawValue] else { continue }
            var inc: Int64 = 0
            var exp: Int64 = 0
            for a in (item.amounts ?? []) where a.currency == "CNY" || a.currency == nil {
                inc += a.incomeAmount ?? 0
                exp += a.expenseAmount ?? 0
            }
            income[p] = inc
            expense[p] = exp
        }
        periodIncome = income
        periodExpense = expense
        // 汇总卡沿用「本月」口径
        monthIncomeCents = income[.thisMonth] ?? 0
        monthExpenseCents = expense[.thisMonth] ?? 0
    }

    // MARK: - 日期范围卡展示辅助（与 Web 的 displayDateRange 一致）

    /// 区间副标题 —— 严格对齐 Web `HomePageBase.ts` 的 `displayDateRange`：
    /// - today / yesterday → `formatDateTimeToLongDate`（「2026年10月8日」）
    /// - thisWeek / thisMonth / lastMonth → `startTime` – `endTime`（各为「10月4日」）
    /// - thisYear → `formatDateTimeToGregorianLikeLongYear`（「2026年」）
    func rangeSubtitle(_ period: OverviewPeriod) -> String {
        guard let r = ranges[period] else { return "" }
        let start = Date(timeIntervalSince1970: TimeInterval(r.start))
        let end = Date(timeIntervalSince1970: TimeInterval(r.end))
        switch period {
        case .today, .yesterday:
            return Self.longDateFormatter.string(from: start)
        case .thisYear:
            return Self.yearFormatter.string(from: start)
        default:
            // Web 用 en dash（–）前后各留一个空格
            return "\(Self.monthDayFormatter.string(from: start)) – \(Self.monthDayFormatter.string(from: end))"
        }
    }

    /// 汇总卡左上角的月份标题 —— 对齐 Web `formatDateTimeToGregorianLikeLongMonth` 的**实际渲染**：
    /// Web 端 moment 的活动 locale 实际停留在 en（自定义 locale key 未生效），中文界面下
    /// `MMMM` 仍渲染英文长月名（如「October」，见 Web 手机端截图），故此处直接用英文月名
    var summaryMonthTitle: String {
        Self.englishMonthName(month)
    }

    /// 公历月份 → 英文长月名（对齐 Web 卡片标题的实际渲染「January…December」）
    private static func englishMonthName(_ month: Int) -> String {
        let names = ["January", "February", "March", "April", "May", "June",
                     "July", "August", "September", "October", "November", "December"]
        guard month >= 1 && month <= 12 else { return "\(month)月" }
        return names[month - 1]
    }

    private static let longDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy年M月d日"
        return f
    }()

    private static let monthDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日"
        return f
    }()

    private static let yearFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy年"
        return f
    }()

    /// 日历点某天 → 只筛选该日
    func selectDay(_ date: Date) {
        filter = TransactionFilter()
        searchKeyword = ""
        filter.startDate = date
        filter.endDate = date
        Task { await load() }
    }

    func income(for period: OverviewPeriod) -> Int64 { periodIncome[period] ?? 0 }
    func expense(for period: OverviewPeriod) -> Int64 { periodExpense[period] ?? 0 }

    func shiftMonth(by delta: Int) {
        var comps = DateComponents(year: year, month: month)
        comps.month! += delta
        guard let date = Calendar.current.date(from: comps) else { return }
        let newComps = Calendar.current.dateComponents([.year, .month], from: date)
        year = newComps.year!
        month = newComps.month!
        Task { await load() }
    }

    func accountName(_ id: String?) -> String {
        accounts.first { $0.id == id }?.name ?? "—"
    }

    func categoryName(_ id: String?) -> String {
        guard let id = id else { return "—" }
        for c in categories {
            if c.id == id { return c.name }
            if let subs = c.subCategories, let hit = subs.first(where: { $0.id == id }) {
                return hit.name
            }
        }
        return "—"
    }

    func categoryColor(_ id: String?) -> Color {
        guard let id = id else { return Theme.brand }
        for c in categories {
            if c.id == id, let color = c.color { return Color(hex: color) }
            if let subs = c.subCategories, let hit = subs.first(where: { $0.id == id }), let color = hit.color {
                return Color(hex: color)
            }
        }
        return Theme.brand
    }

    /// 分类 SF Symbol 名（经 CategoryIconCatalog 编号映射）。
    /// 返回 nil 表示找不到分类（转账/余额调整等），行 UI 回退交易类型图标
    func categoryIcon(_ id: String?) -> String? {
        guard let id = id else { return nil }
        for c in categories {
            if c.id == id { return CategoryIconCatalog.symbol(c.icon) }
            if let subs = c.subCategories, let hit = subs.first(where: { $0.id == id }) {
                return CategoryIconCatalog.symbol(hit.icon)
            }
        }
        return nil
    }

    /// 左滑删除：走 POST /transactions/delete.json
    func delete(_ tx: Transaction) async {
        do {
            let req = TransactionDeleteRequest(id: tx.id)
            let _: EmptyResult = try await APIClient.shared.request(
                "/api/v1/transactions/delete.json", method: .POST, body: req
            )
            transactions.removeAll { $0.id == tx.id }
            await loadAmounts()
            AppDataStore.shared.invalidateAccounts()
        } catch {
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// 今日合计（用于日分组头右侧）
    func dayExpense(_ items: [Transaction]) -> Int64 {
        items.filter { $0.transactionType == .expense }.reduce(0) { $0 + $1.sourceAmount }
    }

    func dayIncome(_ items: [Transaction]) -> Int64 {
        items.filter { $0.transactionType == .income }.reduce(0) { $0 + $1.sourceAmount }
    }
}

struct TransactionsView: View {
    @StateObject private var vm = TransactionsViewModel()
    @Binding var showAdd: Bool
    // 底部避让由 MainTabView 统一施加；本页不再需要读取 mainTabBarInset
    @ObservedObject private var serverSettings = ServerSettings.shared
    /// 底栏内容高度（MainTabView 经环境值下发）：iOS 15 上 safeAreaInset 穿不透
    /// NavigationView，滚动内容末尾需自行留出底栏高度，避免最后一张卡被底栏挡住
    @Environment(\.mainTabBarInset) private var tabBarInset
    /// 跨 Tab 路由（统计页跳转时应用筛选）
    @EnvironmentObject private var router: TabRouter
    @State private var editing: Transaction?
    @State private var duplicating: Transaction?
    @State private var detail: Transaction?
    /// 点击区间行 → 推入「区间详情页」（对齐 Web 的 /transaction/list?dateType=...）
    @State private var detailContext: RangeDetailContext?
    /// 首页搜索入口：推入账单列表页时自动聚焦搜索框（消费后由 onChange 复位）
    @State private var pushListWithSearch = false
    /// 账单列表独立页（点击汇总卡从右侧滑入）；筛选/搜索入口都在该页
    @State private var showListPage = false
    /// 列表 / 日历 两种浏览方式（对齐 Web 的 TransactionListPageType）
    @State private var showCalendar = false
    /// AI 识图直连流程：点入口直接拉起相册，选完图进识别页
    @StateObject private var aiFlow = AIReceiptFlow()
    /// 语音记账流程：语音页解析成功 → 结果确认页
    @StateObject private var voiceFlow = AIVoiceFlow()
    /// 汇总卡右上角「换背景图」入口
    @State private var showBackgroundSheet = false
    @StateObject private var calendarVM = TransactionCalendarViewModel()
    /// 首页背景图变化时刷新汇总卡底图
    @State private var backgroundToken = UUID()

    init(showAdd: Binding<Bool> = .constant(false)) {
        _showAdd = showAdd
    }

    /// 进入账单列表页（系统原生 push 动画）
    private func openListPage() {
        showListPage = true
    }

    var body: some View {
        // 首页包在 NavigationView 里：日历页/账单列表页/区间详情页改为**系统原生 push**
        //（NavigationLink 编程式跳转），获得标准视差滑动、边缘阴影与左滑跟手返回。
        // 顶栏用 VStack 放列表上方（不悬浮）：iOS 15 下 safeAreaInset+List 的内容避让不可靠，
        // 汇总卡顶部会被固定栏压住；改为上下结构后列表恒从栏下方开始，栏体不透明观感不变。
        // 顶栏放进 ScrollView 内容里随页滚动：内容超出视口时上滑顶栏先滚走，
        // 滚动停顿后汇总卡顶部恰好停在状态栏下方（不与状态栏/顶栏重叠）；
        // 不用 safeAreaInset 悬浮（iOS 15 下其内容避让不可靠，汇总卡顶部会被压住）。
        NavigationView {
            ScrollView {
                VStack(spacing: 0) {
                    topBar
                    // 首页只留总览卡片区：汇总卡 + 日期范围卡 + AI 识图入口。
                    // 账单列表（搜索/日分组/左滑操作）整体移入 BillListPageView，点汇总卡推入。
                    // 用 ScrollView+VStack 自控间距：insetGrouped List 首组顶部有 ~30pt 系统默认
                    // 留白（iOS 15 无 listSectionSpacing，收不掉），导致顶栏与汇总卡间隙过大。
                    VStack(spacing: 0) {
                        summaryCard
                            // 顶部 8 + 顶栏底部 4 = 12pt 紧凑间隙（与卡间距节奏一致）；
                            // 水平 17pt 沿用原 insetGrouped 的系统分组边距
                            .contentShape(Rectangle())
                            // 点汇总卡 → 原生 push 账单列表页（内部的小按钮如隐藏金额/换背景不受影响）
                            .onTapGesture { openListPage() }
                            .padding(.top, 8)
                            .padding(.bottom, 12)

                        // 检索框（首页入口）：样式与账单列表页搜索框一致，
                        // 点击推入列表页并自动聚焦搜索框，不直接在首页输入
                        Button {
                            pushListWithSearch = true
                            openListPage()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.secondary)
                                Text("搜索备注 / 金额")
                                    .font(.system(size: 15))
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(HomePalette.card)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .padding(.bottom, 12)

                        periodCard

                        // AI 识图/语音入口常驻：不再依赖 server_settings 开关门控——
                        // 开关拉取失败（隧道未就绪等）会导致入口整场消失，反复修不好；
                        // 后端未开启时点进去会收到明确报错，比入口凭空消失更可理解。
                        // 两入口并排一行（原两张全宽卡纵向堆叠把语音卡压到底栏下）
                        aiEntryRow
                            .padding(.top, 12)
                    }
                    .padding(.horizontal, 17)
                    // iOS 15：MainTabView 的 safeAreaInset 穿不透 NavigationView，
                    // 内容末尾自行留出「底栏高度 + 底部安全区 + 呼吸空间」，
                    // 否则最后一张卡（AI 识图/语音入口）会被底栏盖住
                    .padding(.bottom, tabBarInset + ScreenMetrics.bottomSafeInset + 16)
                    // 隐藏右侧滚动指示条（iOS 15 上 UIScrollView.appearance 不生效，
                    // 通过 overlay 视图的响应链向上找到所属 UIScrollView 直接关闭）
                    // allowsHitTesting(false)：overlay 视图绝不能参与命中测试，否则页面点不动
                    .overlay(ScrollIndicatorHider().allowsHitTesting(false))
                    // iOS 15 下 ScrollView 不支持 .refreshable（iOS 16+ 才有），
                    // 通过同样的响应链手法给 UIScrollView 挂真 UIRefreshControl
                    .overlay(ScrollRefreshAttacher { await vm.load() }.allowsHitTesting(false))
                }
                // 首页隐藏系统导航栏（自绘顶栏替代）；推入的二级页会自动显示导航栏
                .navigationBarHidden(true)
            }
            .refreshable { await vm.load() }
            // 返回首页后复位搜索聚焦标记，下次普通点汇总卡不再弹键盘；
            // 同时清掉筛选态/搜索词，避免"不点清除就一直在"的残留
            .onChange(of: showListPage) { visible in
                if !visible {
                    pushListWithSearch = false
                    if vm.isFiltering { vm.clearFilter() }
                }
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            // 隐藏的编程式导航链接（iOS 15 手法）：三个二级页全部走系统 push
            .background(
                VStack {
                    NavigationLink(
                        destination: CalendarPageView(vm: calendarVM) { date in
                            // 选定日期：pop 日历页，落定后再 push 账单列表页看当日账单
                            vm.selectDay(date)
                            showCalendar = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                                showListPage = true
                            }
                        },
                        isActive: $showCalendar
                    ) { EmptyView() }

                    NavigationLink(
                        destination: BillListPageView(vm: vm, onEdit: { tx in
                            editing = tx
                        }, onDuplicate: { tx in
                            duplicating = tx
                        }, onDetail: { tx in
                            detail = tx
                        }, focusSearchOnAppear: pushListWithSearch),
                        isActive: $showListPage
                    ) { EmptyView() }

                    NavigationLink(destination: detailDestination, isActive: detailActive) { EmptyView() }
                }
            )
        }
        .navigationViewStyle(.stack)
        // AI 识图直连流程：点入口直接拉起相册，选完图进识别页，关闭后刷新首页
        .modifier(AIReceiptFlowModifier(flow: aiFlow, onReceiptDismiss: {
            Task { await vm.load() }
        }))
        // 语音记账流程：语音页解析成功 → 结果确认页，关闭后刷新首页
        .modifier(AIVoiceFlowModifier(flow: voiceFlow, onResultsDismiss: {
            Task { await vm.load() }
        }))
        .sheet(isPresented: $showBackgroundSheet) {
            NavigationView {
                HomeBackgroundSettingsView()
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("完成") { showBackgroundSheet = false }
                        }
                    }
            }
        }
        .sheet(item: $editing, onDismiss: {
            // 编辑保存后刷新首页列表与区间汇总
            Task { await vm.load() }
        }) { tx in
            TransactionEditView(transaction: tx, mode: .edit)
        }
        .sheet(item: $duplicating, onDismiss: {
            // 复制落库后刷新首页列表与区间汇总
            Task { await vm.load() }
        }) { tx in
            TransactionEditView(transaction: tx, mode: .duplicate)
        }
        .sheet(item: $detail, onDismiss: {
            // 从详情页内部编辑/复制后，关闭详情时刷新
            Task { await vm.load() }
        }) { tx in
            TransactionDetailView(transaction: tx, onChanged: {
                Task { await vm.load() }
            })
        }
        .task {
            await ServerSettings.shared.loadIfNeeded()
            // 与云端同步背景图（Web 端设置的背景图原生共用）
            await HomeBackground.syncFromCloud()
            await vm.load()
        }
        .onReceive(NotificationCenter.default.publisher(for: .homeBackgroundChanged)) { _ in
            // 切背景图后刷新汇总卡底图
            backgroundToken = UUID()
        }
        .onReceive(NotificationCenter.default.publisher(for: .transactionsChanged)) { _ in
            // 加号长按菜单等别的入口落库了交易（如 AI 识图批量添加）→ 刷新首页
            Task { await vm.load() }
        }
        // 跨 Tab 跳转：统计页「查看账单明细」等 → 应用筛选并原生 push 账单列表页
        .onChange(of: router.pendingTransactionFilter) { request in
            guard let request = request else { return }
            vm.applyFilterRequest(request)
            router.pendingTransactionFilter = nil
            openListPage()
        }
    }

    /// 区间详情页的 push 目标（detailContext 非空时才有内容）
    private var detailDestination: some View {
        Group {
            if let ctx = detailContext {
                RangeDetailView(context: ctx, mainVM: vm)
            } else {
                EmptyView()
            }
        }
    }

    /// 由 RangeDetailContext 派生的 isActive 绑定（pop 时清空 context）
    private var detailActive: Binding<Bool> {
        Binding(
            get: { detailContext != nil },
            set: { if !$0 { detailContext = nil } }
        )
    }

    /// 极简顶部工具行：月份切换 + 搜索/清筛选 + 列表·日历切换 + 筛选 + 新增。
    /// 用 `overlay` 悬浮在列表之上（透明底、无导航栏），与 Web 的无导航栏观感一致。
    private var topBar: some View {
        HStack(spacing: 10) {
            // 月份切换胶囊：左箭头 · 月份 · 右箭头
            HStack(spacing: 14) {
                Button { vm.shiftMonth(by: -1) } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.plain)

                Text(verbatim: "\(vm.year)年\(vm.month)月")
                    .font(.system(size: 15, weight: .semibold))
                    .monospacedDigit()
                    .frame(minWidth: 78)

                Button { vm.shiftMonth(by: 1) } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.plain)
            }
            .foregroundColor(HomePalette.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
            .overlay(
                Capsule().strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
            )

            Spacer()

            // 右侧图标组：日历（筛选/搜索入口已移入账单列表页；加号与底栏重复也移除）
            HStack(spacing: 6) {
                iconBarButton(
                    icon: "calendar",
                    active: showCalendar
                ) {
                    showCalendar = true
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 4)
        // 固定顶栏背景：与页面同底色并延伸进状态栏区域，底部一条细分隔线
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

    /// 顶部工具行的单个胶囊图标按钮
    private func iconBarButton(icon: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(active ? Theme.brand : HomePalette.ink)
                .frame(width: 34, height: 34)
                .background(
                    Circle()
                        .fill(active ? Theme.brand.opacity(0.14) : Color.primary.opacity(0.05))
                )
        }
        .buttonStyle(.plain)
    }

    /// AI 识图 / 语音记账入口：一行两条横向紧凑按钮。
    /// 历史教训：两张「图标在上+标题副标题在下」的竖排卡高 ~106pt，
    /// 把整页撑超一屏，底部入口被 tabbar 压住显示不全；
    /// 压缩为「图标徽章 + 标题同行」的 48pt 矮条后整页收进一屏
    private var aiEntryRow: some View {
        HStack(spacing: 12) {
            entryButton(title: "AI 识图", icon: "camera.fill") {
                aiFlow.start()
            }
            entryButton(title: "语音记账", icon: "mic.fill") {
                voiceFlow.start()
            }
        }
    }

    /// 紧凑入口按钮：图标徽章 + 标题横向排布，宽度对半分
    private func entryButton(title: String, icon: String,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Theme.brand)
                    .frame(width: 30, height: 30)
                    .background(Theme.brand.opacity(0.13))
                    .cornerRadius(9)
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(HomePalette.ink)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity)
            .background(HomePalette.card)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 汇总卡（对齐 Web `.home-summary-card`）
    /// 两段：① 月份+支出徽标+隐藏金额开关 ② 大金额 + 当月收入/月结余。
    /// 净资产/总资产/总负债概览已按需求移除（账户页仍有完整净资产卡）。
    /// 设置背景图后转为白字 + 投影（对应 Web 的 `.has-bg`）。
    private var summaryCard: some View {
        // 依赖 backgroundToken：用户更换/移除背景图后触发重建
        let bgURL = HomeBackground.imageURL
        _ = backgroundToken
        let hasBG = bgURL != nil
        // 有背景图时统一走白色系
        let primaryText: Color = hasBG ? .white : HomePalette.ink
        let secondaryText: Color = hasBG ? Color.white.opacity(0.9) : HomePalette.secondary
        let balance = vm.monthNetCents

        return VStack(alignment: .leading, spacing: 0) {
            // ① 月份 + 支出徽标 + 隐藏金额开关
            // trailing 32：给右上角悬浮的「换背景图」按钮（30×30、距边 12，占 12~42pt）让位，
            // 否则行尾的眼睛按钮会被它整个盖住（点不到也看不见）
            HStack(spacing: 8) {
                Text(vm.summaryMonthTitle)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(primaryText)
                Text("支出")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(hasBG ? .white : HomePalette.expense)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 2)
                    .background(hasBG ? Color.white.opacity(0.22) : HomePalette.expenseBg)
                    .cornerRadius(8)
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.16)) { vm.hideAmounts.toggle() }
                } label: {
                    Image(systemName: vm.hideAmounts ? "eye.slash.fill" : "eye.fill")
                        .font(.system(size: 16))
                        .foregroundColor(secondaryText)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.trailing, 32)
            .padding(.bottom, 6)

            // 大支出金额
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(vm.hideAmounts ? "＊＊＊＊" : AmountFormat.format(vm.monthExpenseCents))
                    .font(.system(size: 30, weight: .semibold))
                    .monospacedDigit()
                    .foregroundColor(primaryText)
                    .minimumScaleFactor(0.55)
                    .lineLimit(1)
                    .modifier(HomeShadow(active: hasBG))
            }
            .padding(.bottom, 10)

            // ③ 当月收入 · 月结余
            HStack(alignment: .top, spacing: 0) {
                metricCell(
                    label: "当月收入",
                    value: vm.hideAmounts ? "＊＊＊" : AmountFormat.format(vm.monthIncomeCents),
                    valueColor: hasBG ? .white : HomePalette.income,
                    labelColor: secondaryText,
                    shadow: hasBG
                )
                Rectangle()
                    .fill(hasBG ? Color.white.opacity(0.28) : HomePalette.divider)
                    .frame(width: 1)
                    .padding(.trailing, 16)
                metricCell(
                    label: "月结余",
                    value: vm.hideAmounts ? "＊＊＊" : AmountFormat.format(balance),
                    valueColor: hasBG ? .white : (balance >= 0 ? HomePalette.income : HomePalette.expense),
                    labelColor: secondaryText,
                    shadow: hasBG
                )
                Spacer(minLength: 0)
            }
            .padding(.top, 12)
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack {
                HomePalette.card
                if let url = bgURL {
                    CachedAsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Color.clear
                    }
                    // 图片上再压一层中性蒙层，保证白字可读（不使用主色渐变，
                    // 以免与 Web 的「原图 + 白字」观感不符）
                    Color.black.opacity(0.28)
                }
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(alignment: .topTrailing) {
            // 换背景图入口（对应 Web 的 `.home-card-gallery-btn`：30×30、圆角 8）
            Button { showBackgroundSheet = true } label: {
                Image(systemName: "photo.on.rectangle")
                    .font(.system(size: 17))
                    .foregroundColor(hasBG ? Color.white.opacity(0.85) : Color.black.opacity(0.35))
                    .frame(width: 30, height: 30)
                    .background(hasBG ? Color.black.opacity(0.30) : Color.black.opacity(0.04))
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .padding(12)
        }
        .shadow(color: Color.black.opacity(HomePalette.isDark ? 0.5 : 0.08), radius: 10, x: 0, y: 4)
    }

    /// 汇总卡底部指标单元（13pt 标签 / 15pt semibold 数值，与区间行金额同规格）
    private func metricCell(label: String, value: String,
                            valueColor: Color, labelColor: Color, shadow: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(labelColor)
                .modifier(HomeShadow(active: shadow))
            Text(verbatim: value)
                .font(.system(size: 15, weight: .semibold))
                .monospacedDigit()
                .foregroundColor(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .modifier(HomeShadow(active: shadow))
        }
        .padding(.trailing, 16)
    }

    // MARK: - 日期范围卡（6 区间）
    /// 每行：彩色图标徽章 + 标题/日期副标题 + 右侧收入/支出双金额；点击按该区间筛选账单
    private var periodCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(OverviewPeriod.allCases.enumerated()), id: \.element.id) { idx, period in
                Button {
                    // 对齐 Web：点区间行 → 推入区间详情页（/transaction/list?dateType=...）
                    if let r = vm.ranges[period] {
                        detailContext = RangeDetailContext(period: period, range: r)
                    }
                } label: {
                    periodRow(period)
                }
                .buttonStyle(.plain)
                if idx < OverviewPeriod.allCases.count - 1 {
                    // 58 = 行左 padding 14 + 图标 32 + 间距 12，分隔线与标题文字左缘对齐
                    Divider().padding(.leading, 58)
                }
            }
        }
        .background(HomePalette.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: Color.black.opacity(HomePalette.isDark ? 0.5 : 0.06), radius: 10, x: 0, y: 4)
    }

    private func periodRow(_ period: OverviewPeriod) -> some View {
        HStack(spacing: 12) {
            Image(systemName: period.icon)
                .font(.system(size: 17))
                .foregroundColor(period.color)
                .frame(width: 32, height: 32)
                .background(period.color.opacity(0.14))
                .cornerRadius(10)

            VStack(alignment: .leading, spacing: 3) {
                Text(period.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(HomePalette.ink)
                Text(verbatim: vm.rangeSubtitle(period))
                    .font(.system(size: 13))
                    .foregroundColor(HomePalette.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            // 右侧收支双金额：与汇总卡指标同规格（15 semibold 等宽数字）
            VStack(alignment: .trailing, spacing: 3) {
                Text(verbatim: vm.hideAmounts ? "＊＊＊" : AmountFormat.format(vm.income(for: period)))
                    .font(.system(size: 15, weight: .semibold))
                    .monospacedDigit()
                    .foregroundColor(HomePalette.income)
                    .lineLimit(1)
                Text(verbatim: vm.hideAmounts ? "＊＊＊" : AmountFormat.format(vm.expense(for: period)))
                    .font(.system(size: 15, weight: .semibold))
                    .monospacedDigit()
                    .foregroundColor(HomePalette.expense)
                    .lineLimit(1)
            }
            .minimumScaleFactor(0.7)

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Color(.tertiaryLabel))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    static func dayLabel(_ d: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(d) { return "今天" }
        if cal.isDateInYesterday(d) { return "昨天" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日 EEEE"
        return f.string(from: d)
    }
}

// MARK: - 滚动指示条隐藏（iOS 15 兼容）
/// iOS 15 上 `UIScrollView.appearance().shows*ScrollIndicator = false` 对 SwiftUI 的
/// ScrollView 不生效（系统在创建时未走 appearance 代理），且 `.scrollIndicators(.hidden)`
/// 要 iOS 16+。这里把一个透明 UIView 放进滚动内容内部，经响应链向上找到所属
/// UIScrollView 直接关掉指示条——该属性一旦置 false 即持续生效，无需反复刷新。
/// 注意必须放在滚动内容**内部**（overlay 在内容上而非 ScrollView 外层），
/// 否则响应链不经过 UIScrollView。
private struct ScrollIndicatorHider: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async { Self.hideIndicators(from: uiView) }
    }

    static func hideIndicators(from view: UIView) {
        var responder: UIResponder? = view
        while let next = responder?.next {
            if let scrollView = next as? UIScrollView {
                scrollView.showsVerticalScrollIndicator = false
                scrollView.showsHorizontalScrollIndicator = false
                return
            }
            responder = next
        }
    }
}

/// iOS 15 的 ScrollView 下拉刷新补丁：`.refreshable` 在 iOS 15 只对 List 生效，
/// ScrollView 要 iOS 16+ 才原生支持。此视图作为滚动内容的 overlay，沿响应链找到
/// 所属 UIScrollView 后挂一个真 UIRefreshControl（UIScroll 挂 UIRefreshControl
/// 自 iOS 10 起实测稳定）。iOS 16+ 直接交给系统 `.refreshable`，不做任何事，避免双刷新控件。
/// 同样必须放在滚动内容**内部**（overlay 在内容上而非 ScrollView 外层），响应链才经过 UIScrollView。
/// （模块内可见：AccountsView 的 ScrollView 列表同样使用）
struct ScrollRefreshAttacher: UIViewRepresentable {
    let onRefresh: () async -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        let action = onRefresh
        DispatchQueue.main.async { Self.attach(from: uiView, onRefresh: action) }
    }

    static func attach(from view: UIView, onRefresh: @escaping () async -> Void) {
        if #available(iOS 16.0, *) { return }
        var responder: UIResponder? = view
        while let next = responder?.next {
            if let scrollView = next as? UIScrollView {
                if let box = objc_getAssociatedObject(scrollView, &ScrollRefreshAttacher.associatedKey) as? RefreshBox {
                    box.onRefresh = onRefresh
                } else {
                    let box = RefreshBox(scrollView: scrollView, onRefresh: onRefresh)
                    objc_setAssociatedObject(scrollView, &ScrollRefreshAttacher.associatedKey, box, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
                }
                return
            }
            responder = next
        }
    }

    private static var associatedKey: UInt8 = 0

    /// 持有 UIRefreshControl 与回调；关联到 scrollView 上保活
    private final class RefreshBox: NSObject {
        private weak var scrollView: UIScrollView?
        private let control = UIRefreshControl()
        var onRefresh: () async -> Void

        init(scrollView: UIScrollView, onRefresh: @escaping () async -> Void) {
            self.scrollView = scrollView
            self.onRefresh = onRefresh
            super.init()
            control.addTarget(self, action: #selector(pullTriggered), for: .valueChanged)
            scrollView.addSubview(control)
        }

        @objc private func pullTriggered() {
            // Tint 与页面浅色背景协调
            control.tintColor = .secondaryLabel
            let action = onRefresh
            Task { @MainActor in
                await action()
                self.control.endRefreshing()
            }
        }
    }
}

// MARK: - 账单列表独立页（点击首页汇总卡从右侧滑入）
/// 承载原首页的交易列表：搜索 / 加载与空态 / 日分组 / 左滑编辑删除；
/// 筛选面板与搜索框也收在该页（首页只留总览卡片）。
/// 通过 NavigationLink 原生 push 进入，导航栏由系统提供（左滑跟手返回）。
private struct BillListPageView: View {
    @ObservedObject var vm: TransactionsViewModel
    let onEdit: (Transaction) -> Void
    let onDuplicate: (Transaction) -> Void
    let onDetail: (Transaction) -> Void
    /// 从首页搜索入口进入时自动聚焦搜索框并弹键盘
    var focusSearchOnAppear: Bool = false
    @State private var showFilter = false
    @FocusState private var searchFieldFocused: Bool

    private var grouped: [(date: Date, items: [Transaction])] {
        let cal = Calendar.current
        // 搜索/筛选态（走 list.json）时后端可能返回相关性排序（如金额精确命中置顶），
        // 采用「连续同一天保序分组」：只合并相邻同日行、不重排，保留后端顺序；
        // 非搜索态（by_month 按月浏览）保持原按天倒序分组逻辑。
        if vm.isFiltering {
            var groups: [(date: Date, items: [Transaction])] = []
            for tx in vm.transactions {
                let day = cal.startOfDay(for: tx.date)
                if let last = groups.last, last.date == day {
                    groups[groups.count - 1].items.append(tx)
                } else {
                    groups.append((day, [tx]))
                }
            }
            return groups
        }
        let dict = Dictionary(grouping: vm.transactions) { cal.startOfDay(for: $0.date) }
        return dict.keys.sorted(by: >).map { ($0, dict[$0] ?? []) }
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color(.systemGroupedBackground).ignoresSafeArea()
            List {
                // 搜索框（对齐 Web 的描述/金额关键字搜索，防抖；胶囊样式）
                Section {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                        TextField("搜索备注 / 金额", text: $vm.searchKeyword)
                            .textFieldStyle(.plain)
                            .focused($searchFieldFocused)
                            .onChange(of: vm.searchKeyword) { _ in vm.scheduleSearch() }
                        if !vm.searchKeyword.isEmpty {
                            Button { vm.searchKeyword = ""; vm.scheduleSearch() } label: {
                                Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        // 筛选面板入口：收在搜索框行内，不占导航栏
                        Button {
                            showFilter = true
                        } label: {
                            Image(systemName: vm.filter.isActive
                                    ? "line.3.horizontal.decrease.circle.fill"
                                    : "line.3.horizontal.decrease.circle")
                                .foregroundColor(vm.filter.isActive ? Theme.brand : .secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(HomePalette.card)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 8, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .onAppear {
                        // 首页搜索入口进来时直接聚焦弹键盘
                        if focusSearchOnAppear {
                            searchFieldFocused = true
                        }
                    }
                    // 隐藏 List 右侧滚动指示条（同首页，响应链方案）
                    .overlay(ScrollIndicatorHider().allowsHitTesting(false))
                }

                if vm.isLoading && vm.transactions.isEmpty {
                    Section {
                        HStack { Spacer(); ProgressView(); Spacer() }
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                } else if !vm.isLoading && vm.transactions.isEmpty {
                    Section {
                        VStack(spacing: 12) {
                            Image(systemName: "tray")
                                .font(.system(size: 26, weight: .medium))
                                .foregroundColor(.secondary)
                                .frame(width: 64, height: 64)
                                .background(Color(.secondarySystemFill))
                                .cornerRadius(22)
                            Text(vm.isFiltering ? "没有符合条件的账单" : "本月还没有账单")
                                .font(.subheadline).foregroundColor(.secondary)
                            if vm.isFiltering {
                                Button("清除筛选") { vm.clearFilter() }.font(.footnote)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                }

                // 保序分组下同一日期可能出现多个分组（相关性置顶组 + 时间倒序组），
                // 不能用 \.date 作身份，改用索引
                ForEach(Array(grouped.enumerated()), id: \.offset) { _, group in
                    Section(header: dayHeader(group.date, items: group.items)) {
                        ForEach(group.items) { tx in
                            TransactionRow(tx: tx, vm: vm)
                                .contentShape(Rectangle())
                                .onTapGesture { onDetail(tx) }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        Task { await vm.delete(tx) }
                                    } label: {
                                        Label("删除", systemImage: "trash")
                                    }
                                    Button {
                                        onEdit(tx)
                                    } label: {
                                        Label("编辑", systemImage: "pencil")
                                    }
                                    .tint(Theme.brand)
                                    Button {
                                        onDuplicate(tx)
                                    } label: {
                                        Label("复制", systemImage: "doc.on.doc")
                                    }
                                    .tint(.indigo)
                                }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .environment(\.defaultMinListRowHeight, 0)
            .refreshable { await vm.load() }
        }
        .navigationTitle(vm.isFiltering ? "已筛选账单" : "账单明细")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarHidden(false)
        // 顶部不放常驻按钮：清除筛选只在空态出现，筛选入口收进搜索框右侧漏斗
        .sheet(isPresented: $showFilter) {
            TransactionFilterSheet(
                filter: vm.filter,
                accounts: vm.accounts,
                categories: vm.categoriesForFilter,
                onApply: { vm.applyFilter($0) }
            )
        }
    }

    /// 日分组头：日期 + 当日支出/收入合计（对齐 Web 的当日合计）
    private func dayHeader(_ date: Date, items: [Transaction]) -> some View {
        let exp = vm.dayExpense(items)
        let inc = vm.dayIncome(items)
        return HStack(spacing: 0) {
            Text(TransactionsView.dayLabel(date))
            Spacer()
            HStack(spacing: 10) {
                if exp > 0 {
                    Text("支 \(AmountFormat.format(exp))")
                        .foregroundColor(Theme.expense)
                }
                if inc > 0 {
                    Text("收 \(AmountFormat.format(inc))")
                        .foregroundColor(Theme.income)
                }
            }
        }
        .font(.footnote)
        .textCase(nil)
    }
}

// MARK: - 区间详情页（对齐 Web：首页点「今天/昨天/…」→ 推入 /transaction/list?dateType=...）

/// 区间详情页 VM：拉取单个区间的账单（list.json + min_time/max_time **毫秒级**时间过滤，
/// 契约与主页面筛选分支一致）；删除直接转发主 VM（同步刷新主列表与区间汇总）
@MainActor
final class RangeDetailViewModel: ObservableObject {
    @Published var transactions: [Transaction] = []
    @Published var isLoading = false
    @Published var error: String?

    let context: RangeDetailContext
    let mainVM: TransactionsViewModel

    init(context: RangeDetailContext, mainVM: TransactionsViewModel) {
        self.context = context
        self.mainVM = mainVM
    }

    /// 区间收支合计（复用主 VM 已拉取的 amounts.json 结果）
    var incomeCents: Int64 { mainVM.income(for: context.period) }
    var expenseCents: Int64 { mainVM.expense(for: context.period) }

    func load() async {
        isLoading = true
        error = nil
        do {
            // list.json 的时间过滤是毫秒级时间序列 id（Unix 秒 × 1000）；
            // range.end 为 23:59:59（秒），补足到 23:59:59.999
            let start = Int64(context.range.start) * 1000
            let end = Int64(context.range.end) * 1000 + 999
            let page: TransactionPage = try await APIClient.shared.request(
                "/api/v1/transactions/list.json",
                query: [
                    URLQueryItem(name: "count", value: "500"),
                    URLQueryItem(name: "with_count", value: "true"),
                    URLQueryItem(name: "min_time", value: "\(start)"),
                    URLQueryItem(name: "max_time", value: "\(end)"),
                    URLQueryItem(name: "sort_by", value: "time"),
                    URLQueryItem(name: "sort_order", value: "desc")
                ]
            )
            transactions = page.items
            isLoading = false
        } catch {
            isLoading = false
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    func delete(_ tx: Transaction) async {
        await mainVM.delete(tx)
        transactions.removeAll { $0.id == tx.id }
    }

    func dayExpense(_ items: [Transaction]) -> Int64 {
        items.filter { $0.transactionType == .expense }.reduce(0) { $0 + $1.sourceAmount }
    }

    func dayIncome(_ items: [Transaction]) -> Int64 {
        items.filter { $0.transactionType == .income }.reduce(0) { $0 + $1.sourceAmount }
    }
}

/// 区间详情页：顶栏（返回 + 区间名 + 日期副标题 + 收支合计）+ 按日分组账单列表。
/// 分类/账户名解析复用主 VM；行 UI 复用 TransactionRow；编辑/详情 sheet 与主列表一致。
struct RangeDetailView: View {
    @StateObject private var vm: RangeDetailViewModel
    @ObservedObject private var mainVM: TransactionsViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var editing: Transaction?
    @State private var duplicating: Transaction?
    @State private var detail: Transaction?

    init(context: RangeDetailContext, mainVM: TransactionsViewModel) {
        _vm = StateObject(wrappedValue: RangeDetailViewModel(context: context, mainVM: mainVM))
        self.mainVM = mainVM
    }

    private var grouped: [(date: Date, items: [Transaction])] {
        let cal = Calendar.current
        let dict = Dictionary(grouping: vm.transactions) { cal.startOfDay(for: $0.date) }
        return dict.keys.sorted(by: >).map { ($0, dict[$0] ?? []) }
    }

    var body: some View {
        VStack(spacing: 0) {
            summaryRow

            if vm.isLoading && vm.transactions.isEmpty {
                Spacer()
                ProgressView()
                Spacer()
            } else if let error = vm.error {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 26, weight: .medium))
                        .foregroundColor(.orange)
                        .frame(width: 64, height: 64)
                        .background(Color.orange.opacity(0.12))
                        .cornerRadius(22)
                    Text(error)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    Button {
                        Task { await vm.load() }
                    } label: {
                        Text("重试")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 22)
                            .padding(.vertical, 8)
                            .background(Theme.brand)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 32)
                Spacer()
            } else if vm.transactions.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "tray")
                        .font(.system(size: 26, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 64, height: 64)
                        .background(Color(.secondarySystemFill))
                        .cornerRadius(22)
                    Text("该区间还没有账单")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
            } else {
                transactionList
            }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle(vm.context.period.title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarHidden(false)
        .task { await vm.load() }
        .sheet(item: $editing, onDismiss: {
            // 编辑保存后同步刷新详情列表 + 主页面的列表与区间汇总
            Task {
                await vm.load()
                await mainVM.load()
            }
        }) { tx in
            TransactionEditView(transaction: tx, mode: .edit)
        }
        .sheet(item: $duplicating, onDismiss: {
            // 复制为新交易落库后同样刷新两个层级
            Task {
                await vm.load()
                await mainVM.load()
            }
        }) { tx in
            TransactionEditView(transaction: tx, mode: .duplicate)
        }
        .sheet(item: $detail, onDismiss: {
            // 从详情页内部编辑/复制后，关闭详情时刷新（详情页自身无法就地更新）
            Task {
                await vm.load()
                await mainVM.load()
            }
        }) { tx in
            TransactionDetailView(transaction: tx, onChanged: {
                Task {
                    await vm.load()
                    await mainVM.load()
                }
            })
        }
    }

    /// 系统导航栏下方的摘要卡（首页六区间行同款风格：区间彩色徽章 + 日期 + 收支合计）
    private var summaryRow: some View {
        let period = vm.context.period
        return HStack(spacing: 12) {
            Image(systemName: period.icon)
                .font(.system(size: 17))
                .foregroundColor(period.color)
                .frame(width: 34, height: 34)
                .background(period.color.opacity(0.14))
                .cornerRadius(10)

            VStack(alignment: .leading, spacing: 2) {
                Text(period.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(HomePalette.ink)
                Text(mainVM.rangeSubtitle(period))
                    .font(.system(size: 12))
                    .foregroundColor(HomePalette.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 3) {
                Text("收 \(mainVM.hideAmounts ? "＊＊＊" : AmountFormat.format(vm.incomeCents))")
                    .foregroundColor(HomePalette.income)
                Text("支 \(mainVM.hideAmounts ? "＊＊＊" : AmountFormat.format(vm.expenseCents))")
                    .foregroundColor(HomePalette.expense)
            }
            .font(.system(size: 15, weight: .semibold))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(HomePalette.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: Color.black.opacity(HomePalette.isDark ? 0.5 : 0.06), radius: 8, x: 0, y: 3)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private var transactionList: some View {
        List {
            ForEach(grouped, id: \.date) { group in
                Section(header: dayHeader(group.date, items: group.items)) {
                    ForEach(group.items) { tx in
                        TransactionRow(tx: tx, vm: mainVM)
                            .contentShape(Rectangle())
                            .onTapGesture { detail = tx }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    Task { await vm.delete(tx) }
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                                Button {
                                    editing = tx
                                } label: {
                                    Label("编辑", systemImage: "pencil")
                                }
                                .tint(Theme.brand)
                                Button {
                                    duplicating = tx
                                } label: {
                                    Label("复制", systemImage: "doc.on.doc")
                                }
                                .tint(.indigo)
                            }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .environment(\.defaultMinListRowHeight, 0)
        .refreshable { await vm.load() }
    }

    /// 日分组头（与主列表同款式）
    private func dayHeader(_ date: Date, items: [Transaction]) -> some View {
        let exp = vm.dayExpense(items)
        let inc = vm.dayIncome(items)
        return HStack(spacing: 0) {
            Text(TransactionsView.dayLabel(date))
            Spacer()
            HStack(spacing: 10) {
                if exp > 0 {
                    Text("支 \(AmountFormat.format(exp))")
                        .foregroundColor(Theme.expense)
                }
                if inc > 0 {
                    Text("收 \(AmountFormat.format(inc))")
                        .foregroundColor(Theme.income)
                }
            }
        }
        .font(.footnote)
        .textCase(nil)
    }
}

struct TransactionRow: View {
    let tx: Transaction
    @ObservedObject var vm: TransactionsViewModel

    private var amountColor: Color {
        switch tx.transactionType {
        case .expense: return Theme.expense
        case .income: return Theme.income
        default: return .primary
        }
    }

    private var amountText: String {
        switch tx.transactionType {
        case .transfer:
            return "→ \(AmountFormat.format(tx.sourceAmount, currency: nil))"
        case .modifyBalance:
            return AmountFormat.format(tx.sourceAmount)
        default:
            let prefix = tx.transactionType == .expense ? "-" : "+"
            return prefix + AmountFormat.format(tx.sourceAmount)
        }
    }

    private var iconName: String {
        switch tx.transactionType {
        case .income: return "arrow.down.left"
        case .transfer: return "arrow.left.arrow.right"
        case .modifyBalance: return "equal.circle"
        case .expense: return "arrow.up.right"
        }
    }

    private var iconColor: Color {
        switch tx.transactionType {
        case .income: return Theme.income
        case .transfer: return .gray
        case .modifyBalance: return Theme.brand
        case .expense: return Theme.expense
        }
    }

    /// 支出/收入且能映射到分类时，行首显示**分类图标**（分类色浅底），与 Web 端账单列表一致；
    /// 转账/余额调整/分类缺失时回退交易类型箭头
    private var showsCategoryIcon: Bool {
        tx.transactionType == .expense || tx.transactionType == .income
    }

    var body: some View {
        HStack(spacing: 12) {
            if showsCategoryIcon, let symbol = vm.categoryIcon(tx.categoryId) {
                // 分类图标用**分类色**（浅底），对齐 Web 端；不用交易类型色（否则支出行全红）
                let catColor = vm.categoryColor(tx.categoryId)
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(catColor)
                    .frame(width: 32, height: 32)
                    .background(catColor.opacity(0.13))
                    .cornerRadius(10)
            } else {
                Image(systemName: iconName)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(iconColor)
                    .frame(width: 32, height: 32)
                    .background(iconColor.opacity(0.12))
                    .cornerRadius(9)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(vm.categoryName(tx.categoryId))
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(HomePalette.ink)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(vm.accountName(tx.sourceAccountId))
                    if let comment = tx.comment, !comment.isEmpty {
                        Text("· \(comment)").lineLimit(1)
                    }
                    if let installment = tx.installmentLabel {
                        Text("分期 \(installment)")
                            .font(.footnote)
                            .foregroundColor(Theme.brand)
                            .lineLimit(1)
                    }
                }
                .font(.footnote)
                .foregroundColor(.secondary)
            }
            Spacer()
            Text(amountText)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(amountColor)
        }
        .padding(.vertical, 2)
    }
}

extension Color {
    /// 解析 #RRGGBB / RRGGBB
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 3 {
            s = s.map { String($0) + String($0) }.joined()
        }
        var rgb: UInt64 = 0
        Scanner(string: s).scanHexInt64(&rgb)
        let r = Double((rgb >> 16) & 0xFF) / 255
        let g = Double((rgb >> 8) & 0xFF) / 255
        let b = Double(rgb & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - 账单筛选面板

/// 筛选面板：类型 / 分类多选 / 账户多选 / 日期范围 / 排序（对齐 Web 手机端筛选 Popover）
struct TransactionFilterSheet: View {
    @State var filter: TransactionFilter
    let accounts: [Account]
    let categories: [TransactionCategory]
    let onApply: (TransactionFilter) -> Void

    @Environment(\.dismiss) private var dismiss

    /// 类型选项（0 为全部）
    private let typeOptions: [(Int, String)] = [
        (0, "全部"), (3, "支出"), (2, "收入"), (4, "转账"), (1, "余额调整")
    ]

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("类型")) {
                    Picker("类型", selection: $filter.type) {
                        ForEach(typeOptions, id: \.0) { Text($0.1).tag($0.0) }
                    }
                    .pickerStyle(.segmented)
                }

                Section(header: Text("日期范围")) {
                    Toggle("限定日期", isOn: Binding(
                        get: { filter.startDate != nil || filter.endDate != nil },
                        set: { on in
                            if on {
                                filter.startDate = filter.startDate ?? Date()
                                filter.endDate = filter.endDate ?? Date()
                            } else {
                                filter.startDate = nil
                                filter.endDate = nil
                            }
                        }
                    ))
                    if filter.startDate != nil {
                        DatePicker("开始", selection: Binding(
                            get: { filter.startDate ?? Date() },
                            set: { filter.startDate = $0 }
                        ), displayedComponents: .date)
                        DatePicker("结束", selection: Binding(
                            get: { filter.endDate ?? Date() },
                            set: { filter.endDate = $0 }
                        ), displayedComponents: .date)
                    }
                }

                Section(header: Text("账户")) {
                    ForEach(accounts, id: \.id) { acc in
                        checkRow(acc.name, isOn: filter.accountIds.contains(acc.id)) {
                            toggle(&filter.accountIds, acc.id)
                        }
                    }
                }

                Section(header: Text("分类")) {
                    ForEach(categories, id: \.id) { cat in
                        checkRow(cat.name, isOn: filter.categoryIds.contains(cat.id)) {
                            toggle(&filter.categoryIds, cat.id)
                        }
                    }
                }

                Section(header: Text("排序")) {
                    Picker("排序字段", selection: $filter.sortBy) {
                        Text("默认").tag("")
                        Text("时间").tag("time")
                        Text("金额").tag("amount")
                    }
                    Picker("排序方向", selection: $filter.sortOrder) {
                        Text("降序").tag("desc")
                        Text("升序").tag("asc")
                    }
                }

                Section {
                    Button("重置") { filter.reset() }
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
                        onApply(filter)
                        dismiss()
                    }
                    .font(.body.weight(.semibold))
                }
            }
        }
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

    private func toggle(_ arr: inout [String], _ id: String) {
        if let idx = arr.firstIndex(of: id) { arr.remove(at: idx) } else { arr.append(id) }
    }
}
