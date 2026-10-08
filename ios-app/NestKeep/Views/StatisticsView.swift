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
    /// 日均支出
    var dailyAverageExpenseCents: Int64 {
        let days = Calendar.current.range(of: .day, in: .month,
                                          for: Calendar.current.date(from: DateComponents(year: year, month: month))!)?.count ?? 30
        guard days > 0 else { return 0 }
        return totalExpenseCents / Int64(days)
    }

    var periodLabel: String { "\(year)年\(month)月" }

    func load() async {
        isLoading = true
        error = nil
        do {
            if categories.isEmpty {
                categories = (try? await APIClient.shared.request("/api/v1/transaction/categories/list.json")) ?? []
            }
            guard let start = Calendar.current.date(from: DateComponents(year: year, month: month, day: 1)),
                  let end = Calendar.current.date(byAdding: .month, value: 1, to: start) else {
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

    /// 汇总每日收支
    private func buildDaily(_ items: [StatisticDailyItem]) {
        let dayCount = Calendar.current.range(
            of: .day, in: .month,
            for: Calendar.current.date(from: DateComponents(year: year, month: month))!
        )?.count ?? 30
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

    func shiftMonth(by delta: Int) {
        var comps = DateComponents(year: year, month: month)
        comps.month! += delta
        guard let date = Calendar.current.date(from: comps) else { return }
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

    private var accent: Color { mode == .expense ? Theme.expense : Theme.income }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
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
                        Button { vm.shiftMonth(by: -1) } label: { Image(systemName: "chevron.left") }
                        Text(vm.periodLabel).font(.subheadline.weight(.medium)).frame(minWidth: 82)
                        Button { vm.shiftMonth(by: 1) } label: { Image(systemName: "chevron.right") }
                    }
                }
            }
            .refreshable { await vm.load() }
        }
        .task { await vm.load() }
    }

    // MARK: - 概览卡
    private var overviewCard: some View {
        VStack(spacing: 14) {
            HStack(spacing: 0) {
                overviewCell("支出", vm.totalExpenseCents, Theme.expense)
                Rectangle().fill(Color.white.opacity(0.25)).frame(width: 1, height: 40)
                overviewCell("收入", vm.totalIncomeCents, Theme.income)
                Rectangle().fill(Color.white.opacity(0.25)).frame(width: 1, height: 40)
                overviewCell("结余", vm.netCents, .white)
            }
            Divider().overlay(Color.white.opacity(0.25))
            HStack {
                Text("日均支出").font(.caption).foregroundColor(.white.opacity(0.8))
                Spacer()
                Text(AmountFormat.format(vm.dailyAverageExpenseCents))
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
            }
        }
        .padding(18)
        .background(
            LinearGradient(colors: [Theme.brand, Theme.brand.opacity(0.78)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .cornerRadius(18)
        .shadow(color: Theme.brand.opacity(0.3), radius: 10, x: 0, y: 5)
    }

    private func overviewCell(_ title: String, _ cents: Int64, _ color: Color) -> some View {
        VStack(spacing: 5) {
            Text(title).font(.caption).foregroundColor(.white.opacity(0.8))
            Text(AmountFormat.format(cents))
                .font(.system(size: 15, weight: .semibold, design: .rounded))
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
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
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
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
    }

    // MARK: - 每日柱状图（自绘）
    private var dailyChartCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("每日\(mode.rawValue)").font(.headline)
            BarChart(values: dailyValues, color: accent)
                .frame(height: 130)
            HStack {
                Text("1日").font(.caption2).foregroundColor(.secondary)
                Spacer()
                Text("\(vm.daysInMonth)日").font(.caption2).foregroundColor(.secondary)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
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
