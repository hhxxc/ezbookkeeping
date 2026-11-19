import SwiftUI

/// 交易详情页：展示单笔交易的完整信息（对齐 Web 的 View 模式），
/// 并提供「复制」与「编辑」入口。
/// 2026-11 美化：卡片式重排（ScrollView+VStack 自控间距，与首页/编辑页同一设计语言）——
/// Hero 卡（分类色图标 + 金额 + 标签芯片）+ 信息卡（图标行）+ 备注卡 + 双按钮操作区。
struct TransactionDetailView: View {
    let transaction: Transaction
    /// 编辑/复制落库后通知上级刷新（上级列表自行 reload）
    var onChanged: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var showEdit = false
    @State private var showDuplicate = false
    @State private var didEdit = false
    /// 完整分类（icon/颜色映射）；内嵌 brief 只有 id/name
    @State private var category: TransactionCategory?
    /// 标签详情（名字 + 颜色，芯片渲染用）
    @State private var tagById: [String: TransactionTag] = [:]

    // MARK: - 派生数据

    private var amountText: String {
        switch transaction.transactionType {
        case .expense: return "-" + AmountFormat.format(transaction.sourceAmount, currency: transaction.currency)
        case .income: return "+" + AmountFormat.format(transaction.sourceAmount, currency: transaction.currency)
        case .transfer: return AmountFormat.format(transaction.sourceAmount, currency: transaction.currency)
        case .modifyBalance: return AmountFormat.format(transaction.sourceAmount, currency: transaction.currency)
        }
    }

    private var amountColor: Color {
        switch transaction.transactionType {
        case .expense: return Theme.expense
        case .income: return Theme.income
        case .transfer: return HomePalette.ink
        case .modifyBalance: return Theme.brand
        }
    }

    private var typeLabel: String {
        switch transaction.transactionType {
        case .expense: return "支出"
        case .income: return "收入"
        case .transfer: return "转账"
        case .modifyBalance: return "余额调整"
        }
    }

    /// 交易类型小图标（分类缺失/转账/余额调整时也作 Hero 图标兜底）
    private var typeSymbol: String {
        switch transaction.transactionType {
        case .expense: return "arrow.up.right"
        case .income: return "arrow.down.left"
        case .transfer: return "arrow.left.arrow.right"
        case .modifyBalance: return "equal.circle"
        }
    }

    private var typeTint: Color {
        switch transaction.transactionType {
        case .expense: return Theme.expense
        case .income: return Theme.income
        case .transfer: return .gray
        case .modifyBalance: return Theme.brand
        }
    }

    /// Hero 图标：支出/收入且能映射到分类 → 分类图标（分类色，与账单列表一致）；
    /// 否则回退交易类型图标
    private var heroSymbol: String {
        if transaction.transactionType == .expense || transaction.transactionType == .income,
           let c = category {
            return CategoryIconCatalog.symbol(c.icon)
        }
        return typeSymbol
    }

    /// Hero 图标底色：优先分类色，回退交易类型色
    private var heroTint: Color {
        if transaction.transactionType == .expense || transaction.transactionType == .income,
           let hex = category?.color, !hex.isEmpty {
            return Color(hex: hex)
        }
        return typeTint
    }

    /// Hero 副标题：类型 · 分类名（如「支出 · 食品」）；
    /// 完整分类未加载完时先用内嵌 brief 的分类名兜底（首帧即有）
    private var heroSubtitle: String {
        let name = category?.name ?? transaction.categoryName
        if let name = name, !name.isEmpty,
           transaction.transactionType == .expense || transaction.transactionType == .income {
            return typeLabel + " · " + name
        }
        return typeLabel
    }

    /// 标签芯片数据（名称/颜色；未加载完成时为空不显示）
    private var tagChips: [(name: String, color: Color?)] {
        let ids = transaction.tagIds ?? []
        return ids.compactMap { id in
            guard let t = tagById[id] else { return nil }
            return (t.name, t.color.flatMap { $0.isEmpty ? nil : Color(hex: $0) })
        }
    }

    var body: some View {
        NavigationView {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    heroCard
                    infoCard
                    if let comment = transaction.comment, !comment.isEmpty {
                        commentCard(comment)
                    }
                    actionBar
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 20)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("交易详情")
            .navigationBarTitleDisplayMode(.inline)
            .task { await loadContext() }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            // 编辑保存成功 → 关闭详情，由父级 sheet 的 onDismiss 统一刷新
            // （此前 onChanged + 父级 onDismiss 会各刷一轮，重复请求）
            .sheet(isPresented: $showEdit, onDismiss: {
                if didEdit {
                    didEdit = false
                    dismiss()
                }
            }) {
                TransactionEditView(transaction: transaction, mode: .edit, onSaved: { didEdit = true })
            }
            // 复制保存 → onChanged 通知上级刷新（详情不关闭，onDismiss 是取消/完成也会触发的空刷新，去掉）
            .sheet(isPresented: $showDuplicate) {
                TransactionEditView(transaction: transaction, mode: .duplicate, onSaved: { onChanged?() })
            }
        }
        .navigationViewStyle(.stack)
    }

    // MARK: - Hero 卡（分类图标 + 金额 + 标签芯片）

    private var heroCard: some View {
        VStack(spacing: 0) {
            Image(systemName: heroSymbol)
                .font(.system(size: 26, weight: .semibold))
                .foregroundColor(heroTint)
                .frame(width: 64, height: 64)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(heroTint.opacity(0.14))
                )

            Text(amountText)
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(amountColor)
                .minimumScaleFactor(0.55)
                .lineLimit(1)
                .padding(.top, 14)

            Text(heroSubtitle)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(HomePalette.secondary)
                .padding(.top, 6)

            let chips = tagChips
            if !chips.isEmpty {
                let rows = Self.wrapRows(chips, availableWidth: UIScreen.main.bounds.width - 96)
                VStack(spacing: 8) {
                    ForEach(rows.indices, id: \.self) { rowIdx in
                        HStack(spacing: 8) {
                            Spacer(minLength: 0)
                            ForEach(rows[rowIdx].indices, id: \.self) { i in
                                tagChip(rows[rowIdx][i])
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
                .padding(.top, 12)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal, 16)
        .background(cardBackground)
    }

    private func tagChip(_ chip: (name: String, color: Color?)) -> some View {
        let color = chip.color ?? Theme.brand
        return Text(chip.name)
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(color.opacity(0.12)))
            .lineLimit(1)
    }

    // MARK: - 信息卡（账户/时间/分期等）

    private var infoCard: some View {
        VStack(spacing: 0) {
            if transaction.transactionType == .transfer {
                infoRow("转出账户", icon: "arrow.up.right", tint: Theme.brand,
                        value: transaction.sourceAccount?.name ?? "—")
                cardDivider
                infoRow("转入账户", icon: "arrow.down.left", tint: Theme.brand,
                        value: transaction.destinationAccount?.name ?? "—")
                if let d = transaction.destinationAmount, d != transaction.sourceAmount {
                    cardDivider
                    infoRow("转入金额", icon: "banknote.fill", tint: Theme.brand,
                            value: AmountFormat.format(d, currency: transaction.currency))
                }
            } else {
                infoRow("账户",
                        icon: "creditcard.fill", tint: Theme.brand,
                        value: transaction.sourceAccount?.name ?? "—")
            }
            cardDivider
            infoRow("时间", icon: "clock.fill", tint: Theme.brand,
                    value: Self.fullDateTime(transaction.date))
            if transaction.installmentPlanId != nil {
                cardDivider
                infoRow("分期", icon: "calendar", tint: Theme.brand,
                        value: transaction.installmentLabel ?? "—")
            }
        }
        .padding(.vertical, 4)
        .background(cardBackground)
    }

    private func infoRow(_ title: String, icon: String, tint: Color, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(tint)
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(tint.opacity(0.12))
                )
            Text(title)
                .font(.system(size: 15))
                .foregroundColor(HomePalette.secondary)
            Spacer(minLength: 12)
            Text(value)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(HomePalette.ink)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var cardDivider: some View {
        Divider()
            .padding(.leading, 58)
    }

    // MARK: - 备注卡

    private func commentCard(_ comment: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Theme.brand.opacity(0.55))
                    .frame(width: 3, height: 13)
                Text("备注")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(HomePalette.secondary)
            }
            Text(comment)
                .font(.system(size: 15))
                .foregroundColor(HomePalette.ink)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(cardBackground)
    }

    // MARK: - 操作区（复制 + 编辑）

    private var actionBar: some View {
        HStack(spacing: 12) {
            actionButton("复制为新交易", icon: "doc.on.doc", primary: false,
                         disabled: transaction.transactionType == .modifyBalance) {
                showDuplicate = true
            }
            actionButton("编辑", icon: "pencil", primary: true,
                         disabled: !(transaction.editable ?? true)) {
                showEdit = true
            }
        }
        .padding(.top, 4)
    }

    private func actionButton(_ title: String, icon: String, primary: Bool,
                              disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(primary ? AnyShapeStyle(Theme.aiGradient)
                                  : AnyShapeStyle(Theme.brand.opacity(0.12)))
            )
            .foregroundColor(primary ? .white : Theme.brand)
            .opacity(disabled ? 0.4 : 1)
        }
        .disabled(disabled)
    }

    // MARK: - 复用样式

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(HomePalette.card)
    }

    // MARK: - 数据加载

    /// 分类 icon/颜色 + 标签名字/颜色（详情渲染用；失败静默，页面仍可用内嵌 brief 展示）
    private func loadContext() async {
        if transaction.transactionType == .expense || transaction.transactionType == .income {
            if let cats = try? await AppDataStore.shared.getCategories() {
                var flat: [TransactionCategory] = []
                for c in cats {
                    flat.append(c)
                    flat.append(contentsOf: c.subCategories ?? [])
                }
                category = flat.first { $0.id == transaction.categoryId }
            }
        }
        guard let ids = transaction.tagIds, !ids.isEmpty else { return }
        guard let result = try? await AppDataStore.shared.getTags() else { return }
        var map: [String: TransactionTag] = [:]
        for t in result.tags { map[t.id] = t }
        tagById = map
    }

    /// 芯片按估算宽度贪心分行（iOS 15 无 FlowLayout，与编辑页小类芯片同一策略）
    private static func wrapRows(_ chips: [(name: String, color: Color?)],
                                 availableWidth: CGFloat) -> [[(name: String, color: Color?)]] {
        var rows: [[(name: String, color: Color?)]] = []
        var current: [(name: String, color: Color?)] = []
        var currentWidth: CGFloat = 0
        for chip in chips {
            var textWidth: CGFloat = 0
            for ch in chip.name {
                let isWide = ch.unicodeScalars.first.map { $0.properties.isIdeographic || $0.value > 0x2E7F } ?? false
                textWidth += isWide ? 12 : 6.5
            }
            let chipWidth = textWidth + 20 + 8   // 水平 padding + 间距
            if currentWidth + chipWidth > availableWidth && !current.isEmpty {
                rows.append(current)
                current = []
                currentWidth = 0
            }
            current.append(chip)
            currentWidth += chipWidth
        }
        if !current.isEmpty { rows.append(current) }
        return rows
    }

    static func fullDateTime(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy年M月d日 HH:mm"
        return f.string(from: d)
    }
}
