import Foundation
import Speech
import AVFoundation

// MARK: - AudioRecorder (nonisolated 核心)
//
// 所有 AVAudioEngine / SFSpeechRecognitionTask 的操作都在这里完成。
// 这个类从不接触 @MainActor 属性，也不持有 VoiceService 强引用。
// 它把识别事件通过一个 AsyncStream 向外吐，调用方（VoiceService 壳子）
// 自己在 MainActor 上消费这个流，更新 @Published。
//
// 为什么用 @unchecked Sendable + DispatchQueue 而不是 actor：
//   - AVAudioEngine.installTap 的 closure 在 audio 线程以 sync 方式调用，
//     frequency 很高。用 actor 会每帧 hop，延迟和性能都差。
//   - SFSpeechRecognitionTask 的 handler 同理。
//   - 我们只需要保证内部可变状态（request, task, engine）在自己的串行
//     队列上访问即可，这比 actor 更贴近 AVFoundation 的心智模型。
final class AudioRecorder: @unchecked Sendable {

    enum Event: Sendable {
        case partialTranscript(String)
        case finalTranscript(String)
        case error(String)
        case ended   // 任何原因（手动停、final、error）导致结束
    }

    // 内部状态只在 queue 上读写
    private let queue = DispatchQueue(label: "opc.voice.recorder", qos: .userInitiated)
    private let recognizer: SFSpeechRecognizer?
    private var audioEngine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var tapInstalled = false
    private var eventSink: ((Event) -> Void)?

    init(locale: Locale = Locale(identifier: "zh-CN")) {
        self.recognizer = SFSpeechRecognizer(locale: locale)
    }

    var isAvailable: Bool {
        recognizer?.isAvailable ?? false
    }

    /// 启动录音。eventHandler 会在内部 queue 上被回调（nonisolated context），
    /// 调用方负责 hop 到 MainActor 再更新 UI。
    func start(eventHandler: @escaping @Sendable (Event) -> Void) throws {
        try queue.sync {
            guard let recognizer = recognizer, recognizer.isAvailable else {
                throw VoiceService.VoiceError.recognizerUnavailable
            }

            // 幂等清理
            teardownLocked()

            self.eventSink = eventHandler

            let req = SFSpeechAudioBufferRecognitionRequest()
            req.shouldReportPartialResults = true
            self.request = req

            let engine = AVAudioEngine()
            self.audioEngine = engine

            let inputNode = engine.inputNode
            let format = inputNode.outputFormat(forBus: 0)

            // tap closure 在 audio 线程跑：这里不访问 @MainActor 任何东西。
            // 对 self.request 的访问是 nonisolated → 合法。并发安全由
            // AVAudioEngine 自身保证（tap 不会和 removeTap 并行）。
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                // 注意：不跳 queue.async。每 buffer hop 会拖垮性能。
                // request.append 本身是线程安全的。
                self?.request?.append(buffer)
            }
            self.tapInstalled = true

            engine.prepare()
            do {
                try engine.start()
            } catch {
                teardownLocked()
                throw error
            }

            // recognitionTask 的 handler 也在系统底层线程跑
            self.task = recognizer.recognitionTask(with: req) { [weak self] result, error in
                guard let self = self else { return }
                if let result = result {
                    let text = result.bestTranscription.formattedString
                    if result.isFinal {
                        self.eventSink?(.finalTranscript(text))
                        self.stopInternal()
                    } else {
                        self.eventSink?(.partialTranscript(text))
                    }
                }
                if let error = error {
                    self.eventSink?(.error(error.localizedDescription))
                    self.stopInternal()
                }
            }
        }
    }

    /// 外部调用的 stop。同步执行清理，保证调用后立刻不再产生事件。
    func stop() {
        queue.sync {
            teardownLocked()
            eventSink?(.ended)
            eventSink = nil
        }
    }

    /// 内部触发的 stop（来自 task handler）。不能再 queue.sync（已经在 queue 上）。
    private func stopInternal() {
        // task handler 可能在 queue 外的线程跑，所以用 async 到 queue 上清理。
        queue.async { [weak self] in
            guard let self = self else { return }
            self.teardownLocked()
            self.eventSink?(.ended)
            self.eventSink = nil
        }
    }

    /// 必须在 queue 上调用。幂等。
    private func teardownLocked() {
        task?.cancel()
        task = nil

        if let engine = audioEngine {
            if engine.isRunning {
                engine.stop()
            }
            if tapInstalled {
                engine.inputNode.removeTap(onBus: 0)
                tapInstalled = false
            }
        }
        audioEngine = nil

        request?.endAudio()
        request = nil
    }

    deinit {
        // 最后一次兜底清理。不加锁，deinit 时已无外部引用。
        task?.cancel()
        if let engine = audioEngine, engine.isRunning {
            engine.stop()
        }
        if tapInstalled, let engine = audioEngine {
            engine.inputNode.removeTap(onBus: 0)
        }
        request?.endAudio()
    }
}

// MARK: - VoiceService (@MainActor 外壳)

@MainActor
public final class VoiceService: NSObject, ObservableObject {
    public static let shared = VoiceService()

    @Published public var isRecording = false
    @Published public var transcript = ""
    @Published public var isAuthorized = false

    private let recorder = AudioRecorder()
    // 正在消费事件流的 Task。stopRecording 时取消它，防止事件泄漏到下一次会话。
    private var consumerTask: Task<Void, Never>?

    override init() {
        super.init()
    }

    // MARK: - Authorization

    /// nonisolated 避免 continuation 继承 @MainActor 导致后台 resume crash。
    nonisolated public func requestAuthorization() async -> Bool {
        logInfo("voice", "requestAuthorization begin")
        let status: SFSpeechRecognizerAuthorizationStatus = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in
                logInfo("voice", "SFSpeechRecognizer.requestAuthorization callback status=\(status.rawValue)")
                cont.resume(returning: status)
            }
        }
        let ok = (status == .authorized)
        logInfo("voice", "requestAuthorization complete authorized=\(ok)")
        await MainActor.run {
            VoiceService.shared.isAuthorized = ok
        }
        return ok
    }

    // MARK: - Recording control

    public func startRecording() throws {
        logInfo("voice", "startRecording begin isAuthorized=\(isAuthorized) isAvailable=\(recorder.isAvailable)")
        guard recorder.isAvailable else {
            logWarn("voice", "recognizer unavailable")
            throw VoiceError.recognizerUnavailable
        }
        guard isAuthorized else {
            logWarn("voice", "not authorized")
            throw VoiceError.notAuthorized
        }

        // 先取消旧的消费任务（如果有的话）
        consumerTask?.cancel()
        consumerTask = nil

        // 用 AsyncStream 把 nonisolated 回调桥接到 MainActor。
        // 回调里只做 continuation.yield，不访问 @MainActor 属性 → 安全。
        let stream = AsyncStream<AudioRecorder.Event>(bufferingPolicy: .unbounded) { continuation in
            do {
                try self.recorder.start { event in
                    continuation.yield(event)
                    if case .ended = event {
                        continuation.finish()
                    }
                }
            } catch {
                // 启动失败：把错误通过流带出去，并立刻 finish。
                continuation.yield(.error(error.localizedDescription))
                continuation.finish()
            }
        }

        transcript = ""
        isRecording = true

        // 在 MainActor Task 上消费流。这里每次 yield 都会 hop 回主线程 ——
        // 频率是语音识别结果，远远低于 audio tap buffer，性能没问题。
        consumerTask = Task { @MainActor [weak self] in
            for await event in stream {
                guard let self = self else { break }
                switch event {
                case .partialTranscript(let text):
                    self.transcript = text
                case .finalTranscript(let text):
                    self.transcript = text
                case .error(let msg):
                    logError("voice", "recognition error: \(msg)")
                case .ended:
                    self.isRecording = false
                }
            }
            // 流结束 = 录音结束，保险再写一次 isRecording
            self?.isRecording = false
        }

        logInfo("voice", "startRecording: audio engine + task launched")
    }

    public func stopRecording() {
        logInfo("voice", "stopRecording")
        recorder.stop()      // 同步清理 audio engine + task
        consumerTask?.cancel()
        consumerTask = nil
        isRecording = false
        // transcript 不清空：调用方可能需要读最后一次结果
    }

    // MARK: - Errors

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

// MARK: - TTSService
//
// AVSpeechSynthesizer 的 speak/stop 调用可以从任意线程发起（Apple 文档未强制
// 主线程，但为了和 UI 绑定一致，仍保持 @MainActor 外壳）。
// 它没有高频底层线程回调，所以不需要像 VoiceService 那样拆 nonisolated 层。
// 唯一要留意的是：如果将来订阅 AVSpeechSynthesizerDelegate 的回调，delegate
// 方法是 nonisolated 的，需要用和 AudioRecorder 同样的方式桥接。
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

        if let voiceId = voiceId, let voice = AVSpeechSynthesisVoice(identifier: voiceId) {
            utterance.voice = voice
        } else if let language = language, let voice = AVSpeechSynthesisVoice(language: language) {
            utterance.voice = voice
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: "zh-CN")
        }

        utterance.rate = rate.map(Float.init) ?? AVSpeechUtteranceDefaultSpeechRate
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
