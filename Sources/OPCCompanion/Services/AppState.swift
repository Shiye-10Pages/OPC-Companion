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
    @Published public var lastSessionDate: String = ""  // 上次会话所在日期（跨日归档用）
    @Published public var triggeredTasksToday: Set<String> = []  // 今天已触发的任务 ID
    @Published public var lastTriggerDate: String = ""  // 上次检查日期
    private var lastCheckTimestamp: TimeInterval = 0    // 系统时间回拨防护

    // 计时提醒防重触发标志
    @Published public var timerWarningFired = false
    @Published public var timerOvertimeFired = false

    // 一键整理防重入
    @Published public var isOrganizing = false

    // 顶部 banner（承接原系统消息，3 秒自动消失）
    @Published public var banner: BannerMessage?
    private var bannerDismissTask: Task<Void, Never>?

    // 添加任务浮层显示开关（放 MainTabView 层级承载，避免在 borderless NSPanel 里用 .sheet 崩）
    @Published public var showAddTaskOverlay = false
    // 定时任务表单（同理，从 SettingsView .sheet 迁到 MainTabView overlay）
    @Published public var showScheduledTaskForm = false
    @Published public var editingScheduledTask: ScheduledTask?

    // Dreaming 候选审核（每日最多弹一次，和早晨仪式同理）
    @Published public var pendingLearnings: [(id: UUID, date: String, entry: String)] = []
    @Published public var showDreamingReview = false
    @Published public var lastDreamingReviewDate: String = ""

    // T1-1 早晨仪式
    @Published public var lastMorningRitualDate: String = ""
    @Published public var showMorningRitual: Bool = false

    // T1-2 完成后 next 候选浮层
    @Published public var nextCandidates: [TaskItem] = []

    // T1-3 进展 ping
    @Published public var showProgressPingPanel: Bool = false
    @Published public var lastProgressPingAt: Date?
    public static let progressPingIntervalMinutes = 20

    // T1-4 Pomodoro 循环状态
    public enum PomodoroPhase: String { case idle, work, rest }
    @Published public var pomodoroPhase: PomodoroPhase = .idle
    @Published public var pomodoroAnchorTaskId: UUID?

    // T2-6 Post-mortem 队列
    @Published public var postMortemQueue: [TaskItem] = []

    public func enqueuePostMortem(_ task: TaskItem) {
        postMortemQueue.append(task)
    }

    public func dequeuePostMortem() {
        if !postMortemQueue.isEmpty { postMortemQueue.removeFirst() }
    }

    /// 读最多 3 个 pending 任务作为"下一个"候选（T1-2）。
    public func refreshNextCandidates(excluding: UUID? = nil) {
        let pending = tasks.filter { $0.status == .pending && $0.id != excluding }
        nextCandidates = Array(pending.prefix(3))
    }

    private var cancellables = Set<AnyCancellable>()
    private var globalTimer: Timer?

    /// 发送一条 banner，承接原系统消息的"一瞥性"信息。
    /// 会话消息流保持纯净：banner 不进 messages，不写进 conversations/*.jsonl。
    public func showBanner(_ text: String, kind: BannerMessage.Kind = .info, duration: TimeInterval = 3.0) {
        bannerDismissTask?.cancel()
        let msg = BannerMessage(text: text, kind: kind)
        banner = msg
        bannerDismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled, self?.banner?.id == msg.id else { return }
            self?.banner = nil
        }
    }

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
                // Pomodoro：自动进入下一阶段；非 Pomodoro：提醒超时
                if activeTask.pomodoroCycle {
                    advancePomodoro(from: activeTask)
                } else {
                    sendNotification(title: "任务结束", body: "任务 [\(activeTask.title)] 已超时，请确认是否完成。")
                    showBanner("任务 \(activeTask.title) 已超时", kind: .warning, duration: 5.0)
                    MemoryService.shared.appendToToday(.timers, entry: "⏰ 任务 [\(activeTask.title)] 超时")
                }
            } else if menuBarStatus != .overtime {
                menuBarStatus = .overtime
            }
        } else if totalSeconds > 0, Double(remainingSeconds) <= Double(totalSeconds) * 0.2 {
            if !timerWarningFired {
                menuBarStatus = .warning
                timerWarningFired = true
                sendNotification(title: "时间提醒", body: "任务 [\(activeTask.title)] 剩余时间不足 20%。")
                showBanner("任务 \(activeTask.title) 剩余时间 <20%", kind: .info)
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

    /// Pomodoro 推进：work→rest / rest→idle（并让用户发起下一轮）
    private func advancePomodoro(from finished: TaskItem) {
        guard let idx = tasks.firstIndex(where: { $0.id == finished.id }) else { return }
        tasks[idx].actualMinutes = Self.actualMinutes(for: tasks[idx])
        tasks[idx].status = .done
        let finishedTitle = tasks[idx].title
        activeTask = nil
        saveTasks()

        if finished.isPomodoroBreak {
            // 休息结束 → 回到 idle，提示下一轮
            pomodoroPhase = .idle
            pomodoroAnchorTaskId = nil
            menuBarStatus = .idle
            resetTimerFlags()
            showBanner("休息结束 · 准备下一轮 🍅", kind: .info, duration: 5.0)
            refreshNextCandidates()
        } else {
            // 工作段结束 → 启动 5 分钟休息段
            pomodoroPhase = .rest
            let breakTask = TaskItem(
                title: "☕ 休息",
                status: .inProgress,
                timerMinutes: 5,
                timerStart: Date(),
                timerEnd: Date().addingTimeInterval(5 * 60),
                pomodoroCycle: true,
                isPomodoroBreak: true
            )
            tasks.append(breakTask)
            activeTask = breakTask
            menuBarStatus = .focus
            resetTimerFlags()
            lastProgressPingAt = Date()
            saveTasks()
            showBanner("完成 \(finishedTitle) · 休息 5 分钟", kind: .success, duration: 5.0)
            MemoryService.shared.appendToToday(.tasks, entry: "🍅 完成 \(finishedTitle)\(Self.estimateVsActualNote(for: tasks[idx]))")
        }
    }

    /// 计时进行中定期 ping（由每分钟定时调用）：
    /// 满足 20min 节拍时弹出进展输入面板；用户可填一句或跳过。
    public func checkProgressPing(now: Date = Date()) {
        guard let active = activeTask, active.status == .inProgress else { return }
        let last = lastProgressPingAt ?? active.timerStart ?? now
        let elapsed = now.timeIntervalSince(last)
        let threshold = Double(Self.progressPingIntervalMinutes * 60)
        if elapsed >= threshold, !showProgressPingPanel {
            showProgressPingPanel = true
            lastProgressPingAt = now
        }
    }

    public func submitProgressNote(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        showProgressPingPanel = false
        guard !trimmed.isEmpty else { return }
        let taskTitle = activeTask?.title ?? "(无任务)"
        MemoryService.shared.appendToToday(.tasks, entry: "进展 · \(taskTitle)：\(trimmed)")
        showBanner("进展已记录", kind: .success, duration: 2.0)
    }

    public func skipProgressPing() {
        showProgressPingPanel = false
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
            showBanner("⏰ \(task.name)", kind: .info)
            MemoryService.shared.appendToToday(.timers, entry: "\(task.name) — \(task.prompt)")
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

        // 加载上次会话日期（跨日归档标记）
        if let data = loadFile(named: "session-state.txt"),
           let text = String(data: data, encoding: .utf8) {
            lastSessionDate = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // 加载上次早晨仪式日期
        if let data = loadFile(named: "ritual-state.txt"),
           let text = String(data: data, encoding: .utf8) {
            lastMorningRitualDate = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // 加载上次 Dreaming 审核日期
        if let data = loadFile(named: "dreaming-state.txt"),
           let text = String(data: data, encoding: .utf8) {
            lastDreamingReviewDate = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    public func saveSessionState() {
        let url = Self.dataDirectory.appendingPathComponent("session-state.txt")
        try? lastSessionDate.write(to: url, atomically: true, encoding: .utf8)
    }

    public func saveRitualState() {
        let url = Self.dataDirectory.appendingPathComponent("ritual-state.txt")
        try? lastMorningRitualDate.write(to: url, atomically: true, encoding: .utf8)
    }

    public func saveDreamingState() {
        let url = Self.dataDirectory.appendingPathComponent("dreaming-state.txt")
        try? lastDreamingReviewDate.write(to: url, atomically: true, encoding: .utf8)
    }

    public func markDreamingReviewDone(now: Date = Date()) {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        lastDreamingReviewDate = f.string(from: now)
        saveDreamingState()
        showDreamingReview = false
        pendingLearnings = []
    }

    /// 打开面板时检查：今日还未完成早晨仪式 → 触发
    public func checkMorningRitual(now: Date = Date()) {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        let today = f.string(from: now)
        if lastMorningRitualDate != today {
            showMorningRitual = true
        }
    }

    public func finishMorningRitual(items: [String], now: Date = Date()) {
        let cleaned = items.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        for title in cleaned {
            _ = addPinnedTask(title: title)
            MemoryService.shared.appendToToday(.tasks, entry: "锁定：\(title)")
        }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        lastMorningRitualDate = f.string(from: now)
        saveRitualState()
        showMorningRitual = false
        if !cleaned.isEmpty {
            showBanner("已锁定今日 \(cleaned.count) 件事", kind: .success)
        }
    }

    /// 触发 Dreaming 审核：扫候选 → 有则弹浮层。可由仪式衔接或 /学习 命令调用。
    public func triggerDreamingIfNeeded() {
        let candidates = DreamingService.shared.harvestCandidates()
        guard !candidates.isEmpty else { return }
        pendingLearnings = candidates.map { (UUID(), $0.date, $0.entry) }
        showDreamingReview = true
    }

    /// 把对话流中的某条消息转成随手记。消息会从 UI 隐藏，且 ChatEngine 后续不再带入上下文。
    /// 若是用户消息，紧邻其后的 assistant 回复也会一同隐藏，保持对话流的连贯性（PRD-QC §3.2.4）。
    /// 保存时剥离 `<think>...</think>` 块，只留最终回复内容。
    public func convertMessageToNote(_ message: Message) {
        guard let idx = messages.firstIndex(where: { $0.id == message.id }) else { return }
        let parsed = ThinkingParser.parse(messages[idx].content)
        let content = (parsed.main.isEmpty ? messages[idx].content : parsed.main)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }
        captureNote(content: content, source: .convertFromMessage, inputMode: messages[idx].inputMode)
        messages[idx].hidden = true

        if messages[idx].role == .user {
            let next = idx + 1
            if next < messages.count, messages[next].role == .assistant, !messages[next].hidden {
                messages[next].hidden = true
            }
        }

        showBanner("已转随手记", kind: .success)
        MemoryService.shared.appendToToday(.notes, entry: content)
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
            showBanner("没有待处理的随手记", kind: .info)
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
                // 保持 assistant role 以维持消息流纯净（只有 user/assistant），错误以 banner 和气泡内容双通道反馈
                messages[idx].content = "整理失败：\(error.localizedDescription)"
            }
            showBanner("随手记整理失败：\(error.localizedDescription)", kind: .error, duration: 5.0)
        }
    }

    /// 把随手记推送到 Notion inbox 数据库（默认用 Name 作为 title 属性）
    /// 返回 true 表示推送成功；失败时 note 状态保持 pending，便于重试。
    @discardableResult
    public func pushNoteToNotion(_ note: Note) async -> Bool {
        guard let dbId = config.notionDatabaseIds.inbox, !dbId.isEmpty else {
            showBanner("Notion 推送失败：未绑定收件箱数据库", kind: .error, duration: 5.0)
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
            showBanner("Notion 推送失败：序列化错误", kind: .error, duration: 5.0)
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
            showBanner("已推送到 Notion", kind: .success)
            MemoryService.shared.appendToToday(.notion, entry: "推送随手记：\(note.content)")
            return true
        } catch {
            showBanner("Notion 推送失败：\(error.localizedDescription)", kind: .error, duration: 5.0)
            return false
        }
    }

    // MARK: - Timer / Task 操作 API（供 ToolExecutor 调用）

    @discardableResult
    public func startTimer(task title: String, minutes: Int, pomodoroCycle: Bool = false, focusMode: Bool = false) -> TaskItem {
        let task = TaskItem(
            title: title,
            status: .inProgress,
            timerMinutes: minutes,
            timerStart: Date(),
            timerEnd: Date().addingTimeInterval(TimeInterval(minutes * 60)),
            pomodoroCycle: pomodoroCycle,
            focusMode: focusMode
        )
        tasks.append(task)
        activeTask = task
        menuBarStatus = .focus
        resetTimerFlags()
        lastProgressPingAt = Date()  // 启动时重置 ping 计时
        saveTasks()
        if pomodoroCycle {
            pomodoroPhase = .work
            pomodoroAnchorTaskId = task.id
        }
        if focusMode {
            Task { await FocusModeService.shared.enable() }
        }
        showBanner("已启动计时：\(title) · \(minutes) 分钟", kind: .success)
        MemoryService.shared.appendToToday(.tasks, entry: "启动计时：\(title) · \(minutes) 分钟")
        return task
    }

    public func completeCurrentTimer(note: String? = nil) {
        guard let active = activeTask,
              let idx = tasks.firstIndex(where: { $0.id == active.id }) else { return }
        tasks[idx].status = .done
        tasks[idx].actualMinutes = Self.actualMinutes(for: tasks[idx])
        activeTask = nil
        menuBarStatus = .idle
        resetTimerFlags()
        saveTasks()
        let detail = note.map { " — \($0)" } ?? ""
        let estimateNote = Self.estimateVsActualNote(for: tasks[idx])
        showBanner("已完成：\(active.title)", kind: .success)
        MemoryService.shared.appendToToday(.tasks, entry: "完成：\(active.title)\(estimateNote)\(detail)")
        enqueuePostMortem(tasks[idx])
        refreshNextCandidates(excluding: active.id)
        if tasks[idx].focusMode {
            Task { await FocusModeService.shared.disable() }
        }
    }

    /// 从 timerStart 到现在的分钟数（向上取整）；没有 start 则 nil
    static func actualMinutes(for task: TaskItem) -> Int? {
        guard let start = task.timerStart else { return nil }
        let seconds = max(0, Date().timeIntervalSince(start))
        return Int(ceil(seconds / 60.0))
    }

    static func estimateVsActualNote(for task: TaskItem) -> String {
        guard let actual = task.actualMinutes else { return "" }
        if let estimate = task.timerMinutes, estimate > 0 {
            return " · 实 \(actual)m（估 \(estimate)m）"
        }
        return " · 实 \(actual)m"
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
        showBanner("已延长 \(minutes) 分钟", kind: .info)
        MemoryService.shared.appendToToday(.tasks, entry: "延长 \(minutes) 分钟：\(active.title)")
    }

    @discardableResult
    public func addPinnedTask(title: String) -> TaskItem {
        let task = TaskItem(title: title, status: .pending)
        tasks.append(task)
        saveTasks()
        return task
    }

    /// 添加任务的统一入口：有计时 → startTimer；无计时 → pinned + banner + daily note。
    /// AddTask 表单用，避免在多处重复 banner/memory 写入逻辑。
    @discardableResult
    public func addOrStartTask(
        title: String,
        minutes: Int?,
        pomodoroCycle: Bool = false,
        focusMode: Bool = false
    ) -> TaskItem? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let m = minutes, m > 0 {
            return startTimer(task: trimmed, minutes: m, pomodoroCycle: pomodoroCycle, focusMode: focusMode)
        } else {
            let task = addPinnedTask(title: trimmed)
            showBanner("已添加任务：\(trimmed)", kind: .success)
            MemoryService.shared.appendToToday(.tasks, entry: "新增待办：\(trimmed)")
            return task
        }
    }

    public func openInbox() {
        selectedTab = .inbox
    }

    public func convertNoteToTask(_ note: Note) {
        let task = TaskItem(title: note.content, status: .pending)
        tasks.append(task)
        saveTasks()
        markNoteDone(note)
        showBanner("已转任务：\(note.content)", kind: .success)
        MemoryService.shared.appendToToday(.tasks, entry: "从随手记转任务：\(note.content)")
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
        try? JSONEncoder().encode(tasks).write(to: url, options: .atomic)
    }

    public func saveScheduledTasks() {
        let url = Self.dataDirectory.appendingPathComponent(Self.scheduledTasksPath)
        Self.ensureParentDirectory(url)
        try? JSONEncoder().encode(scheduledTasks).write(to: url, options: .atomic)
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
            // 剔除历史 jsonl 里遗留的 .system 消息（老数据污染），保持对话流纯净
            let filteredMessages = dayMessages.filter { $0.role != .system }

            if !filteredMessages.isEmpty {
                let dateString = file.deletingPathExtension().lastPathComponent
                conversationHistory.append(ConversationDay(date: dateString, messages: filteredMessages))
            }
        }
    }

    public func appendMessage(_ message: Message) {
        messages.append(message)
        saveTodayMessages()
    }

    private func saveTodayMessages() {
        guard !Self.isRunningTests else { return }
        // 新设计：消息流只持久化 user/assistant，老代码如仍产生 .system 则不进 jsonl
        guard let last = messages.last, last.role != .system else { return }
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

        if let data = try? JSONEncoder().encode(last),
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

    回复规则：
    - 使用中文
    - 简短有力，每次回复控制在 3 句话以内
    - 不要在回复文本中附加任何结构化指令标记（如 [ACTION:...]）

    执行操作请使用 tool / function calling，而不是在文本中拼指令字符串：
    - 启动计时 → 调用 start_timer 工具
    - 延长计时 → 调用 extend_timer 工具
    - 查询 / 修改 Notion → 调用对应的 notion_* 工具（写操作 tool 会要求用户在 UI 中确认）
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
    case chat       // 主会话（默认，无 popover）
    case tasks      // 任务 popover（原底部 Tab 取消后，顶部 status bar 驱动）
    case inbox
    case history
    case settings

    var title: String {
        switch self {
        case .chat: return "对话"
        case .tasks: return "任务"
        case .inbox: return "收件箱"
        case .history: return "历史"
        case .settings: return "设置"
        }
    }

    var icon: String {
        switch self {
        case .chat: return "bubble.left.and.text.bubble.right"
        case .tasks: return "checklist"
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
