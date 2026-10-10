import Foundation
import Speech
import AVFoundation

/// 语音转文字（iOS 自带 Speech 框架，zh-CN，免费、隐私好）。
/// 实时上屏中间结果；用户停顿 ~1.2s 自动停止（口述记账是短句，无需手动点停）。
/// 权限：麦克风 + 语音识别两项，任一被拒给出可读提示（引导去设置）。
@MainActor
final class VoiceTranscriber: NSObject, ObservableObject {
    /// 是否正在录音识别
    @Published private(set) var isRecording = false
    /// 实时转写文本（含中间结果）
    @Published var transcript = ""
    /// 不可恢复的错误（权限被拒/不可用/引擎失败）
    @Published var error: String?

    /// 停顿自动停止后回调（视图侧触发「开始解析」）
    var onAutoStop: (() -> Void)?

    private var audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var recognizer: SFSpeechRecognizer?
    /// 口述停顿检测：每次有新结果就重置，1.2s 没有新结果即认为说完
    private var silenceTimer: Timer?
    /// 最长录音 60s 兜底（系统单次识别本身也有限制）
    private var maxDurationTimer: Timer?
    /// 是否已经说出过内容（未说话停顿不算说完）
    private var hasSpoken = false

    private static let silenceInterval: TimeInterval = 1.2

    /// 点按开始/停止
    func toggle() {
        if isRecording {
            stop()
        } else {
            start()
        }
    }

    func start() {
        guard !isRecording else { return }
        error = nil
        transcript = ""
        hasSpoken = false

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
        // 每次新建 recognizer/引擎，避免上次取消后的残留状态
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        audioEngine = AVAudioEngine()

        let zhRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
        guard let recognizer = zhRecognizer, recognizer.isAvailable else {
            error = "当前设备的语音识别不可用，请稍后重试"
            return
        }
        self.recognizer = recognizer

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
                        self.transcript = text
                        self.hasSpoken = true
                        self.resetSilenceTimer()
                    }
                }

                if let taskError = taskError {
                    // 用户主动 stop 后取消任务会带 "cancelled" 错误，不当作故障
                    if (taskError as NSError).code != 203 && self.isRecording {
                        self.stopEngine()
                        self.error = "语音识别出错：\(taskError.localizedDescription)"
                    }
                    return
                }

                if result?.isFinal == true {
                    self.stopEngine()
                }
            }
        }

        maxDurationTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.stop()
            }
        }
    }

    private func resetSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: Self.silenceInterval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isRecording, self.hasSpoken else { return }
                self.stop()
                self.onAutoStop?()
            }
        }
    }

    func stop() {
        guard isRecording else { return }
        recognitionRequest?.endAudio()
        stopEngine()
    }

    private func stopEngine() {
        silenceTimer?.invalidate()
        silenceTimer = nil
        maxDurationTimer?.invalidate()
        maxDurationTimer = nil
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        isRecording = false

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
