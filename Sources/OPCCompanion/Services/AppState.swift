import Foundation
import SwiftUI
import AppKit
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

    // "我想"清扫会话：/聊聊 触发后激活，带 10 分钟时限和进入前的锚点任务
    @Published public var wishClearingSession: WishClearingSession?

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

    // 用户最后一次可观测活动时间（发消息 / 捕获随手记 / 打开面板 / 点按钮 等）
    // 用于"长时间静默"识别 → AI 主动提醒"你锁定的 X 还没动"
    public var lastActivityAt: Date = Date()

    // 今日已触发的主动提醒 key 集合（morning_missed / late_night 等），跨日重置。
    // 每个 key 每天只触发一次，避免同一主题反复打扰。
    private var dailyAlertsFired: Set<String> = []
    private var dailyAlertsDate: String = ""

    // idle_drift 单独用时间戳判断（每 30 分钟可再触发一次），不走 dailyAlertsFired 的"当日一次"
    private var lastIdleDriftAt: Date?

    // 一键整理防重入
    @Published public var isOrganizing = false

    // 正在推送到 Notion 的 note id 集合：防止用户连点 Notion 按钮导致创建多条重复页面
    private var pushingNoteIds: Set<UUID> = []

    // 批量删除随手记的撤销快照（5 秒内通过 banner 的"撤销"按钮恢复）
    private var pendingUndoNotes: [Note] = []
    private var pendingUndoExpireTask: Task<Void, Never>?

    // UI 字号缩放系数：Cmd+= 放大 / Cmd+- 缩小 / Cmd+0 重置。范围 0.7 - 1.5。
    @Published public var fontScale: Double = 1.0

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
    public func showBanner(_ text: String, kind: BannerMessage.Kind = .info, duration: TimeInterval = 3.0, action: BannerMessage.Action? = nil) {
        bannerDismissTask?.cancel()
        let msg = BannerMessage(text: text, kind: kind, action: action)
        banner = msg
        bannerDismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled, self?.banner?.id == msg.id else { return }
            self?.banner = nil
        }
    }

    /// 处理 banner 点击 action。点击前重新检查条件，已过期就不动只关闭 banner。
    public func handleBannerAction(_ action: BannerMessage.Action) {
        switch action {
        case .openMorningRitual:
            let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
            let today = df.string(from: Date())
            // 条件仍然成立（今天还没做仪式）→ 弹仪式
            if lastMorningRitualDate != today {
                showMorningRitual = true
            }
        case .undoBatchDelete:
            undoBatchDelete()
        }
        banner = nil
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
        // 每秒检查一次主动介入信号（早晨仪式错过 / 长时间静默 / 深夜）
        checkDriftSignals()

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
                    // 计时到点音效（通知 sound=.default 在前台时可能被抑制，直接用 NSSound 兜底）
                    NSSound(named: "Glass")?.play()
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

    /// 在所有可观测的用户活动处调用：发消息、捕获随手记、打开面板、点按钮等。
    /// 被 checkDriftSignals 用来判断"静默"。
    public func markActivity(_ now: Date = Date()) {
        lastActivityAt = now
    }

    /// tick() 每秒调用一次。识别 3 种需要主动介入的信号，每天每种只触发一次。
    private func checkDriftSignals(now: Date = Date()) {
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
        let today = df.string(from: now)
        // 跨日重置
        if dailyAlertsDate != today {
            dailyAlertsFired.removeAll()
            dailyAlertsDate = today
        }

        let cal = Calendar.current
        let hour = cal.component(.hour, from: now)

        // 1. 早晨仪式错过：10 点后还没完成仪式 → 菜单栏警告 + 可点击 banner 一次
        if hour >= 10 && lastMorningRitualDate != today && !dailyAlertsFired.contains("morning_missed") {
            dailyAlertsFired.insert("morning_missed")
            hasUnreadReminders = true
            showBanner("今天还没锁定 3 件事", kind: .warning, duration: 8.0, action: .openMorningRitual)
            MemoryService.shared.appendToToday(.tasks, entry: "⚠️ 早晨仪式未完成（\(hour):00 提醒）")
        }

        // 2. 长时间静默 + 有待办任务：30 分钟无活动 + pending 任务 → banner。
        // 允许每 30 分钟再次触发（避免一天只提醒一次后长期静默无后续），触发后 reset 计时。
        let idle = now.timeIntervalSince(lastActivityAt)
        let hasPending = tasks.contains { $0.status == .pending }
        let hasActive = activeTask?.status == .inProgress
        let sinceLastDrift = lastIdleDriftAt.map { now.timeIntervalSince($0) } ?? .infinity
        if idle >= 1800 && hasPending && !hasActive && sinceLastDrift >= 1800 {
            lastIdleDriftAt = now
            lastActivityAt = now   // 重置静默计时，下一次再静默 30 分钟后可再提醒
            let nextTask = tasks.first(where: { $0.status == .pending })?.title ?? "焦点任务"
            showBanner("静默 30 分钟了 · 要不要回到 [\(nextTask)]？", kind: .info, duration: 6.0)
            MemoryService.shared.appendToToday(.tasks, entry: "⏸ 静默 30 分钟提醒（锚点：\(nextTask)）")
        }

        // 3. 深夜提醒：23 点后仍有活跃计时 → 问是否明天再战
        if hour >= 23 && hasActive && !dailyAlertsFired.contains("late_night") {
            dailyAlertsFired.insert("late_night")
            let taskTitle = activeTask?.title ?? ""
            showBanner("已 \(hour):00 · [\(taskTitle)] 明天再战？", kind: .info, duration: 8.0)
            NSSound(named: "Tink")?.play()
            MemoryService.shared.appendToToday(.tasks, entry: "🌙 深夜提醒（\(hour):00, 任务：\(taskTitle)）")
        }
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
            saveTriggerState()
        }
        lastCheckTimestamp = nowTimestamp

        if lastTriggerDate != today {
            triggeredTasksToday.removeAll()
            lastTriggerDate = today
            saveTriggerState()
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
            saveTriggerState()
            // 定时任务音效（通知本身 sound=.default，在前台抑制时这里兜底确保用户能听到）
            NSSound(named: "Ping")?.play()
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

        // 加载触发状态（防止 kill/重启后当天闹钟重复响）
        if let data = loadFile(named: Self.triggerStatePath),
           let snapshot = try? JSONDecoder().decode(TriggerStateSnapshot.self, from: data) {
            self.triggeredTasksToday = Set(snapshot.triggeredTasksToday)
            self.lastTriggerDate = snapshot.lastTriggerDate
        }

        // 加载字号缩放（Cmd+/-/0 调整后持久化）
        if let data = loadFile(named: "font-scale.txt"),
           let text = String(data: data, encoding: .utf8),
           let s = Double(text.trimmingCharacters(in: .whitespacesAndNewlines)) {
            self.fontScale = max(0.7, min(1.5, s))
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

        // 恢复活跃计时：tasks 里若有 inProgress 且 timerEnd 未过期的任务，重新挂到 activeTask 上
        // 这样 kill/重启后 tick 能继续工作，菜单栏也能显示倒计时
        if let revived = tasks.first(where: { task in
            task.status == .inProgress && (task.timerEnd ?? .distantPast) > Date()
        }) {
            activeTask = revived
            menuBarStatus = .focus
            // 根据剩余时间推断 fired 标志，避免重启瞬间重复推送"剩余不足 20%"通知
            if let timerMinutes = revived.timerMinutes,
               let end = revived.timerEnd {
                let total = timerMinutes * 60
                let remaining = Int(end.timeIntervalSince(Date()))
                if total > 0 && Double(remaining) <= Double(total) * 0.2 {
                    timerWarningFired = true
                    menuBarStatus = .warning
                }
            }
        }
        // 对所有已超时但未完成的 inProgress 任务：标 overtimeFired，防止重启瞬间再次推超时通知
        let overtimeExists = tasks.contains { task in
            task.status == .inProgress && (task.timerEnd ?? .distantPast) <= Date()
        }
        if overtimeExists {
            timerOvertimeFired = true
            if activeTask == nil {
                menuBarStatus = .overtime
            }
        }

        // Pomodoro phase：kill/重启后不保留进行中的番茄循环阶段，避免 phase 和真实时间脱节
        pomodoroPhase = .idle
        pomodoroAnchorTaskId = nil
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

    public func captureNote(content: String, source: Note.Source, inputMode: InputMode = .text, kind: Note.Kind = .note) {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let note = Note(content: trimmed, source: source, inputMode: inputMode, kind: kind)
        notes.append(note)
        InboxService.shared.append(note)
        markActivity()
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

    /// 批量删除随手记 + 记录 5 秒内可撤销的快照（Inbox 的"批量删除"入口用）
    public func batchDeleteNotesWithUndo(ids: Set<UUID>) {
        let snapshot = notes.filter { ids.contains($0.id) }
        guard !snapshot.isEmpty else { return }
        notes.removeAll { ids.contains($0.id) }
        InboxService.shared.saveAll(notes)

        pendingUndoNotes = snapshot
        pendingUndoExpireTask?.cancel()
        pendingUndoExpireTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 5 * 1_000_000_000)
            guard !Task.isCancelled else { return }
            self?.pendingUndoNotes = []
        }

        showBanner("已删除 \(snapshot.count) 条 · 5 秒内可撤销",
                   kind: .info,
                   duration: 5.0,
                   action: .undoBatchDelete)
    }

    /// 恢复上次批量删除的随手记（由 banner "撤销" 按钮触发）
    public func undoBatchDelete() {
        guard !pendingUndoNotes.isEmpty else { return }
        let restore = pendingUndoNotes
        pendingUndoNotes = []
        pendingUndoExpireTask?.cancel()
        pendingUndoExpireTask = nil
        for note in restore where !notes.contains(where: { $0.id == note.id }) {
            notes.append(note)
        }
        InboxService.shared.saveAll(notes)
        showBanner("已恢复 \(restore.count) 条", kind: .success, duration: 2.5)
    }

    // MARK: - Wish Clearing Session

    /// 启动 "/聊聊" 会话：记录进入前的锚点任务，开始 10 分钟计时。
    /// 已有未过期 session 时保留不重置；已过期 session 会被新的替换掉。
    public func startWishClearingSession(anchorTask: String?) {
        if let current = wishClearingSession, !current.expired {
            return
        }
        wishClearingSession = WishClearingSession(
            startedAt: Date(),
            anchorTask: anchorTask,
            timeBudgetMinutes: 10,
            processedCount: 0
        )
    }

    public func endWishClearingSession() {
        wishClearingSession = nil
    }

    public func incrementWishClearingProcessed() {
        guard var session = wishClearingSession else { return }
        session.processedCount += 1
        wishClearingSession = session
    }

    /// 从 Inbox 的 "聊聊这条" 按钮触发：切到 chat tab，启动 session，发送 `/聊聊 <内容摘要>`。
    /// 用户看到的是 30 字内容摘要，id 通过 message.metadata 传递，AI 直接拿到全文上下文。
    public func dispatchWishChat(noteId: UUID) {
        guard !isLoading else {
            showBanner("正在回复中，稍候再聊", kind: .info)
            return
        }
        guard let note = notes.first(where: { $0.id == noteId }) else {
            showBanner("这条随手记已不存在", kind: .warning)
            return
        }
        selectedTab = .chat
        if wishClearingSession == nil {
            let anchor = activeTask?.title ?? tasks.first(where: { $0.status == .pending })?.title
            startWishClearingSession(anchorTask: anchor)
        }

        // 对话流和发给 AI 的内容都用 note 全文，保证 AI 能精确聊这一条，用户也能在对话里看到自己记的原话
        let userMessage = "/聊聊 \(note.content)"

        appendMessage(Message(
            role: .user,
            content: userMessage,
            metadata: ["wish_note_id": noteId.uuidString]
        ))
        let placeholder = Message(role: .assistant, content: "")
        appendMessage(placeholder)
        let msgID = placeholder.id

        // C1：guard 后立即同步设 true，避免 Task 调度之间的并发窗口
        isLoading = true

        Task { @MainActor in
            defer {
                persistMessage(id: msgID)
                isLoading = false
            }
            do {
                let response = try await ChatEngine.shared.sendMessage(
                    userMessage,
                    systemPrompt: systemPrompt,
                    onAssistantDelta: { delta in
                        Task { @MainActor in
                            if let idx = AppState.shared.messages.firstIndex(where: { $0.id == msgID }) {
                                AppState.shared.messages[idx].content += delta
                            }
                        }
                    }
                )
                // M7：取更长的版本（见 ChatView 对应注释）
                if let idx = messages.firstIndex(where: { $0.id == msgID }),
                   messages[idx].content.count < response.count {
                    messages[idx].content = response
                }
            } catch {
                if let idx = messages.firstIndex(where: { $0.id == msgID }) {
                    let partial = messages[idx].content
                    if !partial.isEmpty {
                        messages[idx].content = partial + "\n\n— [连接中断: \(error.localizedDescription)]"
                    } else {
                        messages[idx].content = "抱歉，出了点问题：\(error.localizedDescription)"
                    }
                }
                showBanner("消息发送失败：\(error.localizedDescription)", kind: .error, duration: 5.0)
                endWishClearingSession()
            }
        }
    }

    /// 一键整理：把待处理随手记列表发给 AI，请它分类/建议优先级，结果展示在对话流。
    public func organizePendingNotes() async {
        guard !isOrganizing else { return }
        // 和普通对话共用 isLoading，防止"正常 sendMessage + 一键整理"并发污染 messages 上下文
        guard !isLoading else {
            showBanner("正在回复中，稍候再整理", kind: .info)
            return
        }
        isOrganizing = true
        isLoading = true

        let pending = notes.filter { $0.status == .pending }
        guard !pending.isEmpty else {
            showBanner("没有待处理的随手记", kind: .info)
            isOrganizing = false
            isLoading = false
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

        defer {
            persistMessage(id: msgID)
            isOrganizing = false
            isLoading = false
        }

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
            if let idx = messages.firstIndex(where: { $0.id == msgID }),
               messages[idx].content.count < response.count {
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
        // 防止同一条 note 的并发重复推送（用户连点按钮导致 Notion 创建多条重复页面）
        guard !pushingNoteIds.contains(note.id) else {
            showBanner("正在推送中，请稍候", kind: .info)
            return false
        }
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
        pushingNoteIds.insert(note.id)
        defer { pushingNoteIds.remove(note.id) }
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
        let verb = minutes >= 0 ? "延长" : "缩短"
        showBanner("已\(verb) \(abs(minutes)) 分钟", kind: .info)
        MemoryService.shared.appendToToday(.tasks, entry: "延长 \(minutes) 分钟：\(active.title)")
    }

    @discardableResult
    public func addPinnedTask(title: String) -> TaskItem {
        let task = TaskItem(title: title, status: .pending)
        tasks.append(task)
        saveTasks()
        return task
    }

    /// 取消当前活跃计时（AI tool cancel_timer 调用）。任务状态置 .cancelled，activeTask 释放。
    public func cancelCurrentTimer(reason: String? = nil) {
        guard let active = activeTask,
              let idx = tasks.firstIndex(where: { $0.id == active.id }) else { return }
        tasks[idx].status = .cancelled
        activeTask = nil
        menuBarStatus = .idle
        resetTimerFlags()
        saveTasks()
        let detail = reason.map { "（\($0)）" } ?? ""
        showBanner("已取消：\(active.title)\(detail)", kind: .info)
        MemoryService.shared.appendToToday(.tasks, entry: "取消计时：\(active.title)\(detail)")
    }

    /// 按标题匹配把一条 pinned 标记为 done（AI tool mark_task_done）。title 支持前缀/包含匹配。
    /// 返回匹配到的 task（若有）。
    @discardableResult
    public func markPinnedTaskDoneByTitle(_ title: String) -> TaskItem? {
        let query = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return nil }
        guard let idx = tasks.firstIndex(where: { task in
            task.status == .pending && (task.title == query || task.title.contains(query))
        }) else { return nil }
        tasks[idx].status = .done
        saveTasks()
        showBanner("已完成：\(tasks[idx].title)", kind: .success)
        MemoryService.shared.appendToToday(.tasks, entry: "完成：\(tasks[idx].title)")
        return tasks[idx]
    }

    /// 按标题匹配删除一条 pinned（AI tool delete_pinned_task）。
    @discardableResult
    public func deletePinnedTaskByTitle(_ title: String) -> TaskItem? {
        let query = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return nil }
        guard let idx = tasks.firstIndex(where: { task in
            task.status != .done && (task.title == query || task.title.contains(query))
        }) else { return nil }
        let removed = tasks.remove(at: idx)
        if activeTask?.id == removed.id {
            activeTask = nil
            menuBarStatus = .idle
            resetTimerFlags()
        }
        saveTasks()
        showBanner("已删除：\(removed.title)", kind: .info)
        MemoryService.shared.appendToToday(.tasks, entry: "删除任务：\(removed.title)")
        return removed
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

    /// 手动微调 UI 字号（Cmd+= / Cmd+- 调用）。delta 正数放大、负数缩小。
    public func adjustFontScale(_ delta: Double) {
        fontScale = max(0.7, min(1.5, fontScale + delta))
        saveFontScale()
    }

    /// 重置 UI 字号到 1.0（Cmd+0 调用）。
    public func resetFontScale() {
        fontScale = 1.0
        saveFontScale()
    }

    private func saveFontScale() {
        let url = Self.dataDirectory.appendingPathComponent("font-scale.txt")
        try? String(fontScale).write(to: url, atomically: true, encoding: .utf8)
    }

    /// 持久化"今日已触发定时任务"集合，避免 kill/重启后同一天重复触发闹钟
    public func saveTriggerState() {
        let url = Self.dataDirectory.appendingPathComponent(Self.triggerStatePath)
        Self.ensureParentDirectory(url)
        let snapshot = TriggerStateSnapshot(
            triggeredTasksToday: Array(triggeredTasksToday),
            lastTriggerDate: lastTriggerDate
        )
        try? JSONEncoder().encode(snapshot).write(to: url, options: .atomic)
    }

    private static let pinnedTasksPath = "tasks/pinned.json"
    private static let scheduledTasksPath = "timers/scheduled.json"
    private static let triggerStatePath = "timers/trigger-state.json"

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
            // 剔除历史 jsonl 里的：
            // (1) .system 消息（老数据污染）
            // (2) 空 content 的 assistant（旧 placeholder bug 遗留：空气泡被写入 jsonl，回填时会造成无意义空行）
            let filteredMessages = dayMessages.filter { msg in
                guard msg.role != .system else { return false }
                if msg.role == .assistant && msg.content.isEmpty { return false }
                return true
            }

            if !filteredMessages.isEmpty {
                let dateString = file.deletingPathExtension().lastPathComponent
                conversationHistory.append(ConversationDay(date: dateString, messages: filteredMessages))
            }
        }

        // 启动时把"今天"的对话回填到当前消息流，支持 kill/重启后接着聊
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        let today = df.string(from: Date())
        if messages.isEmpty, let todayDay = conversationHistory.first(where: { $0.date == today }) {
            messages = todayDay.messages
        }
        // 今日对话的真实来源是 messages（实时追加到 jsonl）；
        // conversationHistory 只留昨天和更早的快照，避免"今天"副本 stale 误导其他消费方
        conversationHistory.removeAll { $0.date == today }
    }

    public func appendMessage(_ message: Message) {
        messages.append(message)
        // user 消息视为活动信号，刷新 lastActivityAt（assistant 消息不算用户活动）
        if message.role == .user {
            markActivity()
        }
        // 空 assistant placeholder 暂不入 jsonl（流式期间 content 还没到），
        // 等内容填充完毕由调用方显式 persistMessage(id:) 写入。避免空气泡污染历史。
        if message.role == .assistant && message.content.isEmpty {
            return
        }
        saveTodayMessages()
    }

    /// 流式响应完成后，把当前 messages 中指定 id 的消息追加到今天的 jsonl。
    /// 用于 AI 回复（placeholder append 时被跳过，这里做最终持久化）。
    public func persistMessage(id: UUID) {
        guard let msg = messages.first(where: { $0.id == id }) else { return }
        guard msg.role != .system, !msg.content.isEmpty else { return }
        appendMessageLine(msg)
    }

    private func saveTodayMessages() {
        guard !Self.isRunningTests else { return }
        guard let last = messages.last, last.role != .system else { return }
        appendMessageLine(last)
    }

    private func appendMessageLine(_ message: Message) {
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

        if let data = try? JSONEncoder().encode(message),
           let line = String(data: data, encoding: .utf8),
           let newline = "\n".data(using: .utf8),
           let lineData = line.data(using: .utf8) {
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

    ## 核心职责
    1. 帮助用户管理工作节奏：计时、提醒、任务跟踪
    2. 通过 Notion 查看和管理用户的日程与待办
    3. 在用户偏离计划时主动提醒
    4. 回复简洁直接，不要啰嗦

    ## 回复规则
    - 使用中文；简短有力，每次 3 句以内（/聊聊 语境例外）
    - 不要在回复文本中附加结构化指令标记（如 [ACTION:...]）
    - 执行操作用 tool / function calling，不要在文本中拼指令字符串：
      - 启动计时 → start_timer；延长计时 → extend_timer
      - 查询 / 修改 Notion → notion_* 工具（写操作会要求用户确认）

    ## 上下文信号使用规则
    - **今日焦点任务（pinned tasks）**：判断"用户本来该做什么"的**唯一**依据。snapshot 里明细只列"还需行动"（▶ 进行中 / ○ 待办）；已完成任务单独汇总在"今日已完成 N 个"里，**不要基于已完成任务提醒用户去做**。若显示"今日任务全部完成"，则用户今天已达成目标，不要再催促。
    - **项目库摘要**（若出现在上下文）：只用于识别"我想 X 是否和某个项目有关联"；**绝不**作为"回到哪"的依据，**绝不**指导项目内部 how-to
    - **Notion 任务库**：不主动推；只有用户明确问"我之前记的 X"时才用 tool 查询
    - **历史记忆时效**：snapshot 只包含近 3 天 daily note 和最近一期周报。用户问"3 天前及更早"的任何事实（例："上周 / 上个月我做了 / 聊过什么"），**必须先调用 `memory_search` tool** 再回答，不许凭记忆断言"没记录"。

    ## /聊聊 触发协议

    当用户消息以 `/聊聊` 开头（可能带参数如 `/聊聊 <note_id>` 或 `/聊聊 <关键词>`），进入 **Wish Clearing 模式**：

    ### 1. 进入前埋锚（第一条回复）
    不要直接展开内容。先问锚点。如果上下文"当前状态"里已有"活跃计时"或"待办任务"，直接列出让用户确认：
    > "看到你今日焦点是 [A]，活跃计时剩 [B]。先确认你愿意暂停 10 分钟聊这个？"
    如果没有活跃锚点，简短问一句：
    > "进来前你本来在做什么？"

    ### 2. 情境分辨（根据用户回应判断三类）
    - **(A) 新想法冒出**（语气："刚想到"、"突然有个点子"、"临时冒出来"）
      → 不展开。一句话记录，引导回锚点：
      > "记下了。回到 [锚点]。"
    - **(B) 卡住逃避**（语气："做不下去"、"头疼"、"先不想搞"、"先聊这个"）
      → 拒绝展开，指出真问题：
      > "听起来是 [锚点] 卡住了，不要用我想的讨论逃开。先聊卡在哪。"
    - **(C) 主动清扫**（语气："我有空了"、"帮我过一下"、"清一下积压"）
      → 进入限时展开，声明边界：
      > "好。聊 10 分钟，到点叫停。从最早那条开始。"

    ### 3. 展开过程约束（仅 C 路径）
    - 每条 wish 只做四个判断之一：**现在做 / 推迟 / 彻底删 / 升级为任务**
    - 不替用户做决定，用提问逼清楚：
      > "这件事现在做，会替换掉 pinned 里的哪一条？不替换就不该现在做。"
    - 只做时机和优先级判断，不指导项目内部 how-to
    - **每条 wish 做出决策后必须立即调用 `log_wish_decision` tool**（decision 参数用中文：**立即做 / 升级为任务 / 先留着 / 删除**），否则这条 wish 白聊，明天十页打开 app 看不到任何痕迹

    ### 4. 退出姿态
    任一条件触发，主动结束：
    - 上下文里 Wish Clearing 的"剩余"接近 0 或显示"时间到"
    - 用户说"先到这"、"回去了"、"回工作"
    - 连续 3 轮没有决策产出（空转）

    结束时**依次**做两件事：
    1. 先给用户做状态回放（简短即可，不要编造用户进入前在做的具体步骤）：
       > "聊了 X 分钟。回到 [锚点]，接着你刚才的位置继续。"
       如果锚点字段为空，就说 "回去做你本来的事。"
       **禁止**编造"你刚才停在第二步"、"停在写周报的开头" 这类细节 —— 你没有这些信息。
    2. **紧接着调用 `end_wish_clearing` tool** 结束 session。这一步**必做**，否则下一次普通对话会被 wish 上下文污染。

    ## 行为禁区
    - 默认对话（非 /聊聊 语境）**不要主动翻 wish 池**，不要推荐"要不要聊聊积压"
    - **不要 AI 自行发起 wish clearing** —— 必须等用户用 `/聊聊` 触发
    - 项目库 / Notion 任务库的数据**不参与**"你该回到哪"的决策
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
            // 用极简 system prompt，避免 /聊聊 协议这类无关内容干扰"今日统计总结"
            let summary = try await ChatEngine.shared.sendMessage(
                summaryPrompt,
                systemPrompt: "你是简洁的日报助手，把用户今日完成数据压缩成一段不超过 80 字的中文总结，禁止加前后缀或 <think> 标签。",
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

struct TriggerStateSnapshot: Codable {
    var triggeredTasksToday: [String]
    var lastTriggerDate: String
}

public struct WishClearingSession: Sendable {
    public let startedAt: Date
    public let anchorTask: String?
    public let timeBudgetMinutes: Int
    public var processedCount: Int

    public var elapsedSeconds: Int {
        Int(Date().timeIntervalSince(startedAt))
    }

    public var remainingSeconds: Int {
        max(0, timeBudgetMinutes * 60 - elapsedSeconds)
    }

    public var expired: Bool {
        elapsedSeconds >= timeBudgetMinutes * 60
    }
}

public enum MenuBarStatus {
    case idle
    case focus
    case warning
    case overtime
    case rest
}
