import SwiftUI
import Combine

/// 计划账单频率类型（对应 Go TransactionScheduleFrequencyType / Web ScheduledTemplateFrequencyType）
enum ScheduleFrequencyType: Int, CaseIterable, Identifiable {
    case disabled = 0
    case weekly = 1
    case monthly = 2
    case daily = 3
    case yearly = 4

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .disabled: return "禁用"
        case .daily: return "每日"
        case .weekly: return "每周"
        case .monthly: return "每月"
        case .yearly: return "每年"
        }
    }
}

/// 模板新增 / 编辑。
/// 普通模板（templateType=1）与计划账单（templateType=2）共用表单；
/// 计划账单额外提供频率 / 起止日期。对齐 Web 的 `/template/add`、`/template/edit`。
@MainActor
final class TemplateEditViewModel: ObservableObject {
    let template: TransactionTemplate?
    let templateType: Int

    @Published var name = ""
    @Published var type: TransactionType = .expense
    @Published var categoryId = ""
    @Published var sourceAccountId = ""
    @Published var destinationAccountId = ""
    @Published var amountText = ""
    @Published var comment = ""
    @Published var selectedTagIds: Set<String> = []

    // 计划账单字段
    @Published var frequencyType: ScheduleFrequencyType = .disabled
    @Published var frequencyValues: Set<Int> = []
    @Published var startDate: String = ""
    @Published var endDate: String = ""

    @Published var accounts: [Account] = []
    @Published var categories: [TransactionCategory] = []
    @Published var tags: [TransactionTag] = []
    @Published var tagGroups: [TransactionTagGroup] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var didSave = false

    var isSchedule: Bool { templateType == 2 }
    var isEdit: Bool { template != nil }
    /// 转账需要目标账户；余额调整不允许作为模板
    var needsCategory: Bool { type != .transfer }

    init(template: TransactionTemplate?, templateType: Int) {
        self.template = template
        self.templateType = templateType
    }

    var navigationTitle: String {
        if isEdit { return isSchedule ? "编辑计划账单" : "编辑模板" }
        return isSchedule ? "新增计划账单" : "新增模板"
    }

    func load() async {
        isLoading = true
        error = nil
        do {
            async let accs: [Account] = APIClient.shared.request("/api/v1/accounts/list.json")
            async let cats: [TransactionCategory] = APIClient.shared.request("/api/v1/transaction/categories/list.json")
            async let tagList: [TransactionTag] = APIClient.shared.request("/api/v1/transaction/tags/list.json")
            async let groupList: [TransactionTagGroup] = APIClient.shared.request("/api/v1/transaction/tags/groups/list.json")
            accounts = try await accs
            categories = try await cats
            tags = (try? await tagList) ?? []
            tagGroups = (try? await groupList) ?? []

            if let t = template {
                name = t.name
                type = t.transactionType
                categoryId = t.categoryId ?? ""
                sourceAccountId = t.sourceAccountId ?? ""
                destinationAccountId = t.destinationAccountId ?? ""
                amountText = AmountFormat.centsToText(t.sourceAmount)
                comment = t.comment ?? ""
                selectedTagIds = Set(t.tagIds ?? [])
                frequencyType = ScheduleFrequencyType(rawValue: t.scheduledFrequencyType ?? 0) ?? .disabled
                frequencyValues = parseFrequency(t.scheduledFrequency)
                startDate = t.scheduledStartDate ?? ""
                endDate = t.scheduledEndDate ?? ""
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

    /// 解析 "1,3" -> [1,3]
    private func parseFrequency(_ s: String?) -> Set<Int> {
        guard let s = s, !s.isEmpty else { return [] }
        return Set(s.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) })
    }

    /// 序列化 [1,3] -> "1,3"（升序）
    private func serializeFrequency() -> String {
        frequencyValues.sorted().map(String.init).joined(separator: ",")
    }

    private func defaultCategoryId() -> String {
        let wantType = type == .income
            ? TransactionCategoryType.income.rawValue
            : TransactionCategoryType.expense.rawValue
        return categories.first(where: { $0.type == wantType })?.id ?? ""
    }

    func typeChanged() {
        if needsCategory && categoryId.isEmpty {
            categoryId = defaultCategoryId()
        }
    }

    func save() async {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            error = "请输入模板名称"
            return
        }
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

        let cents = TransactionEditViewModel.toCents(amount)
        let isTransfer = type == .transfer
        isLoading = true
        error = nil

        do {
            let tagIds = Array(selectedTagIds)
            if isEdit, let id = template?.id {
                let req = TemplateModifyRequest(
                    id: id, name: name.trimmingCharacters(in: .whitespaces), type: type.rawValue,
                    categoryId: needsCategory ? categoryId : "0",
                    sourceAccountId: sourceAccountId,
                    destinationAccountId: isTransfer ? destinationAccountId : "0",
                    sourceAmount: cents,
                    destinationAmount: isTransfer ? cents : 0,
                    tagIds: tagIds, comment: comment,
                    scheduledFrequencyType: isSchedule ? frequencyType.rawValue : nil,
                    scheduledFrequency: isSchedule ? serializeFrequency() : nil,
                    scheduledStartDate: isSchedule ? (startDate.isEmpty ? nil : startDate) : nil,
                    scheduledEndDate: isSchedule ? (endDate.isEmpty ? nil : endDate) : nil,
                    utcOffset: isSchedule ? Int16(TimeZone.current.secondsFromGMT() / 60) : nil
                )
                let _: EmptyResult = try await APIClient.shared.request(
                    "/api/v1/transaction/templates/modify.json", method: .POST, body: req
                )
            } else {
                let req = TemplateCreateRequest(
                    templateType: templateType, name: name.trimmingCharacters(in: .whitespaces),
                    type: type.rawValue,
                    categoryId: needsCategory ? categoryId : "0",
                    sourceAccountId: sourceAccountId,
                    destinationAccountId: isTransfer ? destinationAccountId : "0",
                    sourceAmount: cents,
                    destinationAmount: isTransfer ? cents : 0,
                    tagIds: tagIds, comment: comment,
                    scheduledFrequencyType: isSchedule ? frequencyType.rawValue : nil,
                    scheduledFrequency: isSchedule ? serializeFrequency() : nil,
                    scheduledStartDate: isSchedule ? (startDate.isEmpty ? nil : startDate) : nil,
                    scheduledEndDate: isSchedule ? (endDate.isEmpty ? nil : endDate) : nil,
                    utcOffset: isSchedule ? Int16(TimeZone.current.secondsFromGMT() / 60) : nil,
                    clientSessionId: UUID().uuidString
                )
                let _: EmptyResult = try await APIClient.shared.request(
                    "/api/v1/transaction/templates/add.json", method: .POST, body: req
                )
            }
            isLoading = false
            didSave = true
        } catch {
            isLoading = false
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }
}

/// 模板新增 / 编辑请求体（对应 Go TransactionTemplateCreateRequest / ModifyRequest）
struct TemplateCreateRequest: Codable {
    let templateType: Int
    let name: String
    let type: Int
    let categoryId: String
    let sourceAccountId: String
    let destinationAccountId: String
    let sourceAmount: Int64
    let destinationAmount: Int64
    let tagIds: [String]
    let comment: String
    let scheduledFrequencyType: Int?
    let scheduledFrequency: String?
    let scheduledStartDate: String?
    let scheduledEndDate: String?
    let utcOffset: Int16?
    let clientSessionId: String
}

struct TemplateModifyRequest: Codable {
    let id: String
    let name: String
    let type: Int
    let categoryId: String
    let sourceAccountId: String
    let destinationAccountId: String
    let sourceAmount: Int64
    let destinationAmount: Int64
    let tagIds: [String]
    let comment: String
    let scheduledFrequencyType: Int?
    let scheduledFrequency: String?
    let scheduledStartDate: String?
    let scheduledEndDate: String?
    let utcOffset: Int16?
}

struct TemplateEditView: View {
    @StateObject private var vm: TemplateEditViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showStartDate = false
    @State private var showEndDate = false
    @State private var showFrequency = false

    init(template: TransactionTemplate?, templateType: Int) {
        _vm = StateObject(wrappedValue: TemplateEditViewModel(template: template, templateType: templateType))
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("名称")) {
                    TextField("模板名称", text: $vm.name)
                }

                Section {
                    Picker("类型", selection: $vm.type) {
                        Text("支出").tag(TransactionType.expense)
                        Text("收入").tag(TransactionType.income)
                        Text("转账").tag(TransactionType.transfer)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: vm.type) { _ in vm.typeChanged() }
                }

                Section(header: Text("金额")) {
                    TextField("0.00", text: $vm.amountText)
                        .keyboardType(.decimalPad)
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

                if !vm.tags.isEmpty {
                    Section(header: Text("标签")) {
                        TagSelector(tags: vm.tags, groups: vm.tagGroups, selected: $vm.selectedTagIds)
                    }
                }

                Section(header: Text("备注")) {
                    TextField("可选", text: $vm.comment)
                }

                if vm.isSchedule {
                    Section(header: Text("计划频率")) {
                        Button {
                            showFrequency = true
                        } label: {
                            HStack {
                                Text("频率")
                                Spacer()
                                Text(frequencySummary).foregroundColor(.secondary)
                            }
                        }
                        Button {
                            showStartDate = true
                        } label: {
                            HStack {
                                Text("开始日期")
                                Spacer()
                                Text(vm.startDate.isEmpty ? "不限" : vm.startDate).foregroundColor(.secondary)
                            }
                        }
                        Button {
                            showEndDate = true
                        } label: {
                            HStack {
                                Text("结束日期")
                                Spacer()
                                Text(vm.endDate.isEmpty ? "不限" : vm.endDate).foregroundColor(.secondary)
                            }
                        }
                    }
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
            .sheet(isPresented: $showFrequency) {
                FrequencyPickerSheet(type: $vm.frequencyType, values: $vm.frequencyValues)
            }
            .sheet(isPresented: $showStartDate) {
                DateOnlyPickerSheet(title: "开始日期", dateString: $vm.startDate)
            }
            .sheet(isPresented: $showEndDate) {
                DateOnlyPickerSheet(title: "结束日期", dateString: $vm.endDate)
            }
        }
    }

    private var frequencySummary: String {
        switch vm.frequencyType {
        case .disabled: return "禁用"
        case .daily: return "每日"
        case .weekly:
            let names = vm.frequencyValues.sorted().map(weekdayName)
            return names.isEmpty ? "每周" : "每周 " + names.joined(separator: "、")
        case .monthly:
            let days = vm.frequencyValues.sorted().map { "\($0)日" }
            return days.isEmpty ? "每月" : "每月 " + days.joined(separator: "、")
        case .yearly:
            let items = vm.frequencyValues.sorted().map(monthDayName)
            return items.isEmpty ? "每年" : "每年 " + items.joined(separator: "、")
        }
    }

    private func weekdayName(_ v: Int) -> String {
        // 0=周日 ... 6=周六（对齐 Go time.Weekday / Web WeekDay）
        ["周日", "周一", "周二", "周三", "周四", "周五", "周六"][v % 7]
    }

    private func monthDayName(_ v: Int) -> String {
        let month = v / 100
        let day = v % 100
        return "\(month)月\(day)日"
    }

    private func flatCategories(_ cats: [TransactionCategory]) -> [TransactionCategory] {
        cats.flatMap { c in
            var arr = [c]
            if let subs = c.subCategories { arr.append(contentsOf: subs) }
            return arr
        }
        .filter { cat in
            if vm.type == .income { return cat.type == TransactionCategoryType.income.rawValue }
            if vm.type == .expense { return cat.type == TransactionCategoryType.expense.rawValue }
            return true
        }
    }
}

// MARK: - 频率选择

/// 计划账单频率选择：类型 + 具体值多选（对齐 Web ScheduleFrequencySheet）
struct FrequencyPickerSheet: View {
    @Binding var type: ScheduleFrequencyType
    @Binding var values: Set<Int>
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("频率")) {
                    Picker("频率", selection: $type) {
                        ForEach(ScheduleFrequencyType.allCases) { t in Text(t.displayName).tag(t) }
                    }
                    .pickerStyle(.segmented)
                }

                switch type {
                case .disabled, .daily:
                    EmptyView()
                case .weekly:
                    Section(header: Text("选择星期")) {
                        ForEach(0..<7, id: \.self) { v in
                            Button {
                                toggle(v)
                            } label: {
                                HStack {
                                    Text(["周日", "周一", "周二", "周三", "周四", "周五", "周六"][v])
                                    Spacer()
                                    if values.contains(v) {
                                        Image(systemName: "checkmark").foregroundColor(Theme.brand)
                                    }
                                }
                            }
                            .foregroundColor(.primary)
                        }
                    }
                case .monthly:
                    Section(header: Text("选择日期")) {
                        ForEach(1...28, id: \.self) { v in
                            Button {
                                toggle(v)
                            } label: {
                                HStack {
                                    Text("\(v)日")
                                    Spacer()
                                    if values.contains(v) {
                                        Image(systemName: "checkmark").foregroundColor(Theme.brand)
                                    }
                                }
                            }
                            .foregroundColor(.primary)
                        }
                    }
                case .yearly:
                    Section(header: Text("选择月与日")) {
                        ForEach(1...12, id: \.self) { month in
                            let maxDay = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][month - 1]
                            ForEach(1...maxDay, id: \.self) { day in
                                let code = month * 100 + day
                                Button {
                                    toggle(code)
                                } label: {
                                    HStack {
                                        Text("\(month)月\(day)日")
                                        Spacer()
                                        if values.contains(code) {
                                            Image(systemName: "checkmark").foregroundColor(Theme.brand)
                                        }
                                    }
                                }
                                .foregroundColor(.primary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("计划频率")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private func toggle(_ v: Int) {
        if values.contains(v) { values.remove(v) } else { values.insert(v) }
    }
}

// MARK: - 日期选择（YYYY-MM-DD）

/// 单日期选择，输出 YYYY-MM-DD 字符串（对齐 Web date-selection-sheet 的 TextualYearMonthDay）
struct DateOnlyPickerSheet: View {
    let title: String
    @Binding var dateString: String
    @Environment(\.dismiss) private var dismiss

    @State private var date = Date()
    @State private var useNone = false

    var body: some View {
        NavigationView {
            Form {
                Section {
                    Toggle("不限制", isOn: $useNone)
                }
                if !useNone {
                    Section(header: Text(title)) {
                        DatePicker(title, selection: $date, displayedComponents: .date)
                            .datePickerStyle(.graphical)
                            .labelsHidden()
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") {
                        dateString = useNone ? "" : Self.formatter.string(from: date)
                        dismiss()
                    }
                }
            }
            .onAppear {
                if let d = Self.formatter.date(from: dateString) {
                    date = d
                }
                useNone = dateString.isEmpty
            }
        }
    }

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}
