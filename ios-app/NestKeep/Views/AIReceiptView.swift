import SwiftUI
import UIKit
import Combine

/// AI 识图记账页：选票据图 → 识别 → 结果列表 → 选中一条进「新增交易」并预填。
/// 后端关闭该能力时首页入口不展示；仍被打开时用错误提示兜底（避免空白页）。
@MainActor
final class AIReceiptViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var error: String?
    @Published var results: [ReceiptRecognizer.Recognized] = []
    @Published var previewImage: UIImage?
    @Published var accounts: [Account] = []
    @Published var categories: [TransactionCategory] = []

    func loadRefData() async {
        accounts = (try? await APIClient.shared.request("/api/v1/accounts/list.json")) ?? []
        categories = (try? await APIClient.shared.request("/api/v1/transaction/categories/list.json")) ?? []
    }

    func recognize(_ data: Data) async {
        isLoading = true
        error = nil
        results = []
        previewImage = UIImage(data: data)
        do {
            results = try await ReceiptRecognizer.recognize(imageData: data)
            if results.isEmpty { error = "图片中没有识别到交易信息" }
            isLoading = false
        } catch {
            isLoading = false
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    func reset() {
        results = []
        previewImage = nil
        error = nil
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
    /// 选中的识别结果 → 打开预填的新增交易页
    @State private var editing: ReceiptRecognizer.Recognized?

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
                            Text("正在识别…").font(.footnote).foregroundColor(.secondary)
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

                    // 识别结果
                    ForEach(vm.results) { item in
                        Button {
                            editing = item
                        } label: {
                            resultCard(item)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 16)
                    }

                    if !vm.results.isEmpty {
                        Text("点击任一条结果，进入记账页确认后保存")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 16)
            }
            .safeAreaInset(edge: .bottom) { Color.clear.frame(height: tabBarInset) }
            .navigationTitle("AI 识图记账")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("返回") { dismiss() }
                }
            }
            .sheet(isPresented: $showPicker) {
                PhotoPicker { data in
                    Task { await vm.recognize(data) }
                }
            }
            .sheet(item: $editing) { item in
                TransactionEditView(transaction: item.asPrefillTransaction(), mode: .add)
            }
            .task { await vm.loadRefData() }
        }
    }

    private func resultCard(_ item: ReceiptRecognizer.Recognized) -> some View {
        VStack(alignment: .leading, spacing: 8) {
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
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
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
            geoLocation: nil
        )
    }
}
