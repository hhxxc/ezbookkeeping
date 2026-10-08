import SwiftUI
import Combine

/// 「默认分类」一键导入：对齐 Web `categories/PresetPage.vue`。
/// 展示内置预设分类（对齐 Web `src/consts/category.ts`），确认后批量导入：
/// `POST /api/v1/transaction/categories/add_batch.json`
/// body `{categories: [{name,type,icon,color,comment,subCategories:[{name,type,parentId,icon,color,comment}]}]}`
/// 注意 icon 为 `json:",string"`，必须发字符串。
struct PresetCategoriesView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTypes: Set<Int> = [1, 2]
    @State private var isSubmitting = false
    @State private var error: String?
    @State private var done = false

    private var groups: [(type: Int, name: String, categories: [PresetCategory])] {
        PresetCategoryCatalog.typeNames.map { (type: $0.0, name: $0.1, categories: PresetCategoryCatalog.categories(type: $0.0)) }
    }

    private var totalCount: Int {
        groups.filter { selectedTypes.contains($0.type) }
            .reduce(0) { $0 + $1.categories.count }
    }

    var body: some View {
        List {
            Section {
                ForEach(PresetCategoryCatalog.typeNames, id: \.0) { item in
                    Button {
                        if selectedTypes.contains(item.0) { selectedTypes.remove(item.0) }
                        else { selectedTypes.insert(item.0) }
                    } label: {
                        HStack {
                            Text(item.1).foregroundColor(.primary)
                            Spacer()
                            Text("\(PresetCategoryCatalog.categories(type: item.0).count) 个")
                                .font(.caption).foregroundColor(.secondary)
                            Image(systemName: selectedTypes.contains(item.0) ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(selectedTypes.contains(item.0) ? Theme.brand : .secondary)
                        }
                    }
                }
            } header: {
                Text("选择要导入的分类类型")
            } footer: {
                Text("将把所选类型的预设分类（含子分类）导入到你的账户，已存在的同名分类不会重复导入。")
            }

            ForEach(groups.filter { selectedTypes.contains($0.type) }, id: \.type) { group in
                Section(header: Text(group.name)) {
                    ForEach(group.categories) { cat in
                        DisclosureGroup {
                            ForEach(cat.subCategories) { sub in
                                HStack(spacing: 10) {
                                    Image(systemName: CategoryIconCatalog.symbol("\(sub.icon)"))
                                        .foregroundColor(.white)
                                        .font(.system(size: 11))
                                        .frame(width: 24, height: 24)
                                        .background(Circle().fill(Color(hex: sub.color)))
                                    Text(sub.name).font(.subheadline)
                                }
                            }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: CategoryIconCatalog.symbol("\(cat.icon)"))
                                    .foregroundColor(.white)
                                    .font(.system(size: 13))
                                    .frame(width: 30, height: 30)
                                    .background(Circle().fill(Color(hex: cat.color)))
                                Text(cat.name)
                            }
                        }
                    }
                }
            }

            if let error = error {
                Section { Text(error).foregroundColor(.red).font(.footnote) }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("默认分类")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    Task { await submit() }
                } label: {
                    if isSubmitting { ProgressView() } else { Text("导入").bold() }
                }
                .disabled(isSubmitting || selectedTypes.isEmpty)
            }
        }
        .alert("导入完成", isPresented: $done) {
            Button("好") { dismiss() }
        } message: {
            Text("已导入所选预设分类。")
        }
    }

    private func submit() async {
        isSubmitting = true
        error = nil
        do {
            let payload = buildPayload()
            let req = CategoryBatchCreateRequest(categories: payload)
            let _: EmptyResult = try await APIClient.shared.request(
                "/api/v1/transaction/categories/add_batch.json", method: .POST, body: req
            )
            isSubmitting = false
            done = true
        } catch {
            isSubmitting = false
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func buildPayload() -> [CategoryBatchItem] {
        var result: [CategoryBatchItem] = []
        for group in groups where selectedTypes.contains(group.type) {
            for cat in group.categories {
                let subs = cat.subCategories.map { sub in
                    CategoryBatchSubItem(name: sub.name, type: group.type,
                                         parentId: "0", icon: "\(sub.icon)", color: sub.color, comment: "")
                }
                result.append(CategoryBatchItem(name: cat.name, type: group.type,
                                                icon: "\(cat.icon)", color: cat.color,
                                                comment: "", subCategories: subs))
            }
        }
        return result
    }
}

// MARK: - 批量创建请求模型
// 对应 Go TransactionCategoryCreateBatchRequest /
// TransactionCategoryCreateWithSubCategories / TransactionCategoryCreateRequest

struct CategoryBatchCreateRequest: Codable {
    let categories: [CategoryBatchItem]
}

struct CategoryBatchItem: Codable {
    let name: String
    let type: Int
    let icon: String        // json:",string"
    let color: String
    let comment: String
    let subCategories: [CategoryBatchSubItem]
}

struct CategoryBatchSubItem: Codable {
    let name: String
    let type: Int
    let parentId: String
    let icon: String        // json:",string"
    let color: String
    let comment: String
}
