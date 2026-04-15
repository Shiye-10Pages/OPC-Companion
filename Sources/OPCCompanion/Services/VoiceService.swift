import Foundation
import Speech
import AVFoundation

@MainActor
public final class VoiceService: NSObject, ObservableObject {
    public static let shared = VoiceService()

    @Published public var isRecording = false
    @Published public var transcript = ""
    @Published public var isAuthorized = false

    private let speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private let audioEngine = AVAudioEngine()
    private var recognitionTask: SFSpeechRecognitionTask?

    override init() {
        self.speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
        super.init()
    }

    public func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                Task { @MainActor in
                    self.isAuthorized = status == .authorized
                    continuation.resume(returning: status == .authorized)
                }
            }
        }
    }

    public func startRecording() throws {
        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            throw VoiceError.recognizerUnavailable
        }

        guard isAuthorized else {
            throw VoiceError.notAuthorized
        }

        // 取消之前的识别任务
        recognitionTask?.cancel()
        recognitionTask = nil

        // 创建新的识别请求
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            throw VoiceError.requestCreationFailed
        }

        recognitionRequest.shouldReportPartialResults = true

        // 获取输入节点并安装 tap
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            Task { @MainActor in
                self?.recognitionRequest?.append(buffer)
            }
        }

        audioEngine.prepare()
        try audioEngine.start()

        isRecording = true
        transcript = ""

        // 启动识别任务
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            Task { @MainActor in
                guard let self = self else { return }

                if let result = result {
                    self.transcript = result.bestTranscription.formattedString
                }

                if error != nil || result?.isFinal == true {
                    self.stopRecording()
                }
            }
        }
    }

    public func stopRecording() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        isRecording = false
    }

    public enum VoiceError: Error, LocalizedError {
        case notAuthorized
        case recognizerUnavailable
        case requestCreationFailed

        public var errorDescription: String? {
            switch self {
            case .notAuthorized:
                return "语音识别未授权，请在系统设置中开启"
            case .recognizerUnavailable:
                return "语音识别不可用"
            case .requestCreationFailed:
                return "无法创建识别请求"
            }
        }
    }
}

// TTS 语音合成 (macOS 版本)
@MainActor
public final class TTSService: NSObject, ObservableObject {
    public static let shared = TTSService()

    @Published public var isSpeaking = false

    private let synthesizer = AVSpeechSynthesizer()

    override init() {
        super.init()
    }

    public func speak(_ text: String, language: String? = nil, voiceId: String? = nil, rate: Double? = nil) {
        let utterance = AVSpeechUtterance(string: text)

        // 优先使用指定的语音
        if let voiceId = voiceId, let voice = AVSpeechSynthesisVoice(identifier: voiceId) {
            utterance.voice = voice
        } else if let language = language, let voice = AVSpeechSynthesisVoice(language: language) {
            utterance.voice = voice
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: "zh-CN")
        }

        // 使用配置的语速
        utterance.rate = rate != nil ? Float(rate!) : AVSpeechUtteranceDefaultSpeechRate
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0

        synthesizer.speak(utterance)
    }

    public static func availableVoices() -> [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("zh") || $0.language.hasPrefix("en") }
    }

    public static func voiceDisplayName(_ voice: AVSpeechSynthesisVoice) -> String {
        let lang: String
        switch voice.language {
        case let l where l.hasPrefix("zh"):
            lang = "中文"
        case let l where l.hasPrefix("en"):
            lang = "英文"
        default:
            lang = voice.language
        }
        return "\(voice.name) (\(lang))"
    }

    public func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    public func isCurrentlySpeaking() -> Bool {
        synthesizer.isSpeaking
    }
}