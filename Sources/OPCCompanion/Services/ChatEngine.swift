import Foundation

public final class ChatEngine: @unchecked Sendable {
    public static let shared = ChatEngine()

    private static let maxHistoryMessages = 24
    private static let maxToolRoundTrips = 4  // 防止 AI 陷入无限 tool-call 循环

    public init() {}

    // MARK: - 本地计时识别（发给 AI 前先尝试本地正则）

    public static func detectLocalTimer(in message: String) -> TimerAction? {
        let patterns = [
            #"开始[\s]*(.{1,40}?)[\s，,、]+(\d{1,3})[\s]*分钟"#,
            #"开始[\s]*(.{1,40}?)(\d{1,3})分钟"#
        ]
        for patternStr in patterns {
            guard let regex = try? NSRegularExpression(pattern: patternStr) else { continue }
            let range = NSRange(message.startIndex..<message.endIndex, in: message)
            guard let match = regex.firstMatch(in: message, options: [], range: range),
                  let taskRange = Range(match.range(at: 1), in: message),
                  let minutesRange = Range(match.range(at: 2), in: message) else { continue }
            let task = String(message[taskRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let minutes = Int(message[minutesRange]),
                  minutes > 0, minutes <= 24 * 60,
                  !task.isEmpty else { continue }
            return TimerAction(task: task, minutes: minutes)
        }
        return nil
    }

    // MARK: - Session ID（保留为历史兼容 & 测试友好）

    static func makeSessionID(for date: Date = Date()) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd"
        return "00000000-0000-0000-0000-\(dateFormatter.string(from: date))0000"
    }

    // MARK: - API Key 解析

    static func resolvedAPIKey(fallback: String) -> String {
        let cached = CredentialCache.shared.getMinimaxAPIKey().trimmingCharacters(in: .whitespacesAndNewlines)
        if !cached.isEmpty { return cached }
        return fallback.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - 对外主入口

    /// 发送消息，触发 MiniMax 流式响应 + tool-call 循环，直到最终自然语言回复。
    /// - Parameter onAssistantDelta: 流式文本增量回调（主线程排队）。tool 执行期间不回调。
    public func sendMessage(
        _ userMessage: String,
        systemPrompt: String,
        useConversationHistory: Bool = true,
        onAssistantDelta: @Sendable @escaping (String) -> Void = { _ in }
    ) async throws -> String {
        logInfo("chat", "sendMessage begin len=\(userMessage.count)")
        let apiConfig = await MainActor.run { AppState.shared.config.apiConfig }
        let apiKey = Self.resolvedAPIKey(fallback: apiConfig.apiKey)
        guard !apiKey.isEmpty else {
            logWarn("chat", "missing api key")
            throw ChatError.missingAPIKey
        }

        let clientConfig = MiniMaxClient.Config(
            apiKey: apiKey,
            endpoint: Self.resolvedEndpoint(from: apiConfig),
            model: Self.resolvedModel(from: apiConfig)
        )
        let client = MiniMaxClient(config: clientConfig)

        var wire = try await buildInitialWire(
            userMessage: userMessage,
            systemPrompt: systemPrompt,
            useConversationHistory: useConversationHistory
        )

        var finalText = ""
        for round in 0..<Self.maxToolRoundTrips {
            let (assistantContent, toolCalls, _) = try await drainStream(
                client: client,
                wire: wire,
                onAssistantDelta: onAssistantDelta
            )

            wire.append(WireMessage(
                role: "assistant",
                content: assistantContent.isEmpty ? nil : assistantContent,
                toolCalls: toolCalls.isEmpty ? nil : toolCalls
            ))

            finalText = assistantContent.isEmpty ? finalText : assistantContent

            if toolCalls.isEmpty {
                break
            }

            for call in toolCalls {
                let result: String
                if ToolExecutor.requiresConfirmation.contains(call.function.name) {
                    let approved = await NotionConfirmManager.shared.requestConfirmation(toolCall: call)
                    if approved {
                        result = await ToolExecutor.execute(call)
                    } else {
                        result = #"{"status":"canceled","message":"用户取消了操作"}"#
                        await MainActor.run {
                            AppState.shared.showBanner(
                                "已取消 Notion 操作：\(call.function.name)",
                                kind: .info
                            )
                            MemoryService.shared.appendToToday(
                                .notion,
                                entry: "用户取消：\(call.function.name)"
                            )
                        }
                    }
                } else {
                    result = await ToolExecutor.execute(call)
                }
                wire.append(WireMessage(role: "tool", content: result, toolCallId: call.id))
            }

            if round == Self.maxToolRoundTrips - 1 {
                // 达到最大回合数，强制结束
                break
            }
        }

        logInfo("chat", "sendMessage done len=\(finalText.count)")
        guard !finalText.isEmpty else {
            logWarn("chat", "empty response")
            throw ChatError.invalidResponse
        }
        return finalText
    }

    /// 设置页"测试连接"用的轻量探测。
    public func testMiniMaxConnection(config: APIConfig) async throws -> String {
        let apiKey = Self.resolvedAPIKey(fallback: config.apiKey)
        guard !apiKey.isEmpty else { throw ChatError.missingAPIKey }

        let clientConfig = MiniMaxClient.Config(
            apiKey: apiKey,
            endpoint: Self.resolvedEndpoint(from: config),
            model: Self.resolvedModel(from: config),
            maxTokens: 16
        )
        let client = MiniMaxClient(config: clientConfig)

        let stream = client.chatStream(
            messages: [
                WireMessage(role: "user", content: "Reply with ok only.")
            ],
            tools: []
        )

        var output = ""
        for try await chunk in stream {
            if let delta = chunk.contentDelta { output += delta }
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Internal

    private func drainStream(
        client: MiniMaxClient,
        wire: [WireMessage],
        onAssistantDelta: @Sendable @escaping (String) -> Void,
        allowRetry: Bool = true
    ) async throws -> (content: String, toolCalls: [WireToolCall], finishReason: String?) {
        do {
            return try await drainStreamOnce(client: client, wire: wire, onAssistantDelta: onAssistantDelta)
        } catch let error as MiniMaxClient.ClientError where allowRetry && error.isRetriable {
            // 网络 / 5xx / 限流 类错误做一次自动重试
            try? await Task.sleep(nanoseconds: 800_000_000)
            return try await drainStreamOnce(client: client, wire: wire, onAssistantDelta: onAssistantDelta)
        }
    }

    private func drainStreamOnce(
        client: MiniMaxClient,
        wire: [WireMessage],
        onAssistantDelta: @Sendable @escaping (String) -> Void
    ) async throws -> (content: String, toolCalls: [WireToolCall], finishReason: String?) {
        let stream = client.chatStream(messages: wire, tools: ToolExecutor.availableTools)
        var content = ""
        let buffer = ToolCallBuffer()
        var finishReason: String?

        for try await chunk in stream {
            if let delta = chunk.contentDelta, !delta.isEmpty {
                content += delta
                onAssistantDelta(delta)
            }
            for d in chunk.toolCallDeltas {
                buffer.apply(delta: d)
            }
            if let reason = chunk.finishReason { finishReason = reason }
        }

        return (content, buffer.finalized(), finishReason)
    }

    @MainActor
    private func buildInitialWire(
        userMessage: String,
        systemPrompt: String,
        useConversationHistory: Bool
    ) -> [WireMessage] {
        var wire: [WireMessage] = []

        let trimmed = systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let memorySnapshot = MemoryService.shared.composeSnapshot()
        let stateSnapshot = Self.buildStateSnapshot()
        var combined = trimmed
        if !memorySnapshot.isEmpty {
            if !combined.isEmpty { combined += "\n\n" }
            combined += memorySnapshot
        }
        if !stateSnapshot.isEmpty {
            if !combined.isEmpty { combined += "\n\n" }
            combined += stateSnapshot
        }
        if !combined.isEmpty {
            wire.append(WireMessage(role: "system", content: combined))
        }

        if useConversationHistory {
            let history = AppState.shared.messages
                .filter { $0.role != .system && !$0.hidden }
                .suffix(Self.maxHistoryMessages)

            for msg in history {
                let role = msg.role == .user ? "user" : "assistant"
                // 老 assistant 回复可能含 [ACTION:...] 指令串，发回 API 会强化错误模式，先剥离
                let content = role == "assistant"
                    ? ThinkingParser.stripLegacyActionTags(msg.content)
                    : msg.content
                wire.append(WireMessage(role: role, content: content))
            }

            if wire.last?.role != "user" || wire.last?.content != userMessage {
                wire.append(WireMessage(role: "user", content: userMessage))
            }
        } else {
            wire.append(WireMessage(role: "user", content: userMessage))
        }

        return wire
    }

    private func buildInitialWire(
        userMessage: String,
        systemPrompt: String,
        useConversationHistory: Bool
    ) async throws -> [WireMessage] {
        await MainActor.run {
            buildInitialWire(
                userMessage: userMessage,
                systemPrompt: systemPrompt,
                useConversationHistory: useConversationHistory
            )
        }
    }

    /// 实时状态简报：注入 system prompt，让 AI 感知用户在 app 内的完整上下文
    @MainActor
    private static func buildStateSnapshot() -> String {
        let state = AppState.shared
        var lines: [String] = ["## 当前状态"]

        // 活跃计时
        if let active = state.activeTask, active.status == .inProgress {
            let remaining = active.remainingSeconds.map { "\($0 / 60):\(String(format: "%02d", $0 % 60))" } ?? "?"
            lines.append("- 活跃计时: \(active.title) (剩余 \(remaining))")
        }

        // 待办任务
        let pending = state.tasks.filter { $0.status == .pending }
        if !pending.isEmpty {
            let names = pending.prefix(5).map { $0.title }.joined(separator: " / ")
            lines.append("- 待办任务(\(pending.count)): \(names)")
        }

        // 今日已完成
        let done = state.tasks.filter { $0.status == .done }
        if !done.isEmpty {
            lines.append("- 今日已完成: \(done.count) 个")
        }

        // 未处理随手记
        let noteCount = state.unreadNoteCount
        if noteCount > 0 {
            lines.append("- 未处理随手记: \(noteCount) 条")
        }

        // 定时任务
        let enabledTimers = state.scheduledTasks.filter { $0.enabled }
        if !enabledTimers.isEmpty {
            let names = enabledTimers.prefix(3).map { "\($0.time) \($0.name)" }.joined(separator: " / ")
            lines.append("- 定时提醒(\(enabledTimers.count)): \(names)")
        }

        lines.append("")
        lines.append("你可以调用 get_tasks / get_inbox_notes / get_today_daily_note / get_scheduled_tasks 获取详细信息。")

        return lines.count > 3 ? lines.joined(separator: "\n") : ""
    }

    private static func resolvedEndpoint(from config: APIConfig) -> URL {
        let base = config.normalizedBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if base.contains("api.minimax") {
            return URL(string: "\(base)/text/chatcompletion_v2") ?? MiniMaxClient.defaultEndpoint
        }
        return MiniMaxClient.defaultEndpoint
    }

    private static func resolvedModel(from config: APIConfig) -> String {
        config.defaultModel
    }

    // MARK: - Errors

    public enum ChatError: Error, LocalizedError {
        case invalidResponse
        case missingAPIKey
        case commandFailed(String)

        public var errorDescription: String? {
            switch self {
            case .invalidResponse: return "无法获取有效响应"
            case .missingAPIKey: return "请先在设置中填写 API Key"
            case .commandFailed(let message): return message
            }
        }
    }
}

// MARK: - 兼容旧 Action 枚举（部分视图/测试仍在用）

public enum Action {
    case timer(TimerAction)
    case timerExtend(TimerExtendAction)
    case notion(NotionAction)
}

public struct TimerAction: Codable {
    public let task: String
    public let minutes: Int

    public init(task: String, minutes: Int) {
        self.task = task
        self.minutes = minutes
    }
}

public struct TimerExtendAction: Codable {
    public let task: String
    public let minutes: Int

    public init(task: String, minutes: Int) {
        self.task = task
        self.minutes = minutes
    }
}

public struct NotionAction: Codable {
    public let operation: String
    public let parameters: [String: String]

    public init(operation: String, parameters: [String: String]) {
        self.operation = operation
        self.parameters = parameters
    }
}
