import SwiftUI

/// 新增 / 编辑账户（对齐 Web 的账户编辑页）。
/// 支持：名称、类别、图标、颜色、货币、初始余额（仅新增）、信用卡账单日、备注、隐藏。
struct AccountEditView: View {
    let account: Account?

    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var category = 1
    @State private var icon = 1
    @State private var color = "26A69A"
    @State private var currency = "CNY"
    @State private var balanceText = ""
    @State private var balanceTime = Date()
    @State private var comment = ""
    @State private var statementDate = 0
    @State private var hidden = false

    @State private var isSaving = false
    @State private var error: String?

    private var isEdit: Bool { account != nil }

    /// 预填直接在 init 里初始化 @State，不走 onAppear：
    /// iOS 15.1 实测 sheet 内 NavigationView 根部的 onAppear 可能不触发，
    /// 导致编辑页全空（名称/类别/图标都是默认值），保存被「请输入账户名称」拦下
    init(account: Account?) {
        self.account = account
        _name = State(initialValue: account?.name ?? "")
        _category = State(initialValue: account?.category ?? 1)
        _icon = State(initialValue: Int(account?.icon ?? "1") ?? 1)
        _color = State(initialValue: account?.color ?? "26A69A")
        _currency = State(initialValue: account?.currency ?? "CNY")
        _comment = State(initialValue: account?.comment ?? "")
        _statementDate = State(initialValue: account?.creditCardStatementDate ?? 0)
        _hidden = State(initialValue: account?.hidden ?? false)
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("名称")) {
                    TextField("账户名称", text: $name)
                }

                Section(header: Text("类别")) {
                    Picker("类别", selection: $category) {
                        ForEach(AccountCategoryConst.all, id: \.0) { Text($0.1).tag($0.0) }
                    }
                }

                Section(header: Text("图标")) {
                    IconGrid(selected: $icon)
                }

                Section(header: Text("颜色")) {
                    ColorGrid(selected: $color)
                }

                Section(header: Text("货币")) {
                    TextField("如 CNY", text: $currency)
                        .autocapitalization(.allCharacters)
                        .disableAutocorrection(true)
                }

                if !isEdit {
                    Section(header: Text("初始余额")) {
                        TextField("0.00", text: $balanceText)
                            .keyboardType(.numbersAndPunctuation)
                        if !balanceText.isEmpty && balanceText != "0" {
                            DatePicker("余额时间", selection: $balanceTime)
                        }
                    }
                }

                if category == 3 {
                    Section(header: Text("信用卡账单日")) {
                        Picker("账单日", selection: $statementDate) {
                            Text("不设置").tag(0)
                            ForEach(1...28, id: \.self) { Text("每月 \($0) 日").tag($0) }
                        }
                    }
                }

                Section(header: Text("备注")) {
                    TextField("可选", text: $comment)
                }

                if isEdit {
                    Section {
                        Toggle("隐藏账户", isOn: $hidden)
                    }
                }

                if let error = error {
                    Section { Text(error).foregroundColor(.red).font(.footnote) }
                }
            }
            .navigationTitle(isEdit ? "编辑账户" : "新增账户")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving { ProgressView() } else { Text("保存").bold() }
                    }
                    .disabled(isSaving)
                }
            }
        }
    }

    private func save() async {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            error = "请输入账户名称"
            return
        }
        guard currency.count == 3 else {
            error = "货币代码需为 3 位，如 CNY"
            return
        }

        isSaving = true
        error = nil
        do {
            if let acc = account {
                let req = AccountModifyRequest(
                    id: acc.id,
                    name: name,
                    category: category,
                    icon: "\(icon)",
                    color: color,
                    currency: currency,
                    balance: nil,
                    balanceTime: nil,
                    comment: comment,
                    creditCardStatementDate: category == 3 ? statementDate : 0,
                    hidden: hidden
                )
                let _: EmptyResult = try await APIClient.shared.request(
                    "/api/v1/accounts/modify.json", method: .POST, body: req
                )
            } else {
                let cents = Self.parseBalance(balanceText)
                let req = AccountCreateRequest(
                    name: name,
                    category: category,
                    icon: "\(icon)",
                    color: color,
                    currency: currency,
                    balance: cents,
                    balanceTime: cents != 0 ? Int64(balanceTime.timeIntervalSince1970) : 0,
                    comment: comment,
                    creditCardStatementDate: category == 3 ? statementDate : 0
                )
                let _: EmptyResult = try await APIClient.shared.request(
                    "/api/v1/accounts/add.json", method: .POST, body: req
                )
            }
            isSaving = false
            AppDataStore.shared.invalidateAccounts()
            dismiss()
        } catch {
            isSaving = false
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// 元 -> 分（NSDecimalNumber 规避 Swift6 Float16 推断）
    private static func parseBalance(_ text: String) -> Int64 {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let amount = Decimal(string: trimmed) else { return 0 }
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

// MARK: - 图标选择网格

private struct IconGrid: View {
    @Binding var selected: Int

    private let columns = [GridItem(.adaptive(minimum: 52), spacing: 10)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(AccountIconCatalog.options, id: \.0) { item in
                Button {
                    selected = item.0
                } label: {
                    Image(systemName: item.1)
                        .font(.system(size: 18))
                        .foregroundColor(selected == item.0 ? .white : .primary)
                        .frame(width: 44, height: 44)
                        .background(
                            Circle().fill(selected == item.0 ? Theme.brand : Color(.tertiarySystemFill))
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - 颜色选择网格

private struct ColorGrid: View {
    @Binding var selected: String

    private let columns = [GridItem(.adaptive(minimum: 44), spacing: 10)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(AccountColorCatalog.all, id: \.self) { hex in
                Button {
                    selected = hex
                } label: {
                    ZStack {
                        Circle().fill(Color(hex: hex)).frame(width: 32, height: 32)
                        if selected == hex {
                            Image(systemName: "checkmark")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.white)
                        }
                    }
                    .frame(width: 40, height: 40)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }
}
