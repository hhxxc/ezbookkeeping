import SwiftUI
import Combine

/// 分类管理：支出 / 收入分类的增删改、显隐、排序（对齐 Web 分类管理页）
@MainActor
final class CategoriesViewModel: ObservableObject {
    @Published var categories: [TransactionCategory] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var type: Int = TransactionCategoryType.expense.rawValue

    func load() async {
        isLoading = true
        error = nil
        do {
            let all: [TransactionCategory] = try await APIClient.shared.request(
                "/api/v1/transaction/categories/list.json",
                query: [URLQueryItem(name: "type", value: "\(type)")]
            )
            // 后端按 parent_id 分组返回；这里把子分类挂回父分类便于展示
            categories = all
            isLoading = false
        } catch {
            isLoading = false
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// 一级分类（含其子分类）
    var topLevel: [TransactionCategory] {
        categories.filter { ($0.parentId ?? "0") == "0" || ($0.parentId ?? "") == "" }
            .sorted { ($0.displayOrder ?? 0) < ($1.displayOrder ?? 0) }
    }

    func add(_ req: CategoryCreateRequest) async {
        do {
            let _: EmptyResult = try await APIClient.shared.request(
                "/api/v1/transaction/categories/add.json", method: .POST, body: req
            )
            await load()
        } catch {
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    func modify(_ req: CategoryModifyRequest) async {
        do {
            let _: EmptyResult = try await APIClient.shared.request(
                "/api/v1/transaction/categories/modify.json", method: .POST, body: req
            )
            await load()
        } catch {
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    func toggleHide(_ cat: TransactionCategory) async {
        do {
            let _: EmptyResult = try await APIClient.shared.request(
                "/api/v1/transaction/categories/hide.json", method: .POST,
                body: CategoryHideRequest(id: cat.id, hidden: !(cat.hidden ?? false))
            )
            await load()
        } catch {
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    func delete(_ cat: TransactionCategory) async {
        do {
            let _: EmptyResult = try await APIClient.shared.request(
                "/api/v1/transaction/categories/delete.json", method: .POST,
                body: CategoryIdRequest(id: cat.id)
            )
            await load()
        } catch {
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }
}

struct CategoriesView: View {
    @StateObject private var vm = CategoriesViewModel()
    @State private var editing: TransactionCategory?
    @State private var addingTo: TransactionCategory?   // 非 nil 表示新增子分类
    @State private var showAddRoot = false

    var body: some View {
        List {
            Picker("类型", selection: $vm.type) {
                Text("支出").tag(TransactionCategoryType.expense.rawValue)
                Text("收入").tag(TransactionCategoryType.income.rawValue)
                Text("转账").tag(TransactionCategoryType.transfer.rawValue)
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)
            .onChange(of: vm.type) { _ in Task { await vm.load() } }

            ForEach(vm.topLevel, id: \.id) { cat in
                Section {
                    categoryRow(cat, isSub: false)
                    if let subs = cat.subCategories {
                        ForEach(subs, id: \.id) { sub in
                            categoryRow(sub, isSub: true)
                        }
                    }
                    Button {
                        addingTo = cat
                    } label: {
                        Label("添加子分类", systemImage: "plus.circle")
                            .font(.subheadline)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("分类管理")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showAddRoot = true } label: { Image(systemName: "plus") }
            }
        }
        .refreshable { await vm.load() }
        .sheet(isPresented: $showAddRoot) {
            CategoryEditView(category: nil, type: vm.type, parentId: "0")
        }
        .sheet(item: $editing) { cat in
            CategoryEditView(category: cat, type: vm.type, parentId: cat.parentId ?? "0")
        }
        .sheet(item: $addingTo) { parent in
            CategoryEditView(category: nil, type: vm.type, parentId: parent.id)
        }
        .task { await vm.load() }
    }

    private func categoryRow(_ cat: TransactionCategory, isSub: Bool) -> some View {
        HStack(spacing: 12) {
            if isSub { Spacer().frame(width: 18) }
            Image(systemName: CategoryIconCatalog.symbol(cat.icon))
                .foregroundColor(.white)
                .font(.system(size: 13))
                .frame(width: isSub ? 28 : 32, height: isSub ? 28 : 32)
                .background(Circle().fill(Color(hex: cat.color ?? "26A69A")))
            Text(cat.name)
            if cat.hidden ?? false {
                Text("已隐藏").font(.caption2).foregroundColor(.secondary)
            }
            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture { editing = cat }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) { Task { await vm.delete(cat) } } label: {
                Label("删除", systemImage: "trash")
            }
            Button { Task { await vm.toggleHide(cat) } } label: {
                Label(cat.hidden ?? false ? "显示" : "隐藏",
                      systemImage: cat.hidden ?? false ? "eye" : "eye.slash")
            }
            .tint(.gray)
        }
    }
}

// MARK: - 分类编辑

struct CategoryEditView: View {
    let category: TransactionCategory?
    let type: Int
    let parentId: String

    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var icon = 1
    @State private var color = "26A69A"
    @State private var comment = ""
    @State private var hidden = false
    @State private var isSaving = false
    @State private var error: String?

    private var isEdit: Bool { category != nil }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("名称")) {
                    TextField("分类名称", text: $name)
                }
                Section(header: Text("图标")) {
                    CategoryIconGrid(selected: $icon)
                }
                Section(header: Text("颜色")) {
                    CategoryColorGrid(selected: $color)
                }
                Section(header: Text("备注")) {
                    TextField("可选", text: $comment)
                }
                if isEdit {
                    Section { Toggle("隐藏分类", isOn: $hidden) }
                }
                if let error = error {
                    Section { Text(error).foregroundColor(.red).font(.footnote) }
                }
            }
            .navigationTitle(isEdit ? "编辑分类" : "新增分类")
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
            .onAppear {
                guard let c = category else { return }
                name = c.name
                icon = Int(c.icon ?? "1") ?? 1
                color = c.color ?? "26A69A"
                comment = c.comment ?? ""
                hidden = c.hidden ?? false
            }
        }
    }

    private func save() async {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            error = "请输入分类名称"
            return
        }
        isSaving = true
        error = nil
        do {
            if let c = category {
                let req = CategoryModifyRequest(
                    id: c.id, name: name, parentId: c.parentId ?? parentId,
                    icon: "\(icon)", color: color, comment: comment, hidden: hidden
                )
                let _: EmptyResult = try await APIClient.shared.request(
                    "/api/v1/transaction/categories/modify.json", method: .POST, body: req
                )
            } else {
                let req = CategoryCreateRequest(
                    name: name, type: type, parentId: parentId,
                    icon: "\(icon)", color: color, comment: comment
                )
                let _: EmptyResult = try await APIClient.shared.request(
                    "/api/v1/transaction/categories/add.json", method: .POST, body: req
                )
            }
            isSaving = false
            dismiss()
        } catch {
            isSaving = false
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }
}

private struct CategoryIconGrid: View {
    @Binding var selected: Int
    private let columns = [GridItem(.adaptive(minimum: 50), spacing: 10)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(CategoryIconCatalog.options, id: \.0) { item in
                Button { selected = item.0 } label: {
                    Image(systemName: item.1)
                        .font(.system(size: 17))
                        .foregroundColor(selected == item.0 ? .white : .primary)
                        .frame(width: 42, height: 42)
                        .background(Circle().fill(selected == item.0 ? Theme.brand : Color(.tertiarySystemFill)))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct CategoryColorGrid: View {
    @Binding var selected: String
    private let columns = [GridItem(.adaptive(minimum: 44), spacing: 10)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(AccountColorCatalog.all, id: \.self) { hex in
                Button { selected = hex } label: {
                    ZStack {
                        Circle().fill(Color(hex: hex)).frame(width: 32, height: 32)
                        if selected == hex {
                            Image(systemName: "checkmark")
                                .font(.system(size: 13, weight: .bold)).foregroundColor(.white)
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
