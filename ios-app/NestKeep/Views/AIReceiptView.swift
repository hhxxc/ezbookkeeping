import SwiftUI
import UIKit
import PhotosUI
import Combine

/// AI 识图记账页：进入即拉起相册（多选）→ 识别 → 结果默认全选 → 底部「确认添加」批量落库 → 成功后自动返回。
/// 个别结果落库失败时保留在列表里，可点右侧 ✎ 进「新增交易」预填页修正后单独保存。
/// 后端关闭该能力时入口不展示；仍被打开时用错误提示兜底（避免空白页）。
@MainActor
final class AIReceiptViewModel: ObservableObject {
    @Published var isLoading = false
    /// 多张图片时的识别进度文案（如「识别中 2/3…」）
    @Published var progressText = ""
    @Published var isAdding = false
    @Published var error: String?
    @Published var results: [ReceiptRecognizer.Recognized] = []
    /// 勾选的识别结果（识别完成后默认全部勾选 = 默认全部添加）
    @Published var selectedIds: Set<UUID> = []
    @Published var previewImage: UIImage?
    @Published var previewCount = 0
    @Published var accounts: [Account] = []
    @Published var categories: [TransactionCategory] = []

    func loadRefData() async {
        // 走共享缓存（识图落库与记账页共用同一份引用数据）
        accounts = (try? await AppDataStore.shared.getAccounts()) ?? []
        categories = (try? await AppDataStore.shared.getCategories()) ?? []
    }

    /// 语音记账等入口直接带入的解析结果（跳过识别，进确认/落库流程）
    func prefill(_ items: [ReceiptRecognizer.Recognized]) {
        error = nil
        isLoading = false
        progressText = ""
        results = items
        // 默认全部添加（与识别完成后的口径一致）
        selectedIds = Set(items.map(\.id))
    }

    /// 最近一次识别用的图片，供「重试识别」复用
    private(set) var lastImages: [Data] = []

    /// 是否有上次识别的图片可重试（视图判断用，勿跨文件直接访问 lastImages——
    /// Xcode 26.6 下 private(set) 属性的跨文件 getter 访问会报 private 不可达）
    var hasLastImages: Bool { !lastImages.isEmpty }

    /// 手动重试：用上次的图片重新识别
    func retry() async {
        await recognizeAll(lastImages)
    }

    /// 识别失败自动重试一次（超时/网络抖动；识别本身较慢，只重试一次避免久等）
    private func recognizeWithRetry(_ data: Data) async throws -> [ReceiptRecognizer.Recognized] {
        do {
            return try await ReceiptRecognizer.recognize(imageData: data)
        } catch {
            return try await ReceiptRecognizer.recognize(imageData: data)
        }
    }

    /// 识别多张图片（顺序识别，结果合并；单张失败不中断，最后汇总提示）
    func recognizeAll(_ images: [Data]) async {
        guard !images.isEmpty else { return }
        lastImages = images
        isLoading = true
        error = nil
        results = []
        selectedIds = []
        previewImage = images.first.flatMap { UIImage(data: $0) }
        previewCount = images.count

        var all: [ReceiptRecognizer.Recognized] = []
        var firstError: String?

        for (index, data) in images.enumerated() {
            progressText = images.count > 1 ? "识别中 \(index + 1)/\(images.count)…" : "识别中…"
            do {
                all += try await recognizeWithRetry(data)
            } catch {
                if firstError == nil {
                    firstError = (error as? APIError)?.errorDescription ?? error.localizedDescription
                }
            }
        }

        isLoading = false
        progressText = ""

        results = all
        // 默认全部添加（对齐 Web 端识图 Sheet 的全选行为）
        selectedIds = Set(all.map(\.id))

        if all.isEmpty {
            error = firstError ?? "图片中没有识别到交易信息"
        } else if let e = firstError {
            error = "部分图片识别失败：\(e)"
        }
    }

    var selectedCount: Int { selectedIds.count }

    var allSelected: Bool { !results.isEmpty && selectedIds.count == results.count }

    func toggle(_ item: ReceiptRecognizer.Recognized) {
        if selectedIds.contains(item.id) {
            selectedIds.remove(item.id)
        } else {
            selectedIds.insert(item.id)
        }
    }

    func toggleAll() {
        selectedIds = allSelected ? [] : Set(results.map(\.id))
    }

    func remove(_ item: ReceiptRecognizer.Recognized) {
        results.removeAll { $0.id == item.id }
        selectedIds.remove(item.id)
    }

    /// 批量添加勾选的结果。成功条数返回给调用方；
    /// 成功的条目从列表移除，失败条目保留（可点 ✎ 修正）并汇总错误信息。
    func addSelected() async -> Int {
        let targets = results.filter { selectedIds.contains($0.id) }
        guard !targets.isEmpty else { return 0 }

        isAdding = true
        error = nil

        var success = 0
        var failedItems: [ReceiptRecognizer.Recognized] = []
        var firstError: String?

        for item in targets {
            do {
                let time = item.time ?? Int64(Date().timeIntervalSince1970)
                let date = Date(timeIntervalSince1970: TimeInterval(time))
                let tz = TimeZone.current
                let isTransfer = item.transactionType == .transfer
                // 分类/账户兜底：AI 没认出或已失效时回退默认分类/第一个账户，避免后端报
                // 「transaction category not found」导致整条落库失败
                let sourceAccountId = displayAccountId(item.sourceAccountId) ?? ""
                let req = TransactionCreateRequest(
                    type: item.type,
                    categoryId: displayCategoryId(item) ?? "0",
                    time: time,
                    utcOffset: tz.secondsFromGMT(for: date) / 60,
                    sourceAccountId: sourceAccountId,
                    destinationAccountId: isTransfer
                        ? displayDestinationAccountId(source: sourceAccountId, destination: item.destinationAccountId) ?? ""
                        : nil,
                    sourceAmount: item.sourceAmount ?? item.destinationAmount ?? 0,
                    destinationAmount: isTransfer ? (item.destinationAmount ?? item.sourceAmount) : nil,
                    comment: item.comment,
                    tagIds: item.tagIds ?? [],
                    pictureIds: [],
                    geoLocation: nil,
                    clientSessionId: UUID().uuidString
                )
                let _: EmptyResult = try await APIClient.shared.request(
                    "/api/v1/transactions/add.json", method: .POST, body: req
                )
                success += 1
            } catch {
                failedItems.append(item)
                if firstError == nil {
                    firstError = (error as? APIError)?.errorDescription ?? error.localizedDescription
                }
            }
        }

        isAdding = false

        // 成功的移出列表；失败的保留并取消勾选（避免重复提交）
        results.removeAll { item in !failedItems.contains { $0.id == item.id } }
        selectedIds = []

        if !failedItems.isEmpty {
            error = "已添加 \(success) 笔，\(failedItems.count) 笔保存失败：\(firstError ?? "")。可点结果右侧 ✎ 修正后保存"
        }

        return success
    }

    func accountName(_ id: String?) -> String {
        guard let id = id else { return "未识别" }
        return accounts.first { $0.id == id }?.name ?? "未匹配账户"
    }

    func categoryName(_ id: String?) -> String {
        guard let id = id else { return "未识别" }
        for c in categories {
            if c.id == id { return c.name }
            if let subs = c.subCategories, let hit = subs.first(where: { $0.id == id }) { return hit.name }
        }
        return "未匹配分类"
    }

    // MARK: - 落库前兜底解析
    // 后端要求：除余额调整外，交易必须挂一个可见的「子分类」且类型匹配（大类直接挂会被拒）。
    // AI 没认出分类（结果里 categoryId 为空，界面显示「未识别」）或认出的分类已被删除时，
    // 直接提交会报「transaction category not found」。这里回退到用户分类里第一个可见叶子分类，
    // 口径与「新增交易」页的 defaultCategoryId() 一致；账户同理回退到第一个账户。

    /// 类型对应的分类类型
    private func categoryType(for type: TransactionType) -> TransactionCategoryType? {
        switch type {
        case .income: return .income
        case .expense: return .expense
        case .transfer: return .transfer
        case .modifyBalance: return nil
        }
    }

    /// 该 id 是否是当前用户分类里可直接挂在交易上的子分类（可见 + 类型匹配）
    func usableCategory(_ id: String?, type: TransactionType) -> Bool {
        guard let id = id, !id.isEmpty, let wantType = categoryType(for: type) else { return false }
        for c in categories {
            guard c.hidden != true, let subs = c.subCategories else { continue }
            if let hit = subs.first(where: { $0.id == id && $0.hidden != true }) {
                return hit.type == wantType.rawValue
            }
        }
        return false
    }

    /// 该类型下第一个可见叶子分类（大类有子分类时取其第一个子分类）
    func defaultCategoryId(for type: TransactionType) -> String? {
        guard let wantType = categoryType(for: type) else { return "0" }
        guard let first = categories.first(where: { $0.type == wantType.rawValue && $0.hidden != true }) else { return nil }
        let subs = (first.subCategories ?? []).filter { $0.hidden != true }
        return subs.first?.id ?? first.id
    }

    /// 展示与落库共用的分类解析：识别结果可用就用原值，否则回退默认分类
    func displayCategoryId(_ item: ReceiptRecognizer.Recognized) -> String? {
        if item.transactionType == .modifyBalance { return "0" }
        if usableCategory(item.categoryId, type: item.transactionType) { return item.categoryId }
        return defaultCategoryId(for: item.transactionType)
    }

    /// 账户解析：识别结果里的账户已不存在/没识别出来时，回退第一个账户
    func displayAccountId(_ id: String?) -> String? {
        if let id = id, !id.isEmpty, accounts.contains(where: { $0.id == id }) { return id }
        return accounts.first?.id
    }

    /// 转账目标账户解析：无效或与源账户相同时，回退到另一个账户
    func displayDestinationAccountId(source: String?, destination: String?) -> String? {
        let resolvedSource = displayAccountId(source)
        if let d = destination, !d.isEmpty, d != resolvedSource,
           accounts.contains(where: { $0.id == d }) { return d }
        return accounts.first(where: { $0.id != resolvedSource })?.id
    }
}

struct AIReceiptView: View {
    /// 入口选完图带进来的图片；非空时进页直接开始识别（不再自动拉起相册）
    var initialImages: [Data] = []
    /// 语音记账等入口预填的解析结果；非空时进页直接进确认/落库流程
    var initialResults: [ReceiptRecognizer.Recognized] = []
    @StateObject private var vm = AIReceiptViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var showPicker = false
    /// 点 ✎ → 打开预填的新增交易页修正
    @State private var editing: ReceiptRecognizer.Recognized?
    /// 编辑页保存成功后要移除的结果项（onDismiss 时清除）
    @State private var editRemoveTarget: ReceiptRecognizer.Recognized?

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    // 选图区
                    if let img = vm.previewImage {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 240)
                            .cornerRadius(12)
                            .padding(.horizontal, 16)
                        if vm.previewCount > 1 {
                            Text("已选 \(vm.previewCount) 张图片")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                    }

                    Button {
                        showPicker = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "photo.on.rectangle.angled")
                            Text(vm.previewImage == nil ? "选择票据图片" : "重新选择").bold()
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Theme.brand.opacity(0.12))
                        .foregroundColor(Theme.brand)
                        .cornerRadius(12)
                    }
                    .padding(.horizontal, 16)

                    if vm.isLoading {
                        VStack(spacing: 10) {
                            ProgressView()
                            Text(vm.progressText.isEmpty ? "正在识别…" : vm.progressText)
                                .font(.footnote).foregroundColor(.secondary)
                        }
                        .padding(.top, 20)
                    }

                    if vm.isAdding {
                        VStack(spacing: 10) {
                            ProgressView()
                            Text("正在添加…").font(.footnote).foregroundColor(.secondary)
                        }
                        .padding(.top, 20)
                    }

                    if let error = vm.error {
                        Text(error)
                            .font(.footnote)
                            .foregroundColor(Theme.expense)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)

                        // 识别失败：用上次的图片一键重试（不需要重新选图）
                        if !vm.isLoading && vm.hasLastImages {
                            Button {
                                Task { await vm.retry() }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "arrow.clockwise")
                                    Text("重试识别").bold()
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Theme.brand)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 4)
                        }
                    }

                    // 识别结果列表：点行勾选/取消（默认全选），✎ 进预填编辑页
                    if !vm.results.isEmpty {
                        VStack(spacing: 0) {
                            HStack {
                                Text("识别结果 (\(vm.results.count))")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(HomePalette.ink)
                                Spacer()
                                Button {
                                    vm.toggleAll()
                                } label: {
                                    Text(vm.allSelected ? "全不选" : "全选")
                                        .font(.subheadline)
                                        .foregroundColor(Theme.brand)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)

                            ForEach(vm.results) { item in
                                resultRow(item)
                            }
                        }
                        .background(Color(.secondarySystemGroupedBackground))
                        .cornerRadius(12)
                        .padding(.horizontal, 16)
                    }
                }
                .padding(.vertical, 16)
                // 底部确认栏是 overlay 悬浮的，给列表尾部留出它的占用空间，
                // 保证最后一条结果能滚到栏上方完整可见
                .padding(.bottom, 96)
            }
            // 底部确认栏用 overlay 悬浮 + 内容手动留白，不依赖 safeAreaInset
            // （iOS 15 上 sheet + NavigationView 里 safeAreaInset 定位不可靠，内容会钻到栏底下）
            .overlay(alignment: .bottom) {
                if !vm.results.isEmpty {
                    confirmBar
                }
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("AI 识图记账")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("返回") { dismiss() }
                }
            }
            // iOS 15 系统导航栏安全区坑（详见项目记忆）：NavigationView 必须显式 .stack
            .navigationViewStyle(.stack)
            .sheet(isPresented: $showPicker) {
                // 关闭相册由 binding 驱动（ReceiptPhotoPicker 不自行 UIKit dismiss），
                // 规避 iOS 15 上嵌套 sheet 被 UIKit dismiss 后父 sheet 的「返回」失效
                ReceiptPhotoPicker { datas in
                    showPicker = false
                    guard !datas.isEmpty else { return }
                    Task { await vm.recognizeAll(datas) }
                }
            }
            .sheet(item: $editing, onDismiss: {
                // 编辑页保存成功（onSaved 回调里已记下目标）→ 从结果列表移除该条
                if let target = editRemoveTarget {
                    vm.remove(target)
                    editRemoveTarget = nil
                }
            }) { item in
                // ✎ 修正页同样预填兜底后的分类/账户，与实际落库口径一致
                TransactionEditView(
                    transaction: item.asPrefillTransaction(
                        categoryId: vm.displayCategoryId(item),
                        sourceAccountId: vm.displayAccountId(item.sourceAccountId)
                    ),
                    mode: .add,
                    onSaved: {
                        editRemoveTarget = item
                    }
                )
            }
            .task {
                await vm.loadRefData()
                // 入口已带图进来（先选完图再进本页）：直接开始识别，不再拉起相册。
                // 空图进入（无入口图）时保留「选择票据图片」按钮手动选。
                if !initialImages.isEmpty {
                    await vm.recognizeAll(initialImages)
                } else if !initialResults.isEmpty {
                    // 语音记账入口：解析结果已就绪，直接进确认/落库流程
                    vm.prefill(initialResults)
                }
            }
        }
    }

    /// 底部批量确认栏：默认全部添加，一键落库，全部成功后自动返回
    private var confirmBar: some View {
        VStack(spacing: 8) {
            Button {
                Task {
                    let added = await vm.addSelected()
                    if added > 0 && vm.results.isEmpty {
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        dismiss()
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    if vm.isAdding {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                    }
                    Text(vm.isAdding ? "正在添加…" : "确认添加 (\(vm.selectedCount))")
                        .bold()
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(vm.selectedCount > 0 && !vm.isAdding ? Theme.brand : Color.gray.opacity(0.4))
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .disabled(vm.selectedCount == 0 || vm.isAdding)
            .padding(.horizontal, 16)
            .padding(.top, 10)
            // 底部再留 8pt 呼吸空间；材质延伸进 Home 指示条区域
            .padding(.bottom, 8)
            .background(.ultraThinMaterial)
            .background(Color(.systemGroupedBackground).opacity(0.6).ignoresSafeArea(edges: .bottom))
        }
    }

    private func resultRow(_ item: ReceiptRecognizer.Recognized) -> some View {
        HStack(spacing: 12) {
            // 勾选态
            Image(systemName: vm.selectedIds.contains(item.id) ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 22))
                .foregroundColor(vm.selectedIds.contains(item.id) ? Theme.brand : Color(.tertiaryLabel))

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(typeLabel(item.transactionType))
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(color(for: item.transactionType))
                        .cornerRadius(6)
                    Spacer()
                    Text(AmountFormat.format(item.sourceAmount ?? 0))
                        .font(.system(.body, design: .rounded).weight(.semibold))
                        .foregroundColor(color(for: item.transactionType))
                }
                if let time = item.time {
                    Label(timeText(time), systemImage: "clock")
                        .font(.footnote).foregroundColor(.secondary)
                }
                Label(vm.categoryName(vm.displayCategoryId(item)), systemImage: "square.grid.2x2")
                    .font(.footnote).foregroundColor(.secondary)
                Label(vm.accountName(vm.displayAccountId(item.sourceAccountId)), systemImage: "creditcard")
                    .font(.footnote).foregroundColor(.secondary)
                if let comment = item.comment, !comment.isEmpty {
                    Label(comment, systemImage: "text.alignleft")
                        .font(.footnote).foregroundColor(.secondary).lineLimit(2)
                }
            }

            // ✎ 进预填编辑页修正（保存成功后自动从结果列表移除）
            Button {
                editing = item
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 16))
                    .foregroundColor(Color(.tertiaryLabel))
                    .frame(width: 34, height: 34)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture { vm.toggle(item) }
        .overlay(alignment: .top) {
            Rectangle().fill(Color.primary.opacity(0.05)).frame(height: 0.5)
        }
    }

    private func typeLabel(_ t: TransactionType) -> String {
        switch t {
        case .expense: return "支出"
        case .income: return "收入"
        case .transfer: return "转账"
        case .modifyBalance: return "余额调整"
        }
    }

    private func color(for t: TransactionType) -> Color {
        switch t {
        case .expense: return Theme.expense
        case .income: return Theme.income
        case .transfer: return .gray
        case .modifyBalance: return Theme.brand
        }
    }

    private func timeText(_ ts: Int64) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy年M月d日 HH:mm"
        return f.string(from: Date(timeIntervalSince1970: TimeInterval(ts)))
    }
}

/// AI 识图入口的「直连」流程状态：点入口**直接拉起相册**（不再先弹中间页），
/// 选完图关掉相册后再进识别页。识别页关闭后回调给宿主刷新首页。
@MainActor
final class AIReceiptFlow: ObservableObject {
    @Published var showPicker = false
    @Published var showReceipt = false
    private(set) var images: [Data] = []

    func start() {
        images = []
        showPicker = true
    }

    /// 相册结束（选完或取消）。取消时只关相册留在原页；选到图则关相册后进识别页。
    func handleFinished(_ datas: [Data]) {
        showPicker = false
        guard !datas.isEmpty else { return }
        images = datas
        // iOS 15：上一个 sheet 的收起动画没走完就 present 下一个会静默失败，
        // 稍等再进识别页
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { [weak self] in
            self?.showReceipt = true
        }
    }
}

/// 两个入口（首页 AI 卡片 / 加号长按菜单）共用的 sheet 组合：
/// 第一层 = 相册，第二层 = 识别页
struct AIReceiptFlowModifier: ViewModifier {
    @ObservedObject var flow: AIReceiptFlow
    /// 识别页关闭后的回调（首页刷新等）
    var onReceiptDismiss: (() -> Void)? = nil

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $flow.showPicker) {
                ReceiptPhotoPicker { datas in flow.handleFinished(datas) }
            }
            .sheet(isPresented: $flow.showReceipt, onDismiss: { onReceiptDismiss?() }) {
                AIReceiptView(initialImages: flow.images)
            }
    }
}

extension Notification.Name {
    /// 交易有增删改（如加号长按入口的 AI 批量落库完成后），首页监听刷新
    static let transactionsChanged = Notification.Name("nestkeep.transactionsChanged")
}

/// 相册多选（PHPicker，免相册权限）。识图专用：一次最多选 9 张，全部加载完回调。
/// ⚠️ 本组件不自行 dismiss（哪怕点了取消）——统一走回调由调用方改 SwiftUI binding 关闭。
/// iOS 15 上嵌套 sheet 场景里 UIKit 自己 `picker.dismiss` 会搞乱 presentation 状态，
/// 导致父 sheet 之后 dismiss（返回）失灵。
/// 回调参数为本次选中的图片（取消/未选时为空数组）。
struct ReceiptPhotoPicker: UIViewControllerRepresentable {
    var selectionLimit: Int = 9
    /// 回调统一在主线程；取消时传 []
    let onFinished: ([Data]) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFinished: onFinished) }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = selectionLimit
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    /// 压到长边 ≤1280px（像素）再编码 JPEG q0.75：识图模型对分辨率不敏感（小票文字
    /// 在 1280 长边下仍清晰可读），相比 1600/q0.8 体积约减半，弱网上行时间同步减半
    private static func compressedData(_ image: UIImage) -> Data? {
        // image.size 是点，先换算成像素（@3x 截图 390×844pt 实为 1170×2532px）
        let pixelWidth = image.size.width * image.scale
        let pixelHeight = image.size.height * image.scale
        let longEdge = max(pixelWidth, pixelHeight)
        let maxEdge: CGFloat = 1280
        if longEdge > maxEdge {
            let ratio = maxEdge / longEdge
            let newSize = CGSize(width: pixelWidth * ratio, height: pixelHeight * ratio)
            let format = UIGraphicsImageRendererFormat.default()
            format.scale = 1
            let scaled = UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
                image.draw(in: CGRect(origin: .zero, size: newSize))
            }
            return scaled.jpegData(compressionQuality: 0.75)
        }
        return image.jpegData(compressionQuality: 0.75)
    }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onFinished: ([Data]) -> Void
        init(onFinished: @escaping ([Data]) -> Void) { self.onFinished = onFinished }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            // 注意：这里绝不调用 picker.dismiss，关闭交给调用方的 SwiftUI binding
            let providers = results.map(\.itemProvider).filter { $0.canLoadObject(ofClass: UIImage.self) }
            guard !providers.isEmpty else {
                onFinished([])
                return
            }

            // loadObject 回调在后台线程且并发到达：用锁保护的槽位数组按序收集
            let lock = NSLock()
            var slots = [Data?](repeating: nil, count: providers.count)
            let group = DispatchGroup()

            for (index, provider) in providers.enumerated() {
                group.enter()
                provider.loadObject(ofClass: UIImage.self) { object, _ in
                    if let image = object as? UIImage {
                        let data = ReceiptPhotoPicker.compressedData(image)
                        lock.lock()
                        slots[index] = data
                        lock.unlock()
                    }
                    group.leave()
                }
            }

            group.notify(queue: .main) { [onFinished] in
                onFinished(slots.compactMap { $0 })
            }
        }
    }
}

extension ReceiptRecognizer.Recognized {
    /// 把识别结果包装成一条「待新增」的交易，交给 TransactionEditView 预填。
    /// id 用 UUID（新增模式不会用到真实 id）。
    /// 可选传入兜底解析后的分类/账户（与批量落库口径一致），不传则用识别原值。
    func asPrefillTransaction(categoryId: String? = nil, sourceAccountId: String? = nil) -> Transaction {
        let amount = sourceAmount ?? 0
        return Transaction(
            id: UUID().uuidString,
            type: type,
            categoryId: categoryId ?? self.categoryId,
            category: nil,
            time: time ?? Int64(Date().timeIntervalSince1970),
            utcOffset: nil,
            sourceAccountId: sourceAccountId ?? self.sourceAccountId,
            sourceAccount: nil,
            destinationAccountId: destinationAccountId,
            destinationAccount: nil,
            sourceAmount: amount,
            destinationAmount: destinationAmount,
            hideAmount: nil,
            tagIds: tagIds,
            comment: comment,
            installmentPlanId: nil,
            installmentIndex: nil,
            installmentCount: nil,
            editable: nil,
            geoLocation: nil
        )
    }
}
