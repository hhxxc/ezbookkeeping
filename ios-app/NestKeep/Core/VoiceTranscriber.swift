import Foundation
import Speech
import AVFoundation

/// 语音转文字（iOS 自带 Speech 框架，zh-CN，免费、隐私好）。
/// 按住说话、松开结束（用户完全掌控起止）；多次按住的识别结果累计拼接。
/// 权限：麦克风 + 语音识别两项，任一被拒给出可读提示（引导去设置）。
///
/// 丝滑化要点（复刻微信「按住说话 → 松手 → 完整文字干净出现」的手感）：
/// 1. `prepare()` 进入页面即预热：提前弹授权框、建好 recognizer，避免「按住才弹框/才初始化」的卡顿；
/// 2. recognizer 复用（不每次按住新建），消除重复冷启动；
/// 3. 松手后不立刻 cancel 任务，而是 `endAudio()` 后等 Apple 返回 final 完整结果再定格，
///    避免文字只出半截、随后又「跳一下」补全。
@MainActor
final class VoiceTranscriber: NSObject, ObservableObject {
    /// 是否正在录音识别
    @Published private(set) var isRecording = false
    /// 松手后等待最终转写结果（收尾中）：已停止采集，仍在等 Apple 返回完整文字
    @Published private(set) var isFinalizing = false
    /// 实时转写文本（跨多次按住累计：base + 本次识别）
    @Published var transcript = ""
    /// 不可恢复的错误（权限被拒/不可用/引擎失败）
    @Published var error: String?

    private var audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    /// 复用同一个 recognizer（每次按住新建会重复冷启动/重连，有可观延迟）
    private var recognizer: SFSpeechRecognizer?
    /// 本次按住前已有的文字（新识别结果追加其后）
    private var baseTranscript = ""
    /// 最长录音 60s 兜底（系统单次识别本身也有限制）
    private var maxDurationTimer: Timer?
    /// 松手后等待 final 的兜底超时：final 迟迟不来也定格，避免一直「正在转写」
    private var finalizeTimer: Timer?
    /// 是否已预热（授权已请求、recognizer 已建好）
    private var prepared = false

    /// 进入语音页即调用：提前触发系统语音识别授权（首次会弹框）并建好 recognizer。
    /// 幂等；真正的录音在按住 `start()` 时才发生，这里不占用麦克风。
    func prepare() {
        guard !prepared else { return }
        prepared = true
        SFSpeechRecognizer.requestAuthorization { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.recognizer == nil {
                    self.recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
                }
            }
        }
    }

    func start(base: String = "") {
        guard !isRecording else { return }
        error = nil
        baseTranscript = base
        transcript = base

        SFSpeechRecognizer.requestAuthorization { [weak self] _ in
            Task { @MainActor in
                self?.requestMicAndStart()
            }
        }
    }

    private func requestMicAndStart() {
        AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
            Task { @MainActor in
                guard let self else { return }
                if !granted {
                    self.error = "需要麦克风权限才能语音记账，请在系统设置中开启"
                    return
                }
                self.beginRecognition()
            }
        }
    }

    private func beginRecognition() {
        // 复用 recognizer（prepare 已预热；极端情况下首次直接 start 时在此兜底新建）
        let zhRecognizer = self.recognizer ?? SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
        self.recognizer = zhRecognizer
        guard let recognizer = zhRecognizer, recognizer.isAvailable else {
            error = "当前设备的语音识别不可用，请稍后重试"
            return
        }

        // 清理上一次可能残留的任务/引擎，避免取消后的残留状态
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        audioEngine = AVAudioEngine()

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            self.error = "无法启动麦克风：\(error.localizedDescription)"
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            error = "麦克风初始化失败，请重试"
            return
        }
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            self.error = "无法启动麦克风：\(error.localizedDescription)"
            return
        }

        isRecording = true

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, taskError in
            Task { @MainActor in
                guard let self else { return }

                if let result = result {
                    let text = result.bestTranscription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !text.isEmpty {
                        // 中间结果会整体刷新，拼在本次按住前的已有文字后面
                        self.transcript = self.baseTranscript + text
                    }
                }

                if let taskError = taskError {
                    // 用户主动 stop 后取消任务会带 "cancelled" 错误，不当作故障
                    if (taskError as NSError).code != 203 && self.isRecording {
                        self.error = "语音识别出错：\(taskError.localizedDescription)"
                    }
                    // 出错即收尾（finalizing 中松手触发的 cancel 也走这里，属正常结束）
                    self.finishFinalize()
                    return
                }

                if result?.isFinal == true {
                    self.finishFinalize()
                }
            }
        }

        maxDurationTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.stop()
            }
        }
    }

    /// 松开结束录音：停止采集，但不立刻取消识别任务——等 Apple 返回 final 完整文字再定格。
    func stop() {
        guard isRecording, !isFinalizing else { return }
        isFinalizing = true
        recognitionRequest?.endAudio()
        stopEngineInput()

        // 兜底：final 迟迟不来（网络异常等）也定格，避免一直「正在转写」
        finalizeTimer?.invalidate()
        finalizeTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.finishFinalize()
            }
        }
    }

    /// 停止采集（引擎 + tap），但保留 recognitionTask 等待 final
    private func stopEngineInput() {
        maxDurationTimer?.invalidate()
        maxDurationTimer = nil
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest = nil
    }

    /// 收尾定格：取消任务、复位状态、释放麦克风（final 已到手或兜底超时）
    private func finishFinalize() {
        finalizeTimer?.invalidate()
        finalizeTimer = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        isRecording = false
        isFinalizing = false

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
