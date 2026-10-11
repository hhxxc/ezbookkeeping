import Foundation
import Speech
import AVFoundation

/// 语音转文字（iOS 自带 Speech 框架，zh-CN，免费、隐私好）。
/// 按住说话、松开结束（用户完全掌控起止）；多次按住的识别结果累计拼接。
/// 权限：麦克风 + 语音识别两项，任一被拒给出可读提示（引导去设置）。
@MainActor
final class VoiceTranscriber: NSObject, ObservableObject {
    /// 是否正在录音识别
    @Published private(set) var isRecording = false
    /// 实时转写文本（跨多次按住累计：base + 本次识别）
    @Published var transcript = ""
    /// 不可恢复的错误（权限被拒/不可用/引擎失败）
    @Published var error: String?

    private var audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var recognizer: SFSpeechRecognizer?
    /// 本次按住前已有的文字（新识别结果追加其后）
    private var baseTranscript = ""
    /// 最长录音 60s 兜底（系统单次识别本身也有限制）
    private var maxDurationTimer: Timer?

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
                        // 中间结果会整体刷新，拼在本次按住前的已有文字后面
                        self.transcript = self.baseTranscript + text
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

    func stop() {
        guard isRecording else { return }
        recognitionRequest?.endAudio()
        stopEngine()
    }

    private func stopEngine() {
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
