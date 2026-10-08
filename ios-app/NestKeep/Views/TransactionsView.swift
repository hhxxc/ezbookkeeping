import SwiftUI
import Combine

/// 账单筛选条件（对齐 Web 手机端账单筛选面板）
struct TransactionFilter: Equatable {
    /// 交易类型：0=全部，与 Go TransactionType 一致（1余额调整/2收入/3支出/4转账）
    var type: Int = 0
    var categoryIds: [String] = []
    var accountIds: [String] = []
    var startDate: Date?
    var endDate: Date?
    /// 排序字段：time / amount
    var sortBy: String = "time"
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
            accounts = try await accs
            categories = try await cats
            transactions = try await fetchTransactions()
            await loadAmounts()
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

    func clearFilter() {
        filter = TransactionFilter()
        searchKeyword = ""
        Task { await load() }
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
    @State private var showFilter = false

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
                // 搜索框（对齐 Web 的描述/金额关键字搜索，防抖）
                Section {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                        TextField("搜索备注 / 金额", text: $vm.searchKeyword)
                            .textFieldStyle(.plain)
                            .onChange(of: vm.searchKeyword) { _ in vm.scheduleSearch() }
                        if !vm.searchKeyword.isEmpty {
                            Button { vm.searchKeyword = ""; vm.scheduleSearch() } label: {
                                Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .listRowBackground(Color(.secondarySystemGroupedBackground))
                }

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
                } else if !vm.isLoading && vm.transactions.isEmpty {
                    Section {
                        VStack(spacing: 8) {
                            Image(systemName: "tray").font(.system(size: 34)).foregroundColor(.secondary)
                            Text(vm.isFiltering ? "没有符合条件的账单" : "本月还没有账单")
                                .font(.subheadline).foregroundColor(.secondary)
                            if vm.isFiltering {
                                Button("清除筛选") { vm.clearFilter() }.font(.footnote)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
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
            .navigationTitle(vm.isFiltering ? "筛选结果" : "账单")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if !vm.isFiltering {
                        HStack(spacing: 14) {
                            Button { vm.shiftMonth(by: -1) } label: { Image(systemName: "chevron.left") }
                            Text("\(vm.year)年\(vm.month)月")
                                .font(.subheadline.weight(.medium))
                                .frame(minWidth: 78)
                            Button { vm.shiftMonth(by: 1) } label: { Image(systemName: "chevron.right") }
                        }
                    } else {
                        Button("清除") { vm.clearFilter() }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 16) {
                        Button { showFilter = true } label: {
                            Image(systemName: vm.filter.isActive
                                  ? "line.3.horizontal.decrease.circle.fill"
                                  : "line.3.horizontal.decrease.circle")
                        }
                        Button { showAdd = true } label: { Image(systemName: "plus") }
                    }
                }
            }
            .refreshable { await vm.load() }
            .sheet(item: $editing) { tx in
                TransactionEditView(transaction: tx, mode: .edit)
            }
            .sheet(item: $detail) { tx in
                TransactionDetailView(transaction: tx)
            }
            .sheet(isPresented: $showFilter) {
                TransactionFilterSheet(
                    filter: vm.filter,
                    accounts: vm.accounts,
                    categories: vm.categoriesForFilter,
                    onApply: { vm.applyFilter($0) }
                )
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
