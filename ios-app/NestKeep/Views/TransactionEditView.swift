import SwiftUI
import Combine

/// 新增/编辑交易（支出/收入/转账）。MVP：支持新增；编辑复用表单（保存走 add 暂未实现 modify）
@MainActor
final class TransactionEditViewModel: ObservableObject {
    let transaction: Transaction?

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

    init(transaction: Transaction?) {
        self.transaction = transaction
    }

    func load() async {
        isLoading = true
        error = nil
        do {
            async let accs: [Account] = APIClient.shared.request("/api/v1/accounts/list.json")
            async let cats: [TransactionCategory] = APIClient.shared.request("/api/v1/transaction/categories/list.json")
            accounts = try await accs
            categories = try await cats

            if let tx = transaction {
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
                // 默认选第一个支出分类
                if let firstExpense = categories.first(where: { $0.type == TransactionCategoryType.expense.rawValue }) {
                    categoryId = firstExpense.id
                }
            }
            isLoading = false
        } catch {
            isLoading = false
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    func save() async {
        guard let amount = Decimal(string: amountText, locale: Locale(identifier: "zh_CN")), amount > 0 else {
            error = "请输入有效金额"
            return
        }
        guard !sourceAccountId.isEmpty, !categoryId.isEmpty else {
            error = "请选择账户和分类"
            return
        }
        let roundingHandler = NSDecimalNumberHandler(
            roundingMode: .plain, scale: 0,
            raiseOnExactness: false, raiseOnOverflow: false,
            raiseOnUnderflow: false, raiseOnDivideByZero: false
        )
        let cents = NSDecimalNumber(decimal: amount)
            .multiplying(by: NSDecimalNumber(value: 100))
            .rounding(accordingToBehavior: roundingHandler)
            .int64Value
        let utcOffset = TimeZone.current.secondsFromGMT() / 60
        let req = TransactionCreateRequest(
            type: type.rawValue,
            categoryId: categoryId,
            time: Int64(date.timeIntervalSince1970),
            utcOffset: utcOffset,
            sourceAccountId: sourceAccountId,
            destinationAccountId: type == .transfer ? destinationAccountId : nil,
            sourceAmount: cents,
            destinationAmount: type == .transfer ? cents : nil,
            comment: comment.isEmpty ? nil : comment
        )
        isLoading = true
        error = nil
        do {
            let _: EmptyResult = try await APIClient.shared.request(
                "/api/v1/transactions/add.json", method: .POST, body: req
            )
            isLoading = false
            didSave = true
        } catch {
            isLoading = false
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }
}

struct TransactionEditView: View {
    @StateObject private var vm: TransactionEditViewModel
    @Environment(\.dismiss) private var dismiss

    init(transaction: Transaction?) {
        _vm = StateObject(wrappedValue: TransactionEditViewModel(transaction: transaction))
    }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    Picker("类型", selection: $vm.type) {
                        Text("支出").tag(TransactionType.expense)
                        Text("收入").tag(TransactionType.income)
                        Text("转账").tag(TransactionType.transfer)
                    }
                    .pickerStyle(.segmented)
                }

                Section(header: Text("金额")) {
                    TextField("0.00", text: $vm.amountText)
                        .keyboardType(.decimalPad)
                }

                Section(header: Text("账户")) {
                    Picker("来源账户", selection: $vm.sourceAccountId) {
                        ForEach(vm.accounts, id: \.id) { Text($0.name).tag($0.id) }
                    }
                    if vm.type == .transfer {
                        Picker("目标账户", selection: $vm.destinationAccountId) {
                            ForEach(vm.accounts, id: \.id) { Text($0.name).tag($0.id) }
                        }
                    }
                }

                Section(header: Text("分类")) {
                    Picker("分类", selection: $vm.categoryId) {
                        ForEach(flatCategories(vm.categories), id: \.id) { Text($0.name).tag($0.id) }
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
            .navigationTitle(vm.transaction == nil ? "记一笔" : "编辑")
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
            .onChange(of: vm.didSave) { _ in if vm.didSave { dismiss() } }
        }
    }

    private func flatCategories(_ cats: [TransactionCategory]) -> [TransactionCategory] {
        cats.flatMap { c in
            var arr = [c]
            if let subs = c.subCategories { arr.append(contentsOf: subs) }
            return arr
        }
    }
}
