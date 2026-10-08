import SwiftUI
import Combine

/// 对账单（Reconciliation Statement）：对齐 Web `accounts/ReconciliationStatementPage.vue`。
/// 功能：
///  - 日期范围选择（本月/上月/今年/自定义等，默认本月）
///  - 汇总：交易笔数、总流入、总流出、净现金流、期初余额、期末余额
///  - 明细列表：按日分组，每笔显示分类/金额/时间/**该笔之后的账户余额**
///  - 余额趋势图（按日/按月聚合，柱状图自绘）
/// 接口：`GET /api/v1/transactions/reconciliation_statements.json?account_id&start_time&end_time`
struct ReconciliationStatementView: View {
    let account: Account

    @Environment(\.dismiss) private var dismiss

    @StateObject private var vm = ReconciliationViewModel()

    var body: some View {
        Group {
            if vm.isInitialLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    // 日期范围
                    Section {
                        Picker("日期范围", selection: $vm.rangeType) {
                            ForEach(ReconciliationRangeType.allCases) { r in
                                Text(r.title).tag(r)
                            }
                        }
                        .onChange(of: vm.rangeType) { _ in
                            Task { await vm.load(account: account) }
                        }
                        if vm.rangeType == .custom {
                            DatePicker("开始时间", selection: $vm.customStart, displayedComponents: [.date])
                            DatePicker("结束时间", selection: $vm.customEnd, displayedComponents: [.date])
                            Button("应用自定义范围") {
                                Task { await vm.load(account: account) }
                            }
                        }
                    }

                    // 汇总
                    Section(header: Text("统计")) {
                        statRow("交易笔数", "\(vm.statement?.transactions.count ?? 0)")
                        statRow("总流入", money(vm.statement?.totalInflows ?? 0))
                        statRow("总流出", money(vm.statement?.totalOutflows ?? 0))
                        statRow("净现金流", money(vm.statement?.netCashFlow ?? 0))
                    }

                    Section {
                        statRow("期初余额", money(vm.statement?.openingBalance ?? 0))
                        statRow("期末余额", money(vm.statement?.closingBalance ?? 0))
                    }

                    // 趋势图
                    Section(header: Text("余额趋势")) {
                        Picker("聚合", selection: $vm.granularity) {
                            Text("按日").tag(ReconciliationGranularity.day)
                            Text("按月").tag(ReconciliationGranularity.month)
                        }
                        .pickerStyle(.segmented)
                        .listRowBackground(Color.clear)

                        BalanceTrendChart(values: vm.trendValues, labels: vm.trendLabels)
                            .frame(height: 180)
                            .padding(.vertical, 4)
                    }

                    // 明细
                    if vm.isLoading {
                        Section { ProgressView() }
                    } else if vm.items.isEmpty {
                        Section { Text("没有交易数据").foregroundColor(.secondary) }
                    } else {
                        ForEach(vm.items) { item in
                            switch item.kind {
                            case .date(let text):
                                Section(header: Text(text)) { EmptyView() }
                            case .transaction(let tx, let balance):
                                transactionRow(tx, balance: balance)
                            }
                        }
                    }

                    if let error = vm.error {
                        Section { Text(error).foregroundColor(.red).font(.footnote) }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("对账单")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    Task { await vm.load(account: account) }
                } label: {
                    if vm.isLoading { ProgressView() } else { Image(systemName: "arrow.clockwise") }
                }
                .disabled(vm.isLoading)
            }
        }
        .task { await vm.load(account: account) }
    }

    private func statRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).foregroundColor(.secondary).monospacedDigit()
        }
    }

    private func money(_ cents: Int64) -> String {
        AmountFormat.format(cents, currency: account.currency)
    }

    @ViewBuilder
    private func transactionRow(_ tx: ReconciliationTransactionItem, balance: Int64) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Image(systemName: CategoryIconCatalog.symbol(tx.icon))
                    .foregroundColor(.white)
                    .font(.system(size: 12))
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color(hex: tx.color ?? "26A69A")))
                VStack(alignment: .leading, spacing: 2) {
                    Text(tx.displayName).font(.subheadline)
                    if let comment = tx.comment, !comment.isEmpty {
                        Text(comment).font(.caption2).foregroundColor(.secondary).lineLimit(1)
                    }
                }
                Spacer()
                Text(AmountFormat.format(tx.displayAmount(cents: account.currency), currency: account.currency))
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundColor(tx.isIncome ? HomePalette.income : (tx.isExpense ? HomePalette.expense : .primary))
            }
            HStack {
                Text(tx.timeText).font(.caption2).foregroundColor(.secondary)
                Spacer()
                Text("余额 \(AmountFormat.format(balance, currency: account.currency))")
                    .font(.caption2).foregroundColor(.secondary).monospacedDigit()
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - ViewModel

enum ReconciliationGranularity { case day, month }

enum ReconciliationRangeType: String, CaseIterable, Identifiable {
    case thisMonth, lastMonth, thisYear, lastYear, all, custom
    var id: String { rawValue }
    var title: String {
        switch self {
        case .thisMonth: return "本月"
        case .lastMonth: return "上月"
        case .thisYear: return "今年"
        case .lastYear: return "去年"
        case .all: return "全部"
        case .custom: return "自定义"
        }
    }
}

enum ReconciliationListItem: Identifiable {
    case date(String)
    case transaction(ReconciliationTransactionItem, balance: Int64)

    var id: String {
        switch self {
        case .date(let t): return "d-\(t)"
        case .transaction(let tx, _): return "t-\(tx.id)"
        }
    }

    var kind: Kind {
        switch self {
        case .date(let t): return .date(t)
        case .transaction(let tx, let b): return .transaction(tx, b)
        }
    }
    enum Kind {
        case date(String)
        case transaction(ReconciliationTransactionItem, Int64)
    }
}

@MainActor
final class ReconciliationViewModel: ObservableObject {
    @Published var statement: ReconciliationStatement?
    @Published var items: [ReconciliationListItem] = []
    @Published var isLoading = false
    @Published var isInitialLoading = true
    @Published var error: String?

    @Published var rangeType: ReconciliationRangeType = .thisMonth
    @Published var customStart = Date()
    @Published var customEnd = Date()
    @Published var granularity: ReconciliationGranularity = .day

    private var rawItems: [ReconciliationTransactionItem] = []

    /// 余额趋势（按粒度聚合，取每段最后一笔的账户余额）
    var trendValues: [Double] { buildTrend().0 }
    var trendLabels: [String] { buildTrend().1 }

    private func buildTrend() -> ([Double], [String]) {
        guard !rawItems.isEmpty else { return ([], []) }
        let cal = Calendar.current
        var buckets: [(key: String, label: String, order: Int, last: Int64)] = []
        var indexByKey: [String: Int] = [:]

        for tx in rawItems {
            let date = Date(timeIntervalSince1970: TimeInterval(tx.time))
            let order: Int
            let key: String
            let label: String
            if granularity == .month {
                order = cal.component(.year, from: date) * 100 + cal.component(.month, from: date)
                key = "\(order)"
                label = "\(cal.component(.month, from: date))月"
            } else {
                order = Int(date.timeIntervalSince1970 / 86400)
                let m = cal.component(.month, from: date)
                let d = cal.component(.day, from: date)
                key = "\(order)"
                label = "\(m)/\(d)"
            }
            let balance = tx.accountClosingBalance ?? 0
            if let idx = indexByKey[key] {
                buckets[idx].last = balance   // 同日/同月取最后一笔
            } else {
                indexByKey[key] = buckets.count
                buckets.append((key, label, order, balance))
            }
        }
        buckets.sort { $0.order < $1.order }
        return (buckets.map { Double($0.last) / 100 }, buckets.map { $0.label })
    }

    func load(account: Account) async {
        isLoading = true
        error = nil

        let (start, end) = timeRange()
        let params: [URLQueryItem] = [
            URLQueryItem(name: "account_id", value: account.id),
            URLQueryItem(name: "start_time", value: "\(start)"),
            URLQueryItem(name: "end_time", value: "\(end)")
        ]

        do {
            let resp: ReconciliationStatement = try await APIClient.shared.request(
                "/api/v1/transactions/reconciliation_statements.json", query: params
            )
            statement = resp
            rawItems = resp.items
            items = buildItems(resp.items)
            isLoading = false
            isInitialLoading = false
        } catch {
            isLoading = false
            isInitialLoading = false
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// 把交易按「日」分组，并把每笔的账户余额换算成币种无关的「分」
    private func buildItems(_ txs: [ReconciliationTransactionItem]) -> [ReconciliationListItem] {
        let cal = Calendar.current
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        var result: [ReconciliationListItem] = []
        var lastDay = ""
        // 后端按时间倒序返回；日期分组头按遇到的第一笔插入
        for tx in txs {
            let day = fmt.string(from: Date(timeIntervalSince1970: TimeInterval(tx.time)))
            if day != lastDay {
                result.append(.date(day))
                lastDay = day
            }
            _ = cal
            result.append(.transaction(tx, balance: tx.accountClosingBalance ?? 0))
        }
        return result
    }

    private func timeRange() -> (Int64, Int64) {
        let cal = Calendar.current
        let now = Date()
        switch rangeType {
        case .thisMonth:
            let comps = cal.dateComponents([.year, .month], from: now)
            let start = cal.date(from: comps) ?? now
            let end = cal.date(byAdding: .month, value: 1, to: start) ?? now
            return (Int64(start.timeIntervalSince1970), Int64(end.timeIntervalSince1970) - 1)
        case .lastMonth:
            let comps = cal.dateComponents([.year, .month], from: now)
            let thisMonth = cal.date(from: comps) ?? now
            let start = cal.date(byAdding: .month, value: -1, to: thisMonth) ?? now
            return (Int64(start.timeIntervalSince1970), Int64(thisMonth.timeIntervalSince1970) - 1)
        case .thisYear:
            let start = cal.date(from: DateComponents(year: cal.component(.year, from: now), month: 1, day: 1)) ?? now
            let end = cal.date(byAdding: .year, value: 1, to: start) ?? now
            return (Int64(start.timeIntervalSince1970), Int64(end.timeIntervalSince1970) - 1)
        case .lastYear:
            let thisYear = cal.date(from: DateComponents(year: cal.component(.year, from: now), month: 1, day: 1)) ?? now
            let start = cal.date(byAdding: .year, value: -1, to: thisYear) ?? now
            return (Int64(start.timeIntervalSince1970), Int64(thisYear.timeIntervalSince1970) - 1)
        case .all:
            return (0, 0)
        case .custom:
            let s = cal.startOfDay(for: customStart)
            let e = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: customEnd)) ?? customEnd
            return (Int64(s.timeIntervalSince1970), Int64(e.timeIntervalSince1970) - 1)
        }
    }
}

// MARK: - 响应模型

/// 对账单条目（对应 Go TransactionReconciliationStatementResponseItem）
struct ReconciliationTransactionItem: Codable, Identifiable {
    let id: String
    let type: Int
    let categoryId: String?
    let category: TransactionCategory?
    let time: Int64
    let sourceAccountId: String?
    let destinationAccountId: String?
    let sourceAmount: Int64
    let destinationAmount: Int64?
    let comment: String?
    let accountOpeningBalance: Int64?
    let accountClosingBalance: Int64?

    var icon: String? { category?.icon }
    var color: String? { category?.color }

    var displayName: String {
        if type == TransactionType.modifyBalance.rawValue { return "余额调整" }
        return category?.name ?? "交易"
    }
    var isIncome: Bool { type == TransactionType.income.rawValue }
    var isExpense: Bool { type == TransactionType.expense.rawValue }

    var timeText: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: Date(timeIntervalSince1970: TimeInterval(time)))
    }

    /// 展示金额（分）。转账在目标账户侧取 destinationAmount。
    func displayAmount(cents currency: String?) -> Int64 {
        if type == TransactionType.transfer.rawValue, let dest = destinationAmount, dest != 0 {
            return dest
        }
        return sourceAmount
    }
}

struct ReconciliationStatement: Codable {
    let transactions: [ReconciliationTransactionItem]
    let totalInflows: Int64
    let totalOutflows: Int64
    let openingBalance: Int64
    let closingBalance: Int64

    var items: [ReconciliationTransactionItem] { transactions }
    /// 净现金流 = 流入 - 流出
    var netCashFlow: Int64 { totalInflows - totalOutflows }
}

// MARK: - 余额趋势柱状图（iOS 15 自绘）

struct BalanceTrendChart: View {
    let values: [Double]
    let labels: [String]

    var body: some View {
        GeometryReader { geo in
            let maxV = values.max() ?? 1
            let minV = min(values.min() ?? 0, 0)
            let span = max(maxV - minV, 1)
            let count = max(values.count, 1)
            let barW = max((geo.size.width - CGFloat(count - 1) * 2) / CGFloat(count), 1)

            ZStack(alignment: .bottomLeading) {
                if values.isEmpty {
                    Text("暂无数据").font(.caption).foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    HStack(alignment: .bottom, spacing: 2) {
                        ForEach(values.indices, id: \.self) { i in
                            let h = CGFloat((values[i] - minV) / span) * (geo.size.height - 20)
                            VStack(spacing: 2) {
                                Spacer(minLength: 0)
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Theme.brand)
                                    .frame(width: barW, height: max(h, 2))
                            }
                        }
                    }
                }
            }
        }
    }
}
