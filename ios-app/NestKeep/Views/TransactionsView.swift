import SwiftUI
import Combine

/// 账单页：按月分页列表，按日分组，支持月份切换与下拉刷新
@MainActor
final class TransactionsViewModel: ObservableObject {
    @Published var transactions: [Transaction] = []
    @Published var year: Int
    @Published var month: Int
    @Published var isLoading = false
    @Published var error: String?

    private var accounts: [Account] = []
    private var categories: [TransactionCategory] = []

    init() {
        let comps = Calendar.current.dateComponents([.year, .month], from: Date())
        year = comps.year!
        month = comps.month!
    }

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
            isLoading = false
        } catch {
            isLoading = false
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    func shiftMonth(by delta: Int) {
        var comps = DateComponents(year: year, month: month)
        comps.month! += delta
        let date = Calendar.current.date(from: comps)!
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
}

struct TransactionsView: View {
    @StateObject private var vm = TransactionsViewModel()
    @State private var showAdd = false

    private var grouped: [(date: Date, items: [Transaction])] {
        let cal = Calendar.current
        let dict = Dictionary(grouping: vm.transactions) { cal.startOfDay(for: $0.date) }
        return dict.keys.sorted(by: >).map { ($0, dict[$0] ?? []) }
    }

    var body: some View {
        NavigationView {
            Group {
                if vm.isLoading && vm.transactions.isEmpty {
                    ProgressView()
                } else {
                    List {
                        ForEach(grouped, id: \.date) { group in
                            Section(header: Text(group.date, style: .date)) {
                                ForEach(group.items) { tx in
                                    TransactionRow(tx: tx, vm: vm)
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("账单")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    HStack(spacing: 16) {
                        Button { vm.shiftMonth(by: -1) } label: { Image(systemName: "chevron.left") }
                        Button { vm.shiftMonth(by: 1) } label: { Image(systemName: "chevron.right") }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                }
            }
            .refreshable { await vm.load() }
            .sheet(isPresented: $showAdd) {
                TransactionEditView(transaction: nil)
            }
        }
        .task { await vm.load() }
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
        default:
            let prefix = tx.transactionType == .expense ? "-" : "+"
            return prefix + AmountFormat.format(tx.sourceAmount)
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "circle.fill")
                .foregroundColor(vm.categoryColor(tx.categoryId))
            VStack(alignment: .leading, spacing: 2) {
                Text(vm.categoryName(tx.categoryId))
                if let comment = tx.comment, !comment.isEmpty {
                    Text(comment).font(.caption).foregroundColor(.secondary)
                }
            }
            Spacer()
            Text(amountText)
                .font(.system(.body, design: .rounded))
                .foregroundColor(amountColor)
        }
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
