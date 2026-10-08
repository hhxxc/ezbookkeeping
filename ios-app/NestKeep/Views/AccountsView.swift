import SwiftUI
import Combine

/// 账户列表（含子账户），显示余额
@MainActor
final class AccountsViewModel: ObservableObject {
    @Published var accounts: [Account] = []
    @Published var isLoading = false
    @Published var error: String?

    func load() async {
        isLoading = true
        error = nil
        do {
            accounts = try await APIClient.shared.request("/api/v1/accounts/list.json")
            isLoading = false
        } catch {
            isLoading = false
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }
}

struct AccountsView: View {
    @StateObject private var vm = AccountsViewModel()

    var body: some View {
        NavigationView {
            Group {
                if vm.isLoading && vm.accounts.isEmpty {
                    ProgressView()
                } else {
                    List {
                        ForEach(flattenedAccounts, id: \.id) { account in
                            HStack {
                                Image(systemName: iconName(for: account))
                                    .foregroundColor(.white)
                                    .frame(width: 36, height: 36)
                                    .background(Circle().fill(Theme.brand))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(account.name)
                                    if let currency = account.currency {
                                        Text(currency).font(.caption).foregroundColor(.secondary)
                                    }
                                }
                                Spacer()
                                Text(AmountFormat.format(account.balance, currency: account.currency))
                                    .font(.system(.body, design: .rounded))
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("账户")
            .refreshable { await vm.load() }
        }
        .task { await vm.load() }
    }

    /// 把子账户拍平展示（MVP 简化：不渲染层级缩进）
    private var flattenedAccounts: [Account] {
        vm.accounts.flatMap { acc in
            var arr = [acc]
            if let subs = acc.subAccounts { arr.append(contentsOf: subs) }
            return arr.filter { !($0.hidden ?? false) }
        }
    }

    /// 后端 icon 是数字图标字体编号，原生用 SF Symbols 近似映射（MVP）
    private func iconName(for account: Account) -> String {
        guard let cat = account.category else { return "wallet.pass" }
        switch cat {
        case 1: return "banknote"
        case 2: return "wallet.pass"
        case 3: return "creditcard"
        case 4: return "cpu"
        case 5: return "exclamationmark.circle"
        case 6: return "person.2"
        case 7: return "chart.line.uptrend.xyaxis"
        case 8: return "piggybank"
        case 9: return "doc"
        default: return "wallet.pass"
        }
    }
}
