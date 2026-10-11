import SwiftUI
import Combine

/// 语音记账：按住麦克风说话、松开结束 → 实时上屏文字（松开后可手改）→ 点「解析成账单」提交
/// 调后端 parse_text.json；解析成功关本页，结果交给 AIReceiptView 的确认/落库流程。
@MainActor
final class AIVoiceViewModel: ObservableObject {
    @ObservedObject var transcriber = VoiceTranscriber()
    @Published var isParsing = false
    @Published var error: String?
    /// 手动编辑后的文字（编辑时以手动为准；再次按住说话时会把已编辑文字作为基底追加）
    @Published var manualText: String?

    private var cancellables: Set<AnyCancellable> = []

    init() {
        // 嵌套 ObservableObject 不会自动驱动视图刷新：把 transcriber 的变更转发出去
        transcriber.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    /// 录音中实时上屏转写；松开后以手动编辑为优先
    var displayText: String {
        if transcriber.isRecording { return transcriber.transcript }
        if let manual = manualText, !manual.isEmpty { return manual }
        return transcriber.transcript
    }

    var hasText: Bool { !displayText.isEmpty }

    /// 按住麦克风开始录音（已编辑/已识别的文字作为本次追加的基底）
    func beginHold() {
        error = nil
        transcriber.start(base: displayText)
        // 转写期间以 transcriber.transcript 为准（含基底），避免编辑框与实时上屏互相打架
        manualText = nil
    }

    /// 松开麦克风结束录音（不自动解析，等用户确认/修改后手动提交）
    func endHold() {
        transcriber.stop()
    }

    /// 清空重说
    func clearText() {
        transcriber.transcript = ""
        manualText = nil
        error = nil
    }

    /// 提交解析（提交按钮触发）
    func parseIfNeeded() async {
        guard hasText, !isParsing, !transcriber.isRecording else { return }
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
            VStack(spacing: 16) {
                // 转写文本区：录音中只读实时上屏；松开后变可编辑（识别不准直接改）
                transcriptEditor
                    .padding(.horizontal, 16)

                // 系统语音识别对长数字容易转错（「六千六百零六」可能转成「666￥0」）：
                // 引导用户手改文字 / 逐位念数字，落库前确认页金额也可点击修改
                Text("金额念「零」易被吞掉？可逐位念（如「六六零六」）；识别不准直接改上屏文字，确认页里点金额也能改")
                    .font(.caption2)
                    .foregroundColor(Color(.tertiaryLabel))
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 20)

                Spacer()

                micButton
                    .padding(.bottom, 4)

                // 提交按钮：文字确认/修改好后手动提交（不再停顿自动解析）
                submitButton
                    .padding(.horizontal, 24)

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
            .padding(.top, 16)
            .padding(.bottom, 16)
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
        }
        .onDisappear {
            vm.transcriber.stop()
        }
    }

    /// 录音中：只读实时转写；空闲：可编辑（绑定手动编辑，空时显示占位提示）
    private var transcriptEditor: some View {
        ZStack(alignment: .topLeading) {
            if vm.transcriber.isRecording {
                Text(vm.displayText.isEmpty ? "正在听…" : vm.displayText)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(HomePalette.ink)
                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
                    .padding(.leading, 4)
                    .padding(.top, 8)
                    .padding(.trailing, 26)
            } else {
                if !vm.hasText {
                    Text("按住下方麦克风说话；识别不准可直接在此修改")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(Color(.placeholderText))
                        .padding(.leading, 4)
                        .padding(.top, 8)
                        .padding(.trailing, 26)
                        .allowsHitTesting(false)
                }
                TextEditor(text: Binding(
                    get: { vm.manualText ?? vm.transcriber.transcript },
                    set: { vm.manualText = $0 }
                ))
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(HomePalette.ink)
                .frame(minHeight: 120)
                .padding(.trailing, 20)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
        // 一键清除：清掉识别+手动编辑的全部内容（录音中/解析中不显示，防止误触丢转写）
        .overlay(alignment: .topTrailing) {
            if vm.hasText && !vm.transcriber.isRecording && !vm.isParsing {
                Button {
                    vm.clearText()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(Color(.tertiaryLabel))
                        .padding(8)
                        .contentShape(Rectangle())
                }
            }
        }
    }

    private var statusText: String {
        if vm.isParsing { return "正在解析…" }
        if vm.transcriber.isRecording { return "正在听…松开结束" }
        if vm.hasText { return "确认或修改文字后点上方按钮提交；按住麦克风可继续补充" }
        return "按住麦克风说话，松开结束"
    }

    /// 按住说话的麦克风按钮：按下开始录音、松开停止（不自动解析）
    private var micButton: some View {
        ZStack {
            // 录音中的发散光圈：三圈错峰从按钮向外扩散并淡出（雷达式）
            ForEach(0..<3, id: \.self) { index in
                RippleRing(isActive: vm.transcriber.isRecording, delay: Double(index) * 0.66)
            }
            Circle()
                .fill(vm.transcriber.isRecording ? Theme.expense : Theme.brand)
                .frame(width: 72, height: 72)
            Image(systemName: vm.transcriber.isRecording ? "waveform" : "mic.fill")
                .font(.system(size: 28))
                .foregroundColor(.white)
        }
        .contentShape(Circle())
        // 按住式录音：pressing true=按下开始，false=松开结束；
        // minimumDuration .infinity 让 perform 永不触发（纯按压状态检测）
        .onLongPressGesture(minimumDuration: .infinity, pressing: { pressing in
            if pressing {
                vm.beginHold()
            } else {
                vm.endHold()
            }
        }, perform: {})
        .disabled(vm.isParsing)
    }

    private var submitButton: some View {
        Button {
            Task { await vm.parseIfNeeded() }
        } label: {
            HStack(spacing: 8) {
                if vm.isParsing {
                    ProgressView()
                        .tint(.white)
                }
                Text(vm.isParsing ? "解析中…" : "解析成账单")
                    .font(.system(size: 16, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(
                Capsule().fill(vm.hasText && !vm.transcriber.isRecording
                               ? Theme.brand
                               : Color(.systemFill))
            )
        }
        .foregroundColor(vm.hasText && !vm.transcriber.isRecording ? .white : Color(.placeholderText))
        .disabled(!vm.hasText || vm.isParsing || vm.transcriber.isRecording)
    }
}

/// 麦克风发散光圈：激活时从按钮边缘向外扩散并淡出（三圈错峰，雷达式）
private struct RippleRing: View {
    let isActive: Bool
    var delay: Double = 0
    @State private var pulsing = false

    var body: some View {
        Circle()
            .stroke(Theme.brand, lineWidth: 2)
            .frame(width: 72, height: 72)
            .scaleEffect(pulsing ? 1.9 : 1.0)
            .opacity(isActive ? (pulsing ? 0 : 0.5) : 0)
            .animation(isActive ? .easeOut(duration: 2.0).repeatForever(autoreverses: false).delay(delay) : nil, value: pulsing)
            .onChange(of: isActive) { active in
                if active { restartPulse() }
            }
            .onAppear {
                if isActive { restartPulse() }
            }
    }

    /// 先归零再触发，保证每次重新录音时 repeatForever 都从头起波
    private func restartPulse() {
        pulsing = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            pulsing = true
        }
    }
}
