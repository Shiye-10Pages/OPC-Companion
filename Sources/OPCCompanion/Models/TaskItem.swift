import Foundation

public struct TaskItem: Identifiable, Codable {
    public let id: UUID
    public var title: String
    public var status: TaskStatus
    public var timerMinutes: Int?
    public var timerStart: Date?
    public var timerEnd: Date?
    public var extensions: Int
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        title: String,
        status: TaskStatus = .pending,
        timerMinutes: Int? = nil,
        timerStart: Date? = nil,
        timerEnd: Date? = nil,
        extensions: Int = 0,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.status = status
        self.timerMinutes = timerMinutes
        self.timerStart = timerStart
        self.timerEnd = timerEnd
        self.extensions = extensions
        self.createdAt = createdAt
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