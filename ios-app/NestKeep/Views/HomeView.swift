import SwiftUI
import Combine

/// 首页：总资产 + 本月收支概览（原生理财卡片风）
@MainActor
final class HomeViewModel: ObservableObject {
    @Published var accounts: [Account] = []
    @Published var monthIncomeCents: Int64 = 0
    @Published var monthExpenseCents: Int64 = 0
    @Published var recentTransactions: [Transaction] = []
    @Published var isLoading = false
    @Published var error: String?

    func load() async {
        isLoading = true
        error = nil
        do {
            let cal = Calendar.current
            let now = Date()
            let start = cal.date(from: cal.dateComponents([.year, .month], from: now))!
            let end = cal.date(byAdding: .month, value: 1, to: start)!

            async let accs: [Account] = APIClient.shared.request("/api/v1/accounts/list.json")
            let query = "m_\(Int(start.timeIntervalSince1970))_\(Int(end.timeIntervalSince1970))"
            // 注意：amounts.json 返回的是「字典」(按 query 名为键)，不是数组
            async let amountsDict: [String: TransactionAmountsResponseItem] = APIClient.shared.request(
                "/api/v1/transactions/amounts.json",
                query: [URLQueryItem(name: "query", value: query)]
            )

            accounts = try await accs
            let amountsList = try await amountsDict.values.flatMap { $0.amounts ?? [] }
            var inc: Int64 = 0
            var exp: Int64 = 0
            for a in amountsList where a.currency == "CNY" || a.currency == nil {
                inc += a.incomeAmount ?? 0
                exp += a.expenseAmount ?? 0
            }
            monthIncomeCents = inc
            monthExpenseCents = exp

            // 最近账单（本月）
            if let page: TransactionPage2 = try? await APIClient.shared.request(
                "/api/v1/transactions/list/by_month.json",
                query: [
                    URLQueryItem(name: "year", value: "\(cal.component(.year, from: now))"),
                    URLQueryItem(name: "month", value: "\(cal.component(.month, from: now))"),
                ]
            ) {
                recentTransactions = Array(page.items.prefix(5))
            }
            isLoading = false
        } catch {
            isLoading = false
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    var totalAssetsCents: Int64 {
        accounts.filter { !($0.hidden ?? false) }.reduce(0) { $0 + $1.balance }
    }

    /// 本月结余
    var monthNetCents: Int64 { monthIncomeCents - monthExpenseCents }
}

struct HomeView: View {
    @StateObject private var vm = HomeViewModel()

    private var monthLabel: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月"
        return f.string(from: Date())
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    heroCard
                    overviewRow
                    if !vm.recentTransactions.isEmpty { recentCard }
                    if let error = vm.error {
                        Text(error).font(.footnote).foregroundColor(.red)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .background(Theme.pageBackground.ignoresSafeArea())
            .navigationTitle("巢记")
            .refreshable { await vm.load() }
        }
        .task { await vm.load() }
    }

    // MARK: - 总资产 Hero 卡
    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("总资产").font(.subheadline).fontWeight(.medium)
                    .foregroundColor(.white.opacity(0.85))
                Spacer()
                Image(systemName: "house.lodge.fill")
                    .foregroundColor(.white.opacity(0.85))
            }
            Text(AmountFormat.format(vm.totalAssetsCents))
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .minimumScaleFactor(0.6)
                .lineLimit(1)

            Divider().overlay(Color.white.opacity(0.25))

            HStack(spacing: 0) {
                miniStat(title: "\(monthLabel)支出", amount: vm.monthExpenseCents)
                Rectangle().fill(Color.white.opacity(0.25)).frame(width: 1, height: 28)
                miniStat(title: "\(monthLabel)收入", amount: vm.monthIncomeCents)
                Rectangle().fill(Color.white.opacity(0.25)).frame(width: 1, height: 28)
                miniStat(title: "\(monthLabel)结余", amount: vm.monthNetCents)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Theme.brand, Theme.brand.opacity(0.78)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        )
        .cornerRadius(20)
        .shadow(color: Theme.brand.opacity(0.35), radius: 12, x: 0, y: 6)
    }

    private func miniStat(title: String, amount: Int64) -> some View {
        VStack(spacing: 4) {
            Text(title).font(.caption).foregroundColor(.white.opacity(0.8))
            Text(AmountFormat.format(amount))
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 概述行（账户数等）
    private var overviewRow: some View {
        HStack(spacing: 12) {
            statTile(title: "账户数", value: "\(vm.accounts.count)", icon: "wallet.pass", color: Theme.brand)
            statTile(title: "本月笔数", value: "\(vm.recentTransactions.count)", icon: "list.bullet.rectangle", color: Color(red: 0.29, green: 0.56, blue: 0.89))
        }
    }

    private func statTile(title: String, value: String, icon: String, color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(color)
                .frame(width: 38, height: 38)
                .background(color.opacity(0.12))
                .cornerRadius(10)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption).foregroundColor(.secondary)
                Text(value).font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)
            }
            Spacer()
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
    }

    // MARK: - 最近账单
    private var recentCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("最近账单").font(.headline).padding(.bottom, 10)

            ForEach(Array(vm.recentTransactions.enumerated()), id: \.element.id) { idx, tx in
                HStack(spacing: 12) {
                    Image(systemName: tx.transactionType == .income ? "arrow.down.left" : (tx.transactionType == .transfer ? "arrow.left.arrow.right" : "arrow.up.right"))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(tx.transactionType == .income ? Theme.income : (tx.transactionType == .transfer ? Color.gray : Theme.expense))
                        .frame(width: 32, height: 32)
                        .background((tx.transactionType == .income ? Theme.income : (tx.transactionType == .transfer ? Color.gray : Theme.expense)).opacity(0.12))
                        .cornerRadius(8)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tx.categoryName ?? (tx.transactionType == .transfer ? "转账" : "未分类"))
                            .font(.subheadline).lineLimit(1)
                        Text(Self.dateLabel(tx.date)).font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                    Text(amountText(tx))
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(tx.transactionType == .income ? Theme.income : (tx.transactionType == .transfer ? .primary : Theme.expense))
                }
                .padding(.vertical, 6)

                if idx < vm.recentTransactions.count - 1 {
                    Divider().padding(.leading, 44)
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
    }

    private func amountText(_ tx: Transaction) -> String {
        let v = AmountFormat.format(tx.sourceAmount, currency: tx.currency)
        switch tx.transactionType {
        case .income: return "+\(v)"
        case .expense: return "-\(v)"
        case .transfer: return v
        }
    }

    static func dateLabel(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日"
        return f.string(from: d)
    }
}
