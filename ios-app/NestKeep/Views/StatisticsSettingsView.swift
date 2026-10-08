import SwiftUI
import Combine

/// 统计设置页：对齐 Web `statistics/SettingsPage.vue` 的 9 项设置。
/// 写入云同步（`statistics.*` 键），与 Web 共享同一份服务端设置。
struct StatisticsSettingsView: View {
    @ObservedObject private var store = CloudSettingsStore.shared
    @Environment(\.mainTabBarInset) private var tabBarInset

    var body: some View {
        List {
            // 通用设置
            Section(header: Text("通用设置")) {
                Picker("默认图表数据类型", selection: Binding(
                    get: { store.int("statistics.defaultChartDataType", default: 2) },
                    set: { v in Task { await store.set("statistics.defaultChartDataType", "\(v)") } }
                )) {
                    ForEach(ChartDataTypeOption.all, id: \.type) { Text($0.name).tag($0.type) }
                }

                Picker("统计时区", selection: Binding(
                    get: { store.int("statistics.defaultTimezoneType", default: 0) },
                    set: { v in Task { await store.set("statistics.defaultTimezoneType", "\(v)") } }
                )) {
                    Text("应用时区").tag(0)
                    Text("交易时区").tag(1)
                }

                NavigationLink {
                    AccountFilterSettingsView(type: "statistics", title: "默认账户过滤",
                                              explicitKey: "statistics.defaultAccountFilter")
                } label: {
                    Label("默认账户过滤", systemImage: "person.crop.circle.badge.checkmark")
                }

                NavigationLink {
                    CategoryFilterSettingsView(type: "statistics", title: "默认分类过滤",
                                               explicitKey: "statistics.defaultTransactionCategoryFilter")
                } label: {
                    Label("默认分类过滤", systemImage: "square.grid.2x2")
                }

                Picker("默认排序方式", selection: Binding(
                    get: { store.int("statistics.defaultSortingType", default: 0) },
                    set: { v in Task { await store.set("statistics.defaultSortingType", "\(v)") } }
                )) {
                    Text("按金额").tag(0)
                    Text("按显示顺序").tag(1)
                    Text("按名称").tag(2)
                }
            }

            // 分类分析设置
            Section(header: Text("分类分析设置")) {
                Picker("默认图表类型", selection: Binding(
                    get: { store.int("statistics.defaultCategoricalChartType", default: 1) },
                    set: { v in Task { await store.set("statistics.defaultCategoricalChartType", "\(v)") } }
                )) {
                    Text("饼图").tag(0)
                    Text("柱状图").tag(1)
                }

                Picker("默认日期范围", selection: Binding(
                    get: { store.int("statistics.defaultCategoricalChartDataRangeType", default: 0) },
                    set: { v in Task { await store.set("statistics.defaultCategoricalChartDataRangeType", "\(v)") } }
                )) {
                    ForEach(Self.normalDateRanges, id: \.type) { Text($0.name).tag($0.type) }
                }
            }

            // 趋势分析设置
            Section(header: Text("趋势分析设置")) {
                Picker("默认日期范围", selection: Binding(
                    get: { store.int("statistics.defaultTrendChartDataRangeType", default: 0) },
                    set: { v in Task { await store.set("statistics.defaultTrendChartDataRangeType", "\(v)") } }
                )) {
                    ForEach(Self.trendDateRanges, id: \.type) { Text($0.name).tag($0.type) }
                }
            }

            // 资产趋势设置
            Section(header: Text("资产趋势设置")) {
                Picker("默认日期范围", selection: Binding(
                    get: { store.int("statistics.defaultAssetTrendsChartDataRangeType", default: 0) },
                    set: { v in Task { await store.set("statistics.defaultAssetTrendsChartDataRangeType", "\(v)") } }
                )) {
                    ForEach(Self.assetTrendsDateRanges, id: \.type) { Text($0.name).tag($0.type) }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("统计设置")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) { Color.clear.frame(height: tabBarInset) }
        .task { await store.load() }
    }

    // MARK: - 日期范围选项（对齐 Web DateRange 枚举，仅移动端可用的场景）

    private struct DateRangeOption {
        let type: Int
        let name: String
    }

    /// 通用 / 分类分析场景的日期范围（Normal 场景）
    private static let normalDateRanges: [DateRangeOption] = [
        .init(type: 0, name: "全部"),
        .init(type: 1, name: "今天"),
        .init(type: 2, name: "昨天"),
        .init(type: 3, name: "最近 7 天"),
        .init(type: 4, name: "最近 30 天"),
        .init(type: 5, name: "本周"),
        .init(type: 6, name: "上周"),
        .init(type: 7, name: "本月"),
        .init(type: 8, name: "上月"),
        .init(type: 9, name: "今年"),
        .init(type: 10, name: "去年")
    ]

    /// 趋势分析场景的日期范围（TrendAnalysis 场景）
    private static let trendDateRanges: [DateRangeOption] = [
        .init(type: 0, name: "全部"),
        .init(type: 9, name: "今年"),
        .init(type: 10, name: "去年"),
        .init(type: 101, name: "最近 12 个月"),
        .init(type: 102, name: "最近 24 个月"),
        .init(type: 103, name: "最近 36 个月"),
        .init(type: 104, name: "最近 2 年"),
        .init(type: 105, name: "最近 3 年"),
        .init(type: 106, name: "最近 5 年")
    ]

    /// 资产趋势场景的日期范围（AssetTrends 场景）
    private static let assetTrendsDateRanges: [DateRangeOption] = [
        .init(type: 0, name: "全部"),
        .init(type: 3, name: "最近 7 天"),
        .init(type: 4, name: "最近 30 天"),
        .init(type: 5, name: "本周"),
        .init(type: 6, name: "上周"),
        .init(type: 7, name: "本月"),
        .init(type: 8, name: "上月"),
        .init(type: 9, name: "今年"),
        .init(type: 10, name: "去年"),
        .init(type: 101, name: "最近 12 个月"),
        .init(type: 102, name: "最近 24 个月"),
        .init(type: 103, name: "最近 36 个月"),
        .init(type: 104, name: "最近 2 年"),
        .init(type: 105, name: "最近 3 年"),
        .init(type: 106, name: "最近 5 年")
    ]
}

/// 图表数据类型选项（对齐 Web `ChartDataType`，仅分类分析场景移动端可用的值）
private struct ChartDataTypeOption {
    let type: Int
    let name: String

    static let all: [ChartDataTypeOption] = [
        .init(type: 0, name: "支出按账户"),
        .init(type: 1, name: "支出按一级分类"),
        .init(type: 2, name: "支出按二级分类"),
        .init(type: 3, name: "收入按账户"),
        .init(type: 4, name: "收入按一级分类"),
        .init(type: 5, name: "收入按二级分类"),
        .init(type: 6, name: "账户总资产"),
        .init(type: 7, name: "账户总负债")
    ]
}
