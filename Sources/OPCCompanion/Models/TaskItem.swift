import Foundation

public struct TaskItem: Identifiable, Codable {
    public let id: UUID
    public var title: String
    public var status: TaskStatus
    public var timerMinutes: Int?        // 预估时长
    public var timerStart: Date?
    public var timerEnd: Date?
    public var extensions: Int
    public var createdAt: Date
    public var actualMinutes: Int?       // 完成时记录的实际耗时
    public var pomodoroCycle: Bool       // Pomodoro 循环任务
    public var focusMode: Bool           // 启动时切换 macOS Focus
    public var isPomodoroBreak: Bool     // 由 advancePomodoro 内部创建的休息段（不靠 title 判断）

    public init(
        id: UUID = UUID(),
        title: String,
        status: TaskStatus = .pending,
        timerMinutes: Int? = nil,
        timerStart: Date? = nil,
        timerEnd: Date? = nil,
        extensions: Int = 0,
        createdAt: Date = Date(),
        actualMinutes: Int? = nil,
        pomodoroCycle: Bool = false,
        focusMode: Bool = false,
        isPomodoroBreak: Bool = false
    ) {
        self.id = id
        self.title = title
        self.status = status
        self.timerMinutes = timerMinutes
        self.timerStart = timerStart
        self.timerEnd = timerEnd
        self.extensions = extensions
        self.createdAt = createdAt
        self.actualMinutes = actualMinutes
        self.pomodoroCycle = pomodoroCycle
        self.focusMode = focusMode
        self.isPomodoroBreak = isPomodoroBreak
    }

    // 自定义解码以兼容老 JSON（缺失新字段）
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.title = try c.decode(String.self, forKey: .title)
        self.status = try c.decode(TaskStatus.self, forKey: .status)
        self.timerMinutes = try c.decodeIfPresent(Int.self, forKey: .timerMinutes)
        self.timerStart = try c.decodeIfPresent(Date.self, forKey: .timerStart)
        self.timerEnd = try c.decodeIfPresent(Date.self, forKey: .timerEnd)
        self.extensions = try c.decodeIfPresent(Int.self, forKey: .extensions) ?? 0
        self.createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        self.actualMinutes = try c.decodeIfPresent(Int.self, forKey: .actualMinutes)
        self.pomodoroCycle = try c.decodeIfPresent(Bool.self, forKey: .pomodoroCycle) ?? false
        self.focusMode = try c.decodeIfPresent(Bool.self, forKey: .focusMode) ?? false
        self.isPomodoroBreak = try c.decodeIfPresent(Bool.self, forKey: .isPomodoroBreak) ?? false
    }

    public var remainingSeconds: Int? {
        guard let timerEnd = timerEnd, status == .inProgress else { return nil }
        return max(0, Int(timerEnd.timeIntervalSinceNow))
    }
}

public enum TaskStatus: String, Codable {
    case pending
    case inProgress = "in_progress"
    case done
    case cancelled
}
