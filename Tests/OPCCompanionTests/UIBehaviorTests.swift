import XCTest
@testable import OPCCompanion

@MainActor
final class UIBehaviorTests: XCTestCase {

    // MARK: - tick() warning/overtime 阈值与防重触发

    func testTickFiresWarningAtTwentyPercentOnce() {
        let state = AppState()
        state.messages.removeAll()
        state.tasks.removeAll()
        state.menuBarStatus = .idle
        state.timerWarningFired = false
        state.timerOvertimeFired = false

        // 模拟一个剩余 < 20% 的任务（25 分钟任务，剩余 1 分钟）
        let task = TaskItem(
            title: "测试",
            status: .inProgress,
            timerMinutes: 25,
            timerStart: Date().addingTimeInterval(-24 * 60),
            timerEnd: Date().addingTimeInterval(60),
            extensions: 0
        )
        state.tasks.append(task)
        state.activeTask = task

        invokeTick(on: state)
        XCTAssertEqual(state.menuBarStatus, .warning)
        XCTAssertTrue(state.timerWarningFired)
        let warningMsgs = state.messages.filter { $0.content.contains("剩余时间不足") }
        XCTAssertEqual(warningMsgs.count, 1, "首次跨阈值应只触发一次")

        // 再次 tick，不应再插一条
        invokeTick(on: state)
        let warningMsgsAfter = state.messages.filter { $0.content.contains("剩余时间不足") }
        XCTAssertEqual(warningMsgsAfter.count, 1, "防重触发标志应阻止重复")
    }

    func testTickFiresOvertimeOnceWhenExpired() {
        let state = AppState()
        state.messages.removeAll()
        state.tasks.removeAll()
        state.timerWarningFired = false
        state.timerOvertimeFired = false

        let task = TaskItem(
            title: "已过期",
            status: .inProgress,
            timerMinutes: 25,
            timerStart: Date().addingTimeInterval(-30 * 60),
            timerEnd: Date().addingTimeInterval(-60)
        )
        state.tasks.append(task)
        state.activeTask = task

        invokeTick(on: state)
        XCTAssertEqual(state.menuBarStatus, .overtime)
        XCTAssertTrue(state.timerOvertimeFired)

        let countBefore = state.messages.count
        invokeTick(on: state)
        XCTAssertEqual(state.messages.count, countBefore, "超时提醒不应重复插入")
    }

    func testTickReturnsToIdleWhenNoActiveTask() {
        let state = AppState()
        state.activeTask = nil
        state.menuBarStatus = .focus

        invokeTick(on: state)
        XCTAssertEqual(state.menuBarStatus, .idle)
    }

    // 通过反射调 private tick()
    private func invokeTick(on state: AppState) {
        let mirror = Mirror(reflecting: state)
        _ = mirror  // 抑制 unused warning
        // tick() 是 private 但每秒触发；这里手动模拟它的副作用：直接调用 resetTimerFlags 不行，需要走 tick 逻辑
        // 折中方案：等 1 秒（不实用）。另一思路：开放一个 tickForTesting()
        state.tickForTesting()
    }

    // MARK: - 时间回拨

    func testCheckScheduledTasksClearsTriggeredOnTimeRollback() {
        let state = AppState()
        state.scheduledTasks = []
        state.triggeredTasksToday.removeAll()
        state.lastTriggerDate = ""

        // 第一次：现在
        let now = Date()
        state.checkScheduledTasks(now: now)
        state.triggeredTasksToday.insert("fake-id")

        // 第二次：把"现在"调到 1 小时前（系统时间回拨）
        let past = now.addingTimeInterval(-3600)
        state.checkScheduledTasks(now: past)
        XCTAssertFalse(state.triggeredTasksToday.contains("fake-id"), "时间回拨后应清空已触发集合")
    }

    // MARK: - 消息转随手记

    func testConvertMessageToNoteHidesAndCaptures() {
        let state = AppState()
        state.messages.removeAll()
        state.notes.removeAll()

        let msg = Message(role: .user, content: "调研 langchain")
        state.appendMessage(msg)

        state.convertMessageToNote(msg)

        let stored = state.messages.first { $0.id == msg.id }
        XCTAssertEqual(stored?.hidden, true)
        XCTAssertEqual(state.notes.count, 1)
        XCTAssertEqual(state.notes.first?.content, "调研 langchain")
        XCTAssertEqual(state.notes.first?.source, .convertFromMessage)
    }
}
