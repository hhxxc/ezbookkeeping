import SwiftUI
import Combine

/// 数据管理：统计 / 清空 / 导出（对齐 Web 的数据管理页）
@MainActor
final class DataManagementViewModel: ObservableObject {
    @Published var stats: DataStatistics?
    @Published var isLoading = false
    @Published var error: String?
    @Published var isWorking = false

    func load() async {
        isLoading = true
        error = nil
        do {
            stats = try await APIClient.shared.request("/api/v1/data/statistics.json")
            isLoading = false
        } catch {
            isLoading = false
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// 清空全部交易
    func clearAllTransactions() async -> Bool {
        isWorking = true
        defer { isWorking = false }
        do {
            let _: EmptyResult = try await APIClient.shared.request(
                "/api/v1/data/clear/transactions.json", method: .POST
            )
            await load()
            return true
        } catch {
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    /// 清空全部数据（账户 / 分类 / 标签 / 交易 / 图片）
    func clearAllData() async -> Bool {
        isWorking = true
        defer { isWorking = false }
        do {
            let _: EmptyResult = try await APIClient.shared.request(
                "/api/v1/data/clear/all.json", method: .POST
            )
            await load()
            return true
        } catch {
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    /// 导出 CSV 的下载地址（带 token 由 App 内下载后再分享）
    func exportCSVURL() -> URL? {
        AppSettings.shared.serverURL.appendingPathComponent("/api/v1/data/export.csv")
    }
}

/// 数据统计模型（对应 Go DataStatisticsResponse，全部为字符串化 int64）
struct DataStatistics: Codable {
    let totalAccountCount: String?
    let totalTransactionCategoryCount: String?
    let totalTransactionTagCount: String?
    let totalTransactionCount: String?
    let totalTransactionPictureCount: String?
    let totalTransactionTemplateCount: String?

    var accountCount: Int { Int(totalAccountCount ?? "0") ?? 0 }
    var categoryCount: Int { Int(totalTransactionCategoryCount ?? "0") ?? 0 }
    var tagCount: Int { Int(totalTransactionTagCount ?? "0") ?? 0 }
    var transactionCount: Int { Int(totalTransactionCount ?? "0") ?? 0 }
    var pictureCount: Int { Int(totalTransactionPictureCount ?? "0") ?? 0 }
    var templateCount: Int { Int(totalTransactionTemplateCount ?? "0") ?? 0 }
}

struct DataManagementView: View {
    @StateObject private var vm = DataManagementViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var showClearTx = false
    @State private var showClearAll = false

    var body: some View {
        List {
            Section(header: Text("数据统计")) {
                statRow("账户", vm.stats?.accountCount)
                statRow("分类", vm.stats?.categoryCount)
                statRow("标签", vm.stats?.tagCount)
                statRow("账单", vm.stats?.transactionCount)
                statRow("图片", vm.stats?.pictureCount)
                statRow("模板", vm.stats?.templateCount)
            }

            Section(header: Text("导出")) {
                Button {
                    exportCSV()
                } label: {
                    Label("导出为 CSV", systemImage: "square.and.arrow.up")
                }
            }

            Section(
                header: Text("危险操作"),
                footer: Text("清空操作不可撤销，请先导出备份。")
            ) {
                Button(role: .destructive) {
                    showClearTx = true
                } label: {
                    Label("清空全部账单", systemImage: "trash")
                }
                Button(role: .destructive) {
                    showClearAll = true
                } label: {
                    Label("清空全部数据", systemImage: "exclamationmark.triangle")
                }
            }

            if let error = vm.error {
                Section { Text(error).foregroundColor(.red).font(.footnote) }
            }
        }
        .navigationTitle("数据管理")
        .refreshable { await vm.load() }
        .confirmationDialog("清空全部账单？", isPresented: $showClearTx, titleVisibility: .visible) {
            Button("清空", role: .destructive) { Task { _ = await vm.clearAllTransactions() } }
            Button("取消", role: .cancel) {}
        } message: {
            Text("所有账单记录将被永久删除，账户保留。")
        }
        .confirmationDialog("清空全部数据？", isPresented: $showClearAll, titleVisibility: .visible) {
            Button("全部清空", role: .destructive) { Task { _ = await vm.clearAllData() } }
            Button("取消", role: .cancel) {}
        } message: {
            Text("账户、分类、标签、账单、图片都会被永久删除，且无法恢复。")
        }
        .task { await vm.load() }
    }

    @ViewBuilder
    private func statRow(_ title: String, _ value: Int?) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value.map { "\($0)" } ?? "—").foregroundColor(.secondary)
        }
    }

    /// 导出 CSV：带 token 下载到临时文件后弹系统分享
    private func exportCSV() {
        guard let base = vm.exportCSVURL() else { return }
        var req = URLRequest(url: base)
        if let token = AuthManager.shared.token {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let tz = TimeZone.current
        req.setValue("\(tz.secondsFromGMT() / 60)", forHTTPHeaderField: "X-Timezone-Offset")

        URLSession.shared.dataTask(with: req) { data, _, _ in
            guard let data = data else { return }
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent("ezbookkeeping-export.csv")
            try? data.write(to: tmp)
            DispatchQueue.main.async {
                let activity = UIActivityViewController(activityItems: [tmp], applicationActivities: nil)
                if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let root = scene.windows.first?.rootViewController {
                    root.present(activity, animated: true)
                }
            }
        }.resume()
    }
}
