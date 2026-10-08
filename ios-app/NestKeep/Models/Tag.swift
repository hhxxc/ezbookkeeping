import Foundation

/// 交易标签（对应 Go TransactionTagInfoResponse）。
/// 后端 `id` / `groupId` 均为 `,string` 序列化 → Swift 用 String。
struct TransactionTag: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let groupId: String?
    let displayOrder: Int?
    let hidden: Bool?
}

/// 标签组（对应 Go TransactionTagGroupInfoResponse）
struct TransactionTagGroup: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let displayOrder: Int?
}

/// 标签组 + 组内标签（用于编辑页分组展示）
struct TagSection: Identifiable {
    let id: String
    let name: String
    let tags: [TransactionTag]
}

enum TagGrouping {
    /// 按标签组聚合标签；无组标签归入「未分组」
    static func sections(tags: [TransactionTag], groups: [TransactionTagGroup]) -> [TagSection] {
        let visible = tags.filter { !($0.hidden ?? false) }
        var ordered: [TagSection] = []
        for g in groups.sorted(by: { ($0.displayOrder ?? 0) < ($1.displayOrder ?? 0) }) {
            let items = visible
                .filter { $0.groupId == g.id }
                .sorted { ($0.displayOrder ?? 0) < ($1.displayOrder ?? 0) }
            if !items.isEmpty { ordered.append(TagSection(id: g.id, name: g.name, tags: items)) }
        }
        let grouped = Set(groups.map { $0.id })
        let ungrouped = visible
            .filter { ($0.groupId ?? "0") == "0" || !grouped.contains($0.groupId ?? "") }
            .sorted { ($0.displayOrder ?? 0) < ($1.displayOrder ?? 0) }
        if !ungrouped.isEmpty {
            ordered.append(TagSection(id: "0", name: "未分组", tags: ungrouped))
        }
        return ordered
    }
}
