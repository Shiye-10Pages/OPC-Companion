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

        // Wish Clearing session 维护：过期兜底 + 轮数计数。
        // 只有以 /聊聊 开头的消息才算 wish 回合；普通对话在 session 活期内也不污染 processedCount。
        // 归档服务不走历史，完全不影响 session。
        if useConversationHistory {
            let isWishTurn = userMessage.hasPrefix("/聊聊")
            await MainActor.run {
                let state = AppState.shared
                if let session = state.wishClearingSession {
                    if session.expired {
                        state.endWishClearingSession()
                    } else if isWishTurn {
                        state.incrementWishClearingProcessed()
                    }
                }
            }
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
        // H6：本轮已被用户取消过的 tool 名，同轮再次调用直接短路，避免连弹 4 次确认框
        var canceledThisTurn: Set<String> = []
        var hitLimit = false

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

            // M7：多轮时累积 finalText 而不是只取最后一轮，避免 ChatView 覆盖时丢前几轮内容
            if !assistantContent.isEmpty {
                finalText = finalText.isEmpty ? assistantContent : "\(finalText)\n\n\(assistantContent)"
            }

            if toolCalls.isEmpty {
                break
            }

            for call in toolCalls {
                let result: String
                if canceledThisTurn.contains(call.function.name) {
                    // 本轮用户已明确取消过该 tool，短路返回，引导 AI 放弃
                    result = #"{"status":"canceled","message":"用户本次已明确不做此类操作，请改用其他方式或询问用户"}"#
                } else if ToolExecutor.requiresConfirmation.contains(call.function.name) {
                    let approved = await NotionConfirmManager.shared.requestConfirmation(toolCall: call)
                    if approved {
                        result = await ToolExecutor.execute(call)
                    } else {
                        result = #"{"status":"canceled","message":"用户取消了操作"}"#
                        canceledThisTurn.insert(call.function.name)
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
                hitLimit = true
            }
        }

        // H7：达到 round 上限时，最后一轮的 tool result 从没回灌给 AI 过。
        // 追加一次无 tool 的收尾请求，让 AI 基于已有 tool_results 给用户一个可见的总结文本。
        if hitLimit, wire.last?.role == "tool" {
            do {
                let (wrapContent, _, _) = try await drainStream(
                    client: client,
                    wire: wire,
                    onAssistantDelta: onAssistantDelta
                )
                if !wrapContent.isEmpty {
                    finalText = finalText.isEmpty ? wrapContent : "\(finalText)\n\n\(wrapContent)"
                }
            } catch {
                // 收尾请求失败不 fatal，沿用已有 finalText
                logWarn("chat", "wrap-up drain failed: \(error.localizedDescription)")
            }
        }

        // H5：AI 在 /聊聊 语境生成状态回放（"聊了 X 分钟。回到 Y"）但漏调 end_wish_clearing → 客户端 fallback 清 session
        let trimmedFinal = finalText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedFinal.isEmpty,
           trimmedFinal.contains("聊了"),
           trimmedFinal.contains("回到") {
            await MainActor.run {
                AppState.shared.endWishClearingSession()
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

        // 今日焦点 (pinned)：只列仍需行动的（进行中 + 待办）。已完成任务单独汇总到底部，
        // 避免 AI 把 ✓ 任务当成"你本来该做但没做"来提醒用户。
        let pendingTasks = state.tasks.filter { $0.status == .pending }
        let inProgressTasks = state.tasks.filter { $0.status == .inProgress }
        let doneTasks = state.tasks.filter { $0.status == .done }
        let actionableTasks = inProgressTasks + pendingTasks
        if !actionableTasks.isEmpty {
            lines.append("- 今日焦点 (pinned) 还需行动 \(actionableTasks.count) 条：")
            for task in actionableTasks {
                switch task.status {
                case .inProgress:
                    let remaining = task.remainingSeconds.map { "\($0 / 60):\(String(format: "%02d", $0 % 60))" } ?? "?"
                    lines.append("  ▶ \(task.title) (进行中 · 剩 \(remaining))")
                case .pending:
                    lines.append("  ○ \(task.title) (待办)")
                default: break
                }
            }
        } else if doneTasks.isEmpty {
            lines.append("- 今日焦点 (pinned)：今日未锁定焦点任务（早晨仪式尚未完成）")
        } else {
            lines.append("- 今日焦点 (pinned)：今日任务全部完成，无需再提醒去做")
        }

        // 未处理随手记（按 kind 拆分：note / wish）
        let pendingNotes = state.notes.filter { $0.status == .pending }
        let pendingNoteCount = pendingNotes.filter { $0.kind == .note }.count
        let pendingWishCount = pendingNotes.filter { $0.kind == .wish }.count
        if pendingNoteCount > 0 || pendingWishCount > 0 {
            var parts: [String] = []
            if pendingNoteCount > 0 { parts.append("\(pendingNoteCount) 条随手记") }
            if pendingWishCount > 0 { parts.append("\(pendingWishCount) 条我想") }
            lines.append("- 未处理收件箱: \(parts.joined(separator: " + "))")
        }

        // 定时任务
        let enabledTimers = state.scheduledTasks.filter { $0.enabled }
        if !enabledTimers.isEmpty {
            let names = enabledTimers.prefix(3).map { "\($0.time) \($0.name)" }.joined(separator: " / ")
            lines.append("- 定时提醒(\(enabledTimers.count)): \(names)")
        }

        // Wish Clearing 会话状态
        if let session = state.wishClearingSession {
            let elapsedMin = session.elapsedSeconds / 60
            let remainingMin = session.remainingSeconds / 60
            var sessionLine = "- Wish Clearing 进行中: 已过 \(elapsedMin) 分钟，剩余 \(remainingMin) 分钟，已处理 \(session.processedCount) 条"
            if session.expired {
                sessionLine += "（⚠️ 时间已到，请按协议结束并做状态回放）"
            }
            lines.append(sessionLine)
            if let anchor = session.anchorTask, !anchor.isEmpty {
                lines.append("- 进入前锚点: \(anchor)")
            }
        }

        // 偏离信号：近 5 条 user 消息的主题是否和 pinned 焦点有关联。用 2-char shingle 做粗略关键词匹配。
        if !pendingTasks.isEmpty || !inProgressTasks.isEmpty {
            let recentUserMessages = state.messages
                .filter { $0.role == .user && !$0.hidden }
                .suffix(5)
            if recentUserMessages.count >= 3 {
                var shingles: Set<String> = []
                for task in pendingTasks + inProgressTasks {
                    let chars = Array(task.title)
                    guard chars.count >= 2 else { continue }
                    for i in 0...(chars.count - 2) {
                        shingles.insert(String(chars[i...i+1]))
                    }
                }
                let combinedRecent = recentUserMessages.map { $0.content }.joined(separator: " ")
                let hasMatch = shingles.contains { !$0.isEmpty && combinedRecent.contains($0) }
                if !hasMatch {
                    let anchor = inProgressTasks.first?.title ?? pendingTasks.first?.title ?? "焦点任务"
                    lines.append("- ⚠️ 近 \(recentUserMessages.count) 条消息主题与 pinned 焦点无关联 → 可能在偏离。若再 >3 轮无关，请主动问一句\u{0022}要不要先回到 [\(anchor)]？\u{0022}")
                }
            }
        }

        // 已完成汇总（放底，避免干扰 pinned 决策视野）
        if !doneTasks.isEmpty {
            lines.append("- 今日已完成: \(doneTasks.count) 个")
        }

        lines.append("")
        lines.append("你可以调用 get_tasks / get_inbox_notes / get_today_daily_note / get_scheduled_tasks / memory_search 获取详细信息。")

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
