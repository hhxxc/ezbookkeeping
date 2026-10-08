import SwiftUI

/// 交易详情页：展示单笔交易的完整信息（对齐 Web 的 View 模式），
/// 并提供「复制」与「编辑」入口。
struct TransactionDetailView: View {
    let transaction: Transaction

    @Environment(\.dismiss) private var dismiss
    @State private var showEdit = false
    @State private var showDuplicate = false

    private var amountText: String {
        switch transaction.transactionType {
        case .expense: return "-" + AmountFormat.format(transaction.sourceAmount, currency: transaction.currency)
        case .income: return "+" + AmountFormat.format(transaction.sourceAmount, currency: transaction.currency)
        case .transfer: return AmountFormat.format(transaction.sourceAmount, currency: transaction.currency)
        case .modifyBalance: return AmountFormat.format(transaction.sourceAmount, currency: transaction.currency)
        }
    }

    private var amountColor: Color {
        switch transaction.transactionType {
        case .expense: return Theme.expense
        case .income: return Theme.income
        case .transfer: return .primary
        case .modifyBalance: return Theme.brand
        }
    }

    private var typeLabel: String {
        switch transaction.transactionType {
        case .expense: return "支出"
        case .income: return "收入"
        case .transfer: return "转账"
        case .modifyBalance: return "余额调整"
        }
    }

    var body: some View {
        NavigationView {
            List {
                Section {
                    VStack(spacing: 8) {
                        Text(typeLabel)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(amountText)
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundColor(amountColor)
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .listRowBackground(Color.clear)
                }

                Section {
                    detailRow("分类", transaction.categoryName ?? "—")
                    detailRow(transaction.transactionType == .transfer ? "转出账户" : "账户",
                              transaction.sourceAccount?.name ?? "—")
                    if transaction.transactionType == .transfer {
                        detailRow("转入账户", transaction.destinationAccount?.name ?? "—")
                        if let d = transaction.destinationAmount, d != transaction.sourceAmount {
                            detailRow("转入金额", AmountFormat.format(d, currency: transaction.currency))
                        }
                    }
                    detailRow("时间", Self.fullDateTime(transaction.date))
                }

                if let comment = transaction.comment, !comment.isEmpty {
                    Section(header: Text("备注")) {
                        Text(comment)
                    }
                }

                Section {
                    Button {
                        showDuplicate = true
                    } label: {
                        Label("复制为新交易", systemImage: "doc.on.doc")
                    }
                    .disabled(transaction.transactionType == .modifyBalance)

                    Button {
                        showEdit = true
                    } label: {
                        Label("编辑", systemImage: "pencil")
                    }
                    .disabled(!(transaction.editable ?? true))
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("交易详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            .sheet(isPresented: $showEdit) {
                TransactionEditView(transaction: transaction, mode: .edit)
            }
            .sheet(isPresented: $showDuplicate) {
                TransactionEditView(transaction: transaction, mode: .duplicate)
            }
        }
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).foregroundColor(.secondary)
        }
    }

    static func fullDateTime(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy年M月d日 HH:mm"
        return f.string(from: d)
    }
}
