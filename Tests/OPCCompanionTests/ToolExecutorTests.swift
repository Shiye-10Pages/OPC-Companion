import XCTest
@testable import OPCCompanion

@MainActor
final class ToolExecutorTests: XCTestCase {
    private func makeCleanState() -> AppState {
        let state = AppState.shared
        state.messages.removeAll()
        state.tasks.removeAll()
        state.activeTask = nil
        state.menuBarStatus = .idle
        state.resetTimerFlags()
        return state
    }

    private func call(_ name: String, arguments: String = "{}") -> WireToolCall {
        WireToolCall(id: "call_\(UUID().uuidString)", function: WireFunctionCall(name: name, arguments: arguments))
    }

    func testStartTimerCreatesActiveTask() async {
        let state = makeCleanState()
        let result = await ToolExecutor.execute(call("start_timer", arguments: #"{"task":"写稿","minutes":25}"#))

        XCTAssertTrue(result.contains("\"status\":\"success\""))
        XCTAssertNotNil(state.activeTask)
        XCTAssertEqual(state.activeTask?.title, "写稿")
        XCTAssertEqual(state.activeTask?.status, .inProgress)
        XCTAssertEqual(state.menuBarStatus, .focus)
    }

    func testStartTimerRejectsInvalidArgs() async {
        _ = makeCleanState()
        let result = await ToolExecutor.execute(call("start_timer", arguments: #"{"task":""}"#))
        XCTAssertTrue(result.contains("\"status\":\"error\""))
    }

    func testCompleteTimerClearsActive() async {
        let state = makeCleanState()
        state.startTimer(task: "写稿", minutes: 25)
        XCTAssertNotNil(state.activeTask)

        _ = await ToolExecutor.execute(call("complete_timer", arguments: #"{}"#))
        XCTAssertNil(state.activeTask)
        XCTAssertEqual(state.menuBarStatus, .idle)
    }

    func testExtendTimerExtendsCurrent() async {
        let state = makeCleanState()
        state.startTimer(task: "写稿", minutes: 25)
        let originalEnd = state.activeTask?.timerEnd

        _ = await ToolExecutor.execute(call("extend_timer", arguments: #"{"minutes":10}"#))
        let newEnd = state.activeTask?.timerEnd

        XCTAssertNotNil(originalEnd)
        XCTAssertNotNil(newEnd)
        XCTAssertGreaterThan(newEnd!.timeIntervalSince(originalEnd!), 599)  // 10 min ≈ 600s
    }

    func testAddPinnedTaskAppendsPending() async {
        let state = makeCleanState()
        let before = state.tasks.count

        _ = await ToolExecutor.execute(call("add_pinned_task", arguments: #"{"title":"复盘"}"#))
        XCTAssertEqual(state.tasks.count, before + 1)
        XCTAssertEqual(state.tasks.last?.title, "复盘")
        XCTAssertEqual(state.tasks.last?.status, .pending)
    }

    func testReviewInboxSwitchesTab() async {
        let state = makeCleanState()
        state.selectedTab = .chat

        _ = await ToolExecutor.execute(call("review_inbox"))
        XCTAssertEqual(state.selectedTab, .inbox)
    }

    func testUnknownToolReturnsError() async {
        _ = makeCleanState()
        let result = await ToolExecutor.execute(call("not_a_real_tool"))
        XCTAssertTrue(result.contains("\"status\":\"error\""))
    }
}
