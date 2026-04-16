import Foundation
import SwiftUI
import Combine
import UserNotifications

@MainActor
public final class AppState: ObservableObject {
    public static let shared = AppState()

    // 对话消息
    @Published public var messages: [Message] = []
    @Published public var isLoading = false

    // 当日任务
    @Published public var tasks: [TaskItem] = []
    @Published public var activeTask: TaskItem?

    // 定时任务
    @Published public var scheduledTasks: [ScheduledTask] = []

    // 随手记
    @Published public var notes: [Note] = []

    public var unreadNoteCount: Int {
        notes.filter { $0.status == .pending }.count
    }

    public var hasIncompleteTasks: Bool {
        tasks.contains { $0.status == .pending || $0.status == .inProgress }
    }

    // 全局配置
    @Published public var config: AppConfig = AppConfig()
    @Published public var systemPrompt: String = ""

    // 面板状态
    @Published public var isPanelVisible = false
    @Published public var selectedTab: AppTab = .chat

    // 菜单栏状态
    @Published public var menuBarStatus: MenuBarStatus = .idle
    @Published public var hasUnreadReminders = false

    // 语音状态
    @Published public var isRecording = false
    @Published public var transcriptText = ""

    // 历史数据
    @Published public var conversationHistory: [ConversationDay] = []
    @Published public var lastSummaryDate: String = ""
    @Published public var lastSummary: String = ""
    @Published public var triggeredTasksToday: Set<String> = []  // 今天已触发的任务 ID
    @Published public var lastTriggerDate: String = ""  // 上次检查日期
    private var lastCheckTimestamp: TimeInterval = 0    // 系统时间回拨防护

    // 计时提醒防重触发标志
    @Published public var timerWarningFired = false
    @Published public var timerOvertimeFired = false

    // 一键整理防重入
    @Published public var isOrganizing = false

    private var cancellables = Set<AnyCancellable>()
    private var globalTimer: Timer?

    public init() {
        loadData()
        // 启动时加载凭证（secrets.json，必要时从旧 Keychain 迁移）
        CredentialCache.shared.loadIfNeeded()
        migrateLegacyPlainTextAPIKey()
        startGlobalTimer()
    }

    /// 兼容历史：早期 config.json 里的明文 apiKey 搬到 secrets.json 并清空。
    private func migrateLegacyPlainTextAPIKey() {
        let plaintext = config.apiConfig.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !plaintext.isEmpty else { return }
        CredentialCache.shared.setMinimaxAPIKey(plaintext)
        config.apiConfig.apiKey = ""
        saveConfig()
    }

    private func startGlobalTimer() {
        globalTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            // Timer 的 block 在 main runloop（main thread）执行。
            // assumeIsolated 让 Swift 6 信任当前已在 MainActor，无额外 hop。
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
    }

    private func tick() {
        guard let activeTask = self.activeTask,
              let timerEnd = activeTask.timerEnd,
              activeTask.status == .inProgress else {
            if menuBarStatus != .idle && menuBarStatus != .rest {
                menuBarStatus = .idle
            }
            timerWarningFired = false
            timerOvertimeFired = false
            return
        }

        let now = Date()
        let totalSeconds = activeTask.timerMinutes.map { $0 * 60 } ?? 0
        let remainingSeconds = Int(timerEnd.timeIntervalSince(now))

        if remainingSeconds <= 0 {
            if !timerOvertimeFired {
                menuBarStatus = .overtime
                timerOvertimeFired = true
                sendNotification(title: "任务结束", body: "任务 [\(activeTask.title)] 已超时，请确认是否完成。")
                appendMessage(Message(role: .system, content: "⏰ 任务 [\(activeTask.title)] 已超时！"))
            } else if menuBarStatus != .overtime {
                menuBarStatus = .overtime
            }
        } else if totalSeconds > 0, Double(remainingSeconds) <= Double(totalSeconds) * 0.2 {
            if !timerWarningFired {
                menuBarStatus = .warning
                timerWarningFired = true
                sendNotification(title: "时间提醒", body: "任务 [\(activeTask.title)] 剩余时间不足 20%。")
                appendMessage(Message(role: .system, content: "⚠️ 任务 [\(activeTask.title)] 剩余时间不足 20%。"))
            } else if menuBarStatus != .warning && menuBarStatus != .overtime {
                menuBarStatus = .warning
            }
        } else {
            if menuBarStatus != .focus {
                menuBarStatus = .focus
            }
        }

        objectWillChange.send()
    }

    public func resetTimerFlags() {
        timerWarningFired = false
        timerOvertimeFired = false
    }

    /// 测试入口：直接调用 private tick() 一次
    public func tickForTesting() {
        tick()
    }

    public func checkScheduledTasks(now: Date = Date()) {
        let calendar = Calendar.current
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let today = dateFormatter.string(from: now)

        // 防系统时间回拨：若 now 早于上次检查 60s 以上，认为时间被改，重置触发集合
        let nowTimestamp = now.timeIntervalSince1970
        if lastCheckTimestamp > 0 && nowTimestamp + 60 < lastCheckTimestamp {
            triggeredTasksToday.removeAll()
            lastTriggerDate = ""
        }
        lastCheckTimestamp = nowTimestamp

        if lastTriggerDate != today {
            triggeredTasksToday.removeAll()
            lastTriggerDate = today
        }

        let currentWeekday = calendar.component(.weekday, from: now)
        let hm = DateFormatter()
        hm.dateFormat = "HH:mm"
        let nowString = hm.string(from: now)

        for task in scheduledTasks where task.enabled {
            guard !triggeredTasksToday.contains(task.id.uuidString) else { continue }
            guard Self.scheduleMatches(task.schedule, weekday: currentWeekday) else { continue }
            guard task.time <= nowString else { continue }

            sendNotification(title: task.name, body: task.prompt)
            appendMessage(Message(role: .system, content: "⏰ \(task.name) — \(task.prompt)"))
            hasUnreadReminders = true
            triggeredTasksToday.insert(task.id.uuidString)
        }
    }

    private static func scheduleMatches(_ schedule: TaskSchedule, weekday: Int) -> Bool {
        switch schedule {
        case .daily: return true
        case .weekly(let w): return w.rawValue == weekday
        case .cron: return false
        }
    }

    public func sendNotification(title: String, body: String) {
        guard !Self.isRunningTests else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private static let isRunningTests: Bool = NSClassFromString("XCTestCase") != nil

    private func loadData() {
        // 加载配置
        if let configData = loadFile(named: "config.json"),
           let config = try? JSONDecoder().decode(AppConfig.self, from: configData) {
            self.config = config
        }

        // 加载系统提示词
        if let promptData = loadFile(named: "system-prompt.txt"),
           let prompt = String(data: promptData, encoding: .utf8) {
            self.systemPrompt = prompt
        } else {
            self.systemPrompt = Self.defaultSystemPrompt
            saveSystemPrompt()
        }

        // 加载当日任务（新路径 tasks/pinned.json，兼容旧路径 pinned.json）
        if let tasksData = loadFile(named: Self.pinnedTasksPath) ?? loadFile(named: "pinned.json"),
           let tasks = try? JSONDecoder().decode([TaskItem].self, from: tasksData) {
            self.tasks = tasks
        }

        // 加载定时任务（新路径 timers/scheduled.json，兼容旧路径 scheduled.json）
        if let scheduledData = loadFile(named: Self.scheduledTasksPath) ?? loadFile(named: "scheduled.json"),
           let scheduled = try? JSONDecoder().decode([ScheduledTask].self, from: scheduledData) {
            self.scheduledTasks = scheduled
        }

        // 加载历史对话
        loadConversationHistory()

        // 加载随手记
        notes = InboxService.shared.loadAll()
    }

    /// 把对话流中的某条消息转成随手记。消息会从 UI 隐藏，且 ChatEngine 后续不再带入上下文。
    /// 若是用户消息，紧邻其后的 assistant 回复也会一同隐藏，保持对话流的连贯性（PRD-QC §3.2.4）。
    public func convertMessageToNote(_ message: Message) {
        guard let idx = messages.firstIndex(where: { $0.id == message.id }) else { return }
        let content = messages[idx].content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }
        captureNote(content: content, source: .convertFromMessage, inputMode: messages[idx].inputMode)
        messages[idx].hidden = true

        if messages[idx].role == .user {
            let next = idx + 1
            if next < messages.count, messages[next].role == .assistant, !messages[next].hidden {
                messages[next].hidden = true
            }
        }

        appendMessage(Message(role: .system, content: "📥 已转随手记：\(content)"))
    }

    public func captureNote(content: String, source: Note.Source, inputMode: InputMode = .text) {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let note = Note(content: trimmed, source: source, inputMode: inputMode)
        notes.append(note)
        InboxService.shared.append(note)
    }

    public func markNoteDone(_ note: Note) {
        guard let idx = notes.firstIndex(where: { $0.id == note.id }) else { return }
        notes[idx].status = .done
        notes[idx].processedAt = Date()
        InboxService.shared.saveAll(notes)
    }

    public func deleteNote(_ note: Note) {
        notes.removeAll { $0.id == note.id }
        InboxService.shared.saveAll(notes)
    }

    /// 一键整理：把待处理随手记列表发给 AI，请它分类/建议优先级，结果展示在对话流。
    public func organizePendingNotes() async {
        guard !isOrganizing else { return }
        isOrganizing = true
        defer { isOrganizing = false }

        let pending = notes.filter { $0.status == .pending }
        guard !pending.isEmpty else {
            appendMessage(Message(role: .system, content: "📥 没有待处理的随手记"))
            return
        }
        let lines = pending.enumerated().map { idx, n in "\(idx + 1). \(n.content)" }.joined(separator: "\n")
        let prompt = """
        以下是我累积的随手记，请按主题分类并建议每条的优先级（高/中/低）。给我简短的整理结论，3 句话以内：

        \(lines)
        """
        selectedTab = .chat
        appendMessage(Message(role: .user, content: "整理一下我的随手记"))
        let placeholder = Message(role: .assistant, content: "")
        appendMessage(placeholder)
        let msgID = placeholder.id

        do {
            let response = try await ChatEngine.shared.sendMessage(
                prompt,
                systemPrompt: systemPrompt,
                useConversationHistory: false,
                onAssistantDelta: { delta in
                    Task { @MainActor in
                        if let idx = AppState.shared.messages.firstIndex(where: { $0.id == msgID }) {
                            AppState.shared.messages[idx].content += delta
                        }
                    }
                }
            )
            if let idx = messages.firstIndex(where: { $0.id == msgID }), messages[idx].content != response {
                messages[idx].content = response
            }
        } catch {
            if let idx = messages.firstIndex(where: { $0.id == msgID }) {
                messages[idx].role = .system
                messages[idx].content = "整理失败：\(error.localizedDescription)"
            }
        }
    }

    /// 把随手记推送到 Notion inbox 数据库（默认用 Name 作为 title 属性）
    /// 返回 true 表示推送成功；失败时 note 状态保持 pending，便于重试。
    @discardableResult
    public func pushNoteToNotion(_ note: Note) async -> Bool {
        guard let dbId = config.notionDatabaseIds.inbox, !dbId.isEmpty else {
            appendMessage(Message(role: .system, content: "✗ Notion 推送失败：未在设置中绑定收件箱数据库"))
            return false
        }
        let properties: [String: Any] = [
            "Name": [
                "title": [
                    ["text": ["content": note.content]]
                ]
            ]
        ]
        guard let propertiesData = try? JSONSerialization.data(withJSONObject: properties, options: []) else {
            appendMessage(Message(role: .system, content: "✗ Notion 推送失败：序列化错误"))
            return false
        }
        do {
            let respData = try await NotionService.shared.createPage(databaseId: dbId, propertiesData: propertiesData)
            let json = (try? JSONSerialization.jsonObject(with: respData) as? [String: Any]) ?? [:]
            let pageId = json["id"] as? String
            if let idx = notes.firstIndex(where: { $0.id == note.id }) {
                notes[idx].status = .done
                notes[idx].processedAt = Date()
                notes[idx].notionPageId = pageId
                InboxService.shared.saveAll(notes)
            }
            appendMessage(Message(role: .system, content: "✓ 已推送到 Notion：\(note.content)"))
            return true
        } catch {
            appendMessage(Message(role: .system, content: "✗ Notion 推送失败：\(error.localizedDescription)"))
            return false
        }
    }

    // MARK: - Timer / Task 操作 API（供 ToolExecutor 调用）

    @discardableResult
    public func startTimer(task title: String, minutes: Int) -> TaskItem {
        let task = TaskItem(
            title: title,
            status: .inProgress,
            timerMinutes: minutes,
            timerStart: Date(),
            timerEnd: Date().addingTimeInterval(TimeInterval(minutes * 60))
        )
        tasks.append(task)
        activeTask = task
        menuBarStatus = .focus
        resetTimerFlags()
        saveTasks()
        appendMessage(Message(role: .system, content: "✓ 已启动计时：\(title) · \(minutes) 分钟"))
        return task
    }

    public func completeCurrentTimer(note: String? = nil) {
        guard let active = activeTask,
              let idx = tasks.firstIndex(where: { $0.id == active.id }) else { return }
        tasks[idx].status = .done
        activeTask = nil
        menuBarStatus = .idle
        resetTimerFlags()
        saveTasks()
        let detail = note.map { " — \($0)" } ?? ""
        appendMessage(Message(role: .system, content: "✓ 已完成：\(active.title)\(detail)"))
    }

    public func extendCurrentTimer(by minutes: Int) {
        guard let active = activeTask,
              let idx = tasks.firstIndex(where: { $0.id == active.id }) else { return }
        let base = tasks[idx].timerEnd ?? Date()
        tasks[idx].timerEnd = base.addingTimeInterval(TimeInterval(minutes * 60))
        tasks[idx].extensions += 1
        activeTask = tasks[idx]
        menuBarStatus = .focus
        resetTimerFlags()
        saveTasks()
        appendMessage(Message(role: .system, content: "✓ 已延长 \(minutes) 分钟"))
    }

    @discardableResult
    public func addPinnedTask(title: String) -> TaskItem {
        let task = TaskItem(title: title, status: .pending)
        tasks.append(task)
        saveTasks()
        return task
    }

    public func openInbox() {
        selectedTab = .inbox
    }

    public func convertNoteToTask(_ note: Note) {
        let task = TaskItem(title: note.content, status: .pending)
        tasks.append(task)
        saveTasks()
        markNoteDone(note)
        appendMessage(Message(role: .system, content: "✓ 已转任务：\(note.content)"))
    }

    private func loadFile(named filename: String) -> Data? {
        let url = Self.dataDirectory.appendingPathComponent(filename)
        return try? Data(contentsOf: url)
    }

    public func saveConfig() {
        let url = Self.dataDirectory.appendingPathComponent("config.json")
        try? JSONEncoder().encode(config).write(to: url)
    }

    public func saveSystemPrompt() {
        let url = Self.dataDirectory.appendingPathComponent("system-prompt.txt")
        try? systemPrompt.write(to: url, atomically: true, encoding: .utf8)
    }

    public func saveTasks() {
        let url = Self.dataDirectory.appendingPathComponent(Self.pinnedTasksPath)
        Self.ensureParentDirectory(url)
        try? JSONEncoder().encode(tasks).write(to: url)
    }

    public func saveScheduledTasks() {
        let url = Self.dataDirectory.appendingPathComponent(Self.scheduledTasksPath)
        Self.ensureParentDirectory(url)
        try? JSONEncoder().encode(scheduledTasks).write(to: url)
    }

    private static let pinnedTasksPath = "tasks/pinned.json"
    private static let scheduledTasksPath = "timers/scheduled.json"

    private static func ensureParentDirectory(_ url: URL) {
        let parent = url.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: parent.path) {
            try? FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        }
    }

    private func loadConversationHistory() {
        let fileManager = FileManager.default
        let conversationsDir = Self.dataDirectory.appendingPathComponent("conversations")

        guard let files = try? fileManager.contentsOfDirectory(at: conversationsDir, includingPropertiesForKeys: nil) else {
            return
        }

        let sortedFiles = files
            .filter { $0.pathExtension == "jsonl" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }

        for file in sortedFiles.prefix(30) {
            guard let data = try? Data(contentsOf: file),
                  let lines = String(data: data, encoding: .utf8)?.components(separatedBy: .newlines) else {
                continue
            }

            let dayMessages = lines.compactMap { line -> Message? in
                guard !line.isEmpty, let data = line.data(using: .utf8) else { return nil }
                return try? JSONDecoder().decode(Message.self, from: data)
            }

            if !dayMessages.isEmpty {
                let dateString = file.deletingPathExtension().lastPathComponent
                conversationHistory.append(ConversationDay(date: dateString, messages: dayMessages))
            }
        }
    }

    public func appendMessage(_ message: Message) {
        messages.append(message)
        saveTodayMessages()
    }

    private func saveTodayMessages() {
        guard !Self.isRunningTests else { return }
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: Date())

        let url = Self.dataDirectory
            .appendingPathComponent("conversations")
            .appendingPathComponent("\(dateString).jsonl")

        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: url.path) {
            try? fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        }

        if let data = try? JSONEncoder().encode(messages.last),
           let line = String(data: data, encoding: .utf8),
           let newline = "\n".data(using: .utf8),
           let lineData = line.data(using: .utf8) {
            let fileManager = FileManager.default
            if fileManager.fileExists(atPath: url.path) {
                if let handle = try? FileHandle(forWritingTo: url) {
                    handle.seekToEndOfFile()
                    handle.write(newline)
                    handle.write(lineData)
                    try? handle.close()
                }
            } else {
                try? line.write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }

    public static var dataDirectory: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".opc-companion")
    }

    public static let defaultSystemPrompt = """
    你是 OPC 伴侣，一个 macOS 上的个人工作节奏教练。

    你的职责：
    1. 帮助用户管理工作节奏：计时、提醒、任务跟踪
    2. 通过 Notion 查看和管理用户的日程与待办
    3. 在用户偏离计划时主动提醒
    4. 回复简洁直接，不要啰嗦

    你可以执行的操作：
    - 创建计时任务（用户说"开始XX任务，N分钟"）
    - 查询 Notion 数据库（日历、待办等）
    - 修改 Notion 数据（需要用户确认后执行）

    回复规则：
    - 使用中文
    - 简短有力，每次回复控制在 3 句话以内
    - 如果是计时/任务操作，回复后附上结构化指令（见下方格式）

    当需要创建计时任务时，在回复末尾附加：
    [ACTION:timer:start:{"task":"任务名","minutes":25}]

    当需要操作 Notion 时，在回复末尾附加：
    [ACTION:notion:操作类型:{"参数"}]
    注意：Notion 写入操作必须等待用户在 UI 中确认后才执行。
    """

    public func generateDailySummary() async -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let today = dateFormatter.string(from: Date())

        // 检查今天是否已经生成过总结
        if lastSummaryDate == today && !lastSummary.isEmpty {
            return lastSummary
        }

        // 统计今日数据
        let completedTasks = tasks.filter { $0.status == .done }
        let taskList = completedTasks.map { $0.title }.joined(separator: "、")
        let taskCount = completedTasks.count
        let messageCount = messages.count

        let summaryPrompt = "生成今日工作总结：今日完成 \(taskCount) 个任务，对话 \(messageCount) 条，任务列表：\(taskList)。请用简洁中文总结，100字以内。"

        do {
            let summary = try await ChatEngine.shared.sendMessage(
                summaryPrompt,
                systemPrompt: AppState.defaultSystemPrompt,
                useConversationHistory: false
            )
            lastSummary = summary
            lastSummaryDate = today
            saveDailySummary(summary, date: today)
            return summary
        } catch {
            return "无法生成总结：\(error.localizedDescription)"
        }
    }

    private func saveDailySummary(_ summary: String, date: String) {
        let url = Self.dataDirectory.appendingPathComponent("daily-summaries")
            .appendingPathComponent("\(date).txt")
        let fileManager = FileManager.default

        if !fileManager.fileExists(atPath: url.deletingLastPathComponent().path) {
            try? fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        }

        try? summary.write(to: url, atomically: true, encoding: .utf8)
    }
}

public enum AppTab: String, CaseIterable {
    case chat
    case inbox
    case history
    case settings

    var title: String {
        switch self {
        case .chat: return "对话"
        case .inbox: return "收件箱"
        case .history: return "历史"
        case .settings: return "设置"
        }
    }

    var icon: String {
        switch self {
        case .chat: return "bubble.left.and.text.bubble.right"
        case .inbox: return "tray"
        case .history: return "clock"
        case .settings: return "gear"
        }
    }
}

public struct ConversationDay: Identifiable {
    public let id = UUID()
    public let date: String
    public var messages: [Message]
    public var isExpanded = false
}

public enum MenuBarStatus {
    case idle
    case focus
    case warning
    case overtime
    case rest
}
