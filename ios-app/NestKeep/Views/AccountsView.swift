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
    /// 本 Tab 是否已成功加载过（供「首次选中才加载」门控）
    @Published var hasLoadedOnce = false

    func load(force: Bool = false) async {
        isLoading = true
        error = nil
        do {
            // 走共享缓存；下拉刷新 force=true 绕过 staleTime 强制拉新（余额要新鲜）
            accounts = try await AppDataStore.shared.getAccounts(force: force)
            hasLoadedOnce = true
            isLoading = false
        } catch {
            isLoading = false
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
        // 收支统计卡随列表一起刷新
        await loadStats()
    }

    // MARK: - 年度/累计收支统计

    enum YearStatsRange: String, CaseIterable, Identifiable {
        case thisYear
        case all

        var id: String { rawValue }
        var title: String { self == .thisYear ? "今年" : "全部" }
    }

    @Published var statsRange: YearStatsRange = .thisYear
    @Published private(set) var statsIncomeCents: Int64 = 0
    @Published private(set) var statsExpenseCents: Int64 = 0
    @Published private(set) var statsLoading = false

    /// 收支统计：statistics.json 按分类维度返回，本地按分类类型聚合收入/支出
    ///（口径与统计页一致：金额恒为正，1=收入 2=支出，转账/未知跳过）
    func loadStats() async {
        statsLoading = true
        let cal = Calendar.current
        let now = Date()
        let start: Date
        let end: Date
        switch statsRange {
        case .thisYear:
            start = cal.date(from: cal.dateComponents([.year], from: now)) ?? now
            end = cal.date(byAdding: .year, value: 1, to: start) ?? now
        case .all:
            start = Date(timeIntervalSince1970: 0)
            end = cal.date(byAdding: .year, value: 1, to: now) ?? now
        }
        do {
            let categories = (try? await AppDataStore.shared.getCategories()) ?? []
            var typeById: [String: Int] = [:]
            for c in categories {
                typeById[c.id] = c.type
                for sub in c.subCategories ?? [] { typeById[sub.id] = sub.type }
            }
            // statistics.json 返回的是 StatisticResponse 对象（数组在 .items 里），
            // 直接按数组解码会失败→静默变 0（v1.9.8 的坑）
            let resp: StatisticResponse = try await APIClient.shared.request(
                "/api/v1/transactions/statistics.json",
                query: [
                    URLQueryItem(name: "start_time", value: "\(Int(start.timeIntervalSince1970))"),
                    URLQueryItem(name: "end_time", value: "\(Int(end.timeIntervalSince1970) - 1)"),
                    URLQueryItem(name: "use_transaction_timezone", value: "true")
                ]
            )
            var inc: Int64 = 0
            var exp: Int64 = 0
            for item in resp.items {
                let amount = abs(item.amount)
                switch typeById[item.categoryId ?? "0"] {
                case .some(1): inc += amount
                case .some(2): exp += amount
                default: break
                }
            }
            statsIncomeCents = inc
            statsExpenseCents = exp
            statsLoading = false
        } catch {
            // 失败静默保留旧值（下次切范围/刷新再试）
            statsLoading = false
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
            AppDataStore.shared.invalidateAccounts()
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
            await load(force: true)
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
            await load(force: true)
        } catch {
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }
}

struct AccountsView: View {
    @StateObject private var vm = AccountsViewModel()
    @EnvironmentObject private var router: TabRouter
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
    /// 净资产卡纯色背景选择条（内联展开，不依赖 sheet）
    @State private var showInlinePreset = false
    /// 年度分析页 push 开关
    @State private var showAnalysis = false

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
        // 包 NavigationView：年度分析页走系统 push（返回即回账户页）。
        // 根页隐藏系统导航栏（自绘顶栏），推入的二级页自动显示
        NavigationView {
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
                                .padding(.bottom, showInlinePreset ? 0 : 12)

                            // 纯色选择条：内联展开（不走 sheet——iOS 15 下从保活显隐页面
                            // 弹 sheet 时有不响应的毛病），点色即换并自动收起
                            if showInlinePreset {
                                HStack(spacing: 12) {
                                    // 首位「跟随主题」：实时取当前主题渐变
                                    presetSwatch(PresetBackground(id: "theme", name: "跟随主题",
                                                                  imageName: "",
                                                                  colors: [Theme.brand, Theme.deep]))
                                    ForEach(HomeBackground.solidPresets) { preset in
                                        presetSwatch(preset)
                                    }
                                    Spacer()
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(HomePalette.card)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .shadow(color: Color.black.opacity(HomePalette.isDark ? 0.5 : 0.06), radius: 8, x: 0, y: 3)
                                .padding(.bottom, 12)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                            }

                            // 收支统计卡：默认今年，可切全部（口径同统计页）
                            statsCard
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
                        // iOS 15 ScrollView 无 .refreshable，挂真 UIRefreshControl（见 ScrollRefreshAttacher 注释）
                        .overlay(ScrollRefreshAttacher { await vm.load(force: true) }.allowsHitTesting(false))
                    }
                    .refreshable { await vm.load(force: true) }
                    // 底部避让由 MainTabView 整页容器统一施加，此处不再重复叠加
                }
                }
            }
            .navigationBarHidden(true)
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            // 年度分析页（原生 push，返回即回账户页）
            .background(
                NavigationLink(destination: YearlyAnalysisView(year: currentYear), isActive: $showAnalysis) { EmptyView() }
            )
        }
        .navigationViewStyle(.stack)
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
        // 冷启动不加载（4 Tab 全保活，屏外 .task 也会执行）：首次真正切到本 Tab 才拉数据
        .task { if router.selection == .accounts { await vm.load() } }
        .onChange(of: router.selection) { sel in
            if sel == .accounts && !vm.hasLoadedOnce { Task { await vm.load() } }
        }
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

    // MARK: - 净资产卡（背景 = 第一版纯色渐变 6 选 1，卡片右上角调色板按钮更换）
    private var netAssetsCard: some View {
        let preset = HomeBackground.netAssetsPreset
        let primaryText: Color = .white
        let labelColor: Color = Color.white.opacity(0.9)
        let assetColor: Color = .white
        let liabilityColor: Color = .white

        return VStack(alignment: .leading, spacing: 0) {
            // 标题字阶/间距与主页汇总卡的月份标题一致（16 semibold + 底 6）
            Text("净资产")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(primaryText)
                .modifier(HomeShadow(active: true))
                .padding(.bottom, 6)

            // 大金额 + 眼睛开关
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(masked(AmountFormat.format(vm.netAssetsCents)))
                    .font(.system(size: 30, weight: .semibold))
                    .monospacedDigit()
                    .foregroundColor(primaryText)
                    .minimumScaleFactor(0.55)
                    .lineLimit(1)
                    .modifier(HomeShadow(active: true))
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
            .padding(.bottom, 10)

            // 总资产 / 总负债双列（对齐主页汇总卡的 metricCell 结构：
            // 标签上、金额下，列间 1pt 竖分隔线），两页卡片高度/节奏完全一致
            HStack(alignment: .top, spacing: 0) {
                metricCell(label: "总资产",
                           value: masked(AmountFormat.format(vm.totalAssetsCents)),
                           valueColor: assetColor,
                           labelColor: labelColor,
                           shadow: true)
                Rectangle()
                    .fill(Color.white.opacity(0.28))
                    .frame(width: 1)
                    .padding(.trailing, 16)
                metricCell(label: "总负债",
                           value: masked(AmountFormat.format(vm.totalLiabilitiesCents)),
                           valueColor: liabilityColor,
                           labelColor: labelColor,
                           shadow: true)
                Spacer(minLength: 0)
            }
            .padding(.top, 12)
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack {
                PresetBackgroundView(preset: preset)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: Color.black.opacity(HomePalette.isDark ? 0.5 : 0.08), radius: 10, x: 0, y: 4)
        .overlay(alignment: .topTrailing) {
            // 纯色背景选择入口（对齐主页汇总卡换背景按钮的位置与规格）：
            // 切换卡片下方内联选择条
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showInlinePreset.toggle() }
            } label: {
                Image(systemName: showInlinePreset ? "paintpalette.fill" : "paintpalette")
                    .font(.system(size: 15))
                    .foregroundColor(Color.white.opacity(0.85))
                    .frame(width: 30, height: 30)
                    .background(Color.black.opacity(0.25))
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .padding(12)
        }
    }

    /// 选择条里的单个色块（选中打勾；「跟随主题」未选中时显示魔法棒标识）
    private func presetSwatch(_ preset: PresetBackground) -> some View {
        let selected = HomeBackground.netAssetsPresetID == preset.id
        return Button {
            HomeBackground.netAssetsPresetID = preset.id
        } label: {
            ZStack {
                PresetBackgroundView(preset: preset)
                    .frame(width: 44, height: 44)
                    .clipShape(Circle())
                if selected {
                    Circle()
                        .stroke(Color.white, lineWidth: 2)
                        .frame(width: 44, height: 44)
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                } else if preset.id == "theme" {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                }
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }

    /// 金额隐藏时显示 ＊＊＊＊（与主页汇总卡占位符同款全角星号）
    private func masked(_ text: String) -> String {
        vm.hideAmounts ? "＊＊＊＊" : text
    }

    /// 指标单元（标签上、金额下），与主页汇总卡 metricCell 同款
    private func metricCell(label: String, value: String,
                            valueColor: Color, labelColor: Color, shadow: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(labelColor)
                .modifier(HomeShadow(active: shadow))
            Text(verbatim: value)
                .font(.system(size: 15, weight: .semibold))
                .monospacedDigit()
                .foregroundColor(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .modifier(HomeShadow(active: shadow))
        }
        .padding(.trailing, 16)
    }

    // MARK: - 收支统计卡（默认今年，可切全部）
    private var statsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(vm.statsRange == .thisYear ? "今年收支" : "累计收支")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(HomePalette.ink)
                Spacer()
                Picker("范围", selection: $vm.statsRange) {
                    ForEach(AccountsViewModel.YearStatsRange.allCases) { r in
                        Text(r.title).tag(r)
                    }
                }
                .pickerStyle(.menu)
            }
            .padding(.bottom, 12)
            .onChange(of: vm.statsRange) { _ in
                Task { await vm.loadStats() }
            }

            HStack(alignment: .top, spacing: 0) {
                statsCell(label: "收入",
                          value: masked(AmountFormat.format(vm.statsIncomeCents)),
                          color: HomePalette.income)
                Rectangle()
                    .fill(HomePalette.divider)
                    .frame(width: 1)
                    .padding(.trailing, 16)
                statsCell(label: "支出",
                          value: masked(AmountFormat.format(vm.statsExpenseCents)),
                          color: HomePalette.expense)
                Spacer(minLength: 0)
                if vm.statsLoading {
                    ProgressView().padding(.top, 8)
                }
            }

            // 年度分析入口：逐月趋势 / 建议与提醒 / 预算分配
            Button { showAnalysis = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chart.bar.doc.horizontal")
                        .font(.system(size: 13, weight: .medium))
                    Text("年度分析 · 建议与分配")
                        .font(.system(size: 14, weight: .medium))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(Theme.brand)
                .padding(.top, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HomePalette.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: Color.black.opacity(HomePalette.isDark ? 0.5 : 0.06), radius: 10, x: 0, y: 4)
    }

    private func statsCell(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(HomePalette.secondary)
            Text(verbatim: value)
                .font(.system(size: 15, weight: .semibold))
                .monospacedDigit()
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .padding(.trailing, 16)
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
                .font(.footnote).foregroundColor(.secondary)
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

// MARK: - 年度分析（收支统计卡入口 push 进入）

/// 年度分析页：当年逐月趋势、支出构成、规则化建议（储蓄率/集中度/峰值/环比/赤字）
/// 与下月预算分配建议。数据 = statistics.json + statistics/daily.json，本地聚合计算
struct YearlyAnalysisView: View {
    let year: Int
    @StateObject private var vm = YearlyAnalysisViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if vm.isLoading {
                    VStack(spacing: 10) {
                        ProgressView()
                        Text("正在生成本年度分析…").font(.footnote).foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                    .background(HomePalette.card)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                } else if let error = vm.error {
                    VStack(spacing: 10) {
                        Text(error).font(.footnote).foregroundColor(.red)
                            .multilineTextAlignment(.center)
                        Button("重试") { Task { await vm.load(year: year) } }
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 22).padding(.vertical, 8)
                            .background(Theme.brand)
                            .clipShape(Capsule())
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 30)
                    .background(HomePalette.card)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                } else if !vm.hasData {
                    VStack(spacing: 8) {
                        Image(systemName: "chart.bar").font(.system(size: 30)).foregroundColor(.secondary)
                        Text("\(String(year)) 年还没有收支数据").font(.subheadline).foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                    .background(HomePalette.card)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                } else {
                    overviewCard
                    monthTrendCard
                    composeCard
                    suggestionCard
                    allocationCard
                }
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("年度分析")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarHidden(false)
        .chineseBackButton()
        .task { await vm.load(year: year) }
    }

    // 总览：年收入 / 年支出 / 储蓄率
    private var overviewCard: some View {
        HStack(alignment: .top, spacing: 0) {
            metricCell("总收入", AmountFormat.format(vm.totalIncome), HomePalette.income)
            Rectangle().fill(HomePalette.divider).frame(width: 1).padding(.trailing, 14)
            metricCell("总支出", AmountFormat.format(vm.totalExpense), HomePalette.expense)
            Rectangle().fill(HomePalette.divider).frame(width: 1).padding(.trailing, 14)
            metricCell("储蓄率", vm.savingRateText, vm.savingRateColor)
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(HomePalette.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: Color.black.opacity(HomePalette.isDark ? 0.5 : 0.06), radius: 8, x: 0, y: 3)
    }

    private func metricCell(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 12)).foregroundColor(HomePalette.secondary)
            Text(verbatim: value)
                .font(.system(size: 15, weight: .semibold))
                .monospacedDigit()
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .padding(.trailing, 14)
    }

    // 逐月支出柱状趋势
    private var monthTrendCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("月度支出趋势").font(.headline)
            HStack(alignment: .bottom, spacing: 5) {
                ForEach(vm.monthly) { p in
                    VStack(spacing: 4) {
                        Capsule()
                            .fill(p.expense > 0 ? HomePalette.expense.opacity(0.8) : Color.primary.opacity(0.08))
                            .frame(height: barHeight(p.expense))
                        Text("\(p.month)")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 104, alignment: .bottom)
            HStack {
                Text("月均 \(AmountFormat.format(vm.avgMonthlyExpense))")
                Spacer()
                if let peak = vm.peakMonth {
                    Text("\(peak.month)月最高 \(AmountFormat.format(peak.expense))")
                }
            }
            .font(.footnote)
            .foregroundColor(.secondary)
        }
        .padding(16)
        .background(HomePalette.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: Color.black.opacity(HomePalette.isDark ? 0.5 : 0.06), radius: 8, x: 0, y: 3)
    }

    private func barHeight(_ value: Int64) -> CGFloat {
        let maxV = vm.monthly.map { $0.expense }.max() ?? 0
        guard maxV > 0 else { return 2 }
        return max(2, CGFloat(Double(value) / Double(maxV)) * 84)
    }

    // 支出构成（前 6 分类 + 其他）
    private var composeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("支出构成").font(.headline)
            ForEach(vm.topCategories) { c in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color(hex: c.colorHex ?? "26A69A"))
                            .frame(width: 8, height: 8)
                        Text(c.name).font(.subheadline).lineLimit(1)
                        Spacer()
                        Text(verbatim: AmountFormat.format(c.amount))
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundColor(HomePalette.secondary)
                        Text(verbatim: String(format: "%.0f%%", c.ratio * 100))
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(HomePalette.secondary)
                            .frame(width: 34, alignment: .trailing)
                    }
                    GeometryReader { geo in
                        Capsule()
                            .fill(Color.primary.opacity(0.06))
                            .overlay(alignment: .leading) {
                                Capsule()
                                    .fill(Color(hex: c.colorHex ?? "26A69A"))
                                    .frame(width: max(4, geo.size.width * CGFloat(c.ratio)))
                            }
                    }
                    .frame(height: 5)
                }
            }
        }
        .padding(16)
        .background(HomePalette.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: Color.black.opacity(HomePalette.isDark ? 0.5 : 0.06), radius: 8, x: 0, y: 3)
    }

    // 分析与建议（规则生成）
    private var suggestionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("分析与建议").font(.headline)
            ForEach(vm.suggestions) { s in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: s.icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(toneColor(s.tone))
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.title).font(.system(size: 14, weight: .semibold))
                        Text(s.detail)
                            .font(.footnote)
                            .foregroundColor(HomePalette.secondary)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HomePalette.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: Color.black.opacity(HomePalette.isDark ? 0.5 : 0.06), radius: 8, x: 0, y: 3)
    }

    private func toneColor(_ tone: YearlyAnalysisViewModel.SuggestionTone) -> Color {
        switch tone {
        case .good: return HomePalette.income
        case .warn: return HomePalette.expense
        case .info: return Theme.brand
        }
    }

    // 下月预算分配建议（按今年月均支出结构推算）
    private var allocationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("下月预算分配建议")
                .font(.headline)
            Text("按 \(String(vm.year)) 年月均支出结构推算，供参考")
                .font(.caption2)
                .foregroundColor(HomePalette.secondary)
            ForEach(vm.allocations) { a in
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color(hex: a.colorHex ?? "26A69A"))
                        .frame(width: 8, height: 8)
                    Text(a.name).font(.subheadline).lineLimit(1)
                    Spacer()
                    Text(verbatim: "≈ " + AmountFormat.format(a.amount))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HomePalette.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: Color.black.opacity(HomePalette.isDark ? 0.5 : 0.06), radius: 8, x: 0, y: 3)
    }
}

/// 年度分析视图模型
@MainActor
final class YearlyAnalysisViewModel: ObservableObject {
    struct MonthPoint: Identifiable {
        let id: Int          // 0-based 月序
        let month: Int       // 1...12
        let expense: Int64
        let income: Int64
    }

    struct CatStat: Identifiable {
        let id: String
        let name: String
        let colorHex: String?
        let amount: Int64
        let ratio: Double
    }

    struct AllocItem: Identifiable {
        let id: String
        let name: String
        let colorHex: String?
        let amount: Int64
    }

    enum SuggestionTone { case good, warn, info }

    struct Suggestion: Identifiable {
        let id: Int
        let icon: String
        let title: String
        let detail: String
        let tone: SuggestionTone
    }

    @Published var isLoading = true
    @Published var hasData = false
    @Published var error: String?
    @Published var year = Calendar.current.component(.year, from: Date())
    @Published private(set) var monthly: [MonthPoint] = []
    @Published private(set) var topCategories: [CatStat] = []
    @Published private(set) var allocations: [AllocItem] = []
    @Published private(set) var suggestions: [Suggestion] = []
    @Published private(set) var totalExpense: Int64 = 0
    @Published private(set) var totalIncome: Int64 = 0

    var savingRateText: String {
        guard totalIncome > 0 else { return "—" }
        let rate = Double(totalIncome - totalExpense) / Double(totalIncome)
        return String(format: "%.0f%%", rate * 100)
    }

    var savingRateColor: Color {
        guard totalIncome > 0 else { return HomePalette.secondary }
        let rate = Double(totalIncome - totalExpense) / Double(totalIncome)
        if rate >= 0.3 { return HomePalette.income }
        if rate >= 0.1 { return HomePalette.secondary }
        return HomePalette.expense
    }

    var avgMonthlyExpense: Int64 {
        let months = max(1, monthly.filter { $0.expense > 0 || $0.income > 0 }.count)
        return totalExpense / Int64(months)
    }

    var peakMonth: MonthPoint? {
        monthly.max { $0.expense < $1.expense }?.expense == 0 ? nil : monthly.max { $0.expense < $1.expense }
    }

    func load(year: Int) async {
        isLoading = true
        error = nil
        self.year = year
        let cal = Calendar.current
        guard let start = cal.date(from: DateComponents(year: year, month: 1, day: 1)),
              let end = cal.date(from: DateComponents(year: year + 1, month: 1, day: 1)) else {
            isLoading = false
            return
        }
        let query = [
            URLQueryItem(name: "start_time", value: "\(Int(start.timeIntervalSince1970))"),
            URLQueryItem(name: "end_time", value: "\(Int(end.timeIntervalSince1970) - 1)"),
            URLQueryItem(name: "use_transaction_timezone", value: "true")
        ]
        do {
            let categories = (try? await AppDataStore.shared.getCategories()) ?? []
            var typeById: [String: Int] = [:]
            var infoById: [String: (name: String, color: String?)] = [:]
            for c in categories {
                typeById[c.id] = c.type
                infoById[c.id] = (c.name, c.color)
                for sub in c.subCategories ?? [] {
                    typeById[sub.id] = sub.type
                    infoById[sub.id] = (sub.name, sub.color)
                }
            }

            async let statResp: StatisticResponse = APIClient.shared.request(
                "/api/v1/transactions/statistics.json", query: query)
            async let dailyResp: [StatisticDailyItem] = APIClient.shared.request(
                "/api/v1/transactions/statistics/daily.json", query: query)
            let stats = try await statResp
            let dailies = (try? await dailyResp) ?? []

            // 逐月聚合（日粒度 → 12 个月桶）
            var exp = [Int64](repeating: 0, count: 12)
            var inc = [Int64](repeating: 0, count: 12)
            for d in dailies where d.year == year && d.month >= 1 && d.month <= 12 {
                for item in d.items {
                    let amount = abs(item.amount)
                    switch typeById[item.categoryId ?? "0"] {
                    case .some(1): inc[d.month - 1] += amount
                    case .some(2): exp[d.month - 1] += amount
                    default: break
                    }
                }
            }
            monthly = (0..<12).map { MonthPoint(id: $0, month: $0 + 1, expense: exp[$0], income: inc[$0]) }
            totalIncome = inc.reduce(0, +)

            // 分类聚合（支出）
            var catMap: [String: Int64] = [:]
            for item in stats.items {
                let key = item.categoryId ?? "0"
                guard typeById[key] == 2 else { continue }
                catMap[key, default: 0] += abs(item.amount)
            }
            totalExpense = catMap.values.reduce(0, +)

            let sorted = catMap.sorted { $0.value > $1.value }
            let top = sorted.prefix(6)
            topCategories = top.map { key, amount in
                CatStat(id: key,
                        name: infoById[key]?.name ?? "未分类",
                        colorHex: infoById[key]?.color,
                        amount: amount,
                        ratio: totalExpense > 0 ? Double(amount) / Double(totalExpense) : 0)
            }

            // 下月预算分配：按今年月均支出结构推算（当前年按已过月数均摊，历史年按 12）
            let elapsed: Int
            if year == cal.component(.year, from: Date()) {
                elapsed = max(1, cal.component(.month, from: Date()))
            } else {
                elapsed = 12
            }
            let rest = sorted.dropFirst(6)
            let restAmount = rest.reduce(Int64(0)) { $0 + $1.value }
            var allocs = top.map { key, amount in
                AllocItem(id: key,
                          name: infoById[key]?.name ?? "未分类",
                          colorHex: infoById[key]?.color,
                          amount: amount / Int64(elapsed))
            }
            if restAmount > 0 {
                allocs.append(AllocItem(id: "other", name: "其他", colorHex: nil,
                                        amount: restAmount / Int64(elapsed)))
            }
            allocations = allocs

            suggestions = Self.buildSuggestions(year: year, income: totalIncome,
                                                expense: totalExpense,
                                                monthly: monthly, top: topCategories)
            hasData = totalExpense > 0 || totalIncome > 0
            isLoading = false
        } catch {
            isLoading = false
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// 规则化建议：储蓄率 / 支出集中度 / 峰值月 / 半年环比 / 赤字
    private static func buildSuggestions(
        year: Int, income: Int64, expense: Int64,
        monthly: [MonthPoint], top: [CatStat]
    ) -> [Suggestion] {
        var out: [Suggestion] = []
        var seq = 0
        func add(_ icon: String, _ title: String, _ detail: String, _ tone: SuggestionTone) {
            out.append(Suggestion(id: seq, icon: icon, title: title, detail: detail, tone: tone))
            seq += 1
        }
        let money: (Int64) -> String = { AmountFormat.format($0) }

        // 1 储蓄率
        if income > 0 {
            let rate = Double(income - expense) / Double(income)
            if rate >= 0.3 {
                add("checkmark.seal.fill",
                    "储蓄率 \(Int(rate * 100))%，非常健康",
                    "收入覆盖支出后结余充足，可以考虑把结余做定期或稳健理财规划。", .good)
            } else if rate >= 0.1 {
                add("hand.thumbsup.fill",
                    "储蓄率 \(Int(rate * 100))%，状态尚可",
                    "结余占比一般，压缩 1-2 个弹性分类（如餐饮外食）还能再进一步。", .info)
            } else {
                add("exclamationmark.triangle.fill",
                    "储蓄率仅 \(Int(max(0, rate) * 100))%，需要留意",
                    "支出接近甚至超过收入，建议先从占比最高的分类开始压缩。", .warn)
            }
        }

        // 2 支出集中度
        if let first = top.first, expense > 0 {
            let pct = Int(first.ratio * 100)
            if first.ratio > 0.4 {
                add("pie.chart.fill",
                    "「\(first.name)」占支出 \(pct)%，较为集中",
                    "单一分类占比超过四成，可拆分记账粒度观察细节，避免该类失真放大。", .warn)
            } else {
                add("pie.chart.fill",
                    "最大支出分类是「\(first.name)」（\(pct)%）",
                    "分布相对均衡，继续保持按月回顾即可。", .info)
            }
        }

        // 3 峰值月
        let active = monthly.filter { $0.expense > 0 }
        if let peak = active.max(by: { $0.expense < $1.expense }), let avg = active.map({ $0.expense }).avg,
           avg > 0, peak.expense > avg * 6 / 5 {
            let pct = Int((Double(peak.expense) / Double(avg) - 1) * 100)
            add("flame.fill",
                "\(peak.month) 月支出明显高于平均",
                "峰值 \(money(peak.expense)) 比月均高 \(pct)%，回想是否有大额一次性消费或集中采购。", .info)
        }

        // 4 下半年 vs 上半年环比
        let h1 = monthly.prefix(6).reduce(Int64(0)) { $0 + $1.expense }
        let h2 = monthly.suffix(6).reduce(Int64(0)) { $0 + $1.expense }
        if h1 > 0, h2 > 0 {
            let delta = Double(h2 - h1) / Double(h1)
            if delta >= 0.15 {
                add("arrow.up.right",
                    "下半年支出比上半年高 \(Int(delta * 100))%",
                    "涨势明显，检查新增了哪些分类或固定支出，评估是否可持续。", .warn)
            } else if delta <= -0.15 {
                add("arrow.down.right",
                    "下半年支出比上半年低 \(Int(-delta * 100))%",
                    "收缩明显，注意是主动节约还是减少了必要开支。", .good)
            }
        }

        // 5 赤字
        if income > 0, expense > income {
            add("banknote.badge.minus",
                "今年支出大于收入",
                "赤字 \(money(expense - income))，建议设置每月预算上限并从最大分类开始控制。", .warn)
        }
        return out
    }
}

private extension Array where Element == Int64 {
    var avg: Int64? {
        guard !isEmpty else { return nil }
        return reduce(0, +) / Int64(count)
    }
}
