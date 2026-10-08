import SwiftUI
import Combine

/// 首页：本月收支概览 + 账户总资产（核心闭环 MVP 版）
@MainActor
final class HomeViewModel: ObservableObject {
    @Published var accounts: [Account] = []
    @Published var monthIncomeCents: Int64 = 0
    @Published var monthExpenseCents: Int64 = 0
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
            for a in amountsList where a.currency == "CNY" || a.currency == nil {
                monthIncomeCents += a.incomeAmount ?? 0
                monthExpenseCents += a.expenseAmount ?? 0
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
}

struct HomeView: View {
    @StateObject private var vm = HomeViewModel()

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    // 总资产卡片
                    VStack(alignment: .leading, spacing: 8) {
                        Text("总资产").font(.subheadline).foregroundColor(.secondary)
                        Text(AmountFormat.format(vm.totalAssetsCents))
                            .font(.system(size: 34, weight: .semibold, design: .rounded))
                            .foregroundColor(Color(red: 31/255, green: 41/255, blue: 55/255))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
                    .background(Color.white)
                    .cornerRadius(16)
                    .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 2)

                    // 本月收支
                    HStack(spacing: 12) {
                        SummaryTile(title: "本月支出", amount: vm.monthExpenseCents, color: Theme.expense)
                        SummaryTile(title: "本月收入", amount: vm.monthIncomeCents, color: Theme.income)
                    }

                    if let error = vm.error {
                        Text(error).font(.footnote).foregroundColor(.red)
                    }
                }
                .padding(16)
            }
            .background(Theme.pageBackground.ignoresSafeArea())
            .navigationTitle("巢记")
            .refreshable { await vm.load() }
        }
        .task { await vm.load() }
    }
}

struct SummaryTile: View {
    let title: String
    let amount: Int64
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline).foregroundColor(.secondary)
            Text(AmountFormat.format(amount))
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 2)
    }
}
