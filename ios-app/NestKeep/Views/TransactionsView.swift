import SwiftUI
import Combine

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

    private var categories: [TransactionCategory] = []

    init() {
        let comps = Calendar.current.dateComponents([.year, .month], from: Date())
        year = comps.year!
        month = comps.month!
    }

    var totalAssetsCents: Int64 {
        accounts.filter { !($0.hidden ?? false) }.reduce(0) { $0 + $1.balance }
    }

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
            async let accs: [Account] = APIClient.shared.request("/api/v1/accounts/list.json")
            async let cats: [TransactionCategory] = APIClient.shared.request("/api/v1/transaction/categories/list.json")
            async let page: TransactionPage2 = APIClient.shared.request(
                "/api/v1/transactions/list/by_month.json",
                query: [
                    URLQueryItem(name: "year", value: "\(year)"),
                    URLQueryItem(name: "month", value: "\(month)"),
                    URLQueryItem(name: "count", value: "200"),
                    URLQueryItem(name: "sort_order", value: "desc")
                ]
            )
            accounts = try await accs
            categories = try await cats
            transactions = (try await page).items
            await loadAmounts()
            isLoading = false
        } catch {
            isLoading = false
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// 拉取当前自然月的收支合计（用于汇总卡；与列表月份无关，始终是「本月」）
    private func loadAmounts() async {
        let cal = Calendar.current
        let now = Date()
        guard let start = cal.date(from: cal.dateComponents([.year, .month], from: now)),
              let end = cal.date(byAdding: .month, value: 1, to: start) else { return }
        let query = "m_\(Int(start.timeIntervalSince1970))_\(Int(end.timeIntervalSince1970))"
        guard let dict: [String: TransactionAmountsResponseItem] = try? await APIClient.shared.request(
            "/api/v1/transactions/amounts.json",
            query: [URLQueryItem(name: "query", value: query)]
        ) else { return }
        let list = dict.values.flatMap { $0.amounts ?? [] }
        var inc: Int64 = 0
        var exp: Int64 = 0
        for a in list where a.currency == "CNY" || a.currency == nil {
            inc += a.incomeAmount ?? 0
            exp += a.expenseAmount ?? 0
        }
        monthIncomeCents = inc
        monthExpenseCents = exp
    }

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

    /// 左滑删除：走 POST /transactions/delete.json
    func delete(_ tx: Transaction) async {
        do {
            let req = TransactionDeleteRequest(id: tx.id)
            let _: EmptyResult = try await APIClient.shared.request(
                "/api/v1/transactions/delete.json", method: .POST, body: req
            )
            transactions.removeAll { $0.id == tx.id }
            await loadAmounts()
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
    @Environment(\.mainTabBarInset) private var tabBarInset
    @State private var editing: Transaction?
    @State private var detail: Transaction?

    init(showAdd: Binding<Bool> = .constant(false)) {
        _showAdd = showAdd
    }

    private var grouped: [(date: Date, items: [Transaction])] {
        let cal = Calendar.current
        let dict = Dictionary(grouping: vm.transactions) { cal.startOfDay(for: $0.date) }
        return dict.keys.sorted(by: >).map { ($0, dict[$0] ?? []) }
    }

    var body: some View {
        NavigationView {
            List {
                // 汇总卡（原首页内容）—— 作为列表首行，与 Web 首页并入本页对应
                Section {
                    summaryCard
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowBackground(Color.clear)
                }

                if vm.isLoading && vm.transactions.isEmpty {
                    Section {
                        HStack { Spacer(); ProgressView(); Spacer() }
                            .listRowBackground(Color.clear)
                    }
                }

                ForEach(grouped, id: \.date) { group in
                    Section(header: dayHeader(group.date, items: group.items)) {
                        ForEach(group.items) { tx in
                            TransactionRow(tx: tx, vm: vm)
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
                                }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .safeAreaInset(edge: .bottom) {
                // 浮层底部导航的避让（列表滚到底时最后几行不被加号/导航盖住）
                Color.clear.frame(height: tabBarInset)
            }
            .navigationTitle("账单")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    HStack(spacing: 14) {
                        Button { vm.shiftMonth(by: -1) } label: { Image(systemName: "chevron.left") }
                        Text("\(vm.year)年\(vm.month)月")
                            .font(.subheadline.weight(.medium))
                            .frame(minWidth: 78)
                        Button { vm.shiftMonth(by: 1) } label: { Image(systemName: "chevron.right") }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                }
            }
            .refreshable { await vm.load() }
            .sheet(item: $editing) { tx in
                TransactionEditView(transaction: tx, mode: .edit)
            }
            .sheet(item: $detail) { tx in
                TransactionDetailView(transaction: tx)
            }
        }
        .task { await vm.load() }
    }

    // MARK: - 汇总卡
    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("总资产").font(.subheadline.weight(.medium))
                    .foregroundColor(.white.opacity(0.85))
                Spacer()
                Image(systemName: "house.lodge.fill")
                    .foregroundColor(.white.opacity(0.85))
            }
            Text(AmountFormat.format(vm.totalAssetsCents))
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .minimumScaleFactor(0.6)
                .lineLimit(1)

            Divider().overlay(Color.white.opacity(0.25))

            HStack(spacing: 0) {
                miniStat(title: "本月支出", amount: vm.monthExpenseCents)
                Rectangle().fill(Color.white.opacity(0.25)).frame(width: 1, height: 28)
                miniStat(title: "本月收入", amount: vm.monthIncomeCents)
                Rectangle().fill(Color.white.opacity(0.25)).frame(width: 1, height: 28)
                miniStat(title: "本月结余", amount: vm.monthNetCents)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Theme.brand, Theme.brand.opacity(0.78)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        )
        .cornerRadius(18)
        .shadow(color: Theme.brand.opacity(0.30), radius: 10, x: 0, y: 5)
    }

    private func miniStat(title: String, amount: Int64) -> some View {
        VStack(spacing: 4) {
            Text(title).font(.caption).foregroundColor(.white.opacity(0.8))
            Text(AmountFormat.format(amount))
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    /// 日分组头：日期 + 当日支出/收入合计（对齐 Web 的当日合计）
    private func dayHeader(_ date: Date, items: [Transaction]) -> some View {
        let exp = vm.dayExpense(items)
        let inc = vm.dayIncome(items)
        return HStack {
            Text(Self.dayLabel(date))
            Spacer()
            if exp > 0 {
                Text("支 \(AmountFormat.format(exp))")
                    .foregroundColor(Theme.expense)
            }
            if inc > 0 {
                Text("收 \(AmountFormat.format(inc))")
                    .foregroundColor(Theme.income)
            }
        }
        .font(.caption)
        .textCase(nil)
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

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(iconColor)
                .frame(width: 32, height: 32)
                .background(iconColor.opacity(0.12))
                .cornerRadius(9)

            VStack(alignment: .leading, spacing: 2) {
                Text(vm.categoryName(tx.categoryId))
                HStack(spacing: 6) {
                    Text(vm.accountName(tx.sourceAccountId))
                    if let comment = tx.comment, !comment.isEmpty {
                        Text("· \(comment)").lineLimit(1)
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
            Spacer()
            Text(amountText)
                .font(.system(.body, design: .rounded))
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
