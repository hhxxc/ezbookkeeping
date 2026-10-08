import SwiftUI
import Combine

/// 统计页：收支概览 + 分类占比饼图 + 每日收支柱状图。
/// iOS 15 没有原生 Charts 框架，图表全部用 SwiftUI Path / 几何图形自绘。
@MainActor
final class StatisticsViewModel: ObservableObject {
    @Published var year: Int
    @Published var month: Int
    @Published var isLoading = false
    @Published var error: String?

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

    struct CategoryStat: Identifiable {
        let id: String
        let name: String
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

    /// 日均支出（年模式下为「日均」，即年支出 / 全年天数）
    var dailyAverageExpenseCents: Int64 {
        let days = periodDayCount
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
            if categories.isEmpty {
                categories = (try? await APIClient.shared.request("/api/v1/transaction/categories/list.json")) ?? []
            }
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

            async let statResp: StatisticResponse = APIClient.shared.request(
                "/api/v1/transactions/statistics.json",
                query: [
                    URLQueryItem(name: "start_time", value: "\(startTs)"),
                    URLQueryItem(name: "end_time", value: "\(endTs)"),
                    URLQueryItem(name: "use_transaction_timezone", value: "true")
                ]
            )
            async let dailyResp: [StatisticDailyItem] = APIClient.shared.request(
                "/api/v1/transactions/statistics/daily.json",
                query: [
                    URLQueryItem(name: "start_time", value: "\(startTs)"),
                    URLQueryItem(name: "end_time", value: "\(endTs)"),
                    URLQueryItem(name: "use_transaction_timezone", value: "true")
                ]
            )

            let stats = try await statResp
            let daily = (try? await dailyResp) ?? []

            buildCategoryStats(stats.items)
            buildDaily(daily)
            isLoading = false
        } catch {
            isLoading = false
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// 把统计项聚合成分类维度（支出 / 收入分开）
    private func buildCategoryStats(_ items: [StatisticResponseItem]) {
        var expMap: [String: Int64] = [:]
        var incMap: [String: Int64] = [:]
        for item in items {
            let key = item.categoryId ?? "0"
            if item.amount < 0 {
                expMap[key, default: 0] += abs(item.amount)
            } else if item.amount > 0 {
                incMap[key, default: 0] += item.amount
            }
        }
        totalExpenseCents = expMap.values.reduce(0, +)
        totalIncomeCents = incMap.values.reduce(0, +)

        expenseByCategory = makeStats(from: expMap, total: totalExpenseCents)
        incomeByCategory = makeStats(from: incMap, total: totalIncomeCents)
    }

    private func makeStats(from map: [String: Int64], total: Int64) -> [CategoryStat] {
        map.compactMap { key, amount in
            guard amount > 0 else { return nil }
            let cat = findCategory(key)
            return CategoryStat(
                id: key,
                name: cat?.name ?? "未分类",
                color: cat?.color.flatMap { Color(hex: $0) } ?? Theme.brand,
                amount: amount,
                ratio: total > 0 ? Double(amount) / Double(total) : 0
            )
        }
        .sorted { $0.amount > $1.amount }
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

    /// 汇总区间收支：月模式按「日」聚合，年模式按「月」聚合（对齐 Web 年周期柱状图）
    private func buildDaily(_ items: [StatisticDailyItem]) {
        if isYearMode {
            var exp = [Int64](repeating: 0, count: 12)
            var inc = [Int64](repeating: 0, count: 12)
            for d in items {
                let m = d.month
                guard m >= 1, m <= 12 else { continue }
                for item in d.items {
                    if item.amount < 0 { exp[m - 1] += abs(item.amount) }
                    else if item.amount > 0 { inc[m - 1] += item.amount }
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
                if item.amount < 0 { exp[idx] += abs(item.amount) }
                else if item.amount > 0 { inc[idx] += item.amount }
            }
        }
        dailyExpense = exp
        dailyIncome = inc
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
    @Environment(\.mainTabBarInset) private var tabBarInset
    @State private var mode: Mode = .expense

    enum Mode: String, CaseIterable {
        case expense = "支出"
        case income = "收入"
    }

    private var stats: [StatisticsViewModel.CategoryStat] {
        mode == .expense ? vm.expenseByCategory : vm.incomeByCategory
    }

    private var dailyValues: [Int64] {
        mode == .expense ? vm.dailyExpense : vm.dailyIncome
    }

    private var totalCents: Int64 {
        mode == .expense ? vm.totalExpenseCents : vm.totalIncomeCents
    }

    /// 主强调色：与 Web 统计页一致，用首页调色板（低饱和红/绿）而非全局鲜色
    private var accent: Color { mode == .expense ? HomePalette.expense : HomePalette.income }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    periodModePicker
                    overviewCard
                    modePicker
                    if !stats.isEmpty {
                        pieCard
                        rankCard
                    }
                    if dailyValues.contains(where: { $0 > 0 }) {
                        dailyChartCard
                    }
                    if let error = vm.error {
                        Text(error).font(.footnote).foregroundColor(.red)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: tabBarInset)
            }
            .background(Theme.pageBackground.ignoresSafeArea())
            .navigationTitle("统计")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    HStack(spacing: 14) {
                        Button { vm.shiftPeriod(by: -1) } label: { Image(systemName: "chevron.left") }
                        Text(vm.periodLabel).font(.subheadline.weight(.medium)).frame(minWidth: 82)
                        Button { vm.shiftPeriod(by: 1) } label: { Image(systemName: "chevron.right") }
                    }
                }
            }
            .refreshable { await vm.load() }
        }
        .task { await vm.load() }
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
    /// Web 结构：`收支概览` 标题(17px/600) + 2×2 网格（支出/收入/结余/日均支出），
    /// 每格「标签 14px 次要色 + 数值 21px/700 主文字色」，**白底卡，不用主题色渐变**。
    private var overviewCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("收支概览")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(HomePalette.ink)
                .padding(.bottom, 16)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12),
                                GridItem(.flexible(), spacing: 12)],
                      spacing: 18) {
                overviewCell("支出", vm.totalExpenseCents, HomePalette.expense)
                overviewCell("收入", vm.totalIncomeCents, HomePalette.income)
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

    /// 概览网格单元：标签 14px 次要色 / 数值 21px-700 指定色（对齐 Web `.statistics-overview-*`）
    private func overviewCell(_ title: String, _ cents: Int64, _ color: Color) -> some View {
        VStack(spacing: 4) {
            Text(title).font(.system(size: 14)).foregroundColor(HomePalette.secondary)
            Text(AmountFormat.format(cents))
                .font(.system(size: 21, weight: .bold))
                .monospacedDigit()
                .foregroundColor(color)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
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
                            Circle().fill(s.color).frame(width: 9, height: 9)
                            Text(s.name).font(.caption).lineLimit(1)
                            Spacer()
                            Text("\(Int((s.ratio * 100).rounded()))%")
                                .font(.caption).foregroundColor(.secondary)
                        }
                    }
                    if stats.count > 6 {
                        Text("等 \(stats.count) 个分类")
                            .font(.caption2).foregroundColor(.secondary)
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
                HStack(spacing: 12) {
                    Text("\(idx + 1)")
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.secondary)
                        .frame(width: 18, alignment: .leading)
                    Circle().fill(s.color).frame(width: 10, height: 10)
                    Text(s.name).font(.subheadline).lineLimit(1)
                    Spacer()
                    Text(AmountFormat.format(s.amount))
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundColor(accent)
                }
                .padding(.vertical, 7)
                if idx < min(stats.count, 10) - 1 {
                    Divider().padding(.leading, 40)
                }
            }
        }
        .padding(16)
        .background(HomePalette.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - 柱状图（自绘）：月模式按日、年模式按月
    private var dailyChartCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(vm.isYearMode ? "每月\(mode.rawValue)" : "每日\(mode.rawValue)")
                .font(.headline)
            BarChart(values: dailyValues, color: accent)
                .frame(height: 130)
            HStack {
                Text(vm.isYearMode ? "1月" : "1日")
                    .font(.caption2).foregroundColor(.secondary)
                Spacer()
                Text(vm.bucketEndLabel).font(.caption2).foregroundColor(.secondary)
            }
        }
        .padding(16)
        .background(HomePalette.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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

// MARK: - 自绘柱状图

struct BarChart: View {
    let values: [Int64]
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let maxValue: Int64 = max(values.max() ?? 1, 1)
            let count: Int = max(values.count, 1)
            let barWidth: CGFloat = max(geo.size.width / CGFloat(count) - 2, 1.5)
            let chartHeight: CGFloat = geo.size.height

            ZStack(alignment: .bottom) {
                // 基线
                Rectangle().fill(Color.secondary.opacity(0.18))
                    .frame(height: 1)
                    .frame(maxHeight: .infinity, alignment: .bottom)

                HStack(alignment: .bottom, spacing: 2) {
                    ForEach(Array(values.enumerated()), id: \.offset) { _, v in
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(v > 0 ? color.opacity(0.85) : Color.clear)
                            .frame(
                                width: barWidth,
                                height: max(chartHeight * CGFloat(Double(v) / Double(maxValue)),
                                            v > 0 ? 2 : 0)
                            )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .bottom)
            }
        }
    }
}
