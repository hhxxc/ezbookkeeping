import SwiftUI
import Combine

/// 模板与计划账单（对齐 Web 的模板 / 计划账单列表）
@MainActor
final class TemplatesViewModel: ObservableObject {
    /// 1=普通模板 2=计划账单
    @Published var templateType = 1
    @Published var templates: [TransactionTemplate] = []
    @Published var categories: [TransactionCategory] = []
    @Published var accounts: [Account] = []
    @Published var isLoading = false
    @Published var error: String?

    func load() async {
        isLoading = true
        error = nil
        do {
            async let t: [TransactionTemplate] = APIClient.shared.request(
                "/api/v1/transaction/templates/list.json",
                query: [URLQueryItem(name: "templateType", value: "\(templateType)")]
            )
            async let c: [TransactionCategory] = APIClient.shared.request("/api/v1/transaction/categories/list.json")
            async let a: [Account] = APIClient.shared.request("/api/v1/accounts/list.json")
            templates = (try? await t) ?? []
            categories = (try? await c) ?? []
            accounts = (try? await a) ?? []
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
    let scheduledStartDate: String?
    let scheduledEndDate: String?
    let displayOrder: Int?
    let hidden: Bool?

    var transactionType: TransactionType { TransactionType(rawValue: type) ?? .expense }
}

struct TemplateIdRequest: Codable { let id: String }
struct TemplateHideRequest: Codable { let id: String; let hidden: Bool }

struct TemplatesView: View {
    @StateObject private var vm = TemplatesViewModel()

    var body: some View {
        List {
            Picker("类型", selection: $vm.templateType) {
                Text("模板").tag(1)
                Text("计划账单").tag(2)
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)
            .onChange(of: vm.templateType) { _ in Task { await vm.load() } }

            if vm.templates.isEmpty && !vm.isLoading {
                Section {
                    VStack(spacing: 8) {
                        Image(systemName: "doc.on.doc").font(.system(size: 34)).foregroundColor(.secondary)
                        Text(vm.templateType == 1 ? "还没有模板" : "还没有计划账单")
                            .font(.subheadline).foregroundColor(.secondary)
                        Text("可在网页端创建，或在新增交易时保存为模板")
                            .font(.caption2).foregroundColor(.secondary)
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
                        .font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                    Text(AmountFormat.format(template.sourceAmount))
                        .font(.system(.body, design: .rounded))
                }
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
        .listStyle(.insetGrouped)
        .navigationTitle("模板与计划账单")
        .refreshable { await vm.load() }
        .task { await vm.load() }
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
