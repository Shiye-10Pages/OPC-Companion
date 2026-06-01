import XCTest
@testable import OPCCompanion

final class MemoryServiceTests: XCTestCase {
    private var tempRoot: URL!

    override func setUp() {
        super.setUp()
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("opc-memory-tests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempRoot)
        tempRoot = nil
        super.tearDown()
    }

    // MARK: - Bootstrap

    func testBootstrapCreatesTemplatesWhenAbsent() {
        let service = MemoryService(rootURL: tempRoot)
        _ = service

        let memoryURL = tempRoot.appendingPathComponent("MEMORY.md")
        let userURL = tempRoot.appendingPathComponent("USER.md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: memoryURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: userURL.path))

        let memory = (try? String(contentsOf: memoryURL, encoding: .utf8)) ?? ""
        XCTAssertTrue(memory.contains("## 行为规则"))
        XCTAssertTrue(memory.contains("## 工作上下文"))
    }

    func testBootstrapPreservesExistingFiles() throws {
        let memoryURL = tempRoot.appendingPathComponent("MEMORY.md")
        try "自定义内容".write(to: memoryURL, atomically: true, encoding: .utf8)

        _ = MemoryService(rootURL: tempRoot)

        let memory = try String(contentsOf: memoryURL, encoding: .utf8)
        XCTAssertEqual(memory, "自定义内容")
    }

    // MARK: - Daily append

    func testAppendToTodayCreatesFileAndSection() {
        let service = MemoryService(rootURL: tempRoot)
        let now = makeDate(hour: 9, minute: 30)

        XCTAssertTrue(service.appendToToday(.tasks, entry: "写代码", now: now))

        let url = tempRoot.appendingPathComponent("\(ymd(now)).md")
        let content = (try? String(contentsOf: url, encoding: .utf8)) ?? ""

        XCTAssertTrue(content.hasPrefix("# \(ymd(now)) "), "应以日期标题开头")
        XCTAssertTrue(content.contains("## 任务"))
        XCTAssertTrue(content.contains("- 09:30 写代码"))
    }

    func testAppendMultipleEntriesToSameSection() {
        let service = MemoryService(rootURL: tempRoot)
        let now = makeDate(hour: 10, minute: 0)

        service.appendToToday(.tasks, entry: "任务 A", now: now)
        service.appendToToday(.tasks, entry: "任务 B", now: makeDate(hour: 10, minute: 30))

        let url = tempRoot.appendingPathComponent("\(ymd(now)).md")
        let content = (try? String(contentsOf: url, encoding: .utf8)) ?? ""

        let lines = content.components(separatedBy: "\n")
        let bullets = lines.filter { $0.hasPrefix("- ") }
        XCTAssertEqual(bullets.count, 2)
        XCTAssertTrue(bullets[0].contains("任务 A"))
        XCTAssertTrue(bullets[1].contains("任务 B"))
    }

    func testAppendDifferentSectionsPreservesOrder() {
        let service = MemoryService(rootURL: tempRoot)
        let now = makeDate(hour: 9, minute: 0)

        // 故意打乱顺序追加
        service.appendToToday(.notes, entry: "随手记 1", now: now)
        service.appendToToday(.tasks, entry: "任务 1", now: now)
        service.appendToToday(.timers, entry: "定时 1", now: now)

        let url = tempRoot.appendingPathComponent("\(ymd(now)).md")
        let content = (try? String(contentsOf: url, encoding: .utf8)) ?? ""

        let tasksIdx = content.range(of: "## 任务")!.lowerBound
        let timersIdx = content.range(of: "## 定时触发")!.lowerBound
        let notesIdx = content.range(of: "## 随手记")!.lowerBound

        XCTAssertLessThan(tasksIdx, timersIdx, "## 任务 应在 ## 定时触发 之前")
        XCTAssertLessThan(timersIdx, notesIdx, "## 定时触发 应在 ## 随手记 之前")
    }

    // MARK: - Snapshot

    func testComposeSnapshotIncludesMemoryAndUser() {
        let service = MemoryService(rootURL: tempRoot)
        let snapshot = service.composeSnapshot()

        XCTAssertTrue(snapshot.contains("## 长期记忆"))
        XCTAssertTrue(snapshot.contains("## 用户画像"))
        XCTAssertTrue(snapshot.contains("## 行为规则"))
    }

    func testComposeSnapshotIncludesYesterdayIfPresent() {
        let service = MemoryService(rootURL: tempRoot)
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        service.appendToToday(.conversation, entry: "昨天聊了记忆架构", now: yesterday)

        let snapshot = service.composeSnapshot()
        XCTAssertTrue(snapshot.contains("## 近 \(MemoryService.daysToInject) 天要点"))
        XCTAssertTrue(snapshot.contains("### 昨日"))
        XCTAssertTrue(snapshot.contains("昨天聊了记忆架构"))
    }

    func testAppendInvalidatesCachedSnapshot() {
        let service = MemoryService(rootURL: tempRoot)
        let now = makeDate(hour: 11, minute: 0)
        let initial = service.composeSnapshot(now: now)
        XCTAssertFalse(initial.contains("缓存刷新测试"))

        XCTAssertTrue(service.appendToToday(.notes, entry: "缓存刷新测试", now: now))

        let updated = service.composeSnapshot(now: now)
        XCTAssertTrue(updated.contains("缓存刷新测试"))
    }

    func testAppendReturnsFalseWhenRootPathIsAFile() throws {
        let blocker = tempRoot.appendingPathComponent("blocker")
        try Data("blocker".utf8).write(to: blocker)
        let service = MemoryService(rootURL: blocker)

        XCTAssertFalse(service.appendToToday(.notes, entry: "不能写入"))
    }

    // MARK: - Helpers

    private func makeDate(hour: Int, minute: Int) -> Date {
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        comps.hour = hour
        comps.minute = minute
        return Calendar.current.date(from: comps)!
    }

    private func ymd(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}
