import Foundation

/// 交易标签（对应 Go TransactionTagInfoResponse）。
/// 后端 `id` / `groupId` 均为 `,string` 序列化 → Swift 用 String。
/// `icon` 为图标字体编号（"0"/nil = 未设置），`color` 为 RRGGBB（""/nil = 默认色）。
struct TransactionTag: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let groupId: String?
    let displayOrder: Int?
    let hidden: Bool?
    let icon: String?
    let color: String?
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

// MARK: - 标签 / 标签组写操作请求体

struct TagCreateRequest: Codable {
    let groupId: String
    let name: String
    let icon: String
    let color: String

    init(groupId: String, name: String, icon: String = "0", color: String = "") {
        self.groupId = groupId
        self.name = name
        self.icon = icon
        self.color = color
    }
}

struct TagModifyRequest: Codable {
    let id: String
    let groupId: String
    let name: String
    let icon: String
    let color: String
}

struct TagHideRequest: Codable { let id: String; let hidden: Bool }
struct TagIdRequest: Codable { let id: String }

struct TagGroupCreateRequest: Codable { let name: String }
struct TagGroupModifyRequest: Codable { let id: String; let name: String }

/// 标签排序（`POST /api/v1/transaction/tags/move.json`）
struct TagMoveRequest: Codable {
    let newDisplayOrders: [TagNewDisplayOrderRequest]
}
struct TagNewDisplayOrderRequest: Codable {
    let id: String
    let displayOrder: Int
}

/// 标签组删除（`POST /api/v1/transaction/tags/groups/delete.json`）
struct TagGroupDeleteRequest: Codable { let id: String }

/// 标签组排序（`POST /api/v1/transaction/tags/groups/move.json`）
struct TagGroupMoveRequest: Codable {
    let newDisplayOrders: [TagGroupNewDisplayOrderRequest]
}
struct TagGroupNewDisplayOrderRequest: Codable {
    let id: String
    let displayOrder: Int
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
