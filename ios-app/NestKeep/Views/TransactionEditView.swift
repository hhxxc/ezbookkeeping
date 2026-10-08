import SwiftUI
import Combine

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
    @Published var accounts: [Account] = []
    @Published var categories: [TransactionCategory] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var didSave = false

    init(transaction: Transaction?, mode: TransactionEditMode = .add) {
        self.originalId = transaction?.id
        self.mode = mode
        self.pending = transaction
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
            async let accs: [Account] = APIClient.shared.request("/api/v1/accounts/list.json")
            async let cats: [TransactionCategory] = APIClient.shared.request("/api/v1/transaction/categories/list.json")
            accounts = try await accs
            categories = try await cats

            if let tx = pending {
                type = tx.transactionType
                amountText = AmountFormat.centsToText(tx.sourceAmount)
                sourceAccountId = tx.sourceAccountId ?? ""
                categoryId = tx.categoryId ?? ""
                date = tx.date
                comment = tx.comment ?? ""
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

    private func defaultCategoryId() -> String {
        let wantType = type == .income
            ? TransactionCategoryType.income.rawValue
            : TransactionCategoryType.expense.rawValue
        return categories.first(where: { $0.type == wantType })?.id ?? ""
    }

    /// 切换类型时同步修正默认分类（余额调整/转账不需分类）
    func typeChanged() {
        if needsCategory && categoryId.isEmpty {
            categoryId = defaultCategoryId()
        }
    }

    func save() async {
        guard let amount = Decimal(string: amountText, locale: Locale(identifier: "zh_CN")), amount > 0 else {
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

        let cents = Self.toCents(amount)
        let utcOffset = TimeZone.current.secondsFromGMT() / 60
        isLoading = true
        error = nil

        do {
            if mode == .edit, let id = originalId {
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
                    tagIds: [],
                    pictureIds: [],
                    comment: comment
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
                    comment: comment.isEmpty ? nil : comment
                )
                let _: EmptyResult = try await APIClient.shared.request(
                    "/api/v1/transactions/add.json", method: .POST, body: req
                )
            }
            isLoading = false
            didSave = true
        } catch {
            isLoading = false
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
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

struct TransactionEditView: View {
    @StateObject private var vm: TransactionEditViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var amountFocused: Bool

    init(transaction: Transaction?, mode: TransactionEditMode = .add) {
        _vm = StateObject(wrappedValue: TransactionEditViewModel(transaction: transaction, mode: mode))
    }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    Picker("类型", selection: $vm.type) {
                        Text("支出").tag(TransactionType.expense)
                        Text("收入").tag(TransactionType.income)
                        Text("转账").tag(TransactionType.transfer)
                        Text("余额调整").tag(TransactionType.modifyBalance)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: vm.type) { _ in vm.typeChanged() }
                }

                Section(header: Text(vm.type == .modifyBalance ? "目标余额" : "金额")) {
                    TextField("0.00", text: $vm.amountText)
                        .keyboardType(.decimalPad)
                        .focused($amountFocused)
                }

                Section(header: Text(vm.type == .transfer ? "转出账户" : "账户")) {
                    Picker("来源账户", selection: $vm.sourceAccountId) {
                        ForEach(vm.accounts, id: \.id) { Text($0.name).tag($0.id) }
                    }
                    if vm.type == .transfer {
                        Picker("目标账户", selection: $vm.destinationAccountId) {
                            ForEach(vm.accounts.filter { $0.id != vm.sourceAccountId }, id: \.id) {
                                Text($0.name).tag($0.id)
                            }
                        }
                    }
                }

                if vm.needsCategory {
                    Section(header: Text("分类")) {
                        Picker("分类", selection: $vm.categoryId) {
                            ForEach(flatCategories(vm.categories), id: \.id) { Text($0.name).tag($0.id) }
                        }
                    }
                }

                Section(header: Text("时间")) {
                    DatePicker("时间", selection: $vm.date)
                        .labelsHidden()
                }

                Section(header: Text("备注")) {
                    TextField("可选", text: $vm.comment)
                }

                if let error = vm.error {
                    Section { Text(error).foregroundColor(.red).font(.footnote) }
                }
            }
            .navigationTitle(vm.navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task { await vm.save() }
                    } label: {
                        if vm.isLoading { ProgressView() } else { Text("保存") }
                    }
                    .disabled(vm.isLoading)
                }
            }
            .task { await vm.load() }
            .onChange(of: vm.didSave) { saved in if saved { dismiss() } }
        }
    }

    private func flatCategories(_ cats: [TransactionCategory]) -> [TransactionCategory] {
        cats.flatMap { c in
            var arr = [c]
            if let subs = c.subCategories { arr.append(contentsOf: subs) }
            return arr
        }
        .filter { cat in
            // 只展示与当前类型匹配的分类
            if vm.type == .income { return cat.type == TransactionCategoryType.income.rawValue }
            if vm.type == .expense { return cat.type == TransactionCategoryType.expense.rawValue }
            return true
        }
    }
}
