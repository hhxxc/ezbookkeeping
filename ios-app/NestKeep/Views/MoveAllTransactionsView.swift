import SwiftUI

/// 「移动全部账单」：把某账户下的全部账单迁移到目标账户。
/// 对齐 Web `accounts/MoveAllTransactionsPage.vue`：
///  1. 选目标账户（不可与源账户相同、不可为多子账户父账户、币种需一致）
///  2. **二次输入目标账户名**做确认（防误操作）
///  3. `POST /api/v1/transactions/move/all.json` body `{fromAccountId, toAccountId}`（均为字符串）
struct MoveAllTransactionsView: View {
    /// 源账户（必须是单账户）
    let fromAccount: Account

    @Environment(\.dismiss) private var dismiss

    @State private var accounts: [Account] = []
    @State private var isLoading = true
    @State private var isMoving = false
    @State private var error: String?
    @State private var toAccountId: String?
    @State private var toAccountName = ""
    @State private var showPicker = false
    @State private var showConfirm = false

    /// 可选目标账户：可见、非自身、非多子账户父账户、币种与源账户一致
    private var candidates: [Account] {
        accounts.filter { acc in
            guard !(acc.hidden ?? false) else { return false }
            guard acc.id != fromAccount.id else { return false }
            guard acc.type != AccountType.multiSubAccounts.rawValue else { return false }
            guard (acc.currency ?? "") == (fromAccount.currency ?? "") else { return false }
            return true
        }
    }

    private var targetAccount: Account? {
        guard let id = toAccountId else { return nil }
        return accounts.first { $0.id == id }
    }

    /// 二次输入的名字须与目标账户名一致（Web `isToAccountNameValid`）
    private var isNameValid: Bool {
        guard let target = targetAccount else { return false }
        return toAccountName.trimmingCharacters(in: .whitespaces) == target.name
    }

    private var canSubmit: Bool {
        targetAccount != nil && isNameValid && !isMoving
    }

    var body: some View {
        NavigationView {
            Group {
                if isLoading {
                    ProgressView()
                } else {
                    Form {
                        Section {
                            // 源账户
                            HStack {
                                Text("源账户")
                                Spacer()
                                Text(fromAccount.name).foregroundColor(.secondary)
                            }

                            // 目标账户
                            Button {
                                showPicker = true
                            } label: {
                                HStack {
                                    Text("目标账户").foregroundColor(.primary)
                                    Spacer()
                                    Text(targetAccount?.name ?? "未指定")
                                        .foregroundColor(targetAccount == nil ? .secondary : .primary)
                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(.caption2).foregroundColor(.secondary)
                                }
                            }
                            .disabled(isMoving)

                            // 二次确认输入
                            VStack(alignment: .leading, spacing: 6) {
                                Text("确认目标账户名称")
                                    .font(.footnote).foregroundColor(.secondary)
                                TextField("请重新输入目标账户名称以确认", text: $toAccountName)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled(true)
                                    .disabled(isMoving)
                            }
                        }

                        Section {
                            Text("此操作会把「\(fromAccount.name)」下的全部账单迁移到目标账户。迁移后源账户将不再有账单，请谨慎操作。")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }

                        if let error = error {
                            Section { Text(error).foregroundColor(.red).font(.footnote) }
                        }
                    }
                }
            }
            .navigationTitle("移动全部账单")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { dismiss() }.disabled(isMoving)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showConfirm = true
                    } label: {
                        if isMoving { ProgressView() } else { Text("移动").bold() }
                    }
                    .disabled(!canSubmit)
                }
            }
            .confirmationDialog("确认移动全部账单？", isPresented: $showConfirm, titleVisibility: .visible) {
                Button("移动全部账单", role: .destructive) { Task { await move() } }
                Button("取消", role: .cancel) {}
            } message: {
                Text("将把「\(fromAccount.name)」的全部账单迁移到「\(targetAccount?.name ?? "")」，此操作不可撤销。")
            }
            .sheet(isPresented: $showPicker) {
                AccountPickerSheet(accounts: candidates, selectedId: $toAccountId, title: "选择目标账户")
            }
        }
        .task { await load() }
    }

    private func load() async {
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

    private func move() async {
        guard let to = targetAccount else { return }
        isMoving = true
        error = nil
        do {
            let req = MoveAllTransactionsRequest(fromAccountId: fromAccount.id, toAccountId: to.id)
            let _: EmptyResult = try await APIClient.shared.request(
                "/api/v1/transactions/move/all.json", method: .POST, body: req
            )
            isMoving = false
            dismiss()
        } catch {
            isMoving = false
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }
}

/// 账户选择弹层（单账户、按类别分组）
struct AccountPickerSheet: View {
    let accounts: [Account]
    @Binding var selectedId: String?
    let title: String

    @Environment(\.dismiss) private var dismiss
    @State private var keyword = ""

    private var filtered: [Account] {
        let kw = keyword.trimmingCharacters(in: .whitespaces)
        guard !kw.isEmpty else { return accounts }
        return accounts.filter { $0.name.localizedCaseInsensitiveContains(kw) }
    }

    private var groups: [(category: Int, name: String, accounts: [Account])] {
        let dict = Dictionary(grouping: filtered) { $0.category ?? 0 }
        return dict.keys.sorted().compactMap { key in
            guard let items = dict[key], !items.isEmpty else { return nil }
            return (key, AccountCategoryConst.name(key), items.sorted { ($0.displayOrder ?? 0) < ($1.displayOrder ?? 0) })
        }
    }

    var body: some View {
        NavigationView {
            List {
                ForEach(groups, id: \.category) { group in
                    Section(header: Text(group.name)) {
                        ForEach(group.accounts, id: \.id) { acc in
                            Button {
                                selectedId = acc.id
                                dismiss()
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: AccountIconCatalog.symbol(acc.icon))
                                        .foregroundColor(.white)
                                        .font(.system(size: 13))
                                        .frame(width: 28, height: 28)
                                        .background(Circle().fill(Color(hex: acc.color ?? "26A69A")))
                                    Text(acc.name).foregroundColor(.primary)
                                    Spacer()
                                    Text(AmountFormat.format(acc.balance, currency: acc.currency))
                                        .font(.caption).foregroundColor(.secondary)
                                    if selectedId == acc.id {
                                        Image(systemName: "checkmark").foregroundColor(Theme.brand)
                                    }
                                }
                            }
                        }
                    }
                }
                if groups.isEmpty {
                    Text("没有可用的账户").foregroundColor(.secondary)
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $keyword, placement: .navigationBarDrawer(displayMode: .always), prompt: "查找账户")
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }
}
