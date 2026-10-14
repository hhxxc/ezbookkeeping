import WidgetKit
import SwiftUI

/// 桌面小组件入口：本月收支/预算快照（数据由主 App 写入 App Group 共享存储）
@main
struct NestKeepWidgetBundle: WidgetBundle {
    var body: some Widget {
        NestKeepBudgetWidget()
    }
}

// MARK: - 数据快照

/// 主 App → Widget 的共享数据（App Group UserDefaults JSON）
struct WidgetSnapshot: Codable {
    let expenseCents: Int64
    let incomeCents: Int64
    let budgetCents: Int64
    let updatedUnix: Int64
}

enum WidgetDataStore {
    static let snapshotKey = "nestkeep.widget.snapshot"

    /// App Group 按 bundle id 推导（com.nestkeep.app.dev[.widget] → group.com.nestkeep.app.dev），
    /// dev/pro 双 flavor 通用
    static var sharedDefaults: UserDefaults? {
        let bundleId = Bundle.main.bundleIdentifier ?? "com.nestkeep.app.dev"
        let base = bundleId.hasSuffix(".widget") ? String(bundleId.dropLast(".widget".count)) : bundleId
        return UserDefaults(suiteName: "group." + base)
    }

    static func loadSnapshot() -> WidgetSnapshot? {
        guard let defaults = sharedDefaults,
              let data = defaults.data(forKey: snapshotKey) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    /// 主 App 侧写入快照并刷新时间线
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
        if #available(iOS 14.0, *) {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}

// MARK: - Timeline Provider

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: Date(), snapshot: WidgetDataStore.loadSnapshot())
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: Date(), snapshot: WidgetDataStore.loadSnapshot()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let entry = SnapshotEntry(date: Date(), snapshot: WidgetDataStore.loadSnapshot())
        // 每 30 分钟刷新一次（数据由主 App 打开时推送，这里只是兜底重读）
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date().addingTimeInterval(1800)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

// MARK: - 视图

struct SnapshotEntryView: View {
    let entry: SnapshotEntry

    var body: some View {
        Group {
            if let s = entry.snapshot {
                content(expense: s.expenseCents, income: s.incomeCents, budget: s.budgetCents)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("巢记")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                    Text("打开 App 更新数据")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
            }
        }
        .widgetBackground()
    }

    private func content(expense: Int64, income: Int64, budget: Int64) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "book.closed.fill")
                    .font(.system(size: 11, weight: .semibold))
                Text("本月支出")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
            }
            .foregroundColor(.secondary)

            Text(verbatim: "¥" + Self.amountText(expense))
                .font(.system(size: 26, weight: .bold))
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            HStack(spacing: 10) {
                HStack(spacing: 3) {
                    Text("收")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Text(verbatim: "¥" + Self.amountText(income))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.green)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                if budget > 0 {
                    HStack(spacing: 3) {
                        Text("预算余")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        let remain = budget - expense
                        Text(verbatim: "¥" + Self.amountText(remain))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(remain >= 0 ? .primary : .red)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    static func amountText(_ cents: Int64) -> String {
        let value = Double(cents) / 100
        if value >= 10000 {
            return String(format: "%.1f万", value / 10000)
        }
        return String(format: "%.2f", value)
    }
}

/// iOS 17 用 containerBackground；iOS 15/16 直接背景色
extension View {
    @ViewBuilder
    func widgetBackground() -> some View {
        if #available(iOSApplicationExtension 17.0, *) {
            self.containerBackground(for: .widget) { Color(UIColor.systemBackground) }
        } else {
            self.padding(12)
                .background(Color(UIColor.systemBackground))
        }
    }
}

// MARK: - Widget

struct NestKeepBudgetWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NestKeepBudgetWidget", provider: SnapshotProvider()) { entry in
            SnapshotEntryView(entry: entry)
        }
        .configurationDisplayName("本月收支")
        .description("查看本月支出、收入与预算余量。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
