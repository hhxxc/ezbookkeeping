import SwiftUI

// MARK: - 模型（与后端 /budget/get.json、/budget/set.json 对齐）

struct BudgetResponse: Codable {
    let year: Int
    let month: Int
    let totalAmount: Int64
    let categoryBudgets: [BudgetCategoryAmount]
}

struct BudgetCategoryAmount: Codable {
    let categoryId: String
    let amount: Int64
}

struct BudgetSaveRequest: Encodable {
    let year: Int
    let month: Int
    let totalAmount: Int64
    let categoryBudgets: [BudgetCategoryAmount]
}

// MARK: - ViewModel

@MainActor
final class BudgetViewModel: ObservableObject {
    /// 当月预算（nil=尚未加载；totalAmount=0 表示未设置）
    @Published var budget: BudgetResponse?
    @Published var isLoading = false
    @Published var error: String?
    @Published var saving = false

    /// 支出分类（预算设置用）
    @Published var expenseCategories: [(id: String, name: String)] = []

    func load(year: Int, month: Int) async {
        isLoading = true
        error = nil
        do {
            let resp: BudgetResponse = try await APIClient.shared.request(
                "/api/v1/budget/get.json",
                query: [
                    URLQueryItem(name: "year", value: "\(year)"),
                    URLQueryItem(name: "month", value: "\(month)"),
                ]
            )
            budget = resp
        } catch {
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
        // 支出分类（含子分类拍平）
        do {
            let categories = try await AppDataStore.shared.getCategories()
            var result: [(String, String)] = []
            for c in categories where c.type == 2 {
                result.append((c.id, c.name))
                for sub in c.subCategories ?? [] {
                    result.append((sub.id, sub.name))
                }
            }
            expenseCategories = result
        } catch {
            // 分类拉取失败不阻塞预算显示
        }
        isLoading = false
    }

    /// 保存预算（金额输入为「元」，转为分）
    func save(year: Int, month: Int, totalYuanText: String, categoryYuanTexts: [String: String]) async -> Bool {
        saving = true
        error = nil
        defer { saving = false }
        let totalCents = Self.yuanTextToCents(totalYuanText) ?? 0
        var categoryBudgets: [BudgetCategoryAmount] = []
        for (categoryId, text) in categoryYuanTexts {
            if let cents = Self.yuanTextToCents(text), cents > 0 {
                categoryBudgets.append(BudgetCategoryAmount(categoryId: categoryId, amount: cents))
            }
        }
        do {
            let resp: BudgetResponse = try await APIClient.shared.request(
                "/api/v1/budget/set.json",
                method: .POST,
                body: BudgetSaveRequest(year: year, month: month, totalAmount: totalCents, categoryBudgets: categoryBudgets)
            )
            budget = resp
            return true
        } catch {
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    /// 元文本 → 分（nil 表示空/非法）
    static func yuanTextToCents(_ text: String) -> Int64? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        guard let value = Double(trimmed), value >= 0, value <= 99_999_999 else { return nil }
        return Int64((value * 100).rounded())
    }

    static func centsToYuanText(_ cents: Int64) -> String {
        guard cents > 0 else { return "" }
        return String(format: "%.2f", Double(cents) / 100)
    }
}

// MARK: - 统计页预算进度卡

/// 当月预算进度卡：仅设置了总预算时显示；接近/超出预算变色
struct BudgetProgressCard: View {
    let totalAmount: Int64
    let expenseCents: Int64
    /// 分类支出（用于超支分类提示行）
    let categoryExpense: [StatisticsViewModel.CategoryStat]
    let categoryBudgets: [BudgetCategoryAmount]
    let onOpenSettings: () -> Void

    private var ratio: Double {
        guard totalAmount > 0 else { return 0 }
        return min(1, Double(expenseCents) / Double(totalAmount))
    }

    private var progressColor: Color {
        let r = Double(expenseCents) / Double(max(totalAmount, 1))
        if r >= 1 { return Theme.expense }
        if r >= 0.9 { return .orange }
        return Theme.income
    }

    var body: some View {
        Button(action: onOpenSettings) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "gauge.with.needle")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Theme.brand)
                    Text("本月预算")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(HomePalette.ink)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(HomePalette.secondary)
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(HomePalette.secondary.opacity(0.15))
                        Capsule()
                            .fill(progressColor)
                            .frame(width: max(6, geo.size.width * ratio))
                            .animation(.easeOut(duration: 0.3), value: ratio)
                    }
                }
                .frame(height: 10)

                HStack(spacing: 4) {
                    if expenseCents > totalAmount {
                        Text("已超支 \(AmountFormat.format(expenseCents - totalAmount))")
                            .foregroundColor(Theme.expense)
                            .font(.system(size: 12, weight: .semibold))
                    } else {
                        Text("还可用 \(AmountFormat.format(totalAmount - expenseCents))")
                            .foregroundColor(HomePalette.ink)
                            .font(.system(size: 12, weight: .semibold))
                    }
                    Spacer()
                    Text("已花 \(AmountFormat.format(expenseCents)) / \(AmountFormat.format(totalAmount))")
                        .foregroundColor(HomePalette.secondary)
                        .font(.system(size: 12))
                        .monospacedDigit()
                }
            }
            .padding(14)
            .background(HomePalette.card)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 预算设置页

/// 当月预算设置：总预算 + 各支出分类预算（留空=不限）
struct BudgetSettingsView: View {
    let year: Int
    let month: Int
    let onSaved: () -> Void
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm = BudgetViewModel()

    @State private var totalYuanText = ""
    @State private var categoryYuanTexts: [String: String] = [:]

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("本月总预算（\(month)月）"), footer: Text("留空表示不设预算。金额单位为元。")) {
                    TextField("如 5000", text: $totalYuanText)
                        .keyboardType(.decimalPad)
                }

                Section(header: Text("分类预算（可选）"), footer: Text("只列出支出分类；留空的分类不限预算。")) {
                    if vm.expenseCategories.isEmpty {
                        Text("暂无支出分类").foregroundColor(.secondary).font(.footnote)
                    }
                    ForEach(vm.expenseCategories, id: \.id) { cat in
                        HStack {
                            Text(cat.name)
                                .font(.subheadline)
                            Spacer()
                            TextField("不限", text: Binding(
                                get: { categoryYuanTexts[cat.id] ?? "" },
                                set: { categoryYuanTexts[cat.id] = $0 }
                            ))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 110)
                        }
                    }
                }

                if let error = vm.error {
                    Section { Text(error).foregroundColor(.red).font(.footnote) }
                }

                Section {
                    Button {
                        Task {
                            if await vm.save(year: year, month: month, totalYuanText: totalYuanText, categoryYuanTexts: categoryYuanTexts) {
                                onSaved()
                                dismiss()
                            }
                        }
                    } label: {
                        if vm.saving {
                            HStack { Spacer(); ProgressView(); Spacer() }
                        } else {
                            Text("保存预算")
                                .font(.body.weight(.semibold))
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(vm.saving)
                }
            }
            .navigationTitle("预算设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { dismiss() }
                }
            }
            .task {
                await vm.load(year: year, month: month)
                if let b = vm.budget {
                    totalYuanText = BudgetViewModel.centsToYuanText(b.totalAmount)
                    for item in b.categoryBudgets {
                        categoryYuanTexts[item.categoryId] = BudgetViewModel.centsToYuanText(item.amount)
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
    }
}
