import Foundation

public struct ScheduledTask: Identifiable, Codable {
    public let id: UUID
    public var name: String
    public var time: String // HH:mm 格式
    public var schedule: TaskSchedule
    public var prompt: String
    public var enabled: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        time: String,
        schedule: TaskSchedule,
        prompt: String,
        enabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.time = time
        self.schedule = schedule
        self.prompt = prompt
        self.enabled = enabled
    }

    public var nextTrigger: Date? {
        let calendar = Calendar.current
        let now = Date()
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        let timeComponents = time.split(separator: ":").compactMap { Int($0) }
        guard timeComponents.count == 2 else { return nil }
        components.hour = timeComponents[0]
        components.minute = timeComponents[1]

        guard var date = calendar.date(from: components) else { return nil }

        // 如果今天已过，则计算下一次的触发日期
        if date <= now {
            switch schedule {
            case .daily:
                date = calendar.date(byAdding: .day, value: 1, to: date) ?? date
            case .weekly(let weekday):
                let currentWeekday = calendar.component(.weekday, from: now)
                let targetWeekday = weekday.calendarWeekday
                var daysToAdd = targetWeekday - currentWeekday
                if daysToAdd <= 0 { daysToAdd += 7 }
                date = calendar.date(byAdding: .day, value: daysToAdd, to: date) ?? date
            case .cron:
                // 简化处理：暂不支持 cron 解析
                return nil
            }
        }
        return date
    }
}

public enum TaskSchedule: Codable, Equatable {
    case daily
    case weekly(Weekday)
    case cron(String)

    public enum Weekday: Int, Codable, CaseIterable {
        case sunday = 1
        case monday = 2
        case tuesday = 3
        case wednesday = 4
        case thursday = 5
        case friday = 6
        case saturday = 7

        var calendarWeekday: Int { rawValue }

        var chineseName: String {
            switch self {
            case .sunday: return "周日"
            case .monday: return "周一"
            case .tuesday: return "周二"
            case .wednesday: return "周三"
            case .thursday: return "周四"
            case .friday: return "周五"
            case .saturday: return "周六"
            }
        }
    }
}