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

    /// 保存排序结果（`newDisplayOrders` 按当前顺序重排可见账户）
    func saveOrder(_ ordered: [Account]) async {
        let req = AccountMoveRequest(newDisplayOrders: ordered.enumerated().map {
            AccountNewDisplayOrderRequest(id: $0.element.id, displayOrder: $0.offset)
        })
        do {
            let _: EmptyResult = try await APIClient.shared.request(
                "/api/v1/accounts/move.json", method: .POST, body: req
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
    /// 对账单 / 移动全部账单的目标账户
    @State private var statementAccount: Account?
    @State private var moveFromAccount: Account?
    /// 排序模式
    @State private var isSorting = false
    @State private var sortItems: [Account] = []

    /// 排序模式下的扁平账户列表（父 + 可见子账户）
    private func flatSortableAccounts() -> [Account] {
        var arr: [Account] = []
        for acc in vm.topLevelAccounts {
            arr.append(acc)
            if let subs = acc.subAccounts {
                arr.append(contentsOf: subs.filter { !($0.hidden ?? false) })
            }
        }
        return arr
    }

    var body: some View {
        NavigationView {
            Group {
                if vm.isLoading && vm.accounts.isEmpty {
                    ProgressView()
                } else {
                    List {
                        if isSorting {
                            Section {
                                ForEach(sortItems, id: \.id) { account in
                                    HStack(spacing: 12) {
                                        Image(systemName: AccountIconCatalog.symbol(account.icon))
                                            .foregroundColor(.white)
                                            .font(.system(size: 15))
                                            .frame(width: 30, height: 30)
                                            .background(Circle().fill(Color(hex: account.color ?? "26A69A")))
                                        Text(account.name)
                                        Spacer()
                                    }
                                }
                                .onMove { from, to in sortItems.move(fromOffsets: from, toOffset: to) }
                            } footer: {
                                Text("拖动调整账户顺序，完成后点「完成」。")
                            }
                        } else {
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
                    }
                    .listStyle(.insetGrouped)
                    .environment(\.editMode, .constant(isSorting ? EditMode.active : EditMode.inactive))
                    // 底部避让由 MainTabView 整页容器统一施加，此处不再重复叠加
                }
            }
            .navigationTitle("账户")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if isSorting {
                        Button("完成") { finishSorting() }
                    } else {
                        Button {
                            vm.hideAmounts.toggle()
                        } label: {
                            Image(systemName: vm.hideAmounts ? "eye.slash" : "eye")
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !isSorting {
                        HStack(spacing: 16) {
                            Button("排序") {
                                sortItems = flatSortableAccounts()
                                isSorting = true
                            }
                            Button { showAdd = true } label: { Image(systemName: "plus") }
                        }
                    }
                }
            }
            .refreshable { await vm.load() }
            .sheet(isPresented: $showAdd) {
                AccountEditView(account: nil)
            }
            .sheet(item: $editingAccount) { acc in
                AccountEditView(account: acc)
            }
            .sheet(item: $statementAccount) { acc in
                NavigationView {
                    ReconciliationStatementView(account: acc)
                        .safeAreaInset(edge: .bottom) { Color.clear.frame(height: tabBarInset) }
                }
            }
            .sheet(item: $moveFromAccount) { acc in
                MoveAllTransactionsView(fromAccount: acc)
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

    private func finishSorting() {
        let ordered = sortItems
        isSorting = false
        Task { await vm.saveOrder(ordered) }
    }

    // MARK: - 净资产卡（对齐 Web `accounts/ListPage.vue` 的 `.account-overview-card`）
    /// Web 结构：`净资产` 小标签(.88em 半透明) → `net-assets` 2em/700 大金额 + 眼睛开关
    /// → 细分隔线 → `总资产 | 总负债`(.85em，绿/红着色)。
    /// 卡片为**白底 20px 圆角**（深色 #1c1c1e），**不使用主题色渐变**。
    private var netAssetsCard: some View {
        let bgURL = HomeBackground.imageURL
        let hasBG = bgURL != nil
        let primaryText: Color = hasBG ? .white : HomePalette.ink
        let labelColor: Color = hasBG ? Color.white.opacity(0.82) : HomePalette.secondary
        let assetColor: Color = hasBG ? Color(hex: "#7FF0C0") : Color(hex: "#07C160")
        let liabilityColor: Color = hasBG ? Color(hex: "#FFB4AB") : Color(hex: "#DC2626")

        return VStack(alignment: .leading, spacing: 0) {
            Text("净资产")
                .font(.system(size: 14))
                .foregroundColor(labelColor)
                .modifier(HomeShadow(active: hasBG))

            // 大金额 + 眼睛开关
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(masked(AmountFormat.format(vm.netAssetsCents)))
                    .font(.system(size: 32, weight: .bold))
                    .monospacedDigit()
                    .foregroundColor(primaryText)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .modifier(HomeShadow(active: hasBG))
                Button {
                    withAnimation(.easeInOut(duration: 0.16)) { vm.hideAmounts.toggle() }
                } label: {
                    Image(systemName: vm.hideAmounts ? "eye.slash.fill" : "eye.fill")
                        .font(.system(size: 17))
                        .foregroundColor(labelColor)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 4)

            Rectangle()
                .fill(hasBG ? Color.white.opacity(0.28) : HomePalette.divider)
                .frame(height: 1)
                .padding(.vertical, 10)

            HStack(spacing: 8) {
                Text("总资产").font(.system(size: 14)).foregroundColor(labelColor)
                    .modifier(HomeShadow(active: hasBG))
                Text(masked(AmountFormat.format(vm.totalAssetsCents)))
                    .font(.system(size: 14, weight: .semibold)).monospacedDigit()
                    .foregroundColor(assetColor).lineLimit(1).minimumScaleFactor(0.6)
                    .modifier(HomeShadow(active: hasBG))
                Text("|").font(.system(size: 14))
                    .foregroundColor(hasBG ? Color.white.opacity(0.4) : Color.black.opacity(0.15))
                Text("总负债").font(.system(size: 14)).foregroundColor(labelColor)
                    .modifier(HomeShadow(active: hasBG))
                Text(masked(AmountFormat.format(vm.totalLiabilitiesCents)))
                    .font(.system(size: 14, weight: .semibold)).monospacedDigit()
                    .foregroundColor(liabilityColor).lineLimit(1).minimumScaleFactor(0.6)
                    .modifier(HomeShadow(active: hasBG))
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack {
                HomePalette.card
                if let url = bgURL {
                    CachedAsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Color.clear
                    }
                    Color.black.opacity(0.32)
                }
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color.black.opacity(HomePalette.isDark ? 0.5 : 0.08), radius: 10, x: 0, y: 4)
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
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button { statementAccount = account } label: {
                Label("对账单", systemImage: "list.bullet.rectangle")
            }
            .tint(Theme.brand)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) { deleting = account } label: {
                Label("删除", systemImage: "trash")
            }
            Button { Task { await vm.toggleHide(account) } } label: {
                Label("隐藏", systemImage: "eye.slash")
            }
            .tint(.gray)
            // 单账户（非父账户）才能移动全部账单
            if account.type != AccountType.multiSubAccounts.rawValue {
                Button { moveFromAccount = account } label: {
                    Label("移动账单", systemImage: "arrow.right.arrow.left")
                }
                .tint(.orange)
            }
        }
    }
}
