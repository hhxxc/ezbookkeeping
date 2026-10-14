import Foundation
import WidgetKit

/// 桌面小组件数据同步（主 App 侧）。
/// 与 NestKeepWidget target 内的同名类型保持字段一致（两 target 独立编译，
/// Swift 无法跨 target 复用非模块代码，这里有意保留一份镜像定义）。
struct WidgetSnapshot: Codable {
    let expenseCents: Int64
    let incomeCents: Int64
    let budgetCents: Int64
    let updatedUnix: Int64
}

enum WidgetDataStore {
    static let snapshotKey = "nestkeep.widget.snapshot"

    /// App Group 按 bundle id 推导（com.nestkeep.app.dev → group.com.nestkeep.app.dev），
    /// 与 Widget target 内的推导逻辑一致，dev/pro 双 flavor 通用
    static var sharedDefaults: UserDefaults? {
        let bundleId = Bundle.main.bundleIdentifier ?? "com.nestkeep.app.dev"
        let base = bundleId.hasSuffix(".widget") ? String(bundleId.dropLast(".widget".count)) : bundleId
        return UserDefaults(suiteName: "group." + base)
    }

    static func currentBudgetCents() -> Int64 {
        guard let data = sharedDefaults?.data(forKey: snapshotKey),
              let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) else { return 0 }
        return snapshot.budgetCents
    }

    /// 写入快照并刷新小组件时间线
    static func saveSnapshot(expenseCents: Int64, incomeCents: Int64, budgetCents: Int64) {
        guard let defaults = sharedDefaults else { return }
        let snapshot = WidgetSnapshot(
            expenseCents: expenseCents,
            incomeCents: incomeCents,
            budgetCents: budgetCents,
            updatedUnix: Int64(Date().timeIntervalSince1970)
        )
        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: snapshotKey)
        }
        WidgetCenter.shared.reloadAllTimelines()
    }
}
