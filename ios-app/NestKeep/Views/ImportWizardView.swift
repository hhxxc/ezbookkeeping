import SwiftUI
import UniformTypeIdentifiers

/// 原生账单导入向导：支持 ezBookkeeping 自家导出的 CSV/TSV 文件（后端内置解析器，零列映射）。
/// 流程：选格式 → 选文件 → 后端解析预览 → 确认导入。
/// 自定义格式（列映射/类型映射）仍请用 Web 端数据管理页。
struct ImportWizardView: View {
    /// 导入成功后回调（外层刷新列表/汇总）
    let onImported: () -> Void
    @Environment(\.dismiss) private var dismiss

    @StateObject private var vm = ImportWizardViewModel()

    /// 支持 ezBookkeeping 导出的两种格式
    enum ImportFormat: String, CaseIterable, Identifiable {
        case csv = "ezbookkeeping_csv"
        case tsv = "ezbookkeeping_tsv"

        var id: String { rawValue }
        var label: String { self == .csv ? "CSV（逗号分隔）" : "TSV（制表符分隔）" }
        var fileExtension: String { self == .csv ? "csv" : "tsv" }
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("文件格式"), footer: Text("支持 ezBookkeeping 导出的 CSV/TSV 文件（设置 → 数据管理 → 导出）。其他格式（自定义列映射、支付宝账单等）请使用网页版导入。")) {
                    Picker("格式", selection: $vm.format) {
                        ForEach(ImportFormat.allCases) { f in
                            Text(f.label).tag(f)
                        }
                    }
                }

                Section {
                    Button {
                        vm.showFilePicker = true
                    } label: {
                        Label(vm.fileName.isEmpty ? "选择文件" : "重新选择：\(vm.fileName)",
                              systemImage: "doc.badge.plus")
                    }
                    .disabled(vm.busy)
                } header: {
                    Text("选择文件")
                }

                switch vm.phase {
                case .parsing:
                    Section {
                        HStack(spacing: 8) {
                            Spacer()
                            ProgressView()
                            Text("正在解析…").font(.footnote).foregroundColor(.secondary)
                            Spacer()
                        }
                    }
                case .parseFailed:
                    Section {
                        Label(vm.error ?? "解析失败", systemImage: "exclamationmark.triangle")
                            .foregroundColor(.orange)
                            .font(.footnote)
                    }
                case .parsed, .importing, .imported:
                    Section(header: Text("解析结果")) {
                        Text("共解析出 \(vm.parsed.count) 笔账单")
                            .font(.subheadline)
                        ForEach(Array(vm.parsed.prefix(50).enumerated()), id: \.offset) { _, tx in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(Self.typeLabel(tx.type))
                                        .font(.footnote)
                                        .foregroundColor(Self.typeColor(tx.type))
                                    Spacer()
                                    Text(Self.amountText(tx))
                                        .font(.subheadline.weight(.semibold))
                                        .monospacedDigit()
                                        .foregroundColor(Self.typeColor(tx.type))
                                }
                                HStack(spacing: 6) {
                                    Text(Self.timeText(tx))
                                    if let cat = tx.originalCategoryName, !cat.isEmpty {
                                        Text("· \(cat)")
                                    }
                                    if let acc = tx.originalSourceAccountName, !acc.isEmpty {
                                        Text("· \(acc)")
                                    }
                                    if let comment = tx.comment, !comment.isEmpty {
                                        Text("· \(comment)").lineLimit(1)
                                    }
                                }
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                            }
                            .padding(.vertical, 2)
                        }
                        if vm.parsed.count > 50 {
                            Text("…仅预览前 50 笔，导入时包含全部")
                                .font(.caption2).foregroundColor(.secondary)
                        }
                    }

                    switch vm.phase {
                    case .importing:
                        Section {
                            HStack(spacing: 8) {
                                Spacer()
                                ProgressView()
                                Text("正在导入…").font(.footnote).foregroundColor(.secondary)
                                Spacer()
                            }
                        }
                    case .imported:
                        Section {
                            Label("导入成功：共 \(vm.importedCount) 笔", systemImage: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        }
                    default:
                        Section {
                            Button {
                                Task { await vm.submitImport(onImported: onImported) }
                            } label: {
                                Text("确认导入 \(vm.parsed.count) 笔")
                                    .frame(maxWidth: .infinity)
                            }
                            .disabled(vm.busy || vm.parsed.isEmpty)
                        } footer: {
                            Text("导入前建议先在数据管理页导出一份备份。重复导入同一文件可能产生重复账单。")
                        }
                    }
                default:
                    EmptyView()
                }

                if let error = vm.error, vm.phase != .parseFailed {
                    Section { Text(error).foregroundColor(.red).font(.footnote) }
                }
            }
            .navigationTitle("导入账单")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if vm.busy { ProgressView() }
                }
            }
            .fileImporter(
                isPresented: $vm.showFilePicker,
                allowedContentTypes: [Self.csvType, Self.tsvType, .plainText],
                allowsMultipleSelection: false
            ) { result in
                vm.handlePickedFile(result)
            }
            .interactiveDismissDisabled(vm.busy)
        }
        .navigationViewStyle(.stack)
    }

    // 某些 SDK 无 UTType.commaDelimitedText 静态成员，用 UTI 字符串构造更稳
    static let csvType = UTType("public.comma-separated-values-text") ?? .plainText
    static let tsvType = UTType("public.tab-separated-values-text") ?? .plainText

    // MARK: - 展示辅助

    static func typeLabel(_ type: Int) -> String {
        switch TransactionType(rawValue: type) {
        case .income: return "收入"
        case .expense: return "支出"
        case .transfer: return "转账"
        case .modifyBalance: return "余额调整"
        default: return "未知"
        }
    }

    static func typeColor(_ type: Int) -> Color {
        switch TransactionType(rawValue: type) {
        case .income: return Theme.income
        case .expense: return Theme.expense
        case .transfer: return .gray
        case .modifyBalance: return Theme.brand
        default: return .primary
        }
    }

    static func amountText(_ tx: ImportParsedTransaction) -> String {
        let prefix = tx.type == TransactionType.income.rawValue ? "+" : (tx.type == TransactionType.expense.rawValue ? "-" : "")
        return prefix + AmountFormat.format(tx.sourceAmount, currency: nil)
    }

    static func timeText(_ tx: ImportParsedTransaction) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(tx.time) / 1000)
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.string(from: date)
    }
}

// MARK: - ViewModel

@MainActor
final class ImportWizardViewModel: ObservableObject {
    @Published var format: ImportWizardView.ImportFormat = .csv
    @Published var showFilePicker = false
    @Published var fileName = ""
    @Published var parsed: [ImportParsedTransaction] = []
    @Published var importedCount = 0
    @Published var error: String?
    @Published var phase: Phase = .idle
    @Published var busy = false

    enum Phase { case idle, parsing, parseFailed, parsed, importing, imported }

    private var pendingFileData: Data?

    /// 文件选择回调：读取内容并请求后端解析
    func handlePickedFile(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        let secured = url.startAccessingSecurityScopedResource()
        defer { if secured { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else {
            error = "无法读取所选文件"
            phase = .parseFailed
            return
        }
        fileName = url.lastPathComponent
        // 按扩展名自动纠正格式（csv → ezbookkeeping_csv，tsv → ezbookkeeping_tsv）
        let ext = url.pathExtension.lowercased()
        if ext == "tsv" { format = .tsv } else if ext == "csv" { format = .csv }
        pendingFileData = data
        Task { await parse(fileData: data) }
    }

    /// multipart 上传解析：fileType + file 两个表单字段
    func parse(fileData: Data) async {
        busy = true
        phase = .parsing
        error = nil
        parsed = []
        do {
            let boundary = "----NestKeepBoundary\(UUID().uuidString)"
            guard var components = URLComponents(
                url: AppSettings.shared.serverURL.appendingPathComponent("/api/v1/transactions/parse_import.json"),
                resolvingAgainstBaseURL: false), let url = components.url else {
                throw APIError.invalidURL
            }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            if let token = AuthManager.shared.token {
                req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            let tz = TimeZone.current
            req.setValue("\(tz.secondsFromGMT() / 60)", forHTTPHeaderField: "X-Timezone-Offset")
            req.setValue(tz.identifier, forHTTPHeaderField: "X-Timezone-Name")

            var body = Data()
            func addField(_ name: String, _ value: String) {
                body.append("--\(boundary)\r\n".data(using: .utf8)!)
                body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
                body.append(value.data(using: .utf8)!)
                body.append("\r\n".data(using: .utf8)!)
            }
            addField("fileType", format.rawValue)
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"file\"; filename=\"import.\(format.fileExtension)\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
            body.append(fileData)
            body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
            req.httpBody = body

            let (data, _) = try await URLSession.shared.data(for: req)
            let decoder = JSONDecoder()
            guard let envelope = try? decoder.decode(APIEnvelope<ImportParsedPage>.self, from: data) else {
                throw APIError.invalidResponse
            }
            guard envelope.success, let result = envelope.result else {
                throw APIError.server(code: envelope.errorCode ?? -1,
                                      message: envelope.errorMessage ?? "解析失败")
            }
            parsed = result.items
            phase = .parsed
        } catch {
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
            phase = .parseFailed
        }
        busy = false
    }

    /// 确认导入：parse 结果原样提交（字段与 TransactionCreateRequest 对齐）
    func submitImport(onImported: @escaping () -> Void) async {
        guard !parsed.isEmpty else { return }
        busy = true
        phase = .importing
        error = nil
        do {
            let body = ImportSubmitRequest(transactions: parsed, clientSessionId: UUID().uuidString)
            let count: Int = try await APIClient.shared.request(
                "/api/v1/transactions/import.json", method: .POST, body: body
            )
            importedCount = count
            phase = .imported
            onImported()
        } catch {
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
            phase = .parsed
        }
        busy = false
    }
}

// MARK: - 模型（与后端 JSON 对齐）

/// parse_import 响应的单条解析结果（int64 id 均为字符串化传输）
struct ImportParsedTransaction: Codable {
    let type: Int
    let categoryId: String?
    let originalCategoryName: String?
    let time: Int64
    let utcOffset: Int?
    let sourceAccountId: String?
    let originalSourceAccountName: String?
    let sourceAmount: Int64
    let destinationAccountId: String?
    let destinationAmount: Int64?
    let tagIds: [String]?
    let comment: String?
}

struct ImportParsedPage: Codable {
    let items: [ImportParsedTransaction]
    let totalCount: Int64?
}

/// import.json 请求体：解析结果原样回传 + 客户端会话 id（后端防重复提交）
struct ImportSubmitRequest: Encodable {
    let transactions: [ImportParsedTransaction]
    let clientSessionId: String
}
