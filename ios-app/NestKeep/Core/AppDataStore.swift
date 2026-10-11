import Foundation
import Combine

/// 全局共享的引用数据缓存（accounts / categories / tags / tagGroups）。
///
/// 解决的问题：
///  - 冷启动 4 个 Tab 全保活，`.task` 同时触发 → accounts 被拉 3 次、categories 2 次；
///  - 记账页（最高频页面）每次打开无条件 4 连拉；
///  - 全 App 结构化数据零磁盘缓存，断网全空白。
///
/// 策略：内存 + 磁盘（Documents）双层缓存，`staleInterval` 内直接用缓存；
/// 过期后走网络刷新（stale-while-revalidate：先回旧值保底，成功后更新）。
/// 数据变更入口调用 `invalidate*` 失效；交易落库/删除（影响账户余额）会
/// 自动失效 accounts（监听 `.transactionsChanged`）。
@MainActor
final class AppDataStore: ObservableObject {
    static let shared = AppDataStore()

    @Published private(set) var accounts: [Account] = []
    @Published private(set) var categories: [TransactionCategory] = []
    @Published private(set) var tags: [TransactionTag] = []
    @Published private(set) var tagGroups: [TransactionTagGroup] = []

    private var accountsAt: Date?
    private var categoriesAt: Date?
    private var tagsAt: Date?
    private var tagGroupsAt: Date?
    /// 防同 key 并发重复请求（4 个 Tab 同时 ensure 时只发一次网络请求）。
    /// 存的是在途 Task，后来者会等待其完成而不是拿到可能为空的缓存
    /// （旧实现命中 inflight 直接 return，冷启动后到的 Tab 会渲染空白）
    private var inflight: [String: Task<Void, Error>] = [:]

    /// 缓存有效期。个人自用 + 单设备，2 分钟足够新鲜；
    /// 变更入口（保存/删除）都会主动失效，不受此值拖累
    private static let staleInterval: TimeInterval = 120

    // MARK: - 磁盘缓存（断网/冷启动先渲染旧数据）

    private struct DiskCache: Codable {
        var accounts: [Account] = []
        var categories: [TransactionCategory] = []
        var tags: [TransactionTag] = []
        var tagGroups: [TransactionTagGroup] = []
    }

    private static var cacheURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("appdata-cache.json")
    }

    private init() {
        loadDiskCache()
        // 交易落库/删除会改变账户余额 → 失效账户缓存（AI 识图批量添加也走此通知）
        NotificationCenter.default.publisher(for: .transactionsChanged)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.invalidateAccounts() }
            .store(in: &cancellables)
    }

    private var cancellables: Set<AnyCancellable> = []

    private func loadDiskCache() {
        guard let data = try? Data(contentsOf: Self.cacheURL),
              let cache = try? JSONDecoder().decode(DiskCache.self, from: data) else { return }
        accounts = cache.accounts
        categories = cache.categories
        tags = cache.tags
        tagGroups = cache.tagGroups
    }

    private func saveDiskCache() {
        let cache = DiskCache(accounts: accounts, categories: categories,
                              tags: tags, tagGroups: tagGroups)
        guard let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: Self.cacheURL, options: .atomic)
    }

    // MARK: - 读取（新鲜缓存直接返回；过期/为空才走网络；网络失败回退旧缓存）

    /// 缓存过期后的取数：同一 key 并发调用只发一次请求，后来者 await 在途任务。
    /// 请求失败时若本地已有旧数据则静默兜底（离线可用），完全没数据才向上抛错
    private func fetchWithDedup(_ key: String, hasData: @escaping () -> Bool, fetch: @escaping () async throws -> Void) async throws {
        if let existing = inflight[key] {
            do {
                try await existing.value
            } catch {
                if !hasData() { throw error }
            }
            return
        }
        let task = Task { try await fetch() }
        inflight[key] = task
        defer { inflight[key] = nil }
        do {
            try await task.value
        } catch {
            if !hasData() { throw error }
        }
    }

    func getAccounts(force: Bool = false) async throws -> [Account] {
        if !force, let at = accountsAt, Date().timeIntervalSince(at) < Self.staleInterval, !accounts.isEmpty {
            return accounts
        }
        try await fetchWithDedup("accounts", hasData: { !self.accounts.isEmpty }) {
            let fetched: [Account] = try await APIClient.shared.request("/api/v1/accounts/list.json")
            self.accounts = fetched
            self.accountsAt = Date()
            self.saveDiskCache()
        }
        return accounts
    }

    func getCategories(force: Bool = false) async throws -> [TransactionCategory] {
        if !force, let at = categoriesAt, Date().timeIntervalSince(at) < Self.staleInterval, !categories.isEmpty {
            return categories
        }
        try await fetchWithDedup("categories", hasData: { !self.categories.isEmpty }) {
            let fetched = try await APIClient.shared.requestCategoryList()
            self.categories = fetched
            self.categoriesAt = Date()
            self.saveDiskCache()
        }
        return categories
    }

    /// 标签 + 标签组（后端两个接口，总是成对使用）
    func getTags(force: Bool = false) async throws -> (tags: [TransactionTag], groups: [TransactionTagGroup]) {
        if !force, let at = tagsAt, let gAt = tagGroupsAt,
           Date().timeIntervalSince(at) < Self.staleInterval,
           Date().timeIntervalSince(gAt) < Self.staleInterval {
            return (tags, tagGroups)
        }
        try await fetchWithDedup("tags", hasData: { !self.tags.isEmpty }) {
            async let t: [TransactionTag] = APIClient.shared.request("/api/v1/transaction/tags/list.json")
            async let g: [TransactionTagGroup] = APIClient.shared.request("/api/v1/transaction/tags/groups/list.json")
            let fetchedTags = try await t
            let fetchedGroups = (try? await g) ?? []
            self.tags = fetchedTags
            self.tagGroups = fetchedGroups
            self.tagsAt = Date()
            self.tagGroupsAt = Date()
            self.saveDiskCache()
        }
        return (tags, tagGroups)
    }

    // MARK: - 失效（数据变更入口调用）

    func invalidateAccounts() {
        accountsAt = nil
    }

    func invalidateCategories() {
        categoriesAt = nil
    }

    func invalidateTags() {
        tagsAt = nil
        tagGroupsAt = nil
    }
}
