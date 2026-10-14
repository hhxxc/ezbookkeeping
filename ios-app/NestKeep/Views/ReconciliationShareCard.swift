import SwiftUI
import UIKit

/// 区间对账单分享长图：固定浅色卡片（不随系统深色模式），
/// 含期间标题/收支汇总/按日支出迷你条形/尾部署名。
/// 渲染走 UIHostingController + drawHierarchy（iOS 15 兼容，ImageRenderer 是 iOS16+）。
struct ReconciliationShareCard: View {
    let periodTitle: String
    let dateRangeText: String
    let incomeCents: Int64
    let expenseCents: Int64
    let totalCount: Int
    /// 按日支出（升序日期），用于迷你条形
    let dailyExpense: [(date: Date, amount: Int64)]

    // 分享图统一浅色配色（不随深色模式）
    private let bg = Color(red: 0.97, green: 0.97, blue: 0.98)
    private let card = Color.white
    private let ink = Color(red: 0.13, green: 0.13, blue: 0.15)
    private let secondary = Color(red: 0.45, green: 0.45, blue: 0.50)
    private let brand = Color(red: 0.30, green: 0.45, blue: 0.95)
    private let expenseColor = Color(red: 0.90, green: 0.28, blue: 0.28)
    private let incomeColor = Color(red: 0.20, green: 0.62, blue: 0.36)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // 头部
            HStack(spacing: 10) {
                Image(systemName: "book.closed.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 38, height: 38)
                    .background(brand)
                    .cornerRadius(11)
                VStack(alignment: .leading, spacing: 1) {
                    Text("巢记 · 对账单")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(ink)
                    Text("\(periodTitle) · \(dateRangeText)")
                        .font(.system(size: 12))
                        .foregroundColor(secondary)
                        .lineLimit(1)
                }
                Spacer()
            }

            // 汇总大卡
            VStack(alignment: .leading, spacing: 10) {
                Text("合计支出")
                    .font(.system(size: 12))
                    .foregroundColor(secondary)
                Text(AmountFormat.format(expenseCents))
                    .font(.system(size: 30, weight: .bold))
                    .foregroundColor(ink)
                    .monospacedDigit()
                HStack(spacing: 16) {
                    if incomeCents > 0 {
                        HStack(spacing: 4) {
                            Text("收入").font(.system(size: 12)).foregroundColor(secondary)
                            Text(AmountFormat.format(incomeCents))
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(incomeColor)
                                .monospacedDigit()
                        }
                    }
                    HStack(spacing: 4) {
                        Text("结余").font(.system(size: 12)).foregroundColor(secondary)
                        Text(AmountFormat.format(incomeCents - expenseCents))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(incomeCents - expenseCents >= 0 ? ink : expenseColor)
                            .monospacedDigit()
                    }
                    HStack(spacing: 4) {
                        Text("笔数").font(.system(size: 12)).foregroundColor(secondary)
                        Text("\(totalCount)")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(ink)
                            .monospacedDigit()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(card)
            .cornerRadius(14)

            // 按日支出条形（最多取最近 14 个有支出的日）
            if !topDays.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("每日支出")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(secondary)
                    ForEach(topDays, id: \.0) { item in
                        HStack(spacing: 8) {
                            Text(Self.dayText(item.0))
                                .font(.system(size: 11))
                                .foregroundColor(secondary)
                                .frame(width: 62, alignment: .leading)
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color(red: 0.92, green: 0.92, blue: 0.94))
                                    Capsule()
                                        .fill(expenseColor.opacity(0.75))
                                        .frame(width: max(4, geo.size.width * item.2))
                                }
                            }
                            .frame(height: 10)
                            Text(AmountFormat.format(item.1))
                                .font(.system(size: 11))
                                .foregroundColor(ink)
                                .monospacedDigit()
                                .frame(width: 78, alignment: .trailing)
                                .minimumScaleFactor(0.7)
                                .lineLimit(1)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(card)
                .cornerRadius(14)
            }

            // 尾部署名
            Text("由 巢记 生成 · \(Self.dateText(Date()))")
                .font(.system(size: 11))
                .foregroundColor(secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 2)
        }
        .padding(18)
        .background(bg)
    }

    /// 最近 14 个有支出的日（升序），返回（日期, 金额, 相对最大值比例）
    private var topDays: [(Date, Int64, CGFloat)] {
        let withExpense = dailyExpense.filter { $0.amount > 0 }
        guard !withExpense.isEmpty else { return [] }
        let slice = withExpense.suffix(14)
        let maxAmount = slice.map { $0.amount }.max() ?? 1
        return slice.map { ($0.date, $0.amount, CGFloat($0.amount) / CGFloat(maxAmount)) }
    }

    static func dayText(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "MM-dd"
        return f.string(from: date)
    }

    static func dateText(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy年M月d日"
        return f.string(from: date)
    }
}

enum ReconciliationShareRenderer {
    /// 把分享卡片渲染为长图（固定浅色、宽度 390）
    @MainActor
    static func render(vm: RangeDetailViewModel, mainVM: TransactionsViewModel) -> UIImage {
        let daily = vm.grouped.map { ($0.date, $0.items.reduce(Int64(0)) { $0 + abs($1.sourceAmount) }) }
            .sorted { $0.0 < $1.0 }
        let card = ReconciliationShareCard(
            periodTitle: vm.context.period.title,
            dateRangeText: mainVM.rangeSubtitle(vm.context.period),
            incomeCents: vm.incomeCents,
            expenseCents: vm.expenseCents,
            totalCount: vm.totalCount ?? vm.grouped.reduce(0) { $0 + $1.items.count },
            dailyExpense: daily
        )
        let host = UIHostingController(rootView: card)
        let width: CGFloat = 390
        let fitSize = host.view.sizeThatFits(CGSize(width: width, height: UIView.layoutFittingCompressedSize.height))
        host.view.bounds = CGRect(x: 0, y: 0, width: width, height: fitSize.height)
        host.view.backgroundColor = UIColor(red: 0.97, green: 0.97, blue: 0.98, alpha: 1)
        host.view.layoutIfNeeded()
        let renderer = UIGraphicsImageRenderer(size: host.view.bounds.size)
        return renderer.image { _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }
    }
}

/// 系统分享面板的 SwiftUI 包装（iOS 15 兼容）
struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
