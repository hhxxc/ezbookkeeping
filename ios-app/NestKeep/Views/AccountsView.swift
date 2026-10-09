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
            VStack(spacing: 0) {
                // 顶栏放列表上方（不悬浮）：iOS 15 下 safeAreaInset+List 的内容避让不可靠，
                // 净资产卡顶部会被固定栏压住；改为上下结构后列表恒从栏下方开始
                topBar
                Group {
                if vm.isLoading && vm.accounts.isEmpty {
                    ProgressView()
                } else if isSorting {
                    // 排序模式：独立 List + editMode 恒 active。
                    // 勿与 .refreshable 同挂（iOS 15 下 List editMode+refreshable 组合点开即闪退），
                    // 也不与普通列表共用（constant editMode 在 inactive 时也会引发异常）
                    List {
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
                    }
                    .listStyle(.insetGrouped)
                    .environment(\.editMode, .constant(.active))
                } else {
                    // 账户列表改 ScrollView+VStack 自控间距（对齐主页 4ccf11d9）：
                    // insetGrouped List 首组顶部 ~30pt 系统留白 iOS 15 收不掉，顶栏与净资产卡间隙过大。
                    // 行左滑（swipeActions）是 List 专属，同一组操作改由长按 contextMenu 承载（用户已确认）
                    ScrollView {
                        VStack(spacing: 0) {
                            netAssetsCard
                                // 顶栏底 4 + 卡顶 8 = 12pt，与主页汇总卡一致
                                .padding(.top, 8)
                                .padding(.bottom, 12)

                            ForEach(vm.groupedAccounts, id: \.category) { group in
                                Text(group.name)
                                    .font(.system(size: 13))
                                    .foregroundColor(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    // 25 = 卡片左缘 17 + 8，贴近原 insetGrouped header 缩进
                                    .padding(.leading, 25)
                                    .padding(.top, 16)
                                    .padding(.bottom, 8)

                                // 分组卡片：白底圆角 + 阴影，与主页卡片同风格
                                VStack(spacing: 0) {
                                    let groupRows = group.accounts.flatMap { rows(for: $0) }
                                    ForEach(groupRows.indices, id: \.self) { idx in
                                        if idx > 0 {
                                            // 64 = 行内边距 16 + 图标 36 + 间距 12，与行文字左缘对齐
                                            Divider().padding(.leading, 64)
                                        }
                                        accountRow(groupRows[idx].0, isSub: groupRows[idx].1)
                                    }
                                }
                                .background(HomePalette.card)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .shadow(color: Color.black.opacity(HomePalette.isDark ? 0.5 : 0.06), radius: 10, x: 0, y: 4)
                            }

                            if vm.groupedAccounts.isEmpty && !vm.isLoading {
                                VStack(spacing: 8) {
                                    Image(systemName: "creditcard").font(.system(size: 34)).foregroundColor(.secondary)
                                    Text("还没有账户").font(.subheadline).foregroundColor(.secondary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 24)
                            }
                        }
                        .padding(.horizontal, 17)
                        .padding(.bottom, 16)
                    }
                    .refreshable { await vm.load() }
                    // 底部避让由 MainTabView 整页容器统一施加，此处不再重复叠加
                }
                }
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
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
        .task { await vm.load() }
    }

    // MARK: - 顶部自绘栏（系统导航栏在 Tab 根页会顶进状态栏，与统计页同款方案）
    /// 标题 + 眼睛（隐藏金额）/ 排序 / 新增；排序模式时右侧换成「完成」
    private var topBar: some View {
        HStack(spacing: 10) {
            Text(isSorting ? "排序模式" : "账户")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(HomePalette.ink)

            Spacer()

            if isSorting {
                Button {
                    finishSorting()
                } label: {
                    Text("完成")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Theme.brand)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    withAnimation(.easeInOut(duration: 0.16)) { vm.hideAmounts.toggle() }
                } label: {
                    Image(systemName: vm.hideAmounts ? "eye.slash" : "eye")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(HomePalette.ink)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(Color.primary.opacity(0.05)))
                }
                .buttonStyle(.plain)

                Button {
                    sortItems = flatSortableAccounts()
                    isSorting = true
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(HomePalette.ink)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(Color.primary.opacity(0.05)))
                }
                .buttonStyle(.plain)

                Button { showAdd = true } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Theme.brand)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(Theme.brand.opacity(0.14)))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 4)
        .background(
            VStack(spacing: 0) {
                Color(.systemGroupedBackground)
                Rectangle()
                    .fill(Color.primary.opacity(0.06))
                    .frame(height: 0.5)
            }
            .ignoresSafeArea(edges: .top)
        )
    }

    private func finishSorting() {
        let ordered = sortItems
        isSorting = false
        Task { await vm.saveOrder(ordered) }
    }

    // MARK: - 净资产卡（样式对齐首页汇总卡：16 圆角 / 同边距 / 同字阶 / 同背景图蒙层）
    private var netAssetsCard: some View {
        let bgURL = HomeBackground.imageURL
        let hasBG = bgURL != nil
        let primaryText: Color = hasBG ? .white : HomePalette.ink
        let labelColor: Color = hasBG ? Color.white.opacity(0.9) : HomePalette.secondary
        let assetColor: Color = hasBG ? .white : HomePalette.income
        let liabilityColor: Color = hasBG ? .white : HomePalette.expense

        return VStack(alignment: .leading, spacing: 0) {
            Text("净资产")
                .font(.system(size: 13))
                .foregroundColor(labelColor)
                .modifier(HomeShadow(active: hasBG))

            // 大金额 + 眼睛开关
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(masked(AmountFormat.format(vm.netAssetsCents)))
                    .font(.system(size: 30, weight: .semibold))
                    .monospacedDigit()
                    .foregroundColor(primaryText)
                    .minimumScaleFactor(0.55)
                    .lineLimit(1)
                    .modifier(HomeShadow(active: hasBG))
                Button {
                    withAnimation(.easeInOut(duration: 0.16)) { vm.hideAmounts.toggle() }
                } label: {
                    Image(systemName: vm.hideAmounts ? "eye.slash.fill" : "eye.fill")
                        .font(.system(size: 16))
                        .foregroundColor(labelColor)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 3)
            .padding(.bottom, 12)

            Rectangle()
                .fill(hasBG ? Color.white.opacity(0.28) : HomePalette.divider)
                .frame(height: 1)
                .padding(.bottom, 12)

            HStack(spacing: 6) {
                Text("总资产").font(.system(size: 13)).foregroundColor(labelColor)
                    .modifier(HomeShadow(active: hasBG))
                Text(masked(AmountFormat.format(vm.totalAssetsCents)))
                    .font(.system(size: 15, weight: .semibold)).monospacedDigit()
                    .foregroundColor(assetColor).lineLimit(1).minimumScaleFactor(0.6)
                    .modifier(HomeShadow(active: hasBG))
                Rectangle()
                    .fill(hasBG ? Color.white.opacity(0.28) : HomePalette.divider)
                    .frame(width: 1, height: 12)
                Text("总负债").font(.system(size: 13)).foregroundColor(labelColor)
                    .modifier(HomeShadow(active: hasBG))
                Text(masked(AmountFormat.format(vm.totalLiabilitiesCents)))
                    .font(.system(size: 15, weight: .semibold)).monospacedDigit()
                    .foregroundColor(liabilityColor).lineLimit(1).minimumScaleFactor(0.6)
                    .modifier(HomeShadow(active: hasBG))
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
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
                    Color.black.opacity(0.28)
                }
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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
        // 原 insetGrouped 行自带内边距，改自绘后补上
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture { editingAccount = account }
        // 原 List 行左滑（swipeActions）的同一组操作，改由长按菜单承载
        .contextMenu {
            Button { statementAccount = account } label: {
                Label("对账单", systemImage: "list.bullet.rectangle")
            }
            Button { Task { await vm.toggleHide(account) } } label: {
                Label("隐藏", systemImage: "eye.slash")
            }
            // 单账户（非父账户）才能移动全部账单
            if account.type != AccountType.multiSubAccounts.rawValue {
                Button { moveFromAccount = account } label: {
                    Label("移动账单", systemImage: "arrow.right.arrow.left")
                }
            }
            Divider()
            Button(role: .destructive) { deleting = account } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }
}
