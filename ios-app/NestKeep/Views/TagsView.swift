import SwiftUI
import Combine

/// 标签图标：有自定义图标（icon 为目录内编号）时用白色 SF Symbol + 彩色圆底，否则青绿 tag.fill（对齐分类行样式）
struct TagIconView: View {
    let icon: String?
    let color: String?
    var size: CGFloat = 26

    private var customSymbol: String? {
        guard let icon, !icon.isEmpty, icon != "0", let n = Int(icon) else { return nil }
        return CategoryIconCatalog.options.first { $0.0 == n }?.1
    }

    private var fillColor: Color {
        guard customSymbol != nil else { return Theme.brand }
        guard let color, !color.isEmpty else { return Theme.brand }
        return Color(hex: color)
    }

    var body: some View {
        ZStack {
            Circle().fill(fillColor)
                .frame(width: size, height: size)
            Image(systemName: customSymbol ?? "tag.fill")
                .font(.system(size: size * 0.44))
                .foregroundColor(.white)
        }
    }
}

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

    func addTag(name: String, groupId: String, icon: String?, color: String?) async {
        do {
            let _: EmptyResult = try await APIClient.shared.request(
                "/api/v1/transaction/tags/add.json", method: .POST,
                body: TagCreateRequest(groupId: groupId, name: name,
                                       icon: icon ?? "0", color: color ?? "")
            )
            await load()
        } catch {
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    func renameTag(_ tag: TransactionTag, to name: String, icon: String?, color: String?) async {
        do {
            let _: EmptyResult = try await APIClient.shared.request(
                "/api/v1/transaction/tags/modify.json", method: .POST,
                body: TagModifyRequest(id: tag.id, groupId: tag.groupId ?? "0", name: name,
                                       icon: icon ?? tag.icon ?? "0",
                                       color: color ?? tag.color ?? "")
            )
            await load()
        } catch {
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// 移动标签到指定标签组（groupId 传 "0" 即移回「未分组」），其余字段保持原值
    func moveTag(_ tag: TransactionTag, to groupId: String) async {
        do {
            let _: EmptyResult = try await APIClient.shared.request(
                "/api/v1/transaction/tags/modify.json", method: .POST,
                body: TagModifyRequest(id: tag.id, groupId: groupId, name: tag.name,
                                       icon: tag.icon ?? "0", color: tag.color ?? "")
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

    func deleteGroup(_ group: TransactionTagGroup) async {
        do {
            let _: EmptyResult = try await APIClient.shared.request(
                "/api/v1/transaction/tags/groups/delete.json", method: .POST,
                body: TagGroupDeleteRequest(id: group.id)
            )
            await load()
        } catch {
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// 保存标签组排序
    func saveGroupOrder(_ ordered: [TransactionTagGroup]) async {
        let req = TagGroupMoveRequest(newDisplayOrders: ordered.enumerated().map {
            TagGroupNewDisplayOrderRequest(id: $0.element.id, displayOrder: $0.offset)
        })
        do {
            let _: EmptyResult = try await APIClient.shared.request(
                "/api/v1/transaction/tags/groups/move.json", method: .POST, body: req
            )
            await load()
        } catch {
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// 保存某个标签组内标签的排序
    func saveTagOrder(_ ordered: [TransactionTag]) async {
        let req = TagMoveRequest(newDisplayOrders: ordered.enumerated().map {
            TagNewDisplayOrderRequest(id: $0.element.id, displayOrder: $0.offset)
        })
        do {
            let _: EmptyResult = try await APIClient.shared.request(
                "/api/v1/transaction/tags/move.json", method: .POST, body: req
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
    @State private var isSorting = false
    @State private var sortGroups: [TransactionTagGroup] = []
    @State private var sortTags: [TransactionTag] = []
    @State private var groupToDelete: TransactionTagGroup?
    @State private var tagToMove: TransactionTag?

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

    /// 排序模式下所有可见标签（按当前分组顺序拍平）
    private var flatVisibleTags: [TransactionTag] {
        vm.sections.flatMap { $0.tags }
    }

    var body: some View {
        List {
            if isSorting {
                Section(header: Text("标签组排序")) {
                    ForEach(sortGroups, id: \.id) { group in
                        HStack {
                            Image(systemName: "folder.fill").foregroundColor(Theme.brand).font(.system(size: 13))
                            Text(group.name)
                            Spacer()
                        }
                    }
                    .onMove { from, to in sortGroups.move(fromOffsets: from, toOffset: to) }
                }
                Section(header: Text("标签排序")) {
                    ForEach(sortTags, id: \.id) { tag in
                        HStack {
                            TagIconView(icon: tag.icon, color: tag.color)
                            Text(tag.name)
                            Spacer()
                        }
                    }
                    .onMove { from, to in sortTags.move(fromOffsets: from, toOffset: to) }
                }
            } else {
                ForEach(vm.sections) { section in
                    Section(header: Text(section.name)) {
                        ForEach(section.tags, id: \.id) { tag in
                            HStack {
                                TagIconView(icon: tag.icon, color: tag.color)
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
                                if !vm.groups.isEmpty {
                                    Button { tagToMove = tag } label: {
                                        Label("移动", systemImage: "folder")
                                    }
                                    .tint(Theme.brand)
                                }
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

                if !vm.groups.isEmpty {
                    Section(header: Text("标签组")) {
                        ForEach(vm.groups.sorted { ($0.displayOrder ?? 0) < ($1.displayOrder ?? 0) }, id: \.id) { group in
                            HStack {
                                Image(systemName: "folder.fill").foregroundColor(Theme.brand).font(.system(size: 13))
                                Text(group.name)
                                Spacer()
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { input = TagInput(kind: .renameGroup(group)) }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) { groupToDelete = group } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .environment(\.editMode, .constant(isSorting ? EditMode.active : EditMode.inactive))
        .navigationTitle("标签管理")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if isSorting {
                    Button("完成") { finishSorting() }
                } else {
                    Button("排序") {
                        sortGroups = vm.groups.sorted { ($0.displayOrder ?? 0) < ($1.displayOrder ?? 0) }
                        sortTags = flatVisibleTags
                        isSorting = true
                    }
                }
            }
        }
        .refreshable { await vm.load() }
        .sheet(item: $input) { ctx in
            TagInputSheet(context: ctx) { name, icon, color in
                switch ctx.kind {
                case .addTag(let groupId): await vm.addTag(name: name, groupId: groupId, icon: icon, color: color)
                case .addGroup: await vm.addGroup(name: name)
                case .renameTag(let tag): await vm.renameTag(tag, to: name, icon: icon, color: color)
                case .renameGroup(let group): await vm.renameGroup(group, to: name)
                }
            }
        }
        .sheet(item: $tagToMove) { tag in
            MoveTagSheet(tagName: tag.name,
                         currentGroupId: tag.groupId ?? "0",
                         groups: vm.groups.sorted { ($0.displayOrder ?? 0) < ($1.displayOrder ?? 0) }) { target in
                await vm.moveTag(tag, to: target)
            }
        }
        .confirmationDialog("删除标签组？", isPresented: Binding(
            get: { groupToDelete != nil },
            set: { if !$0 { groupToDelete = nil } }
        ), titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                if let g = groupToDelete { Task { await vm.deleteGroup(g) } }
                groupToDelete = nil
            }
            Button("取消", role: .cancel) { groupToDelete = nil }
        } message: {
            Text("组内标签不会被删除，会移动到「未分组」。")
        }
        .task { await vm.load() }
    }

    private func finishSorting() {
        let groups = sortGroups
        let tags = sortTags
        isSorting = false
        Task {
            await vm.saveGroupOrder(groups)
            await vm.saveTagOrder(tags)
        }
    }
}

/// 标签名输入弹层（替代 iOS 16+ 的 alert TextField）；标签类弹层附带图标/颜色选择
struct TagInputSheet: View {
    let context: TagsView.TagInput
    /// name + 可选 icon/color（标签组等无图标上下文传 nil）
    let onSubmit: (String, String?, String?) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var icon = "0"
    @State private var color = ""
    @State private var isSaving = false

    private var isTagContext: Bool {
        switch context.kind {
        case .addTag, .renameTag: return true
        default: return false
        }
    }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("名称", text: $text)
                }
                if isTagContext {
                    Section(header: Text("图标")) {
                        TagIconGrid(selected: $icon)
                    }
                    Section(header: Text("颜色")) {
                        TagColorGrid(selected: $color)
                    }
                }
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
                        let iconOut = isTagContext ? icon : nil
                        let colorOut = isTagContext ? color : nil
                        Task {
                            isSaving = true
                            await onSubmit(name, iconOut, colorOut)
                            isSaving = false
                            dismiss()
                        }
                    } label: {
                        if isSaving { ProgressView() } else { Text("保存").font(.body.weight(.semibold)) }
                    }
                    .disabled(isSaving)
                }
            }
            .onAppear {
                text = context.initial
                if case .renameTag(let t) = context.kind {
                    icon = t.icon ?? "0"
                    color = t.color ?? ""
                }
            }
        }
    }
}

/// 移动标签到分组的选择弹层（对齐 Web 的「移动到...」；含「未分组」可移回）
struct MoveTagSheet: View {
    let tagName: String
    let currentGroupId: String
    let groups: [TransactionTagGroup]
    let onMove: (String) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var target = ""
    @State private var isMoving = false

    var body: some View {
        NavigationView {
            List {
                Section(footer: Text("把「\(tagName)」移到选中的标签组")) {
                    ForEach(groups, id: \.id) { group in
                        row(group.id, name: group.name)
                    }
                    row("0", name: "未分组")
                }
            }
            .navigationTitle("移动到...")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task {
                            isMoving = true
                            await onMove(target)
                            isMoving = false
                            dismiss()
                        }
                    } label: {
                        if isMoving { ProgressView() } else { Text("移动").font(.body.weight(.semibold)) }
                    }
                    .disabled(isMoving || target.isEmpty || target == currentGroupId)
                }
            }
            .onAppear { target = currentGroupId }
        }
    }

    private func row(_ id: String, name: String) -> some View {
        Button {
            target = id
        } label: {
            HStack {
                Image(systemName: id == "0" ? "tray" : "folder.fill")
                    .foregroundColor(Theme.brand)
                    .font(.system(size: 13))
                Text(name).foregroundColor(.primary)
                Spacer()
                if target == id {
                    Image(systemName: "checkmark")
                        .foregroundColor(Theme.brand)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// 标签图标选择网格：首项「默认」(tag.fill 青绿) + 分类图标目录（对齐分类编辑的近似映射）
struct TagIconGrid: View {
    @Binding var selected: String

    private let columns = [GridItem(.adaptive(minimum: 52), spacing: 10)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            Button {
                selected = "0"
            } label: {
                ZStack {
                    Circle().fill(selected == "0" ? Theme.brand : Color(.tertiarySystemFill))
                        .frame(width: 44, height: 44)
                    Image(systemName: "tag.fill")
                        .font(.system(size: 17))
                        .foregroundColor(selected == "0" ? .white : .primary)
                }
            }
            .buttonStyle(.plain)

            ForEach(CategoryIconCatalog.options, id: \.0) { item in
                Button {
                    selected = String(item.0)
                } label: {
                    ZStack {
                        Circle().fill(selected == String(item.0) ? Theme.brand : Color(.tertiarySystemFill))
                            .frame(width: 44, height: 44)
                        Image(systemName: item.1)
                            .font(.system(size: 18))
                            .foregroundColor(selected == String(item.0) ? .white : .primary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }
}

/// 标签颜色选择网格：首项「默认」(主题青绿) + 常用色板
struct TagColorGrid: View {
    @Binding var selected: String

    private let columns = [GridItem(.adaptive(minimum: 44), spacing: 10)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            Button {
                selected = ""
            } label: {
                ZStack {
                    Circle().fill(Theme.brand)
                        .frame(width: 32, height: 32)
                    if selected == "" {
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)

            ForEach(AccountColorCatalog.all, id: \.self) { hex in
                Button {
                    selected = hex
                } label: {
                    ZStack {
                        Circle().fill(Color(hex: hex))
                            .frame(width: 32, height: 32)
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
