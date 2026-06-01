import Foundation

/// 每日 23:59:59 → 00:00 切换时，把"昨日会话"归档：
/// 1. 让 AI 生成 100 字以内的"对话主线"摘要
/// 2. 摘要写入昨日 daily note 的 `## 对话主线` section
/// 3. 清空 messages 进入新会话（消息流重新归零，对齐"每天一份日记"语义）
///
/// 两种触发场景都覆盖：
/// - App 在夜里一直开着：每 60s 由 `scheduledCheckTimer` tick 检查跨日
/// - App 关着跨夜：启动时 `AppDelegate.applicationDidFinishLaunching` 检查
@MainActor
public final class SessionArchiveService {
    public static let shared = SessionArchiveService()

    private var isArchiving = false

    private static let isRunningTests: Bool = NSClassFromString("XCTestCase") != nil

    public init() {}

    /// 幂等：跨日标记推进后同一天再次调用立即返回。
    public func checkRolloverNeeded(now: Date = Date()) async {
        guard !Self.isRunningTests else { return }
        guard !isArchiving else { return }

        let state = AppState.shared
        let todayKey = Self.dayKey(now)

        // 首次运行 / lastSessionDate 空：记录 today，不做归档
        if state.lastSessionDate.isEmpty {
            state.lastSessionDate = todayKey
            if !state.saveSessionState() {
                state.showBanner("会话日期保存失败，下次启动可能重复检查归档（详见日志）", kind: .warning, duration: 5.0)
            }
            return
        }

        guard state.lastSessionDate != todayKey else { return }

        isArchiving = true
        defer { isArchiving = false }

        let archiveKey = state.lastSessionDate
        guard let archiveDate = Self.date(from: archiveKey) else {
            state.lastSessionDate = todayKey
            if !state.saveSessionState() {
                state.showBanner("会话日期修复失败，下次启动可能重复检查归档（详见日志）", kind: .warning, duration: 5.0)
            }
            return
        }

        guard await performArchive(state: state, archiveKey: archiveKey, archiveDate: archiveDate) else {
            return
        }

        state.lastSessionDate = todayKey
        if !state.saveSessionState() {
            state.showBanner("归档已完成，但会话日期保存失败，下次启动可能重复归档（详见日志）", kind: .warning, duration: 5.0)
        }
    }

    private func performArchive(state: AppState, archiveKey: String, archiveDate: Date) async -> Bool {
        // C2：流式中跳过归档，避免把正在追加 delta 的 assistant 气泡当作昨日归档删掉
        if state.isLoading {
            return false
        }

        // C3：in-memory 归档源必须按 archiveDate 过滤（仅保留 timestamp 属于目标日的消息），
        // 防止 lastSessionDate 异常场景下把今日消息当昨日归档后又从 UI 清掉
        let archiveMessages: [Message]
        if !state.messages.isEmpty {
            archiveMessages = state.messages.filter { msg in
                guard msg.role != .system && !msg.hidden else { return false }
                return Self.dayKey(msg.timestamp) == archiveKey
            }
        } else {
            archiveMessages = Self.loadMessagesForDate(archiveKey)
        }

        // 记录要移除的 id，AI 调用期间用户新敲的消息不能误删
        let archivedIds = Set(archiveMessages.map { $0.id })

        guard !archiveMessages.isEmpty else {
            state.messages.removeAll { archivedIds.contains($0.id) }
            return true
        }

        let summary = await generateArchiveSummary(messages: archiveMessages)
        let trimmed = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let saved: Bool
        if !trimmed.isEmpty {
            saved = MemoryService.shared.appendToToday(.conversation, entry: trimmed, now: archiveDate)
        } else {
            // N12：摘要生成失败时写一条标记，避免 daily note 静默缺失"对话主线"让用户困惑
            saved = MemoryService.shared.appendToToday(
                .conversation,
                entry: "⚠ 昨日归档摘要生成失败（查看应用日志或重试）",
                now: archiveDate
            )
        }
        guard saved else {
            state.showBanner("昨日归档保存失败，消息已保留，稍后会重试（详见日志）", kind: .warning, duration: 5.0)
            return false
        }

        // 只移除 snapshot 里的消息，保留 AI 调用期间用户新加的
        state.messages.removeAll { archivedIds.contains($0.id) }
        state.showBanner("已进入新会话 · 昨日要点已归档", kind: .info, duration: 4.0)
        return true
    }

    private func generateArchiveSummary(messages: [Message]) async -> String {
        // 剥离 assistant 消息里的 <think> 段，避免思考过程污染 daily note 归档
        let snippet = messages
            .suffix(40)
            .map { msg -> String in
                var content = msg.content
                if msg.role == .assistant {
                    let parsed = ThinkingParser.parse(msg.content)
                    content = parsed.main.isEmpty ? msg.content : parsed.main
                    content = ThinkingParser.stripLegacyActionTags(content)
                }
                return "[\(msg.role.rawValue)] \(content)"
            }
            .joined(separator: "\n")

        let prompt = """
        以下是用户一天与你的对话片段。请生成 100 字以内的中文总结，记录：主要话题、关键决策、未解决的问题。用第三人称，只输出总结文本，不要加任何前后缀或标题；**禁止输出任何 <think> 标签或你的思考过程**。

        ---
        \(snippet)
        """

        do {
            let summary = try await ChatEngine.shared.sendMessage(
                prompt,
                systemPrompt: "你是记忆整理助手，专注把对话浓缩成高信号摘要。",
                useConversationHistory: false
            )
            return summary
        } catch {
            OPCLogger.shared.log(.warn, "archive", "summary failed: \(error.localizedDescription)")
            return ""
        }
    }

    private static func loadMessagesForDate(_ dateKey: String) -> [Message] {
        let url = AppState.dataDirectory
            .appendingPathComponent("conversations")
            .appendingPathComponent("\(dateKey).jsonl")
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else {
            return []
        }
        return text.components(separatedBy: .newlines).compactMap { line -> Message? in
            guard !line.isEmpty, let d = line.data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode(Message.self, from: d)
        }
        .filter { $0.role != .system && !$0.hidden }
    }

    private static func dayKey(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    private static func date(from key: String) -> Date? {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: key)
    }
}
