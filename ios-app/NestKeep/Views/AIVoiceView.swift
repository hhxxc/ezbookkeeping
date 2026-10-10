import SwiftUI
import Combine

/// 语音记账：按一下说话（停顿自动停）→ 实时上屏文字（可手改）→「解析成账单」
/// 调后端 parse_text.json；解析成功关本页，结果交给 AIReceiptView 的确认/落库流程。
@MainActor
final class AIVoiceViewModel: ObservableObject {
    @ObservedObject var transcriber = VoiceTranscriber()
    @Published var isParsing = false
    @Published var error: String?
    /// 手动编辑后的文字（编辑时以手动为准，录音新结果只在编辑为空时覆盖）
    @Published var manualText: String?

    private var cancellables: Set<AnyCancellable> = []

    init() {
        // 嵌套 ObservableObject 不会自动驱动视图刷新：把 transcriber 的变更转发出去
        transcriber.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    var displayText: String {
        if let manual = manualText, !manual.isEmpty { return manual }
        return transcriber.transcript
    }

    var hasText: Bool { !displayText.isEmpty }

    func start() {
        error = nil
        transcriber.start()
    }

    func toggleRecord() {
        if transcriber.isRecording {
            transcriber.stop()
        } else {
            error = nil
            transcriber.start()
        }
    }

    /// 停顿自动停止 → 直接解析（口述记账「说完就走」，无需再点按钮）
    func handleAutoStop() {
        Task { await parseIfNeeded() }
    }

    func parseIfNeeded() async {
        guard hasText, !isParsing else { return }
        if transcriber.isRecording { transcriber.stop() }
        isParsing = true
        error = nil
        do {
            let results = try await TransactionTextParser.parse(displayText)
            isParsing = false
            if results.isEmpty {
                error = "没有从这句话里解析出交易信息，试试说清楚金额，例如「午餐花了32块」"
                return
            }
            onParsed?(results)
        } catch {
            isParsing = false
            if let urlError = error as? URLError, urlError.code == .timedOut {
                self.error = "解析超时了（模型响应慢或网络不稳），点「解析成账单」重试一次"
            } else {
                self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    /// 解析成功回调（流程层接管：关本页 → 进结果确认页）
    var onParsed: (([ReceiptRecognizer.Recognized]) -> Void)?
}

/// 语音记账流程状态：语音页解析成功 → 关语音页 → 进结果确认页（复用识图页）
@MainActor
final class AIVoiceFlow: ObservableObject {
    @Published var showVoice = false
    @Published var showResults = false
    private(set) var parsedResults: [ReceiptRecognizer.Recognized] = []

    func start() {
        parsedResults = []
        showVoice = true
    }

    func handleParsed(_ results: [ReceiptRecognizer.Recognized]) {
        parsedResults = results
        showVoice = false
        // iOS 15：上一个 sheet 收起动画没走完就 present 下一个会静默失败，稍等再进
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { [weak self] in
            self?.showResults = true
        }
    }
}

/// 两个入口（首页语音卡 / 加号长按菜单）共用的 sheet 组合：
/// 第一层 = 语音页，第二层 = 结果确认页（识图页复用）
struct AIVoiceFlowModifier: ViewModifier {
    @ObservedObject var flow: AIVoiceFlow
    /// 结果确认页关闭后的回调（首页刷新等）
    var onResultsDismiss: (() -> Void)? = nil

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $flow.showVoice) {
                AIVoiceView { results in flow.handleParsed(results) }
            }
            .sheet(isPresented: $flow.showResults, onDismiss: { onResultsDismiss?() }) {
                AIReceiptView(initialResults: flow.parsedResults)
            }
    }
}

struct AIVoiceView: View {
    /// 解析成功回调（非空 = 交给流程层）
    let onParsed: ([ReceiptRecognizer.Recognized]) -> Void
    @StateObject private var vm = AIVoiceViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                Spacer()

                // 实时转写文本（可手改）
                VStack(alignment: .leading, spacing: 8) {
                    Text(vm.displayText.isEmpty ? "说一句话，例如「午餐花了 32 块，微信付的」" : vm.displayText)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(vm.displayText.isEmpty ? Color(.placeholderText) : HomePalette.ink)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
                }
                .padding(16)
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(16)
                .padding(.horizontal, 16)

                // 编辑入口：转写不准时手动修正
                TextField("或者直接输入文字记账", text: Binding(
                    get: { vm.manualText ?? "" },
                    set: { vm.manualText = $0 }
                ))
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 16)

                Spacer()
                Spacer()

                micButton
                    .padding(.bottom, 8)

                // 手动解析 / 超时重试入口（自动停顿解析失败时从这里重试）
                if vm.hasText && !vm.transcriber.isRecording && !vm.isParsing {
                    Button {
                        Task { await vm.parseIfNeeded() }
                    } label: {
                        Text("解析成账单")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 28)
                            .padding(.vertical, 10)
                            .background(Capsule().fill(Theme.brand))
                    }
                    .padding(.top, -4)
                }

                Text(statusText)
                    .font(.footnote)
                    .foregroundColor(.secondary)

                if let error = vm.error {
                    Text(error)
                        .font(.footnote)
                        .foregroundColor(Theme.expense)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
            }
            .padding(.vertical, 16)
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("语音记账")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("返回") { dismiss() }
                }
            }
            .navigationViewStyle(.stack)
        }
        .onAppear {
            vm.onParsed = onParsed
            vm.transcriber.onAutoStop = { vm.handleAutoStop() }
            // 进页自动开始听（少一次点按）
            vm.start()
        }
        .onDisappear {
            vm.transcriber.stop()
        }
    }

    private var statusText: String {
        if vm.isParsing { return "正在解析…" }
        if vm.transcriber.isRecording { return "正在听…说完停顿一下即可" }
        if vm.hasText { return "说完啦？点麦克风继续补充，或直接解析" }
        return "点击麦克风开始说话"
    }

    private var micButton: some View {
        Button {
            vm.toggleRecord()
        } label: {
            ZStack {
                // 录音中的脉冲圈
                Circle()
                    .stroke(Theme.brand.opacity(vm.transcriber.isRecording ? 0.35 : 0), lineWidth: 2)
                    .frame(width: 84, height: 84)
                    .scaleEffect(vm.transcriber.isRecording ? 1.15 : 1.0)
                    .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: vm.transcriber.isRecording)
                Circle()
                    .fill(vm.transcriber.isRecording ? Theme.expense : Theme.brand)
                    .frame(width: 72, height: 72)
                Image(systemName: vm.transcriber.isRecording ? "stop.fill" : "mic.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.white)
            }
        }
        .disabled(vm.isParsing)
    }
}
