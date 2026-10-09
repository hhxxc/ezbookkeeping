import SwiftUI
import Combine

/// 模板与计划账单（对齐 Web 的模板 / 计划账单列表），并内嵌「分期账单」段
@MainActor
final class TemplatesViewModel: ObservableObject {
    /// 1=普通模板 2=计划账单 3=分期账单
    @Published var templateType = 1
    @Published var templates: [TransactionTemplate] = []
    /// 分期计划列表（templateType == 3 时使用）
    @Published var plans: [InstallmentPlan] = []
    @Published var categories: [TransactionCategory] = []
    @Published var accounts: [Account] = []
    @Published var isLoading = false
    @Published var error: String?

    func load() async {
        isLoading = true
        error = nil
        do {
            async let c = AppDataStore.shared.getCategories()
            async let a = AppDataStore.shared.getAccounts()
            if templateType == 3 {
                async let p: [InstallmentPlan] = APIClient.shared.request("/api/v1/transactions/installments/list.json")
                accounts = (try? await a) ?? []
                categories = (try? await c) ?? []
                plans = (try? await p) ?? []
                templates = []
            } else {
                async let t: [TransactionTemplate] = APIClient.shared.request(
                    "/api/v1/transaction/templates/list.json",
                    query: [URLQueryItem(name: "templateType", value: "\(templateType)")]
                )
                accounts = (try? await a) ?? []
                categories = (try? await c) ?? []
                templates = (try? await t) ?? []
                plans = []
            }
            isLoading = false
        } catch {
            isLoading = false
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    func categoryName(_ id: String?) -> String {
        guard let id = id else { return "—" }
        for c in categories {
            if c.id == id { return c.name }
            if let subs = c.subCategories, let hit = subs.first(where: { $0.id == id }) { return hit.name }
        }
        return "—"
    }

    func accountName(_ id: String?) -> String {
        accounts.first { $0.id == id }?.name ?? "—"
    }

    func delete(_ template: TransactionTemplate) async {
        do {
            let _: EmptyResult = try await APIClient.shared.request(
                "/api/v1/transaction/templates/delete.json", method: .POST,
                body: TemplateIdRequest(id: template.id)
            )
            templates.removeAll { $0.id == template.id }
        } catch {
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    func toggleHide(_ template: TransactionTemplate) async {
        do {
            let _: EmptyResult = try await APIClient.shared.request(
                "/api/v1/transaction/templates/hide.json", method: .POST,
                body: TemplateHideRequest(id: template.id, hidden: !(template.hidden ?? false))
            )
            await load()
        } catch {
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// 删除分期计划（deleteTransactions = 是否连同全部期次交易一起删除）
    func deletePlan(_ plan: InstallmentPlan, deleteTransactions: Bool) async {
        do {
            let _: EmptyResult = try await APIClient.shared.request(
                "/api/v1/transactions/installments/delete.json", method: .POST,
                body: InstallmentDeleteRequest(id: plan.id, deleteTransactions: deleteTransactions)
            )
            plans.removeAll { $0.id == plan.id }
        } catch {
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// 保存排序结果
    func saveOrder(_ ordered: [TransactionTemplate]) async {
        let req = TemplateMoveRequest(newDisplayOrders: ordered.enumerated().map {
            TemplateNewDisplayOrderRequest(id: $0.element.id, displayOrder: $0.offset)
        })
        do {
            let _: EmptyResult = try await APIClient.shared.request(
                "/api/v1/transaction/templates/move.json", method: .POST, body: req
            )
            await load()
        } catch {
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }
}

/// 模板响应（内嵌 TransactionInfoResponse 字段 + 模板特有字段）
struct TransactionTemplate: Codable, Identifiable {
    let id: String
    let name: String
    let type: Int
    let categoryId: String?
    let sourceAccountId: String?
    let destinationAccountId: String?
    let sourceAmount: Int64
    let destinationAmount: Int64?
    let comment: String?
    let templateType: Int?
    let scheduledFrequencyType: Int?
    let scheduledFrequency: String?
    let scheduledStartDate: String?
    let scheduledEndDate: String?
    let tagIds: [String]?
    let displayOrder: Int?
    let hidden: Bool?

    var transactionType: TransactionType { TransactionType(rawValue: type) ?? .expense }
}

struct TemplateIdRequest: Codable { let id: String }
struct TemplateHideRequest: Codable { let id: String; let hidden: Bool }

/// 模板排序（`POST /api/v1/transaction/templates/move.json`）
struct TemplateMoveRequest: Codable {
    let newDisplayOrders: [TemplateNewDisplayOrderRequest]
}
struct TemplateNewDisplayOrderRequest: Codable {
    let id: String
    let displayOrder: Int
}

struct TemplatesView: View {
    @StateObject private var vm = TemplatesViewModel()
    @State private var isSorting = false
    @State private var sortItems: [TransactionTemplate] = []
    /// 新增 / 编辑模板
    @State private var editingTemplate: TransactionTemplate?
    @State private var showAddTemplate = false
    /// 分期详情 / 新建分期
    @State private var detailPlan: InstallmentPlan?
    @State private var showAddInstallment = false

    var body: some View {
        List {
            if isSorting {
                Section {
                    ForEach(sortItems, id: \.id) { template in
                        HStack(spacing: 12) {
                            Image(systemName: iconName(template))
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 32, height: 32)
                                .background(iconColor(template))
                                .cornerRadius(9)
                            Text(template.name)
                            Spacer()
                        }
                    }
                    .onMove { from, to in sortItems.move(fromOffsets: from, toOffset: to) }
                } footer: {
                    Text("拖动调整顺序，完成后点「完成」。")
                }
            } else {
                Picker("类型", selection: $vm.templateType) {
                    Text("模板").tag(1)
                    Text("计划账单").tag(2)
                    Text("分期账单").tag(3)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .onChange(of: vm.templateType) { _ in Task { await vm.load() } }

                if vm.templateType == 3 {
                    installmentList
                } else {
                    templateList
                }
            }
        }
        .listStyle(.insetGrouped)
        .environment(\.editMode, .constant(isSorting ? EditMode.active : EditMode.inactive))
        .navigationTitle("模板与计划账单")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if isSorting {
                    Button("完成") {
                        let ordered = sortItems
                        isSorting = false
                        Task { await vm.saveOrder(ordered) }
                    }
                } else {
                    HStack(spacing: 16) {
                        if vm.templateType != 3 {
                            Button("排序") {
                                sortItems = vm.templates
                                isSorting = true
                            }
                        }
                        Button {
                            if vm.templateType == 3 {
                                showAddInstallment = true
                            } else {
                                showAddTemplate = true
                            }
                        } label: { Image(systemName: "plus") }
                    }
                }
            }
        }
        .refreshable { await vm.load() }
        .sheet(isPresented: $showAddTemplate) {
            TemplateEditView(template: nil, templateType: vm.templateType)
        }
        .sheet(item: $editingTemplate) { template in
            TemplateEditView(template: template, templateType: template.templateType ?? 1)
        }
        .sheet(isPresented: $showAddInstallment, onDismiss: { Task { await vm.load() } }) {
            TransactionEditView(transaction: nil, mode: .add, defaultInstallment: true)
        }
        .sheet(item: $detailPlan) { plan in
            InstallmentDetailView(planId: plan.id) {
                Task { await vm.load() }
            }
        }
        .task { await vm.load() }
    }

    /// 模板 / 计划账单列表（原逻辑）
    @ViewBuilder
    private var templateList: some View {
        if vm.templates.isEmpty && !vm.isLoading {
            Section {
                VStack(spacing: 8) {
                    Image(systemName: "doc.on.doc").font(.system(size: 34)).foregroundColor(.secondary)
                    Text(vm.templateType == 1 ? "还没有模板" : "还没有计划账单")
                        .font(.subheadline).foregroundColor(.secondary)
                    Text("点右上角 + 新建，或在新增交易时保存为模板")
                        .font(.footnote).foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .listRowBackground(Color.clear)
            }
        }

        ForEach(vm.templates, id: \.id) { template in
            HStack(spacing: 12) {
                Image(systemName: iconName(template))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(iconColor(template))
                    .cornerRadius(9)
                VStack(alignment: .leading, spacing: 2) {
                    Text(template.name)
                    HStack(spacing: 6) {
                        Text(vm.categoryName(template.categoryId))
                        Text("· \(vm.accountName(template.sourceAccountId))")
                    }
                    .font(.footnote).foregroundColor(.secondary)
                }
                Spacer()
                Text(AmountFormat.format(template.sourceAmount))
                    .font(.system(.body, design: .rounded))
            }
            .contentShape(Rectangle())
            .onTapGesture { editingTemplate = template }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(role: .destructive) { Task { await vm.delete(template) } } label: {
                    Label("删除", systemImage: "trash")
                }
                Button { Task { await vm.toggleHide(template) } } label: {
                    Label(template.hidden ?? false ? "显示" : "隐藏",
                          systemImage: template.hidden ?? false ? "eye" : "eye.slash")
                }
                .tint(.gray)
            }
        }

        if let error = vm.error {
            Section { Text(error).foregroundColor(.red).font(.footnote) }
        }
    }

    /// 分期账单列表
    @ViewBuilder
    private var installmentList: some View {
        if vm.plans.isEmpty && !vm.isLoading {
            Section {
                VStack(spacing: 8) {
                    Image(systemName: "repeat").font(.system(size: 34)).foregroundColor(.secondary)
                    Text("还没有分期账单")
                        .font(.subheadline).foregroundColor(.secondary)
                    Text("点右上角 + 新建，或在「记一笔」时打开「分期」")
                        .font(.footnote).foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .listRowBackground(Color.clear)
            }
        }

        ForEach(vm.plans, id: \.id) { plan in
            Button {
                detailPlan = plan
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "repeat")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 32, height: 32)
                        .background(plan.transactionType == .income ? Theme.income : Theme.expense)
                        .cornerRadius(9)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(plan.name)
                            .foregroundColor(.primary)
                        HStack(spacing: 6) {
                            Text(vm.categoryName(plan.categoryId))
                            Text("· \(vm.accountName(plan.sourceAccountId))")
                        }
                        .font(.footnote).foregroundColor(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(AmountFormat.format(plan.periodAmount))
                            .font(.system(.body, design: .rounded))
                            .foregroundColor(.primary)
                        Text(plan.isFinished ? "已完成" : "已入账 \(plan.paidPeriods)/\(plan.totalPeriods) 期")
                            .font(.footnote)
                            .foregroundColor(plan.isFinished ? Theme.income : .secondary)
                    }
                }
            }
            .buttonStyle(.plain)
        }

        if let error = vm.error {
            Section { Text(error).foregroundColor(.red).font(.footnote) }
        }
    }

    private func iconName(_ t: TransactionTemplate) -> String {
        switch t.transactionType {
        case .income: return "arrow.down.left"
        case .transfer: return "arrow.left.arrow.right"
        case .modifyBalance: return "equal.circle"
        case .expense: return "arrow.up.right"
        }
    }

    private func iconColor(_ t: TransactionTemplate) -> Color {
        switch t.transactionType {
        case .income: return Theme.income
        case .transfer: return .gray
        case .modifyBalance: return Theme.brand
        case .expense: return Theme.expense
        }
    }
}
