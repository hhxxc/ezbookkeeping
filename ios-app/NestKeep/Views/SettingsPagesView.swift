import SwiftUI
import Combine

// MARK: - 页面设置（对齐 Web `settings/PageSettingsPage.vue`）
/// 覆盖首页/账单列表/编辑页各自的行为开关，写入云同步设置。
struct PageSettingsView: View {
    @ObservedObject private var store = CloudSettingsStore.shared
    @Environment(\.mainTabBarInset) private var tabBarInset

    /// 时区统计方式（对应 Web `timezoneUsedForStatisticsInHomePage`）
    private static let timezoneOptions: [(Int, String)] = [
        (0, "默认时区"),
        (1, "交易时区")
    ]

    var body: some View {
        List {
            Section(header: Text("概览页")) {
                toggleRow("显示金额", key: "showAmountInHomePage", default: true)
                Picker("统计时区", selection: Binding(
                    get: { store.int("timezoneUsedForStatisticsInHomePage", default: 0) },
                    set: { v in Task { await store.set("timezoneUsedForStatisticsInHomePage", "\(v)") } }
                )) {
                    ForEach(Self.timezoneOptions, id: \.0) { Text($0.1).tag($0.0) }
                }
            }

            Section(header: Text("账单列表页")) {
                Picker("每页条数", selection: Binding(
                    get: { store.int("itemsCountInTransactionListPage", default: 20) },
                    set: { v in Task { await store.set("itemsCountInTransactionListPage", "\(v)") } }
                )) {
                    ForEach([10, 20, 50, 100], id: \.self) { Text("\($0) 条").tag($0) }
                }
                toggleRow("显示合计金额", key: "showTotalAmountInTransactionListPage", default: true)
                toggleRow("显示标签", key: "showTagInTransactionListPage", default: true)
            }

            Section(header: Text("交易编辑页")) {
                toggleRow("自动保存草稿", key: "autoSaveTransactionDraft", default: false,
                          rawValue: { $0 ? "true" : "false" })
                toggleRow("自动获取定位", key: "autoGetCurrentGeoLocation", default: false)
                toggleRow("默认显示交易图片", key: "alwaysShowTransactionPicturesInMobileTransactionEditPage", default: false)
            }

            Section(header: Text("账户列表页")) {
                toggleRow("隐藏无账户的类别", key: "hideCategoriesWithoutAccounts", default: false)
            }

            Section(header: Text("汇率页")) {
                Picker("排序方式", selection: Binding(
                    get: { store.int("currencySortByInExchangeRatesPage", default: 0) },
                    set: { v in Task { await store.set("currencySortByInExchangeRatesPage", "\(v)") } }
                )) {
                    Text("按货币代码").tag(0)
                    Text("按汇率值").tag(1)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("页面设置")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) { Color.clear.frame(height: tabBarInset) }
        .task { await store.load() }
    }

    @ViewBuilder
    private func toggleRow(_ title: String, key: String, default def: Bool,
                           rawValue: @escaping (Bool) -> String = { $0 ? "true" : "false" }) -> some View {
        Toggle(title, isOn: Binding(
            get: { store.bool(key, default: def) },
            set: { v in Task { await store.set(key, rawValue(v)) } }
        ))
    }
}

// MARK: - 字号设置（对齐 Web `settings/TextSizeSettingsPage.vue`）
/// 本地设置（Web 存 localStorage），原生存 UserDefaults，并给出实时预览。
struct TextSizeSettingsView: View {
    @AppStorage("nestkeep.fontSize") private var fontSize = 1
    @Environment(\.mainTabBarInset) private var tabBarInset

    static let options: [(Int, String, CGFloat)] = [
        (0, "小", 0.85), (1, "标准", 1.0), (2, "大", 1.15), (3, "特大", 1.3)
    ]

    private var scale: CGFloat {
        Self.options.first { $0.0 == fontSize }?.2 ?? 1.0
    }

    var body: some View {
        List {
            Section(header: Text("字号")) {
                Picker("字号", selection: $fontSize) {
                    ForEach(Self.options, id: \.0) { Text($0.1).tag($0.0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
            }

            Section(header: Text("预览")) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("2026年10月").font(.system(size: 13 * scale)).foregroundColor(.secondary)
                    HStack {
                        Text("餐饮").font(.system(size: 17 * scale))
                        Spacer()
                        Text("-¥123.45")
                            .font(.system(size: 17 * scale, weight: .semibold))
                            .foregroundColor(HomePalette.expense)
                    }
                    HStack {
                        Text("工资").font(.system(size: 17 * scale))
                        Spacer()
                        Text("+¥8,000.00")
                            .font(.system(size: 17 * scale, weight: .semibold))
                            .foregroundColor(HomePalette.income)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("字号")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) { Color.clear.frame(height: tabBarInset) }
    }
}

// MARK: - 账户过滤器（对齐 Web `settings/AccountFilterSettingsPage.vue`）
/// 选择「哪些账户计入某处统计」。值形如 `{"accountId": true}` 的 JSON 字符串。
struct AccountFilterSettingsView: View {
    let type: String   // homePageOverview / statistics / ...
    let title: String
    /// 显式覆盖设置键（不传则按 `{type}AccountFilterInHomePage` 规则生成）
    var explicitKey: String? = nil

    @ObservedObject private var store = CloudSettingsStore.shared
    @Environment(\.mainTabBarInset) private var tabBarInset

    @State private var accounts: [Account] = []
    @State private var selection: [String: Bool] = [:]
    @State private var isLoading = true

    private var settingKey: String {
        explicitKey ?? "\(type)AccountFilterInHomePage"
    }

    var body: some View {
        List {
            Section(footer: Text("仅所选账户会计入统计。全不选表示不限制。")) {
                if isLoading {
                    ProgressView()
                } else {
                    ForEach(accounts, id: \.id) { acc in
                        Button {
                            selection[acc.id] = !(selection[acc.id] ?? false)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: AccountIconCatalog.symbol(acc.icon))
                                    .foregroundColor(.white)
                                    .font(.system(size: 13))
                                    .frame(width: 28, height: 28)
                                    .background(Circle().fill(Color(hex: acc.color ?? "26A69A")))
                                Text(acc.name).foregroundColor(.primary)
                                Spacer()
                                Image(systemName: (selection[acc.id] ?? false) ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor((selection[acc.id] ?? false) ? Theme.brand : .secondary)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    Task { await save() }
                } label: {
                    Text("保存").bold()
                }
            }
            ToolbarItem(placement: .navigationBarLeading) {
                Menu {
                    Button("全选") { for a in accounts { selection[a.id] = true } }
                    Button("全不选") { for a in accounts { selection[a.id] = false } }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .safeAreaInset(edge: .bottom) { Color.clear.frame(height: tabBarInset) }
        .task { await load() }
    }

    private func load() async {
        await store.load()
        selection = Self.decode(store.string(settingKey))
        do {
            accounts = try await APIClient.shared.request("/api/v1/accounts/list.json")
        } catch {
            accounts = []
        }
        isLoading = false
    }

    private func save() async {
        let json = Self.encode(selection)
        await store.set(settingKey, json)
    }

    static func decode(_ raw: String) -> [String: Bool] {
        guard let data = raw.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Bool] else { return [:] }
        return obj
    }

    static func encode(_ map: [String: Bool]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: map),
              let s = String(data: data, encoding: .utf8) else { return "{}" }
        return s
    }
}

// MARK: - 分类过滤器（对齐 Web `settings/CategoryFilterSettingsPage.vue`）
struct CategoryFilterSettingsView: View {
    let type: String
    let title: String
    /// 显式覆盖设置键（不传则按 `{type}TransactionCategoryFilterInHomePage` 规则生成）
    var explicitKey: String? = nil

    @ObservedObject private var store = CloudSettingsStore.shared
    @Environment(\.mainTabBarInset) private var tabBarInset

    @State private var categories: [TransactionCategory] = []
    @State private var selection: [String: Bool] = [:]
    @State private var isLoading = true

    private var settingKey: String { explicitKey ?? "\(type)TransactionCategoryFilterInHomePage" }

    /// 拍平一级 + 子分类
    private var flat: [TransactionCategory] {
        var arr: [TransactionCategory] = []
        for cat in categories {
            arr.append(cat)
            if let subs = cat.subCategories { arr.append(contentsOf: subs) }
        }
        return arr
    }

    var body: some View {
        List {
            Section(footer: Text("仅所选分类会计入统计。全不选表示不限制。")) {
                if isLoading {
                    ProgressView()
                } else {
                    ForEach(flat, id: \.id) { cat in
                        Button {
                            selection[cat.id] = !(selection[cat.id] ?? false)
                        } label: {
                            HStack(spacing: 10) {
                                if (cat.parentId ?? "0") != "0" { Spacer().frame(width: 16) }
                                Image(systemName: CategoryIconCatalog.symbol(cat.icon))
                                    .foregroundColor(.white)
                                    .font(.system(size: 11))
                                    .frame(width: 26, height: 26)
                                    .background(Circle().fill(Color(hex: cat.color ?? "26A69A")))
                                Text(cat.name).foregroundColor(.primary)
                                Spacer()
                                Image(systemName: (selection[cat.id] ?? false) ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor((selection[cat.id] ?? false) ? Theme.brand : .secondary)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { Task { await save() } } label: { Text("保存").bold() }
            }
            ToolbarItem(placement: .navigationBarLeading) {
                Menu {
                    Button("全选") { for c in flat { selection[c.id] = true } }
                    Button("全不选") { for c in flat { selection[c.id] = false } }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .safeAreaInset(edge: .bottom) { Color.clear.frame(height: tabBarInset) }
        .task { await load() }
    }

    private func load() async {
        await store.load()
        selection = AccountFilterSettingsView.decode(store.string(settingKey))
        do {
            categories = try await APIClient.shared.requestCategoryList()
        } catch {
            categories = []
        }
        isLoading = false
    }

    private func save() async {
        await store.set(settingKey, AccountFilterSettingsView.encode(selection))
    }
}

// MARK: - 标签过滤器（对齐 Web `settings/TransactionTagFilterSettingsPage.vue`）
/// 标签筛选用「包含/排除」三态：未选 / 包含(true) / 排除(false)。
struct TagFilterSettingsView: View {
    @ObservedObject private var store = CloudSettingsStore.shared
    @Environment(\.mainTabBarInset) private var tabBarInset

    @State private var tags: [TransactionTag] = []
    @State private var groups: [TransactionTagGroup] = []
    @State private var state: [String: Int] = [:]   // 0 未选 1 包含 2 排除
    @State private var isLoading = true

    private let settingKey = "statistics.defaultTransactionTagFilter"

    var body: some View {
        List {
            Section(footer: Text("「包含」只统计所选标签；「排除」统计除所选标签外的全部。")) {
                if isLoading {
                    ProgressView()
                } else {
                    ForEach(tags, id: \.id) { tag in
                        HStack(spacing: 10) {
                            Image(systemName: "tag.fill")
                                .font(.system(size: 11)).foregroundColor(.white)
                                .frame(width: 26, height: 26)
                                .background(Circle().fill(Theme.brand))
                            Text(tag.name)
                            Spacer()
                            Picker("", selection: Binding(
                                get: { state[tag.id] ?? 0 },
                                set: { state[tag.id] = $0 }
                            )) {
                                Text("未选").tag(0)
                                Text("包含").tag(1)
                                Text("排除").tag(2)
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("标签筛选")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { Task { await save() } } label: { Text("保存").bold() }
            }
        }
        .safeAreaInset(edge: .bottom) { Color.clear.frame(height: tabBarInset) }
        .task { await load() }
    }

    private func load() async {
        await store.load()
        let raw = store.string(settingKey)
        if let data = raw.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Bool] {
            for (k, v) in obj { state[k] = v ? 1 : 2 }
        }
        async let t: [TransactionTag] = APIClient.shared.request("/api/v1/transaction/tags/list.json")
        async let g: [TransactionTagGroup] = APIClient.shared.request("/api/v1/transaction/tags/groups/list.json")
        tags = (try? await t) ?? []
        groups = (try? await g) ?? []
        isLoading = false
    }

    private func save() async {
        var map: [String: Bool] = [:]
        for (k, v) in state where v != 0 { map[k] = (v == 1) }
        await store.set(settingKey, AccountFilterSettingsView.encode(map))
    }
}

// MARK: - 账户类别显示顺序（对齐 Web `settings/AccountCategoryDisplayOrderSettingsPage.vue`）
struct AccountCategoryOrderView: View {
    @ObservedObject private var store = CloudSettingsStore.shared
    @Environment(\.mainTabBarInset) private var tabBarInset

    @State private var order: [Int] = AccountCategoryConst.all.map { $0.0 }
    @State private var isEditing = false

    private let settingKey = "accountCategoryOrders"

    var body: some View {
        List {
            Section(footer: Text("拖动调整账户列表里各类别的显示顺序。")) {
                ForEach(order, id: \.self) { type in
                    HStack {
                        Image(systemName: "line.3.horizontal").foregroundColor(.secondary)
                        Text(AccountCategoryConst.name(type))
                    }
                }
                .onMove { from, to in
                    order.move(fromOffsets: from, toOffset: to)
                    isEditing = true
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("账户类别顺序")
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.editMode, .constant(.active))
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    Task { await save() }
                } label: { Text("保存").bold() }
                .disabled(!isEditing)
            }
            ToolbarItem(placement: .navigationBarLeading) {
                Button("重置") {
                    order = AccountCategoryConst.all.map { $0.0 }
                    isEditing = true
                }
            }
        }
        .safeAreaInset(edge: .bottom) { Color.clear.frame(height: tabBarInset) }
        .task { await load() }
    }

    private func load() async {
        await store.load()
        let raw = store.string(settingKey)
        let parts = raw.split(separator: ",").compactMap { Int($0) }
        if parts.count == AccountCategoryConst.all.count { order = parts }
    }

    private func save() async {
        await store.set(settingKey, order.map(String.init).joined(separator: ","))
        isEditing = false
    }
}

// MARK: - 云同步设置（对齐 Web `settings/ApplicationCloudSyncSettingsPage.vue`）
struct CloudSyncSettingsView: View {
    @ObservedObject private var store = CloudSettingsStore.shared
    @Environment(\.mainTabBarInset) private var tabBarInset
    @State private var showDisableConfirm = false

    var body: some View {
        List {
            Section {
                HStack {
                    Text("状态")
                    Spacer()
                    Text(store.enabled ? "已启用" : "未启用")
                        .foregroundColor(.secondary)
                }
            } footer: {
                Text("云同步会把部分应用设置（概览页、账单列表、编辑页等）保存到服务端，换设备登录后自动恢复。")
            }

            if store.enabled {
                Section(header: Text("已同步的设置")) {
                    ForEach(store.values.keys.sorted(), id: \.self) { key in
                        HStack {
                            Text(key).font(.footnote)
                            Spacer()
                            Text(store.values[key] ?? "").font(.caption2).foregroundColor(.secondary).lineLimit(1)
                        }
                    }
                }
                Section {
                    Button("停用云同步", role: .destructive) { showDisableConfirm = true }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("设置云同步")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) { Color.clear.frame(height: tabBarInset) }
        .confirmationDialog("停用云同步？", isPresented: $showDisableConfirm, titleVisibility: .visible) {
            Button("停用", role: .destructive) { Task { await store.disable() } }
            Button("取消", role: .cancel) {}
        }
        .task { await store.load() }
    }
}

// MARK: - 浏览器缓存管理（对齐 Web `settings/BrowserCacheSettingPage.vue`）
/// 原生壳里没有浏览器缓存，改为展示本地缓存占用并提供清理（图片缓存 / 汇率缓存 / 全部）。
struct BrowserCacheSettingsView: View {
    @ObservedObject private var store = CloudSettingsStore.shared
    @Environment(\.mainTabBarInset) private var tabBarInset

    @State private var cacheSize: Int64 = 0
    @State private var showClearConfirm = false

    var body: some View {
        List {
            Section(header: Text("文件缓存")) {
                HStack {
                    Text("占用空间")
                    Spacer()
                    Text(ByteCountFormatter.string(fromByteCount: cacheSize, countStyle: .file))
                        .foregroundColor(.secondary)
                }
                Button("清理全部缓存", role: .destructive) { showClearConfirm = true }
            }

            Section(header: Text("缓存过期时间")) {
                Picker("地图数据", selection: Binding(
                    get: { store.int("mapCacheExpiration", default: 7) },
                    set: { v in Task { await store.set("mapCacheExpiration", "\(v)") } }
                )) {
                    ForEach([1, 3, 7, 15, 30], id: \.self) { Text("\($0) 天").tag($0) }
                }
                Picker("汇率数据", selection: Binding(
                    get: { store.int("exchangeRatesDataCacheExpiration", default: 1) },
                    set: { v in Task { await store.set("exchangeRatesDataCacheExpiration", "\(v)") } }
                )) {
                    ForEach([1, 3, 7, 15, 30], id: \.self) { Text("\($0) 天").tag($0) }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("缓存管理")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) { Color.clear.frame(height: tabBarInset) }
        .confirmationDialog("清理全部缓存？", isPresented: $showClearConfirm, titleVisibility: .visible) {
            Button("清理", role: .destructive) { clearCache() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("会清除本地图片缓存与汇率数据缓存，不影响你的账单数据。")
        }
        .task {
            await store.load()
            cacheSize = Self.directorySize(URLCache.shared)
        }
    }

    private func clearCache() {
        URLCache.shared.removeAllCachedResponses()
        let tmp = FileManager.default.temporaryDirectory
        if let items = try? FileManager.default.contentsOfDirectory(at: tmp, includingPropertiesForKeys: nil) {
            for url in items { try? FileManager.default.removeItem(at: url) }
        }
        cacheSize = 0
    }

    private static func directorySize(_ cache: URLCache) -> Int64 {
        Int64(cache.currentDiskUsage)
    }
}
