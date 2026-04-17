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
            state.saveSessionState()
            return
        }

        guard state.lastSessionDate != todayKey else { return }

        isArchiving = true
        defer { isArchiving = false }

        let archiveKey = state.lastSessionDate
        guard let archiveDate = Self.date(from: archiveKey) else {
            state.lastSessionDate = todayKey
            state.saveSessionState()
            return
        }

        await performArchive(state: state, archiveKey: archiveKey, archiveDate: archiveDate)

        state.lastSessionDate = todayKey
        state.saveSessionState()
    }

    private func performArchive(state: AppState, archiveKey: String, archiveDate: Date) async {
        // 归档源：优先 in-memory（app 跨夜开着），回退到 jsonl（重启场景）
        let archiveMessages: [Message]
        if !state.messages.isEmpty {
            archiveMessages = state.messages.filter { $0.role != .system && !$0.hidden }
        } else {
            archiveMessages = Self.loadMessagesForDate(archiveKey)
        }

        // 记录要移除的 id，AI 调用期间用户新敲的消息不能误删
        let archivedIds = Set(archiveMessages.map { $0.id })

        guard !archiveMessages.isEmpty else {
            state.messages.removeAll { archivedIds.contains($0.id) }
            return
        }

        let summary = await generateArchiveSummary(messages: archiveMessages)
        let trimmed = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            MemoryService.shared.appendToToday(.conversation, entry: trimmed, now: archiveDate)
        }

        // 只移除 snapshot 里的消息，保留 AI 调用期间用户新加的
        state.messages.removeAll { archivedIds.contains($0.id) }
        state.showBanner("已进入新会话 · 昨日要点已归档", kind: .info, duration: 4.0)
    }

    private func generateArchiveSummary(messages: [Message]) async -> String {
        let snippet = messages
            .suffix(40)
            .map { "[\($0.role.rawValue)] \($0.content)" }
            .joined(separator: "\n")

        let prompt = """
        以下是用户一天与你的对话片段。请生成 100 字以内的中文总结，记录：主要话题、关键决策、未解决的问题。用第三人称，只输出总结文本，不要加任何前后缀或标题。

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
