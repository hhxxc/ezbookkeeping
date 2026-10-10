import SwiftUI
import Combine
import UIKit
import PhotosUI
import CoreLocation

/// 编辑模式
enum TransactionEditMode {
    case add            // 新增
    case edit           // 编辑已有（走 modify.json）
    case duplicate      // 复制新增（保留内容、不带 id，走 add.json）
}

/// 新增 / 编辑 / 复制交易。
/// 支持 支出 / 收入 / 转账 / 余额调整 四种类型（对齐手机端 Web）。
@MainActor
final class TransactionEditViewModel: ObservableObject {
    let mode: TransactionEditMode
    let originalId: String?
    /// 待回填的原始交易（复制模式不带 id 保存）
    private let pending: Transaction?

    @Published var type: TransactionType = .expense
    @Published var amountText = ""
    @Published var sourceAccountId = ""
    @Published var destinationAccountId = ""
    @Published var categoryId = ""
    @Published var date = Date()
    @Published var comment = ""
    /// 交易时区（影响后端 utcOffset；默认当前设备时区）
    @Published var timeZoneIdentifier = TimeZone.current.identifier
    /// 地理位置（经度/纬度）
    @Published var geoLocation: TransactionGeoLocation?
    /// 分期：是否按分期保存（仅支出新增模式可用）
    @Published var installmentEnabled = false
    /// 分期：总期数（2~60）
    @Published var installmentPeriods = 12
    /// 分期：名称（如「iPhone 15 分期」）
    @Published var installmentName = ""
    @Published var accounts: [Account] = []
    @Published var categories: [TransactionCategory] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var didSave = false

    // 标签 / 图片
    @Published var tags: [TransactionTag] = []
    @Published var tagGroups: [TransactionTagGroup] = []
    @Published var selectedTagIds: Set<String> = []
    /// 已上传的图片（pictureId + 本地预览图，用于编辑页缩略图）
    @Published var pictures: [UploadedPictureItem] = []
    @Published var isUploadingPicture = false

    /// 单张已上传图片
    struct UploadedPictureItem: Identifiable, Equatable {
        let id: String          // pictureId
        let image: UIImage?
        static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    }

    /// 编辑模式进入时的幂等会话 id（新增/复制每次保存唯一）
    private var clientSessionId = UUID().uuidString

    init(transaction: Transaction?, mode: TransactionEditMode = .add, defaultInstallment: Bool = false) {
        self.originalId = transaction?.id
        self.mode = mode
        self.pending = transaction
        self.installmentEnabled = defaultInstallment
    }

    var navigationTitle: String {
        switch mode {
        case .add: return "记一笔"
        case .edit: return "编辑"
        case .duplicate: return "复制"
        }
    }

    /// 余额调整的账户只能改余额，不需要分类
    var needsCategory: Bool { type != .modifyBalance && type != .transfer }

    func load() async {
        isLoading = true
        error = nil
        do {
            // 引用数据走共享缓存：高频入口不再每次 4 连拉（缓存 120s 内直接复用）
            async let accs = AppDataStore.shared.getAccounts()
            async let cats = AppDataStore.shared.getCategories()
            async let tg = AppDataStore.shared.getTags()
            accounts = try await accs
            categories = try await cats
            let fetched = (try? await tg) ?? (tags: [], groups: [])
            tags = fetched.tags
            tagGroups = fetched.groups

            if let tx = pending {
                type = tx.transactionType
                amountText = AmountFormat.centsToText(tx.sourceAmount)
                sourceAccountId = tx.sourceAccountId ?? ""
                categoryId = tx.categoryId ?? ""
                date = tx.date
                comment = tx.comment ?? ""
                selectedTagIds = Set(tx.tagIds ?? [])
                geoLocation = tx.geoLocation
                // 由 utcOffset 反推时区（找不到精确匹配就回退设备时区）
                if let offset = tx.utcOffset {
                    timeZoneIdentifier = TimeZone.knownTimeZoneIdentifiers.first {
                        TimeZone(identifier: $0)?.secondsFromGMT(for: tx.date) == offset * 60
                    } ?? TimeZone.current.identifier
                }
                if tx.transactionType == .transfer {
                    destinationAccountId = tx.destinationAccountId ?? ""
                    if let d = tx.destinationAmount { amountText = AmountFormat.centsToText(d) }
                }
            } else {
                sourceAccountId = accounts.first?.id ?? ""
                categoryId = defaultCategoryId()
            }
            isLoading = false
        } catch {
            isLoading = false
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// 上传一张图片并加入列表（编辑页选图后调用）
    func uploadPicture(_ data: Data) async {
        isUploadingPicture = true
        defer { isUploadingPicture = false }
        do {
            let uploaded = try await PictureUploader.upload(imageData: data)
            let img = UIImage(data: data)
            pictures.append(UploadedPictureItem(id: uploaded.pictureId, image: img))
        } catch {
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    func removePicture(_ id: String) {
        pictures.removeAll { $0.id == id }
    }

    private func defaultCategoryId() -> String {
        let wantType = type == .income
            ? TransactionCategoryType.income.rawValue
            : TransactionCategoryType.expense.rawValue
        // 对齐 Web 端口径：默认选中第一个可见的**叶子**分类（大类有子分类时选其第一个子分类）
        guard let first = categories.first(where: { $0.type == wantType && $0.hidden != true }) else { return "" }
        let subs = (first.subCategories ?? []).filter { $0.hidden != true }
        return subs.first?.id ?? first.id
    }

    /// 切换类型时同步修正默认分类：分类类型与新交易类型不匹配则重置
    func typeChanged() {
        guard needsCategory else { return }
        let wantType = type == .income
            ? TransactionCategoryType.income.rawValue
            : TransactionCategoryType.expense.rawValue
        if let current = categories.first(where: { $0.id == categoryId }), current.type == wantType { return }
        categoryId = defaultCategoryId()
    }

    /// 保存；`keepOpen` = 「再记」：成功后不关页，重置内容继续记下一笔
    func save(keepOpen: Bool = false) async {
        // 金额支持简单表达式（如 12+34.5-3），顺序求值（记账计算器口径）
        guard let amount = Self.evaluateExpression(amountText.trimmingCharacters(in: .whitespaces)), amount > 0 else {
            error = "请输入有效金额"
            return
        }
        guard !sourceAccountId.isEmpty else {
            error = "请选择账户"
            return
        }
        if type == .transfer && destinationAccountId.isEmpty {
            error = "请选择目标账户"
            return
        }
        if needsCategory && categoryId.isEmpty {
            error = "请选择分类"
            return
        }
        // 分期保存的前置校验（金额为全部期次总额）
        let isInstallmentSave = mode == .add && installmentEnabled && type == .expense
        let trimmedInstallmentName = installmentName.trimmingCharacters(in: .whitespacesAndNewlines)
        if isInstallmentSave {
            if trimmedInstallmentName.isEmpty {
                error = "请填写分期名称"
                return
            }
            if installmentPeriods < 2 {
                error = "分期至少 2 期"
                return
            }
        }

        let cents = Self.toCents(amount)
        // 服务端上限：sourceAmount 必须小于 9999999999 分，超限时本地直接提示，避免等服务端报英文错误
        if cents >= 9_999_999_999 {
            error = "金额超出上限（单笔不能超过 99,999,999.98）"
            return
        }
        let utcOffset = (TimeZone(identifier: timeZoneIdentifier) ?? .current).secondsFromGMT(for: date) / 60
        isLoading = true
        error = nil

        do {
            let tagIdList = Array(selectedTagIds)
            let pictureIdList = pictures.map { $0.id }
            if isInstallmentSave {
                // 分期：一次性生成全部期次，后端均摊金额（余数放最后一期），日期按月推进
                let req = InstallmentCreateRequest(
                    name: trimmedInstallmentName,
                    type: TransactionType.expense.rawValue,
                    categoryId: categoryId,
                    time: Int64(date.timeIntervalSince1970),
                    utcOffset: utcOffset,
                    sourceAccountId: sourceAccountId,
                    sourceAmount: cents,
                    totalPeriods: installmentPeriods,
                    hideAmount: false,
                    tagIds: tagIdList,
                    comment: comment
                )
                let _: InstallmentPlan = try await APIClient.shared.request(
                    "/api/v1/transactions/installments/add.json", method: .POST, body: req
                )
            } else if mode == .edit, let id = originalId {
                // 编辑已有交易：走 modify.json
                let req = TransactionModifyRequest(
                    id: id,
                    categoryId: needsCategory ? categoryId : "0",
                    time: Int64(date.timeIntervalSince1970),
                    utcOffset: utcOffset,
                    sourceAccountId: sourceAccountId,
                    destinationAccountId: type == .transfer ? destinationAccountId : "0",
                    sourceAmount: cents,
                    destinationAmount: type == .transfer ? cents : 0,
                    hideAmount: false,
                    tagIds: tagIdList,
                    pictureIds: pictureIdList,
                    comment: comment,
                    geoLocation: geoLocation
                )
                let _: EmptyResult = try await APIClient.shared.request(
                    "/api/v1/transactions/modify.json", method: .POST, body: req
                )
            } else {
                // 新增 / 复制：走 add.json
                let req = TransactionCreateRequest(
                    type: type.rawValue,
                    categoryId: needsCategory ? categoryId : "0",
                    time: Int64(date.timeIntervalSince1970),
                    utcOffset: utcOffset,
                    sourceAccountId: sourceAccountId,
                    destinationAccountId: type == .transfer ? destinationAccountId : nil,
                    sourceAmount: cents,
                    destinationAmount: type == .transfer ? cents : nil,
                    comment: comment.isEmpty ? nil : comment,
                    tagIds: tagIdList,
                    pictureIds: pictureIdList,
                    geoLocation: geoLocation,
                    clientSessionId: clientSessionId
                )
                let _: EmptyResult = try await APIClient.shared.request(
                    "/api/v1/transactions/add.json", method: .POST, body: req
                )
            }
            isLoading = false
            // 交易落库改变账户余额 → 失效账户缓存（AppDataStore 也监听 transactionsChanged，此处直接调用更可靠）
            AppDataStore.shared.invalidateAccounts()
            if keepOpen {
                resetForNextEntry()
            } else {
                didSave = true
            }
        } catch {
            isLoading = false
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// 「再记」成功后重置内容：金额/备注/图片/标签/位置/分期清空，类型/账户/分类/日期保留
    func resetForNextEntry() {
        amountText = ""
        comment = ""
        pictures = []
        selectedTagIds = []
        geoLocation = nil
        date = Date()
        error = nil
        installmentEnabled = false
        installmentName = ""
        clientSessionId = UUID().uuidString
    }

    /// 计算器表达式求值：数字 + 加号/减号，顺序求值（无优先级，与记账 App 一致）。
    /// 纯数字（如 "12.5"）也走这条路径；任一段非法返回 nil。
    static func evaluateExpression(_ raw: String) -> Decimal? {
        guard !raw.isEmpty else { return nil }
        let locale = Locale(identifier: "zh_CN")
        var total = Decimal.zero
        var current = ""
        var pendingOp: Character = "+"
        for ch in raw {
            if ch == "+" || ch == "-" {
                guard let v = Decimal(string: current, locale: locale) else { return nil }
                total = pendingOp == "+" ? total + v : total - v
                pendingOp = ch
                current = ""
            } else if ch.isNumber || ch == "." {
                current.append(ch)
            } else {
                return nil
            }
        }
        guard let last = Decimal(string: current, locale: locale) else { return nil }
        return pendingOp == "+" ? total + last : total - last
    }

    /// 元 -> 分。Xcode 26 / Swift 6 下 `Decimal * 100` 会被推断成 Float16，
    /// 必须走 NSDecimalNumber 显式乘法。
    static func toCents(_ amount: Decimal) -> Int64 {
        let handler = NSDecimalNumberHandler(
            roundingMode: .plain, scale: 0,
            raiseOnExactness: false, raiseOnOverflow: false,
            raiseOnUnderflow: false, raiseOnDivideByZero: false
        )
        return NSDecimalNumber(decimal: amount)
            .multiplying(by: NSDecimalNumber(value: 100))
            .rounding(accordingToBehavior: handler)
            .int64Value
    }
}

/// 键盘按键
private enum EditKey: Hashable {
    case digit(String)
    case dot
    case del
    case op(String)
    case again
    case save
}

/// 记账页（计算器风格）：
/// 顶栏 关闭 · 类型切换 · 更多 → 分类图标网格 → 快捷条（账户/日期/图片）→ 备注+金额 → 自绘数字键盘。
/// 金额支持 12+34.5-3 形式的顺序表达式；「再记」保存后不关页继续记下一笔。
struct TransactionEditView: View {
    @StateObject private var vm: TransactionEditViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var showAccountSheet = false
    @State private var showDestAccountSheet = false
    @State private var showDateSheet = false
    @State private var showPictureSheet = false
    @State private var showMoreSheet = false
    /// 当前展开「小类芯片行」的大类 id（nil=未展开）
    @State private var expandedPrimaryId: String?
    /// 备注 / 分期名称输入框聚焦状态：任一聚焦即弹系统键盘，
    /// 此时必须隐藏自绘数字键盘，否则两块键盘叠加占满整屏
    @FocusState private var noteFieldFocused: Bool
    @FocusState private var installmentFieldFocused: Bool
    /// 系统键盘是否正在显示（备注或分期名称聚焦中）
    private var systemKeyboardShown: Bool { noteFieldFocused || installmentFieldFocused }
    /// 「再记」成功后的轻提示
    @State private var flashText: String?
    /// 保存成功后的回调（识图页预填编辑场景：成功后从识别结果列表移除该条）
    var onSaved: (() -> Void)? = nil

    init(transaction: Transaction?, mode: TransactionEditMode = .add, onSaved: (() -> Void)? = nil, defaultInstallment: Bool = false) {
        _vm = StateObject(wrappedValue: TransactionEditViewModel(transaction: transaction, mode: mode, defaultInstallment: defaultInstallment))
        self.onSaved = onSaved
    }

    /// 键盘布局：4 列 × 4 行（对齐主流记账 App 的计算器键盘）
    private let keys: [EditKey] = [
        .digit("1"), .digit("2"), .digit("3"), .del,
        .digit("4"), .digit("5"), .digit("6"), .op("-"),
        .digit("7"), .digit("8"), .digit("9"), .op("+"),
        .again, .digit("0"), .dot, .save
    ]
    private let keyColumns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)
    private let categoryColumns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 5)

    var body: some View {
        VStack(spacing: 0) {
            topBar

            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    // 转账：转出/转入账户卡
                    if vm.type == .transfer {
                        transferCard
                    }
                    // 余额调整：单账户卡
                    if vm.type == .modifyBalance {
                        adjustCard
                    }
                    // 分类图标网格
                    if vm.needsCategory {
                        categoryGrid
                    }
                    chipsRow
                    if installmentAvailable && vm.installmentEnabled {
                        installmentCard
                    }
                    noteRow
                    if let error = vm.error {
                        Text(error)
                            .font(.footnote)
                            .foregroundColor(Theme.expense)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else if let flash = flashText {
                        Text(flash)
                            .font(.footnote)
                            .foregroundColor(Theme.income)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 14)
            }

            keypadHiddenByKeyboard
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        // 键盘显隐切换平滑过渡（自绘键盘收起/恢复）
        .animation(.easeInOut(duration: 0.18), value: systemKeyboardShown)
        .toolbar {
            // 备注输入的系统键盘加个「完成」
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("完成") { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
            }
        }
        .task { await vm.load() }
        .onChange(of: vm.didSave) { saved in
            if saved {
                dismiss()
                onSaved?()
            }
        }
        .sheet(isPresented: $showAccountSheet) {
            EditAccountPickerSheet(
                title: vm.type == .transfer ? "选择转出账户" : "选择账户",
                accounts: vm.accounts,
                selectedId: vm.sourceAccountId,
                excludeId: nil
            ) { vm.sourceAccountId = $0 }
        }
        .sheet(isPresented: $showDestAccountSheet) {
            EditAccountPickerSheet(
                title: "选择转入账户",
                accounts: vm.accounts,
                selectedId: vm.destinationAccountId,
                excludeId: vm.sourceAccountId
            ) { vm.destinationAccountId = $0 }
        }
        .sheet(isPresented: $showDateSheet) {
            NavigationView {
                DatePicker("日期", selection: $vm.date)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 20)
                    .navigationTitle("选择时间")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("完成") { showDateSheet = false }
                        }
                    }
            }
        }
        .sheet(isPresented: $showPictureSheet) {
            NavigationView {
                Form {
                    Section(header: Text("图片（保存时随交易上传）")) {
                        PicturePickerSection(vm: vm)
                    }
                }
                .navigationTitle("图片")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("完成") { showPictureSheet = false }
                    }
                }
            }
        }
        .sheet(isPresented: $showMoreSheet) {
            NavigationView {
                Form {
                    Section(header: Text("时区")) {
                        Picker("时区", selection: $vm.timeZoneIdentifier) {
                            ForEach(Self.commonTimeZones, id: \.self) { tz in
                                Text(Self.timeZoneDisplay(tz)).tag(tz)
                            }
                        }
                    }
                    Section(header: Text("地理位置")) {
                        GeoLocationRow(geoLocation: $vm.geoLocation)
                    }
                    if !vm.tags.isEmpty {
                        Section(header: Text("标签")) {
                            TagSelector(tags: vm.tags, groups: vm.tagGroups, selected: $vm.selectedTagIds)
                        }
                    }
                }
                .navigationTitle("更多")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("完成") { showMoreSheet = false }
                    }
                }
            }
        }
    }

    // MARK: - 顶栏

    private var topBar: some View {
        HStack(spacing: 12) {
            // 关闭
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(HomePalette.ink)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color.primary.opacity(0.06)))
            }
            .buttonStyle(.plain)

            Spacer(minLength: 8)

            // 类型切换
            Picker("", selection: $vm.type) {
                Text("支出").tag(TransactionType.expense)
                Text("收入").tag(TransactionType.income)
                Text("转账").tag(TransactionType.transfer)
                Text("余额调整").tag(TransactionType.modifyBalance)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 260)
            .onChange(of: vm.type) { _ in vm.typeChanged() }

            Spacer(minLength: 8)

            // 更多（时区/位置/标签）
            Button {
                showMoreSheet = true
            } label: {
                Image(systemName: "plus.circle")
                    .font(.system(size: 20))
                    .foregroundColor(HomePalette.ink)
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
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

    // MARK: - 分类网格（先大类、点击展开小类，对齐移动端 Web 快捷布局交互）

    /// 当前交易类型的一级分类（过滤隐藏）
    private var primaryCategories: [TransactionCategory] {
        vm.categories.filter { cat in
            if cat.hidden == true { return false }
            if vm.type == .income { return cat.type == TransactionCategoryType.income.rawValue }
            if vm.type == .expense { return cat.type == TransactionCategoryType.expense.rawValue }
            return true
        }
    }

    /// 某大类下可见的子分类
    private func visibleSubCategories(of cat: TransactionCategory) -> [TransactionCategory] {
        (cat.subCategories ?? []).filter { $0.hidden != true }
    }

    /// 按 id 定位分类：返回其所属大类与自身（若自身即大类则 sub 为 nil）
    private func locateCategory(_ id: String) -> (parent: TransactionCategory, sub: TransactionCategory?)? {
        guard !id.isEmpty else { return nil }
        for cat in vm.categories {
            if cat.id == id { return (cat, nil) }
            if let subs = cat.subCategories, let sub = subs.first(where: { $0.id == id }) {
                return (cat, sub)
            }
        }
        return nil
    }

    /// 当前选中分类所属的大类 id（用于宫格高亮）
    private var currentPrimaryId: String? {
        locateCategory(vm.categoryId)?.parent.id
    }

    private var categoryGrid: some View {
        VStack(alignment: .leading, spacing: 0) {
            LazyVGrid(columns: categoryColumns, spacing: 14) {
                ForEach(primaryCategories, id: \.id) { cat in
                    let selected = currentPrimaryId == cat.id
                    let catColor = (cat.color?.isEmpty == false ? Color(hex: cat.color!) : Theme.brand)
                    let subs = visibleSubCategories(of: cat)
                    Button {
                        if subs.isEmpty {
                            expandedPrimaryId = nil
                            vm.categoryId = cat.id
                        } else {
                            expandedPrimaryId = cat.id
                            vm.categoryId = subs[0].id
                        }
                    } label: {
                        VStack(spacing: 5) {
                            Image(systemName: CategoryIconCatalog.symbol(cat.icon))
                                .font(.system(size: 17, weight: .medium))
                                .foregroundColor(selected ? .white : HomePalette.ink)
                                .frame(width: 44, height: 44)
                                .background(
                                    Circle().fill(selected ? catColor : Color.primary.opacity(0.06))
                                )
                                .overlay(alignment: .topTrailing) {
                                    // 有小类的大类：右上角小圆点提示可展开
                                    if !subs.isEmpty {
                                        Circle()
                                            .fill(selected ? Color.white.opacity(0.9) : catColor.opacity(0.55))
                                            .frame(width: 6, height: 6)
                                            .offset(x: 3, y: -1)
                                    }
                                }
                            Text(cat.name)
                                .font(.system(size: 13))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .foregroundColor(selected ? catColor : HomePalette.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            if let expandedId = expandedPrimaryId,
               let parent = primaryCategories.first(where: { $0.id == expandedId }),
               !visibleSubCategories(of: parent).isEmpty {
                subCategoryChipBar(parent)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: expandedPrimaryId)
        .padding(.vertical, 4)
        .onChange(of: vm.categoryId) { newId in
            // 编辑已有交易/切换类型回填分类后，自动展开其所属大类的芯片行
            if let (parent, sub) = locateCategory(newId), sub != nil {
                expandedPrimaryId = parent.id
            }
        }
    }

    /// 小类芯片行：按估算宽度贪心换行（iOS 15 无 FlowLayout，中文宽度可准确估算）
    private func subCategoryChipBar(_ parent: TransactionCategory) -> some View {
        let subs = visibleSubCategories(of: parent)
        let rows = wrapChipRows(subs, availableWidth: UIScreen.main.bounds.width - 32)
        let parentColor = (parent.color?.isEmpty == false ? Color(hex: parent.color!) : Theme.brand)
        return VStack(alignment: .leading, spacing: 8) {
            ForEach(rows.indices, id: \.self) { rowIdx in
                HStack(spacing: 8) {
                    ForEach(rows[rowIdx], id: \.id) { sub in
                        let selected = sub.id == vm.categoryId
                        Text(sub.name)
                            .font(.system(size: 13))
                            .foregroundColor(selected ? .white : HomePalette.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(selected ? parentColor : Color.primary.opacity(0.06))
                            )
                            .onTapGesture { vm.categoryId = sub.id }
                    }
                }
            }
        }
        .padding(.top, 12)
    }

    /// 把芯片按估算宽度贪心分行：中文/全角字符≈字号宽，其余≈0.55 倍字号
    private func wrapChipRows(_ subs: [TransactionCategory], availableWidth: CGFloat) -> [[TransactionCategory]] {
        var rows: [[TransactionCategory]] = []
        var current: [TransactionCategory] = []
        var currentWidth: CGFloat = 0
        for sub in subs {
            var textWidth: CGFloat = 0
            for ch in sub.name {
                let isWide = ch.unicodeScalars.first.map { $0.properties.isIdeographic || $0.value > 0x2E7F } ?? false
                textWidth += isWide ? 13 : 7.5
            }
            let chipWidth = textWidth + 24 + 8   // 水平 padding + 间距
            if currentWidth + chipWidth > availableWidth && !current.isEmpty {
                rows.append(current)
                current = []
                currentWidth = 0
            }
            current.append(sub)
            currentWidth += chipWidth
        }
        if !current.isEmpty { rows.append(current) }
        return rows
    }

    // MARK: - 转账 / 余额调整账户卡

    private var transferCard: some View {
        VStack(spacing: 0) {
            accountCardRow(title: "转出账户", accountId: vm.sourceAccountId) {
                showAccountSheet = true
            }
            Divider().padding(.leading, 14)
            accountCardRow(title: "转入账户", accountId: vm.destinationAccountId) {
                showDestAccountSheet = true
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var adjustCard: some View {
        VStack(spacing: 0) {
            accountCardRow(title: "调整账户", accountId: vm.sourceAccountId) {
                showAccountSheet = true
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func accountCardRow(title: String, accountId: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.system(size: 14))
                    .foregroundColor(HomePalette.secondary)
                Spacer()
                Text(vm.accounts.first { $0.id == accountId }?.name ?? "请选择")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(accountId.isEmpty ? HomePalette.secondary : HomePalette.ink)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(.tertiaryLabel))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 快捷条 + 备注行

    private var chipsRow: some View {
        HStack(spacing: 8) {
            if vm.type != .transfer && vm.type != .modifyBalance {
                chip(icon: "creditcard", label: accountChipLabel) {
                    showAccountSheet = true
                }
            }
            chip(icon: "calendar", label: dateChipLabel) {
                showDateSheet = true
            }
            chip(icon: "photo", label: vm.pictures.isEmpty ? "图片" : "图片 \(vm.pictures.count)") {
                showPictureSheet = true
            }
            if installmentAvailable {
                chip(icon: "repeat", label: vm.installmentEnabled ? "分期 \(vm.installmentPeriods) 期" : "分期") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        vm.installmentEnabled.toggle()
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - 分期

    /// 分期入口仅在「新增支出」时可用
    private var installmentAvailable: Bool {
        vm.mode == .add && vm.type == .expense
    }

    /// 分期设置卡：名称 + 期数 + 摊还预览
    private var installmentCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("分期名称（如：iPhone 分期）", text: $vm.installmentName)
                .font(.system(size: 14))
                .focused($installmentFieldFocused)

            HStack(spacing: 12) {
                Text("期数")
                    .font(.system(size: 14))
                    .foregroundColor(HomePalette.secondary)
                Spacer(minLength: 8)
                periodAdjustButton(icon: "minus", disabled: vm.installmentPeriods <= 2) {
                    vm.installmentPeriods = max(2, vm.installmentPeriods - 1)
                }
                Text("\(vm.installmentPeriods) 期")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .frame(minWidth: 44)
                periodAdjustButton(icon: "plus", disabled: vm.installmentPeriods >= 60) {
                    vm.installmentPeriods = min(60, vm.installmentPeriods + 1)
                }
            }

            installmentPreview
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func periodAdjustButton(icon: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(disabled ? Color(.tertiaryLabel) : HomePalette.ink)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.primary.opacity(0.06)))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    /// 摊还预览：每期金额 + 首期日期说明
    @ViewBuilder
    private var installmentPreview: some View {
        let trimmed = vm.amountText.trimmingCharacters(in: .whitespaces)

        if let total = TransactionEditViewModel.evaluateExpression(trimmed), total > 0 {
            let cents = TransactionEditViewModel.toCents(total)
            let periods = max(2, vm.installmentPeriods)
            let per = cents / Int64(periods)
            let last = cents - per * Int64(periods - 1)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text("共 \(periods) 期")
                        .foregroundColor(HomePalette.ink)
                    Text("· 每期 \(AmountFormat.format(per))")
                        .foregroundColor(HomePalette.secondary)
                    if last != per {
                        Text("· 末期 \(AmountFormat.format(last))")
                            .foregroundColor(HomePalette.secondary)
                    }
                }
                .font(.system(size: 13, design: .rounded))

                Text("首期 \(Self.chipDateFormatter.string(from: vm.date)) 起，每月一期按月预记")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        } else {
            Text("输入总金额后自动按期均摊")
                .font(.footnote)
                .foregroundColor(.secondary)
        }
    }

    private func chip(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 12))
                Text(label).font(.system(size: 13)).lineLimit(1)
            }
            .foregroundColor(HomePalette.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Capsule().fill(Color.primary.opacity(0.06)))
        }
        .buttonStyle(.plain)
    }

    private var noteRow: some View {
        HStack(spacing: 10) {
            TextField("点此输入备注...", text: $vm.comment)
                .font(.system(size: 14))
                .focused($noteFieldFocused)
            Spacer(minLength: 8)
            Text(displayAmount)
                .font(.system(size: 26, weight: .semibold))
                .monospacedDigit()
                .foregroundColor(amountColor)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var accountChipLabel: String {
        vm.accounts.first { $0.id == vm.sourceAccountId }?.name ?? "选择账户"
    }

    private var dateChipLabel: String {
        Calendar.current.isDateInToday(vm.date) ? "今天" : Self.chipDateFormatter.string(from: vm.date)
    }

    /// 金额展示：表达式未输完（末尾是运算符/小数点）时显示原文，否则显示求值结果
    private var displayAmount: String {
        if vm.amountText.isEmpty { return "0.00" }
        let trimmed = vm.amountText.trimmingCharacters(in: .whitespaces)
        if let last = trimmed.last, last == "+" || last == "-" || last == "." {
            return trimmed
        }
        if let value = TransactionEditViewModel.evaluateExpression(trimmed) {
            return Self.amountFormatter.string(from: NSDecimalNumber(decimal: value)) ?? trimmed
        }
        return trimmed
    }

    private var amountColor: Color {
        switch vm.type {
        case .expense: return Theme.expense
        case .income: return Theme.income
        default: return HomePalette.ink
        }
    }

    // MARK: - 键盘

    /// 备注等系统键盘弹出时隐藏自绘数字键盘（否则双键盘叠加占满整屏）；
    /// 失焦后自绘键盘滑回。保持占位高度过渡平滑用 conditional + transition 即可
    @ViewBuilder
    private var keypadHiddenByKeyboard: some View {
        if !systemKeyboardShown {
            keypad
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private var keypad: some View {
        LazyVGrid(columns: keyColumns, spacing: 8) {
            ForEach(keys, id: \.self) { key in
                keyButton(key)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(
            VStack(spacing: 0) {
                Rectangle()
                    .fill(Color.primary.opacity(0.06))
                    .frame(height: 0.5)
                Color(.systemGroupedBackground)
            }
            .ignoresSafeArea(edges: .bottom)
        )
    }

    private func keyButton(_ key: EditKey) -> some View {
        let isSave = key == .save
        let disabled = (isSave || key == .again) && vm.isLoading
        return Button {
            tapKey(key)
        } label: {
            keyLabel(key)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isSave ? Theme.brand : Color.primary.opacity(0.06))
                )
                .foregroundColor(isSave ? .white : HomePalette.ink)
                .opacity(disabled ? 0.5 : 1)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    @ViewBuilder
    private func keyLabel(_ key: EditKey) -> some View {
        switch key {
        case .digit(let d):
            Text(d).font(.system(size: 20, weight: .medium))
        case .dot:
            Text(".").font(.system(size: 24, weight: .medium))
        case .del:
            Image(systemName: "delete.left").font(.system(size: 18))
        case .op(let o):
            Text(o).font(.system(size: 22, weight: .medium))
        case .again:
            Text("再记").font(.system(size: 15, weight: .medium)).foregroundColor(Theme.brand)
        case .save:
            Text(vm.isLoading ? "保存中…" : (installmentAvailable && vm.installmentEnabled ? "保存分期" : "保存"))
                .font(.system(size: 16, weight: .semibold))
        }
    }

    private func tapKey(_ key: EditKey) {
        switch key {
        case .digit(let d):
            appendDigit(d)
        case .dot:
            appendDot()
        case .del:
            if !vm.amountText.isEmpty { vm.amountText.removeLast() }
        case .op(let o):
            appendOperator(o)
        case .again:
            Task {
                await vm.save(keepOpen: true)
                if vm.error == nil {
                    flashText = "已记一笔 ✓"
                    try? await Task.sleep(nanoseconds: 1_200_000_000)
                    flashText = nil
                }
            }
        case .save:
            Task { await vm.save() }
        }
    }

    /// 当前正在输入的数字段（最后一个运算符之后的部分）
    private var currentSegment: String {
        if let range = vm.amountText.rangeOfCharacter(from: CharacterSet(charactersIn: "+-"), options: .backwards) {
            return String(vm.amountText[range.upperBound...])
        }
        return vm.amountText
    }

    private func appendDigit(_ d: String) {
        guard vm.amountText.count < 24 else { return }
        let segment = currentSegment
        if segment == "0" {
            // 前导 0 直接替换（0 → 5，而不是 05）
            vm.amountText.removeLast()
        } else if segment == "-0" {
            vm.amountText.removeLast(2)
        }
        vm.amountText += d
    }

    private func appendDot() {
        let segment = currentSegment
        if segment.contains(".") { return }
        if segment.isEmpty {
            vm.amountText += "0."
        } else {
            vm.amountText += "."
        }
    }

    private func appendOperator(_ o: String) {
        guard let last = vm.amountText.last else { return }
        if last == "+" || last == "-" {
            // 连按运算符 → 替换
            vm.amountText.removeLast()
        } else if last == "." {
            vm.amountText.removeLast()
        }
        vm.amountText += o
    }

    // MARK: - 展示辅助

    private static let amountFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f
    }()

    private static let chipDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日"
        return f
    }()

    /// 常用时区列表（东八区排最前，其余按 offset 升序）
    private static let commonTimeZones: [String] = {
        var ids = TimeZone.knownTimeZoneIdentifiers.sorted {
            let a = TimeZone(identifier: $0)?.secondsFromGMT() ?? 0
            let b = TimeZone(identifier: $1)?.secondsFromGMT() ?? 0
            return a < b
        }
        // 把「上海」提到最前（国内用户默认）
        let asiaShanghai = "Asia/Shanghai"
        if let idx = ids.firstIndex(of: asiaShanghai) {
            ids.remove(at: idx)
            ids.insert(asiaShanghai, at: 0)
        }
        return ids
    }()

    /// 时区显示名（中文名 + UTC 偏移）
    private static func timeZoneDisplay(_ id: String) -> String {
        guard let tz = TimeZone(identifier: id) else { return id }
        let offset = tz.secondsFromGMT() / 60
        let sign = offset >= 0 ? "+" : ""
        let hours = offset / 60
        let mins = abs(offset) % 60
        let offsetStr = mins == 0 ? "\(sign)\(hours)" : "\(sign)\(hours):\(String(format: "%02d", mins))"
        let name = tz.localizedName(for: .standard, locale: Locale(identifier: "zh_CN")) ?? id
        return "\(name) (UTC\(offsetStr))"
    }
}

/// 账户选择弹层（单选，点选即回填并关闭）
private struct EditAccountPickerSheet: View {
    let title: String
    let accounts: [Account]
    let selectedId: String
    let excludeId: String?
    let onSelect: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                ForEach(accounts.filter { $0.id != excludeId }, id: \.id) { acc in
                    Button {
                        onSelect(acc.id)
                        dismiss()
                    } label: {
                        HStack {
                            Text(acc.name)
                                .foregroundColor(.primary)
                            Spacer()
                            Text(AmountFormat.format(acc.balance))
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            if acc.id == selectedId {
                                Image(systemName: "checkmark")
                                    .foregroundColor(Theme.brand)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }
}

// MARK: - 地理位置（CoreLocation 获取）

/// 地理位置行：展示当前经纬度 + 获取/清除按钮。
struct GeoLocationRow: View {
    @Binding var geoLocation: TransactionGeoLocation?
    @State private var isLocating = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let geo = geoLocation {
                Text("\(geo.latitude, specifier: "%.6f"), \(geo.longitude, specifier: "%.6f")")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            } else if let error = error {
                Text(error).font(.footnote).foregroundColor(.red)
            }

            HStack(spacing: 12) {
                Button {
                    requestLocation()
                } label: {
                    HStack(spacing: 5) {
                        if isLocating {
                            ProgressView()
                        } else {
                            Image(systemName: "location")
                        }
                        Text(isLocating ? "定位中…" : "获取当前位置")
                    }
                    .font(.subheadline)
                }
                .disabled(isLocating)

                if geoLocation != nil {
                    Button {
                        geoLocation = nil
                    } label: {
                        Text("清除").font(.subheadline).foregroundColor(Theme.expense)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func requestLocation() {
        isLocating = true
        error = nil
        LocationHelper.shared.requestCurrentLocation { result in
            DispatchQueue.main.async {
                isLocating = false
                switch result {
                case .success(let coord):
                    geoLocation = TransactionGeoLocation(latitude: coord.latitude, longitude: coord.longitude)
                case .failure(let err):
                    error = err.errorDescription
                }
            }
        }
    }
}

/// CoreLocation 单次定位封装（iOS 15 无 async CLLocationManager，用 delegate 回调）
final class LocationHelper: NSObject, CLLocationManagerDelegate {
    /// 定位错误（供 Result 使用）
    enum LocationError: LocalizedError {
        case denied
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .denied: return "未授权定位，请在系统设置中开启"
            case .failed(let msg): return "定位失败：\(msg)"
            }
        }
    }

    static let shared = LocationHelper()

    private var manager: CLLocationManager?
    private var completion: ((Result<CLLocationCoordinate2D, LocationError>) -> Void)?

    func requestCurrentLocation(_ completion: @escaping (Result<CLLocationCoordinate2D, LocationError>) -> Void) {
        self.completion = completion
        let manager = CLLocationManager()
        self.manager = manager
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters

        let status = manager.authorizationStatus
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        default:
            self.completion?(.failure(.denied))
            self.completion = nil
            self.manager = nil
        }
    }

    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            manager.requestLocation()
        } else if status == .denied || status == .restricted {
            completion?(.failure(.denied))
            completion = nil
            self.manager = nil
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        completion?(.success(loc.coordinate))
        completion = nil
        self.manager = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        completion?(.failure(.failed(error.localizedDescription)))
        completion = nil
        self.manager = nil
    }
}

// MARK: - 标签多选

/// 标签多选：按标签组分组，点击切换选中（chip 风格，与 Web 一致）
struct TagSelector: View {
    let tags: [TransactionTag]
    let groups: [TransactionTagGroup]
    @Binding var selected: Set<String>

    private let columns = [GridItem(.adaptive(minimum: 76), spacing: 8)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(TagGrouping.sections(tags: tags, groups: groups)) { section in
                VStack(alignment: .leading, spacing: 6) {
                    Text(section.name)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                        ForEach(section.tags) { tag in
                            chip(tag)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func chip(_ tag: TransactionTag) -> some View {
        let on = selected.contains(tag.id)
        return Button {
            if on { selected.remove(tag.id) } else { selected.insert(tag.id) }
        } label: {
            HStack(spacing: 4) {
                if on { Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)) }
                Text(tag.name).lineLimit(1)
            }
            .font(.footnote)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(on ? Theme.brand : Color(.tertiarySystemFill))
            .foregroundColor(on ? .white : .primary)
            .cornerRadius(14)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 图片选择与预览

/// 图片区：已上传缩略图（可删）+ 添加按钮（相册选图）
struct PicturePickerSection: View {
    @ObservedObject var vm: TransactionEditViewModel
    @State private var showPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !vm.pictures.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(vm.pictures) { p in
                            ZStack(alignment: .topTrailing) {
                                Group {
                                    if let img = p.image {
                                        Image(uiImage: img).resizable().scaledToFill()
                                    } else {
                                        Color(.tertiarySystemFill)
                                            .overlay(Image(systemName: "photo").foregroundColor(.secondary))
                                    }
                                }
                                .frame(width: 72, height: 72)
                                .clipShape(RoundedRectangle(cornerRadius: 10))

                                Button {
                                    vm.removePicture(p.id)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 16))
                                        .foregroundColor(.white)
                                        .background(Circle().fill(Color.black.opacity(0.5)))
                                }
                                .buttonStyle(.plain)
                                .offset(x: 5, y: -5)
                            }
                        }
                    }
                    .padding(.vertical, 6)
                }
            }

            Button {
                showPicker = true
            } label: {
                HStack(spacing: 6) {
                    if vm.isUploadingPicture {
                        ProgressView()
                    } else {
                        Image(systemName: "photo")
                    }
                    Text(vm.isUploadingPicture ? "上传中…" : "添加图片")
                }
                .font(.subheadline)
            }
            .disabled(vm.isUploadingPicture)
        }
        .sheet(isPresented: $showPicker) {
            PhotoPicker { imageData in
                Task { await vm.uploadPicture(imageData) }
            }
        }
    }
}

// MARK: - 相册选图（PHPicker，免权限）

/// 最小化的 PHPicker 封装：单选一张，回调 JPEG 数据。
/// 用 PHPickerViewController 而非 UIImagePickerController，避免相册权限弹窗。
struct PhotoPicker: UIViewControllerRepresentable {
    let onPicked: (Data) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPicked: onPicked) }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onPicked: (Data) -> Void
        init(onPicked: @escaping (Data) -> Void) { self.onPicked = onPicked }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard let provider = results.first?.itemProvider,
                  provider.canLoadObject(ofClass: UIImage.self) else { return }
            provider.loadObject(ofClass: UIImage.self) { object, _ in
                guard let image = object as? UIImage,
                      let data = image.jpegData(compressionQuality: 0.8) else { return }
                DispatchQueue.main.async { self.onPicked(data) }
            }
        }
    }
}
