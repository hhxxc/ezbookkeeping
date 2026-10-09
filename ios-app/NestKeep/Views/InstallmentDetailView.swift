import SwiftUI

/// 分期计划详情：计划信息（进度条/每期金额/起止）+ 每期入账明细 + 删除分期。
/// 已入账期次可点开交易详情；未入账期次为预记的未来交易。
struct InstallmentDetailView: View {
    let planId: String
    /// 删除成功后的回调（刷新列表）
    var onDeleted: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var detail: InstallmentPlanDetail?
    @State private var isLoading = false
    @State private var isDeleting = false
    @State private var error: String?
    @State private var showDeleteDialog = false
    @State private var periodDetail: Transaction?

    var body: some View {
        NavigationView {
            Group {
                if let detail = detail {
                    content(detail)
                } else if isLoading {
                    VStack(spacing: 10) {
                        ProgressView()
                        Text("加载中…").font(.footnote).foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = error {
                    VStack(spacing: 12) {
                        Text(error).font(.footnote).foregroundColor(.red).multilineTextAlignment(.center)
                        Button("重试") { Task { await load() } }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("分期详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            .task { await load() }
        }
        .navigationViewStyle(.stack)
    }

    // MARK: - 数据

    private func load() async {
        isLoading = true
        error = nil
        do {
            let result: InstallmentPlanDetail = try await APIClient.shared.request(
                "/api/v1/transactions/installments/get.json",
                query: [URLQueryItem(name: "id", value: planId)]
            )
            detail = result
            isLoading = false
        } catch {
            isLoading = false
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func deletePlan(deleteTransactions: Bool) async {
        guard let plan = detail?.plan else { return }
        isDeleting = true
        defer { isDeleting = false }
        do {
            let _: EmptyResult = try await APIClient.shared.request(
                "/api/v1/transactions/installments/delete.json", method: .POST,
                body: InstallmentDeleteRequest(id: plan.id, deleteTransactions: deleteTransactions)
            )
            onDeleted?()
            dismiss()
        } catch {
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    // MARK: - 内容

    private func content(_ detail: InstallmentPlanDetail) -> some View {
        List {
            planHeader(detail.plan)
            planInfo(detail.plan)
            periodList(detail)
            Section {
                Button(role: .destructive) {
                    showDeleteDialog = true
                } label: {
                    HStack {
                        Spacer()
                        if isDeleting {
                            ProgressView()
                        } else {
                            Label("删除分期", systemImage: "trash")
                        }
                        Spacer()
                    }
                }
                .disabled(isDeleting)
            } footer: {
                Text("删除分期不会自动改动已入账的交易，可在删除时选择是否一并删除全部期次。")
            }
        }
        .listStyle(.insetGrouped)
        .confirmationDialog(
            "删除分期「\(detail.plan.name)」？",
            isPresented: $showDeleteDialog,
            titleVisibility: .visible
        ) {
            Button("删除计划并删除全部 \(detail.plan.totalPeriods) 期交易", role: .destructive) {
                Task { await deletePlan(deleteTransactions: true) }
            }
            Button("仅删除计划（保留全部交易记录）", role: .destructive) {
                Task { await deletePlan(deleteTransactions: false) }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("已入账 \(detail.plan.paidPeriods)/\(detail.plan.totalPeriods) 期。保留的交易会继续留在账单里，但不再与分期关联。")
        }
    }

    private func planHeader(_ plan: InstallmentPlan) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(plan.name)
                        .font(.headline)
                    Spacer()
                    Text(plan.transactionType == .income ? "收入" : "支出")
                        .font(.footnote)
                        .foregroundColor(plan.transactionType == .income ? Theme.income : Theme.expense)
                }

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(AmountFormat.format(plan.totalAmount))
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    Text("共 \(plan.totalPeriods) 期")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                ProgressView(value: Double(plan.paidPeriods), total: Double(max(plan.totalPeriods, 1)))
                    .tint(plan.isFinished ? Theme.income : Theme.brand)

                HStack {
                    Text("已入账 \(plan.paidPeriods)/\(plan.totalPeriods) 期")
                        .font(.footnote)
                        .foregroundColor(plan.isFinished ? Theme.income : .secondary)
                    Spacer()
                    if let next = plan.nextDate, !plan.isFinished {
                        Text("下期 \(Self.shortDate(next))")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }

                if plan.lastPeriodAmount > 0 {
                    Text("每期 \(AmountFormat.format(plan.periodAmount))，末期 \(AmountFormat.format(plan.lastPeriodAmount))")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                } else {
                    Text("每期 \(AmountFormat.format(plan.periodAmount))")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func planInfo(_ plan: InstallmentPlan) -> some View {
        Section {
            detailRow("账户", accountName(plan.sourceAccountId))
            detailRow("分类", categoryName(plan.categoryId))
            detailRow("首期", Self.shortDate(plan.startDate))
            detailRow("末期", Self.shortDate(plan.endDate))
            if let comment = plan.comment, !comment.isEmpty {
                detailRow("备注", comment)
            }
        }
    }

    private func periodList(_ detail: InstallmentPlanDetail) -> some View {
        Section(header: Text("每期明细")) {
            ForEach(detail.transactions, id: \.id) { tx in
                let paid = tx.date <= Date()
                Button {
                    if paid {
                        periodDetail = tx
                    }
                } label: {
                    HStack(spacing: 10) {
                        Text("第 \(tx.installmentIndex.map { $0 + 1 } ?? 0) 期")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.primary)
                        Spacer(minLength: 8)
                        Text(Self.shortDate(tx.date))
                            .font(.footnote)
                            .foregroundColor(.secondary)
                        Text(AmountFormat.format(tx.sourceAmount))
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundColor(.primary)
                        Text(paid ? "已入账" : "待入账")
                            .font(.footnote)
                            .foregroundColor(paid ? Theme.income : .secondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(
                                Capsule().fill(
                                    paid ? Theme.income.opacity(0.12) : Color(.tertiarySystemFill)
                                )
                            )
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(item: $periodDetail) { tx in
            TransactionDetailView(transaction: tx)
        }
    }

    // MARK: - 辅助

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).foregroundColor(.secondary)
        }
    }

    private func accountName(_ id: String) -> String {
        if let acc = detail?.transactions.first(where: { $0.sourceAccountId == id })?.sourceAccount {
            return acc.name ?? id
        }
        return id
    }

    private func categoryName(_ id: String) -> String {
        if let cat = detail?.transactions.first(where: { $0.categoryId == id })?.category {
            return cat.name ?? id
        }
        return id
    }

    private static func shortDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy年M月d日"
        return f.string(from: d)
    }
}
