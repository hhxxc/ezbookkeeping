import SwiftUI
import Combine

/// 汇率页：展示最新汇率列表（含数据源与更新时间），
/// 支持自定义汇率的新增（输入「1 基准货币 = ? 目标货币」）与删除。
/// 与手机端 Web 的 `exchange_rates` 页对齐；基准货币由后端返回，不可改删。
@MainActor
final class ExchangeRatesViewModel: ObservableObject {
    @Published var data: LatestExchangeRateResponse?
    @Published var isLoading = false
    @Published var error: String?

    /// 当前用户的默认货币（= 自定义汇率的计价基准）
    var defaultCurrency: String { AuthManager.shared.currentUser?.defaultCurrency ?? "CNY" }

    /// 列表里除基准货币外的可换算货币（按货币代码排序）
    var rates: [LatestExchangeRate] {
        (data?.exchangeRates ?? []).sorted { $0.currency < $1.currency }
    }

    var updateTimeText: String {
        guard let ts = data?.updateTime, ts > 0 else { return "—" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.string(from: Date(timeIntervalSince1970: TimeInterval(ts)))
    }

    func load() async {
        isLoading = true
        error = nil
        do {
            data = try await APIClient.shared.request("/api/v1/exchange_rates/latest.json")
            isLoading = false
        } catch {
            isLoading = false
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// 新增/更新自定义汇率（rate = 1 默认货币 兑 target 的数量）
    func updateCustomRate(target: String, rate: Double) async -> Bool {
        do {
            let req = UserCustomExchangeRateUpdateRequest(currency: target.uppercased(), rate: "\(rate)")
            let _: UserCustomExchangeRateUpdateResponse = try await APIClient.shared.request(
                "/api/v1/exchange_rates/user_custom/update.json", method: .POST, body: req
            )
            await load()
            return true
        } catch {
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    /// 删除某自定义汇率（默认货币不可删，后端会拒绝）
    func deleteCustomRate(_ currency: String) async {
        do {
            let req = UserCustomExchangeRateDeleteRequest(currency: currency)
            let _: Bool = try await APIClient.shared.request(
                "/api/v1/exchange_rates/user_custom/delete.json", method: .POST, body: req
            )
            await load()
        } catch {
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    func currencyName(_ code: String) -> String {
        Locale(identifier: "zh_CN").localizedString(forCurrencyCode: code) ?? code
    }
}

struct ExchangeRatesView: View {
    @StateObject private var vm = ExchangeRatesViewModel()
    @Environment(\.mainTabBarInset) private var tabBarInset
    @State private var showAdd = false
    @State private var pendingDelete: String?

    var body: some View {
        List {
            if vm.isLoading && vm.data == nil {
                Section { HStack { Spacer(); ProgressView(); Spacer() } }
            }

            if let error = vm.error {
                Section { Text(error).font(.footnote).foregroundColor(Theme.expense) }
            }

            Section(header: Text("汇率（1 \(vm.defaultCurrency) =）")) {
                if vm.rates.isEmpty && !vm.isLoading {
                    Text("暂无汇率数据").foregroundColor(.secondary)
                }
                ForEach(vm.rates) { rate in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(vm.currencyName(rate.currency))")
                            Text(rate.currency).font(.footnote).foregroundColor(.secondary)
                        }
                        Spacer()
                        Text(rate.rate).font(.system(.body, design: .rounded))
                            .foregroundColor(.primary)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if rate.currency != vm.defaultCurrency {
                            Button(role: .destructive) {
                                pendingDelete = rate.currency
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }
                }
            }

            Section {
                if let ds = vm.data?.dataSource, !ds.isEmpty {
                    HStack {
                        Text("数据源")
                        Spacer()
                        if let urlStr = vm.data?.referenceUrl, let url = URL(string: urlStr) {
                            Link(ds, destination: url).font(.footnote)
                        } else {
                            Text(ds).font(.footnote).foregroundColor(.secondary)
                        }
                    }
                }
                HStack {
                    Text("更新时间")
                    Spacer()
                    Text(vm.updateTimeText).font(.footnote).foregroundColor(.secondary)
                }
            }
        }
        .listStyle(.insetGrouped)
        .safeAreaInset(edge: .bottom) { Color.clear.frame(height: tabBarInset) }
        .navigationTitle("汇率")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showAdd = true } label: { Image(systemName: "plus") }
            }
        }
        .refreshable { await vm.load() }
        .task { await vm.load() }
        .sheet(isPresented: $showAdd) {
            ExchangeRateEditSheet(vm: vm)
        }
        .confirmationDialog("确认删除该自定义汇率？", isPresented: Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        ), titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                if let c = pendingDelete { Task { await vm.deleteCustomRate(c) } }
                pendingDelete = nil
            }
            Button("取消", role: .cancel) { pendingDelete = nil }
        }
    }
}

/// 新增自定义汇率：1 个默认货币 = 若干个目标货币
struct ExchangeRateEditSheet: View {
    @ObservedObject var vm: ExchangeRatesViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var targetCurrency = ""
    @State private var rateText = "1"
    @State private var submitting = false
    @State private var errorText: String?

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("基准货币")) {
                    HStack {
                        Text(vm.currencyName(vm.defaultCurrency))
                        Spacer()
                        Text(vm.defaultCurrency).foregroundColor(.secondary)
                    }
                }
                Section(header: Text("目标货币代码（3 位）"),
                        footer: Text("如 USD、HKD、JPY。默认货币自身不能设置自定义汇率。")) {
                    TextField("USD", text: $targetCurrency)
                        .autocapitalization(.allCharacters)
                        .disableAutocorrection(true)
                }
                Section(header: Text("汇率"),
                        footer: Text("含义：1 \(vm.defaultCurrency) = 填入数值 的目标货币")) {
                    TextField("1", text: $rateText)
                        .keyboardType(.decimalPad)
                }
                if let errorText = errorText {
                    Section { Text(errorText).font(.footnote).foregroundColor(Theme.expense) }
                }
            }
            .navigationTitle("自定义汇率")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task {
                            submitting = true
                            errorText = nil
                            let code = targetCurrency.uppercased()
                            guard code.count == 3 else {
                                errorText = "货币代码必须是 3 位"
                                submitting = false
                                return
                            }
                            guard let rate = Double(rateText), rate > 0 else {
                                errorText = "请输入有效汇率"
                                submitting = false
                                return
                            }
                            let ok = await vm.updateCustomRate(target: code, rate: rate)
                            submitting = false
                            if ok { dismiss() } else { errorText = vm.error }
                        }
                    } label: {
                        if submitting { ProgressView() } else { Text("保存") }
                    }
                    .disabled(submitting)
                }
            }
        }
    }
}
