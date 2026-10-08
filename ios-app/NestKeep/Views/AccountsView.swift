import SwiftUI
import Combine

/// 账户列表：净资产汇总 + 按类别分组 + 子账户嵌套 + 增删改
@MainActor
final class AccountsViewModel: ObservableObject {
    @Published var accounts: [Account] = []
    @Published var isLoading = false
    @Published var error: String?
    /// 是否隐藏金额（对齐 Web 的眼睛图标）
    @Published var hideAmounts = false

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

    /// 顶层账户（保留隐藏的，由分组逻辑决定是否展示）
    var topLevelAccounts: [Account] {
        accounts.filter { !($0.hidden ?? false) }
    }

    /// 按类别分组的账户（对齐 Web 的账户列表分组）
    var groupedAccounts: [(category: Int, name: String, accounts: [Account])] {
        let visible = topLevelAccounts
        let dict = Dictionary(grouping: visible) { $0.category ?? 0 }
        return dict.keys.sorted().compactMap { key in
            guard let items = dict[key], !items.isEmpty else { return nil }
            return (key, AccountCategoryConst.name(key), items.sorted { ($0.displayOrder ?? 0) < ($1.displayOrder ?? 0) })
        }
    }

    // MARK: - 净资产汇总

    /// 总资产（isAsset 或按类别推断）
    var totalAssetsCents: Int64 {
        flatten(visibleOnly: true)
            .filter { $0.category.map { AccountCategoryConst.isAsset($0) } ?? ($0.isAsset ?? false) }
            .reduce(0) { $0 + balanceInCNY($1) }
    }

    /// 总负债（取绝对值累加）
    var totalLiabilitiesCents: Int64 {
        flatten(visibleOnly: true)
            .filter { $0.category.map { AccountCategoryConst.isLiability($0) } ?? ($0.isLiability ?? false) }
            .reduce(0) { $0 + abs(balanceInCNY($1)) }
    }

    var netAssetsCents: Int64 { totalAssetsCents - totalLiabilitiesCents }

    /// 拍平账户（含子账户）
    private func flatten(visibleOnly: Bool) -> [Account] {
        var result: [Account] = []
        for acc in accounts {
            if visibleOnly && (acc.hidden ?? false) { continue }
            if let subs = acc.subAccounts, !subs.isEmpty {
                // 多子账户：父账户本身不计金额，只统计子账户
                for sub in subs where !(visibleOnly && (sub.hidden ?? false)) {
                    result.append(sub)
                }
            } else {
                result.append(acc)
            }
        }
        return result
    }

    /// 余额折算（MVP：仅 CNY 直接计入，其他币种原值计入）
    private func balanceInCNY(_ acc: Account) -> Int64 {
        acc.balance
    }

    // MARK: - 增删改

    func create(_ req: AccountCreateRequest) async throws {
        let _: EmptyResult = try await APIClient.shared.request(
            "/api/v1/accounts/add.json", method: .POST, body: req
        )
        await load()
    }

    func modify(_ req: AccountModifyRequest) async throws {
        let _: EmptyResult = try await APIClient.shared.request(
            "/api/v1/accounts/modify.json", method: .POST, body: req
        )
        await load()
    }

    func delete(_ account: Account) async {
        do {
            let _: EmptyResult = try await APIClient.shared.request(
                "/api/v1/accounts/delete.json", method: .POST, body: AccountIdRequest(id: account.id)
            )
            accounts.removeAll { $0.id == account.id }
        } catch {
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    func toggleHide(_ account: Account) async {
        do {
            let _: EmptyResult = try await APIClient.shared.request(
                "/api/v1/accounts/hide.json", method: .POST,
                body: AccountHideRequest(id: account.id, hidden: !(account.hidden ?? false))
            )
            await load()
        } catch {
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }
}

struct AccountsView: View {
    @StateObject private var vm = AccountsViewModel()
    @Environment(\.mainTabBarInset) private var tabBarInset
    @State private var editingAccount: Account?
    @State private var showAdd = false
    @State private var deleting: Account?

    var body: some View {
        NavigationView {
            Group {
                if vm.isLoading && vm.accounts.isEmpty {
                    ProgressView()
                } else {
                    List {
                        Section {
                            netAssetsCard
                                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                                .listRowBackground(Color.clear)
                        }

                        ForEach(vm.groupedAccounts, id: \.category) { group in
                            Section(header: Text(group.name)) {
                                ForEach(group.accounts, id: \.id) { account in
                                    ForEach(rows(for: account).indices, id: \.self) { idx in
                                        let pair = rows(for: account)[idx]
                                        accountRow(pair.0, isSub: pair.1)
                                    }
                                }
                            }
                        }

                        if vm.groupedAccounts.isEmpty && !vm.isLoading {
                            Section {
                                VStack(spacing: 8) {
                                    Image(systemName: "creditcard").font(.system(size: 34)).foregroundColor(.secondary)
                                    Text("还没有账户").font(.subheadline).foregroundColor(.secondary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 24)
                                .listRowBackground(Color.clear)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .safeAreaInset(edge: .bottom) {
                        Color.clear.frame(height: tabBarInset)
                    }
                }
            }
            .navigationTitle("账户")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        vm.hideAmounts.toggle()
                    } label: {
                        Image(systemName: vm.hideAmounts ? "eye.slash" : "eye")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                }
            }
            .refreshable { await vm.load() }
            .sheet(isPresented: $showAdd) {
                AccountEditView(account: nil)
            }
            .sheet(item: $editingAccount) { acc in
                AccountEditView(account: acc)
            }
            .confirmationDialog("删除账户？", isPresented: Binding(
                get: { deleting != nil },
                set: { if !$0 { deleting = nil } }
            ), titleVisibility: .visible) {
                Button("删除", role: .destructive) {
                    if let acc = deleting { Task { await vm.delete(acc) } }
                    deleting = nil
                }
                Button("取消", role: .cancel) { deleting = nil }
            } message: {
                Text("该账户下的账单不会被删除，但账户将不可用。")
            }
        }
        .task { await vm.load() }
    }

    // MARK: - 净资产卡

    private var netAssetsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("净资产").font(.subheadline.weight(.medium)).foregroundColor(.white.opacity(0.85))
                Spacer()
                Image(systemName: "chart.pie.fill").foregroundColor(.white.opacity(0.85))
            }
            Text(masked(AmountFormat.format(vm.netAssetsCents)))
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .minimumScaleFactor(0.6)
                .lineLimit(1)

            Divider().overlay(Color.white.opacity(0.25))

            HStack(spacing: 0) {
                assetCell("总资产", vm.totalAssetsCents)
                Rectangle().fill(Color.white.opacity(0.25)).frame(width: 1, height: 28)
                assetCell("总负债", vm.totalLiabilitiesCents)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [Theme.brand, Theme.brand.opacity(0.78)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .cornerRadius(18)
        .shadow(color: Theme.brand.opacity(0.30), radius: 10, x: 0, y: 5)
    }

    private func assetCell(_ title: String, _ cents: Int64) -> some View {
        VStack(spacing: 4) {
            Text(title).font(.caption).foregroundColor(.white.opacity(0.8))
            Text(masked(AmountFormat.format(cents)))
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    /// 金额隐藏时显示 ****
    private func masked(_ text: String) -> String {
        vm.hideAmounts ? "****" : text
    }

    // MARK: - 账户行（含子账户嵌套）

    /// 把「父账户 + 可见子账户」拍平成一组行，避免 ViewBuilder 自递归
    /// （Swift 5 下 `some View` 自引用会导致 opaque 类型推断失败）
    private func rows(for account: Account) -> [(Account, Bool)] {
        var arr: [(Account, Bool)] = [(account, false)]
        if let subs = account.subAccounts, !subs.isEmpty {
            arr.append(contentsOf: subs.filter { !($0.hidden ?? false) }.map { ($0, true) })
        }
        return arr
    }

    @ViewBuilder
    private func accountRow(_ account: Account, isSub: Bool) -> some View {
        HStack(spacing: 12) {
            if isSub { Spacer().frame(width: 20) }
            Image(systemName: AccountIconCatalog.symbol(account.icon))
                .foregroundColor(.white)
                .font(.system(size: 15))
                .frame(width: isSub ? 30 : 36, height: isSub ? 30 : 36)
                .background(Circle().fill(Color(hex: account.color ?? "26A69A")))
            VStack(alignment: .leading, spacing: 2) {
                Text(account.name)
                HStack(spacing: 6) {
                    if let currency = account.currency, !currency.isEmpty {
                        Text(currency)
                    }
                    if account.type == AccountType.multiSubAccounts.rawValue {
                        Text("多子账户")
                    }
                }
                .font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            Text(masked(AmountFormat.format(account.balance, currency: account.currency)))
                .font(.system(.body, design: .rounded))
        }
        .contentShape(Rectangle())
        .onTapGesture { editingAccount = account }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) { deleting = account } label: {
                Label("删除", systemImage: "trash")
            }
            Button { Task { await vm.toggleHide(account) } } label: {
                Label("隐藏", systemImage: "eye.slash")
            }
            .tint(.gray)
        }
    }
}
