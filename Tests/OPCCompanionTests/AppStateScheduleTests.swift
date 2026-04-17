import XCTest
@testable import OPCCompanion

@MainActor
final class AppStateScheduleTests: XCTestCase {
    private func makeCleanState() -> AppState {
        let state = AppState()
        state.messages.removeAll()
        state.scheduledTasks = []
        state.triggeredTasksToday.removeAll()
        state.lastTriggerDate = ""
        state.hasUnreadReminders = false
        return state
    }

    func testDailyTaskTriggersOnceAndDeduplicates() {
        let state = makeCleanState()
        state.scheduledTasks = [
            ScheduledTask(name: "复盘", time: "00:00", schedule: .daily, prompt: "今日复盘", enabled: true)
        ]

        state.checkScheduledTasks(now: Date())
        XCTAssertTrue(state.hasUnreadReminders)
        XCTAssertEqual(state.triggeredTasksToday.count, 1)
        // 新设计：定时触发不进消息流，改为 banner + daily note
        XCTAssertNotNil(state.banner, "首次触发应弹出 banner")
        XCTAssertTrue(state.banner?.text.contains("复盘") ?? false)

        let firstBannerID = state.banner?.id
        state.checkScheduledTasks(now: Date())
        XCTAssertEqual(state.banner?.id, firstBannerID, "同一天内不应重复触发新 banner")
        XCTAssertEqual(state.triggeredTasksToday.count, 1)
    }

    func testDisabledTaskIsSkipped() {
        let state = makeCleanState()
        state.scheduledTasks = [
            ScheduledTask(name: "停用", time: "00:00", schedule: .daily, prompt: "x", enabled: false)
        ]
        state.checkScheduledTasks(now: Date())
        XCTAssertTrue(state.triggeredTasksToday.isEmpty)
        XCTAssertFalse(state.hasUnreadReminders)
    }

    func testWeeklyMatchesCurrentWeekday() {
        let state = makeCleanState()
        let weekdayNum = Calendar.current.component(.weekday, from: Date())
        guard let weekday = TaskSchedule.Weekday(rawValue: weekdayNum) else {
            XCTFail("weekday decode failed"); return
        }
        state.scheduledTasks = [
            ScheduledTask(name: "周任务", time: "00:00", schedule: .weekly(weekday), prompt: "x", enabled: true)
        ]
        state.checkScheduledTasks(now: Date())
        XCTAssertEqual(state.triggeredTasksToday.count, 1)
    }

    func testDayRolloverClearsTriggeredSet() {
        let state = makeCleanState()
        state.triggeredTasksToday.insert("stale-id")
        state.lastTriggerDate = "1999-01-01"
        state.scheduledTasks = []

        state.checkScheduledTasks(now: Date())

        XCTAssertFalse(state.triggeredTasksToday.contains("stale-id"), "跨天后旧触发记录应清除")
        XCTAssertNotEqual(state.lastTriggerDate, "1999-01-01")
    }

    func testFutureTimeNotYetTriggered() {
        let state = makeCleanState()
        let calendar = Calendar.current
        var comp = calendar.dateComponents([.year, .month, .day], from: Date())
        comp.hour = 3
        comp.minute = 0
        let earlyMorning = calendar.date(from: comp)!

        state.scheduledTasks = [
            ScheduledTask(name: "晚间", time: "23:30", schedule: .daily, prompt: "x", enabled: true)
        ]
        state.checkScheduledTasks(now: earlyMorning)
        XCTAssertTrue(state.triggeredTasksToday.isEmpty, "未到触发时间时不应触发")
    }
}
