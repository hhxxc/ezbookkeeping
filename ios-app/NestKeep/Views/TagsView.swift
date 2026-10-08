import SwiftUI
import Combine

/// 标签管理：标签组 + 标签的增删改、显隐（对齐 Web 的标签管理页）
@MainActor
final class TagsViewModel: ObservableObject {
    @Published var tags: [TransactionTag] = []
    @Published var groups: [TransactionTagGroup] = []
    @Published var isLoading = false
    @Published var error: String?

    func load() async {
        isLoading = true
        error = nil
        do {
            async let t: [TransactionTag] = APIClient.shared.request("/api/v1/transaction/tags/list.json")
            async let g: [TransactionTagGroup] = APIClient.shared.request("/api/v1/transaction/tags/groups/list.json")
            tags = (try? await t) ?? []
            groups = (try? await g) ?? []
            isLoading = false
        } catch {
            isLoading = false
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    var sections: [TagSection] { TagGrouping.sections(tags: tags, groups: groups) }

    func addTag(name: String, groupId: String) async {
        do {
            let _: EmptyResult = try await APIClient.shared.request(
                "/api/v1/transaction/tags/add.json", method: .POST,
                body: TagCreateRequest(groupId: groupId, name: name)
            )
            await load()
        } catch {
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    func renameTag(_ tag: TransactionTag, to name: String) async {
        do {
            let _: EmptyResult = try await APIClient.shared.request(
                "/api/v1/transaction/tags/modify.json", method: .POST,
                body: TagModifyRequest(id: tag.id, groupId: tag.groupId ?? "0", name: name)
            )
            await load()
        } catch {
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    func toggleHideTag(_ tag: TransactionTag) async {
        do {
            let _: EmptyResult = try await APIClient.shared.request(
                "/api/v1/transaction/tags/hide.json", method: .POST,
                body: TagHideRequest(id: tag.id, hidden: !(tag.hidden ?? false))
            )
            await load()
        } catch {
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    func deleteTag(_ tag: TransactionTag) async {
        do {
            let _: EmptyResult = try await APIClient.shared.request(
                "/api/v1/transaction/tags/delete.json", method: .POST, body: TagIdRequest(id: tag.id)
            )
            await load()
        } catch {
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    func addGroup(name: String) async {
        do {
            let _: EmptyResult = try await APIClient.shared.request(
                "/api/v1/transaction/tags/groups/add.json", method: .POST,
                body: TagGroupCreateRequest(name: name)
            )
            await load()
        } catch {
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    func renameGroup(_ group: TransactionTagGroup, to name: String) async {
        do {
            let _: EmptyResult = try await APIClient.shared.request(
                "/api/v1/transaction/tags/groups/modify.json", method: .POST,
                body: TagGroupModifyRequest(id: group.id, name: name)
            )
            await load()
        } catch {
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }
}

struct TagsView: View {
    @StateObject private var vm = TagsViewModel()
    @State private var input: TagInput?

    /// 输入弹层上下文（iOS 15 的 alert 不支持 TextField，改用 sheet）
    struct TagInput: Identifiable {
        enum Kind { case addTag(groupId: String), addGroup, renameTag(TransactionTag), renameGroup(TransactionTagGroup) }
        let id = UUID()
        let kind: Kind
        var title: String {
            switch kind {
            case .addTag: return "新建标签"
            case .addGroup: return "新建标签组"
            case .renameTag: return "重命名标签"
            case .renameGroup: return "重命名标签组"
            }
        }
        var initial: String {
            switch kind {
            case .renameTag(let t): return t.name
            case .renameGroup(let g): return g.name
            default: return ""
            }
        }
    }

    var body: some View {
        List {
            ForEach(vm.sections) { section in
                Section(header: Text(section.name)) {
                    ForEach(section.tags, id: \.id) { tag in
                        HStack {
                            Image(systemName: "tag.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.white)
                                .frame(width: 26, height: 26)
                                .background(Circle().fill(Theme.brand))
                            Text(tag.name)
                            if tag.hidden ?? false {
                                Text("已隐藏").font(.caption2).foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { input = TagInput(kind: .renameTag(tag)) }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) { Task { await vm.deleteTag(tag) } } label: {
                                Label("删除", systemImage: "trash")
                            }
                            Button { Task { await vm.toggleHideTag(tag) } } label: {
                                Label(tag.hidden ?? false ? "显示" : "隐藏",
                                      systemImage: tag.hidden ?? false ? "eye" : "eye.slash")
                            }
                            .tint(.gray)
                        }
                    }
                    Button {
                        input = TagInput(kind: .addTag(groupId: section.id))
                    } label: {
                        Label("添加标签", systemImage: "plus.circle").font(.subheadline)
                    }
                }
            }

            if vm.sections.isEmpty && !vm.isLoading {
                Section {
                    VStack(spacing: 8) {
                        Image(systemName: "tag").font(.system(size: 34)).foregroundColor(.secondary)
                        Text("还没有标签").font(.subheadline).foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .listRowBackground(Color.clear)
                }
            }

            Section {
                Button {
                    input = TagInput(kind: .addGroup)
                } label: {
                    Label("新建标签组", systemImage: "folder.badge.plus")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("标签管理")
        .refreshable { await vm.load() }
        .sheet(item: $input) { ctx in
            TagInputSheet(context: ctx) { name in
                switch ctx.kind {
                case .addTag(let groupId): await vm.addTag(name: name, groupId: groupId)
                case .addGroup: await vm.addGroup(name: name)
                case .renameTag(let tag): await vm.renameTag(tag, to: name)
                case .renameGroup(let group): await vm.renameGroup(group, to: name)
                }
            }
        }
        .task { await vm.load() }
    }
}

/// 标签名输入弹层（替代 iOS 16+ 的 alert TextField）
struct TagInputSheet: View {
    let context: TagsView.TagInput
    let onSubmit: (String) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var isSaving = false

    var body: some View {
        NavigationView {
            Form {
                TextField("名称", text: $text)
            }
            .navigationTitle(context.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        let name = text
                        Task {
                            isSaving = true
                            await onSubmit(name)
                            isSaving = false
                            dismiss()
                        }
                    } label: {
                        if isSaving { ProgressView() } else { Text("保存").font(.body.weight(.semibold)) }
                    }
                    .disabled(isSaving)
                }
            }
            .onAppear { text = context.initial }
        }
    }
}
