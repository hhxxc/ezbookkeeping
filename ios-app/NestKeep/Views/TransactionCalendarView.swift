import SwiftUI
import Combine

/// 日历视图的月历模型：某个月按日聚合的收支合计。
/// 数据来源 `GET /api/v1/transactions/statistics/daily.json`（按天返回 items，
/// amount 正数为收入、负数为支出，与统计页同一口径）。
@MainActor
final class TransactionCalendarViewModel: ObservableObject {
    @Published var year: Int
    @Published var month: Int
    @Published var isLoading = false
    @Published var error: String?
    /// 每日支出（分），下标 = 日 - 1
    @Published var dailyExpense: [Int64] = []
    /// 每日收入（分）
    @Published var dailyIncome: [Int64] = []
    /// 分类列表（统计接口的 amount 恒为正数，需要靠分类 type 区分收入/支出）
    private var categories: [TransactionCategory] = []

    init() {
        let c = Calendar.current.dateComponents([.year, .month], from: Date())
        year = c.year!
        month = c.month!
    }

    var monthLabel: String { "\(year)年\(month)月" }

    /// 该月 1 号是周几（用于网格前导空格），按周一为第一列：周一→0…周日→6
    var leadingBlanks: Int {
        guard let first = Calendar.current.date(from: DateComponents(year: year, month: month, day: 1)) else { return 0 }
        return (Calendar.current.component(.weekday, from: first) + 5) % 7
    }

    var daysInMonth: Int {
        Calendar.current.range(of: .day, in: .month,
                               for: Calendar.current.date(from: DateComponents(year: year, month: month, day: 1))!)?.count ?? 30
    }

    func expense(day: Int) -> Int64 {
        let i = day - 1
        return (i >= 0 && i < dailyExpense.count) ? dailyExpense[i] : 0
    }

    func income(day: Int) -> Int64 {
        let i = day - 1
        return (i >= 0 && i < dailyIncome.count) ? dailyIncome[i] : 0
    }

    /// 分类类型查找（含二级分类）；找不到返回 nil
    private static func categoryType(forKey id: String, in categories: [TransactionCategory]) -> Int? {
        for c in categories {
            if c.id == id { return c.type }
            if let subs = c.subCategories, let hit = subs.first(where: { $0.id == id }) {
                return hit.type
            }
        }
        return nil
    }

    func load() async {
        isLoading = true
        error = nil
        if categories.isEmpty {
            categories = (try? await APIClient.shared.requestCategoryList()) ?? []
        }
        guard let start = Calendar.current.date(from: DateComponents(year: year, month: month, day: 1)),
              let end = Calendar.current.date(byAdding: .month, value: 1, to: start) else {
            isLoading = false
            return
        }
        do {
            let items: [StatisticDailyItem] = try await APIClient.shared.request(
                "/api/v1/transactions/statistics/daily.json",
                query: [
                    URLQueryItem(name: "start_time", value: "\(Int(start.timeIntervalSince1970))"),
                    URLQueryItem(name: "end_time", value: "\(Int(end.timeIntervalSince1970) - 1)"),
                    URLQueryItem(name: "use_transaction_timezone", value: "true")
                ]
            )
            let count = daysInMonth
            var exp = [Int64](repeating: 0, count: count)
            var inc = [Int64](repeating: 0, count: count)
            for d in items {
                guard d.month == month, d.day >= 1, d.day <= count else { continue }
                let idx = d.day - 1
                for item in d.items {
                    // amount 恒为正数，收支方向由分类 type 决定（1=收入 2=支出，转账/未知跳过）
                    let amount = abs(item.amount)
                    switch Self.categoryType(forKey: item.categoryId ?? "0", in: categories) {
                    case .some(2): exp[idx] += amount
                    case .some(1): inc[idx] += amount
                    default: break
                    }
                }
            }
            dailyExpense = exp
            dailyIncome = inc
            isLoading = false
        } catch {
            isLoading = false
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    func shiftMonth(by delta: Int) {
        var comps = DateComponents(year: year, month: month)
        comps.month! += delta
        guard let date = Calendar.current.date(from: comps) else { return }
        let c = Calendar.current.dateComponents([.year, .month], from: date)
        year = c.year!
        month = c.month!
        // 换月即清空旧数据，避免上月的数字短暂串月显示
        dailyExpense = []
        dailyIncome = []
        Task { await load() }
    }
}

/// 账单日历**独立页面**：从首页系统原生 push 进入（标准视差/边缘阴影/跟手返回）。
/// 顶栏使用系统导航栏（返回键自动生成）；内容：月历卡片（含月份切换）。
/// 点击某天 → 回调给账单页按该日筛选。
struct CalendarPageView: View {
    @ObservedObject var vm: TransactionCalendarViewModel
    /// 点击某天：传回该日 00:00 的 Date
    let onSelectDay: (Date) -> Void

    var body: some View {
        ScrollView {
            TransactionCalendarView(vm: vm) { date in
                onSelectDay(date)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 24)
        }
        .navigationTitle("账单日历")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarHidden(false)
        .chineseBackButton()
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
    }
}

/// 账单日历视图：自绘月历网格，每个日期格内显示当日支出/收入，
/// 点击某天 → 回调给账单页按该日筛选。
/// iOS 15 无原生日历组件，全部用 GeometryReader + LazyVGrid 自绘。
struct TransactionCalendarView: View {
    @ObservedObject var vm: TransactionCalendarViewModel
    /// 点击某天：传回该日 00:00 的 Date
    let onSelectDay: (Date) -> Void

    private let weekdays = ["一", "二", "三", "四", "五", "六", "日"]
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)

    var body: some View {
        VStack(spacing: 10) {
            // 月份切换
            HStack {
                Button { vm.shiftMonth(by: -1) } label: { Image(systemName: "chevron.left") }
                Spacer()
                Text(vm.monthLabel).font(.subheadline.weight(.semibold))
                Spacer()
                Button { vm.shiftMonth(by: 1) } label: { Image(systemName: "chevron.right") }
            }
            .padding(.horizontal, 4)

            // 星期表头
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(weekdays, id: \.self) { w in
                    Text(w).font(.footnote).foregroundColor(.secondary)
                }
            }

            // 日期网格
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(0..<vm.leadingBlanks, id: \.self) { _ in
                    Color.clear.frame(height: 52)
                }
                ForEach(1...vm.daysInMonth, id: \.self) { day in
                    dayCell(day)
                }
            }

            if let error = vm.error {
                Text(error).font(.footnote).foregroundColor(Theme.expense)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(14)
        .task { if vm.dailyExpense.isEmpty { await vm.load() } }
    }

    private func dayCell(_ day: Int) -> some View {
        let exp = vm.expense(day: day)
        let inc = vm.income(day: day)
        let isToday = Self.isToday(year: vm.year, month: vm.month, day: day)

        return Button {
            if let date = Calendar.current.date(from: DateComponents(year: vm.year, month: vm.month, day: day)) {
                onSelectDay(date)
            }
        } label: {
            VStack(spacing: 1) {
                Text("\(day)")
                    .font(.footnote)
                    .foregroundColor(isToday ? .white : .primary)
                    .frame(width: 20, height: 20)
                    .background(isToday ? Theme.brand : Color.clear)
                    .clipShape(Circle())
                if exp > 0 {
                    Text(Self.compact(exp)).font(.system(size: 8)).foregroundColor(Theme.expense)
                }
                if inc > 0 {
                    Text(Self.compact(inc)).font(.system(size: 8)).foregroundColor(Theme.income)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Color(.tertiarySystemGroupedBackground))
            .cornerRadius(8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private static func isToday(year: Int, month: Int, day: Int) -> Bool {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        return c.year == year && c.month == month && c.day == day
    }

    /// 日历格里的金额用紧凑形式（如 1.2万 / 320），避免撑破格子
    private static func compact(_ cents: Int64) -> String {
        let yuan = Double(cents) / 100
        if abs(yuan) >= 10000 {
            return String(format: "%.1f万", yuan / 10000)
        }
        if yuan == yuan.rounded() {
            return String(Int(yuan))
        }
        return String(format: "%.0f", yuan)
    }
}
