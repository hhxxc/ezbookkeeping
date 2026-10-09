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
        accounts = (try? await APIClient.shared.request("/api/v1/accounts/list.json")) ?? []
        categories = (try? await APIClient.shared.requestCategoryList()) ?? []
    }

    /// 识别多张图片（顺序识别，结果合并；单张失败不中断，最后汇总提示）
    func recognizeAll(_ images: [Data]) async {
        guard !images.isEmpty else { return }
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
                all += try await ReceiptRecognizer.recognize(imageData: data)
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
                let req = TransactionCreateRequest(
                    type: item.type,
                    categoryId: item.categoryId ?? "0",
                    time: time,
                    utcOffset: tz.secondsFromGMT(for: date) / 60,
                    sourceAccountId: item.sourceAccountId ?? "",
                    destinationAccountId: isTransfer ? item.destinationAccountId : nil,
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
}

struct AIReceiptView: View {
    @StateObject private var vm = AIReceiptViewModel()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.mainTabBarInset) private var tabBarInset
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
                                .font(.caption)
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
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 0) {
                    if !vm.results.isEmpty {
                        confirmBar
                    }
                    Color.clear.frame(height: tabBarInset)
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
            .sheet(isPresented: $showPicker) {
                ReceiptPhotoPicker { datas in
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
                TransactionEditView(transaction: item.asPrefillTransaction(), mode: .add, onSaved: {
                    editRemoveTarget = item
                })
            }
            .task {
                await vm.loadRefData()
                // 进入页面直接拉起相册，少一步「选择票据图片」
                try? await Task.sleep(nanoseconds: 400_000_000)
                showPicker = true
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
            .background(.ultraThinMaterial)
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
                        .font(.caption.weight(.semibold))
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
                        .font(.caption).foregroundColor(.secondary)
                }
                Label(vm.categoryName(item.categoryId), systemImage: "square.grid.2x2")
                    .font(.caption).foregroundColor(.secondary)
                Label(vm.accountName(item.sourceAccountId), systemImage: "creditcard")
                    .font(.caption).foregroundColor(.secondary)
                if let comment = item.comment, !comment.isEmpty {
                    Label(comment, systemImage: "text.alignleft")
                        .font(.caption).foregroundColor(.secondary).lineLimit(2)
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

/// 相册多选（PHPicker，免相册权限）。识图页专用：一次最多选 9 张，全部加载完回调。
struct ReceiptPhotoPicker: UIViewControllerRepresentable {
    var selectionLimit: Int = 9
    let onPicked: ([Data]) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPicked: onPicked) }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = selectionLimit
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onPicked: ([Data]) -> Void
        init(onPicked: @escaping ([Data]) -> Void) { self.onPicked = onPicked }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)

            let providers = results.map(\.itemProvider).filter { $0.canLoadObject(ofClass: UIImage.self) }
            guard !providers.isEmpty else { return }

            // loadObject 回调在后台线程且并发到达：用锁保护的槽位数组按序收集
            let lock = NSLock()
            var slots = [Data?](repeating: nil, count: providers.count)
            let group = DispatchGroup()

            for (index, provider) in providers.enumerated() {
                group.enter()
                provider.loadObject(ofClass: UIImage.self) { object, _ in
                    if let image = object as? UIImage {
                        let data = image.jpegData(compressionQuality: 0.8)
                        lock.lock()
                        slots[index] = data
                        lock.unlock()
                    }
                    group.leave()
                }
            }

            group.notify(queue: .main) { [onPicked] in
                let images = slots.compactMap { $0 }
                if !images.isEmpty { onPicked(images) }
            }
        }
    }
}

extension ReceiptRecognizer.Recognized {
    /// 把识别结果包装成一条「待新增」的交易，交给 TransactionEditView 预填。
    /// id 用 UUID（新增模式不会用到真实 id）。
    func asPrefillTransaction() -> Transaction {
        let amount = sourceAmount ?? 0
        return Transaction(
            id: UUID().uuidString,
            type: type,
            categoryId: categoryId,
            category: nil,
            time: time ?? Int64(Date().timeIntervalSince1970),
            utcOffset: nil,
            sourceAccountId: sourceAccountId,
            sourceAccount: nil,
            destinationAccountId: destinationAccountId,
            destinationAccount: nil,
            sourceAmount: amount,
            destinationAmount: destinationAmount,
            hideAmount: nil,
            tagIds: tagIds,
            comment: comment,
            editable: nil,
            geoLocation: nil,
            installmentPlanId: nil,
            installmentIndex: nil,
            installmentCount: nil
        )
    }
}
