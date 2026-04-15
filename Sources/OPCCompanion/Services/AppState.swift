import Foundation
import SwiftUI
import Combine

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

    private var cancellables = Set<AnyCancellable>()

    public init() {
        loadData()
    }

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

        // 加载当日任务
        if let tasksData = loadFile(named: "pinned.json"),
           let tasks = try? JSONDecoder().decode([TaskItem].self, from: tasksData) {
            self.tasks = tasks
        }

        // 加载定时任务
        if let scheduledData = loadFile(named: "scheduled.json"),
           let scheduled = try? JSONDecoder().decode([ScheduledTask].self, from: scheduledData) {
            self.scheduledTasks = scheduled
        }

        // 加载历史对话
        loadConversationHistory()
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
        let url = Self.dataDirectory.appendingPathComponent("pinned.json")
        try? JSONEncoder().encode(tasks).write(to: url)
    }

    public func saveScheduledTasks() {
        let url = Self.dataDirectory.appendingPathComponent("scheduled.json")
        try? JSONEncoder().encode(scheduledTasks).write(to: url)
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
                guard !line.isEmpty else { return nil }
                return try? JSONDecoder().decode(Message.self, from: line.data(using: .utf8)!)
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
           let line = String(data: data, encoding: .utf8) {
            let fileManager = FileManager.default
            if fileManager.fileExists(atPath: url.path) {
                let handle = try? FileHandle(forWritingTo: url)
                handle?.seekToEndOfFile()
                handle?.write("\n".data(using: .utf8)!)
                handle?.write(line.data(using: .utf8)!)
                handle?.closeFile()
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
            let summary = try await ChatEngine.shared.sendMessage(summaryPrompt, systemPrompt: AppState.defaultSystemPrompt)
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
    case history
    case settings

    var title: String {
        switch self {
        case .chat: return "对话"
        case .history: return "历史"
        case .settings: return "设置"
        }
    }

    var icon: String {
        switch self {
        case .chat: return "bubble.left.and.text.bubble.right"
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