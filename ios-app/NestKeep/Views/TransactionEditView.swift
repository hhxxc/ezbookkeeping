import SwiftUI
import Combine
import UIKit
import PhotosUI
import CoreLocation

/// 编辑模式
enum TransactionEditMode {
    case add            // 新增
    case edit           // 编辑已有（走 modify.json）
    case duplicate      // 复制新增（保留内容、不带 id，走 add.json）
}

/// 新增 / 编辑 / 复制交易。
/// 支持 支出 / 收入 / 转账 / 余额调整 四种类型（对齐手机端 Web）。
@MainActor
final class TransactionEditViewModel: ObservableObject {
    let mode: TransactionEditMode
    let originalId: String?
    /// 待回填的原始交易（复制模式不带 id 保存）
    private let pending: Transaction?

    @Published var type: TransactionType = .expense
    @Published var amountText = ""
    @Published var sourceAccountId = ""
    @Published var destinationAccountId = ""
    @Published var categoryId = ""
    @Published var date = Date()
    @Published var comment = ""
    /// 交易时区（影响后端 utcOffset；默认当前设备时区）
    @Published var timeZoneIdentifier = TimeZone.current.identifier
    /// 地理位置（经度/纬度）
    @Published var geoLocation: TransactionGeoLocation?
    @Published var accounts: [Account] = []
    @Published var categories: [TransactionCategory] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var didSave = false

    // 标签 / 图片
    @Published var tags: [TransactionTag] = []
    @Published var tagGroups: [TransactionTagGroup] = []
    @Published var selectedTagIds: Set<String> = []
    /// 已上传的图片（pictureId + 本地预览图，用于编辑页缩略图）
    @Published var pictures: [UploadedPictureItem] = []
    @Published var isUploadingPicture = false

    /// 单张已上传图片
    struct UploadedPictureItem: Identifiable, Equatable {
        let id: String          // pictureId
        let image: UIImage?
        static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    }

    /// 编辑模式进入时的幂等会话 id（新增/复制每次保存唯一）
    private var clientSessionId = UUID().uuidString

    init(transaction: Transaction?, mode: TransactionEditMode = .add) {
        self.originalId = transaction?.id
        self.mode = mode
        self.pending = transaction
    }

    var navigationTitle: String {
        switch mode {
        case .add: return "记一笔"
        case .edit: return "编辑"
        case .duplicate: return "复制"
        }
    }

    /// 余额调整的账户只能改余额，不需要分类
    var needsCategory: Bool { type != .modifyBalance && type != .transfer }

    func load() async {
        isLoading = true
        error = nil
        do {
            async let accs: [Account] = APIClient.shared.request("/api/v1/accounts/list.json")
            async let cats = APIClient.shared.requestCategoryList()
            async let tagList: [TransactionTag] = APIClient.shared.request("/api/v1/transaction/tags/list.json")
            async let groupList: [TransactionTagGroup] = APIClient.shared.request("/api/v1/transaction/tags/groups/list.json")
            accounts = try await accs
            categories = try await cats
            tags = (try? await tagList) ?? []
            tagGroups = (try? await groupList) ?? []

            if let tx = pending {
                type = tx.transactionType
                amountText = AmountFormat.centsToText(tx.sourceAmount)
                sourceAccountId = tx.sourceAccountId ?? ""
                categoryId = tx.categoryId ?? ""
                date = tx.date
                comment = tx.comment ?? ""
                selectedTagIds = Set(tx.tagIds ?? [])
                geoLocation = tx.geoLocation
                // 由 utcOffset 反推时区（找不到精确匹配就回退设备时区）
                if let offset = tx.utcOffset {
                    timeZoneIdentifier = TimeZone.knownTimeZoneIdentifiers.first {
                        TimeZone(identifier: $0)?.secondsFromGMT(for: tx.date) == offset * 60
                    } ?? TimeZone.current.identifier
                }
                if tx.transactionType == .transfer {
                    destinationAccountId = tx.destinationAccountId ?? ""
                    if let d = tx.destinationAmount { amountText = AmountFormat.centsToText(d) }
                }
            } else {
                sourceAccountId = accounts.first?.id ?? ""
                categoryId = defaultCategoryId()
            }
            isLoading = false
        } catch {
            isLoading = false
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// 上传一张图片并加入列表（编辑页选图后调用）
    func uploadPicture(_ data: Data) async {
        isUploadingPicture = true
        defer { isUploadingPicture = false }
        do {
            let uploaded = try await PictureUploader.upload(imageData: data)
            let img = UIImage(data: data)
            pictures.append(UploadedPictureItem(id: uploaded.pictureId, image: img))
        } catch {
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    func removePicture(_ id: String) {
        pictures.removeAll { $0.id == id }
    }

    private func defaultCategoryId() -> String {
        let wantType = type == .income
            ? TransactionCategoryType.income.rawValue
            : TransactionCategoryType.expense.rawValue
        return categories.first(where: { $0.type == wantType })?.id ?? ""
    }

    /// 切换类型时同步修正默认分类（余额调整/转账不需分类）
    func typeChanged() {
        if needsCategory && categoryId.isEmpty {
            categoryId = defaultCategoryId()
        }
    }

    func save() async {
        guard let amount = Decimal(string: amountText, locale: Locale(identifier: "zh_CN")), amount > 0 else {
            error = "请输入有效金额"
            return
        }
        guard !sourceAccountId.isEmpty else {
            error = "请选择账户"
            return
        }
        if type == .transfer && destinationAccountId.isEmpty {
            error = "请选择目标账户"
            return
        }
        if needsCategory && categoryId.isEmpty {
            error = "请选择分类"
            return
        }

        let cents = Self.toCents(amount)
        let utcOffset = (TimeZone(identifier: timeZoneIdentifier) ?? .current).secondsFromGMT(for: date) / 60
        isLoading = true
        error = nil

        do {
            let tagIdList = Array(selectedTagIds)
            let pictureIdList = pictures.map { $0.id }
            if mode == .edit, let id = originalId {
                // 编辑已有交易：走 modify.json
                let req = TransactionModifyRequest(
                    id: id,
                    categoryId: needsCategory ? categoryId : "0",
                    time: Int64(date.timeIntervalSince1970),
                    utcOffset: utcOffset,
                    sourceAccountId: sourceAccountId,
                    destinationAccountId: type == .transfer ? destinationAccountId : "0",
                    sourceAmount: cents,
                    destinationAmount: type == .transfer ? cents : 0,
                    hideAmount: false,
                    tagIds: tagIdList,
                    pictureIds: pictureIdList,
                    comment: comment,
                    geoLocation: geoLocation
                )
                let _: EmptyResult = try await APIClient.shared.request(
                    "/api/v1/transactions/modify.json", method: .POST, body: req
                )
            } else {
                // 新增 / 复制：走 add.json
                let req = TransactionCreateRequest(
                    type: type.rawValue,
                    categoryId: needsCategory ? categoryId : "0",
                    time: Int64(date.timeIntervalSince1970),
                    utcOffset: utcOffset,
                    sourceAccountId: sourceAccountId,
                    destinationAccountId: type == .transfer ? destinationAccountId : nil,
                    sourceAmount: cents,
                    destinationAmount: type == .transfer ? cents : nil,
                    comment: comment.isEmpty ? nil : comment,
                    tagIds: tagIdList,
                    pictureIds: pictureIdList,
                    geoLocation: geoLocation,
                    clientSessionId: clientSessionId
                )
                let _: EmptyResult = try await APIClient.shared.request(
                    "/api/v1/transactions/add.json", method: .POST, body: req
                )
            }
            isLoading = false
            didSave = true
        } catch {
            isLoading = false
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// 元 -> 分。Xcode 26 / Swift 6 下 `Decimal * 100` 会被推断成 Float16，
    /// 必须走 NSDecimalNumber 显式乘法。
    static func toCents(_ amount: Decimal) -> Int64 {
        let handler = NSDecimalNumberHandler(
            roundingMode: .plain, scale: 0,
            raiseOnExactness: false, raiseOnOverflow: false,
            raiseOnUnderflow: false, raiseOnDivideByZero: false
        )
        return NSDecimalNumber(decimal: amount)
            .multiplying(by: NSDecimalNumber(value: 100))
            .rounding(accordingToBehavior: handler)
            .int64Value
    }
}

struct TransactionEditView: View {
    @StateObject private var vm: TransactionEditViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var amountFocused: Bool

    init(transaction: Transaction?, mode: TransactionEditMode = .add) {
        _vm = StateObject(wrappedValue: TransactionEditViewModel(transaction: transaction, mode: mode))
    }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    Picker("类型", selection: $vm.type) {
                        Text("支出").tag(TransactionType.expense)
                        Text("收入").tag(TransactionType.income)
                        Text("转账").tag(TransactionType.transfer)
                        Text("余额调整").tag(TransactionType.modifyBalance)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: vm.type) { _ in vm.typeChanged() }
                }

                Section(header: Text(vm.type == .modifyBalance ? "目标余额" : "金额")) {
                    TextField("0.00", text: $vm.amountText)
                        .keyboardType(.decimalPad)
                        .focused($amountFocused)
                }

                Section(header: Text(vm.type == .transfer ? "转出账户" : "账户")) {
                    Picker("来源账户", selection: $vm.sourceAccountId) {
                        ForEach(vm.accounts, id: \.id) { Text($0.name).tag($0.id) }
                    }
                    if vm.type == .transfer {
                        Picker("目标账户", selection: $vm.destinationAccountId) {
                            ForEach(vm.accounts.filter { $0.id != vm.sourceAccountId }, id: \.id) {
                                Text($0.name).tag($0.id)
                            }
                        }
                    }
                }

                if vm.needsCategory {
                    Section(header: Text("分类")) {
                        Picker("分类", selection: $vm.categoryId) {
                            ForEach(flatCategories(vm.categories), id: \.id) { Text($0.name).tag($0.id) }
                        }
                    }
                }

                Section(header: Text("时间")) {
                    DatePicker("时间", selection: $vm.date)
                        .labelsHidden()
                }

                Section(header: Text("时区")) {
                    Picker("时区", selection: $vm.timeZoneIdentifier) {
                        ForEach(Self.commonTimeZones, id: \.self) { tz in
                            Text(Self.timeZoneDisplay(tz)).tag(tz)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section(header: Text("地理位置")) {
                    GeoLocationRow(geoLocation: $vm.geoLocation)
                }

                if !vm.tags.isEmpty {
                    Section(header: Text("标签")) {
                        TagSelector(tags: vm.tags, groups: vm.tagGroups, selected: $vm.selectedTagIds)
                    }
                }

                Section(header: Text("图片")) {
                    PicturePickerSection(vm: vm)
                }

                Section(header: Text("备注")) {
                    TextField("可选", text: $vm.comment)
                }

                if let error = vm.error {
                    Section { Text(error).foregroundColor(.red).font(.footnote) }
                }
            }
            .navigationTitle(vm.navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task { await vm.save() }
                    } label: {
                        if vm.isLoading { ProgressView() } else { Text("保存") }
                    }
                    .disabled(vm.isLoading)
                }
            }
            .task { await vm.load() }
            .onChange(of: vm.didSave) { saved in if saved { dismiss() } }
        }
    }

    private func flatCategories(_ cats: [TransactionCategory]) -> [TransactionCategory] {
        cats.flatMap { c in
            var arr = [c]
            if let subs = c.subCategories { arr.append(contentsOf: subs) }
            return arr
        }
        .filter { cat in
            // 只展示与当前类型匹配的分类
            if vm.type == .income { return cat.type == TransactionCategoryType.income.rawValue }
            if vm.type == .expense { return cat.type == TransactionCategoryType.expense.rawValue }
            return true
        }
    }

    /// 常用时区列表（东八区排最前，其余按 offset 升序）
    private static let commonTimeZones: [String] = {
        var ids = TimeZone.knownTimeZoneIdentifiers.sorted {
            let a = TimeZone(identifier: $0)?.secondsFromGMT() ?? 0
            let b = TimeZone(identifier: $1)?.secondsFromGMT() ?? 0
            return a < b
        }
        // 把「上海」提到最前（国内用户默认）
        let asiaShanghai = "Asia/Shanghai"
        if let idx = ids.firstIndex(of: asiaShanghai) {
            ids.remove(at: idx)
            ids.insert(asiaShanghai, at: 0)
        }
        return ids
    }()

    /// 时区显示名（中文名 + UTC 偏移）
    private static func timeZoneDisplay(_ id: String) -> String {
        guard let tz = TimeZone(identifier: id) else { return id }
        let offset = tz.secondsFromGMT() / 60
        let sign = offset >= 0 ? "+" : ""
        let hours = offset / 60
        let mins = abs(offset) % 60
        let offsetStr = mins == 0 ? "\(sign)\(hours)" : "\(sign)\(hours):\(String(format: "%02d", mins))"
        let name = tz.localizedName(for: .standard, locale: Locale(identifier: "zh_CN")) ?? id
        return "\(name) (UTC\(offsetStr))"
    }
}

// MARK: - 地理位置（CoreLocation 获取）

/// 地理位置行：展示当前经纬度 + 获取/清除按钮。
struct GeoLocationRow: View {
    @Binding var geoLocation: TransactionGeoLocation?
    @State private var isLocating = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let geo = geoLocation {
                Text("\(geo.latitude, specifier: "%.6f"), \(geo.longitude, specifier: "%.6f")")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            } else if let error = error {
                Text(error).font(.footnote).foregroundColor(.red)
            }

            HStack(spacing: 12) {
                Button {
                    requestLocation()
                } label: {
                    HStack(spacing: 5) {
                        if isLocating {
                            ProgressView()
                        } else {
                            Image(systemName: "location")
                        }
                        Text(isLocating ? "定位中…" : "获取当前位置")
                    }
                    .font(.subheadline)
                }
                .disabled(isLocating)

                if geoLocation != nil {
                    Button {
                        geoLocation = nil
                    } label: {
                        Text("清除").font(.subheadline).foregroundColor(Theme.expense)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func requestLocation() {
        isLocating = true
        error = nil
        LocationHelper.shared.requestCurrentLocation { result in
            DispatchQueue.main.async {
                isLocating = false
                switch result {
                case .success(let coord):
                    geoLocation = TransactionGeoLocation(latitude: coord.latitude, longitude: coord.longitude)
                case .failure(let err):
                    error = err.errorDescription
                }
            }
        }
    }
}

/// CoreLocation 单次定位封装（iOS 15 无 async CLLocationManager，用 delegate 回调）
final class LocationHelper: NSObject, CLLocationManagerDelegate {
    /// 定位错误（供 Result 使用）
    enum LocationError: LocalizedError {
        case denied
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .denied: return "未授权定位，请在系统设置中开启"
            case .failed(let msg): return "定位失败：\(msg)"
            }
        }
    }

    static let shared = LocationHelper()

    private var manager: CLLocationManager?
    private var completion: ((Result<CLLocationCoordinate2D, LocationError>) -> Void)?

    func requestCurrentLocation(_ completion: @escaping (Result<CLLocationCoordinate2D, LocationError>) -> Void) {
        self.completion = completion
        let manager = CLLocationManager()
        self.manager = manager
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters

        let status = manager.authorizationStatus
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        default:
            self.completion?(.failure(.denied))
            self.completion = nil
            self.manager = nil
        }
    }

    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            manager.requestLocation()
        } else if status == .denied || status == .restricted {
            completion?(.failure(.denied))
            completion = nil
            self.manager = nil
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        completion?(.success(loc.coordinate))
        completion = nil
        self.manager = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        completion?(.failure(.failed(error.localizedDescription)))
        completion = nil
        self.manager = nil
    }
}

// MARK: - 标签多选

/// 标签多选：按标签组分组，点击切换选中（chip 风格，与 Web 一致）
struct TagSelector: View {
    let tags: [TransactionTag]
    let groups: [TransactionTagGroup]
    @Binding var selected: Set<String>

    private let columns = [GridItem(.adaptive(minimum: 76), spacing: 8)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(TagGrouping.sections(tags: tags, groups: groups)) { section in
                VStack(alignment: .leading, spacing: 6) {
                    Text(section.name)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                        ForEach(section.tags) { tag in
                            chip(tag)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func chip(_ tag: TransactionTag) -> some View {
        let on = selected.contains(tag.id)
        return Button {
            if on { selected.remove(tag.id) } else { selected.insert(tag.id) }
        } label: {
            HStack(spacing: 4) {
                if on { Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)) }
                Text(tag.name).lineLimit(1)
            }
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(on ? Theme.brand : Color(.tertiarySystemFill))
            .foregroundColor(on ? .white : .primary)
            .cornerRadius(14)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 图片选择与预览

/// 图片区：已上传缩略图（可删）+ 添加按钮（相册选图）
struct PicturePickerSection: View {
    @ObservedObject var vm: TransactionEditViewModel
    @State private var showPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !vm.pictures.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(vm.pictures) { p in
                            ZStack(alignment: .topTrailing) {
                                Group {
                                    if let img = p.image {
                                        Image(uiImage: img).resizable().scaledToFill()
                                    } else {
                                        Color(.tertiarySystemFill)
                                            .overlay(Image(systemName: "photo").foregroundColor(.secondary))
                                    }
                                }
                                .frame(width: 72, height: 72)
                                .clipShape(RoundedRectangle(cornerRadius: 10))

                                Button {
                                    vm.removePicture(p.id)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 16))
                                        .foregroundColor(.white)
                                        .background(Circle().fill(Color.black.opacity(0.5)))
                                }
                                .buttonStyle(.plain)
                                .offset(x: 5, y: -5)
                            }
                        }
                    }
                    .padding(.vertical, 6)
                }
            }

            Button {
                showPicker = true
            } label: {
                HStack(spacing: 6) {
                    if vm.isUploadingPicture {
                        ProgressView()
                    } else {
                        Image(systemName: "photo.badge.plus")
                    }
                    Text(vm.isUploadingPicture ? "上传中…" : "添加图片")
                }
                .font(.subheadline)
            }
            .disabled(vm.isUploadingPicture)
        }
        .sheet(isPresented: $showPicker) {
            PhotoPicker { imageData in
                Task { await vm.uploadPicture(imageData) }
            }
        }
    }
}

// MARK: - 相册选图（PHPicker，免权限）

/// 最小化的 PHPicker 封装：单选一张，回调 JPEG 数据。
/// 用 PHPickerViewController 而非 UIImagePickerController，避免相册权限弹窗。
struct PhotoPicker: UIViewControllerRepresentable {
    let onPicked: (Data) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPicked: onPicked) }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onPicked: (Data) -> Void
        init(onPicked: @escaping (Data) -> Void) { self.onPicked = onPicked }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard let provider = results.first?.itemProvider,
                  provider.canLoadObject(ofClass: UIImage.self) else { return }
            provider.loadObject(ofClass: UIImage.self) { object, _ in
                guard let image = object as? UIImage,
                      let data = image.jpegData(compressionQuality: 0.8) else { return }
                DispatchQueue.main.async { self.onPicked(data) }
            }
        }
    }
}
