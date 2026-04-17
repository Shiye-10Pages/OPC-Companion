import Foundation

/// 记忆系统：借鉴 OpenClaw（daily notes）+ Hermes（MEMORY.md / USER.md 双文件 + frozen snapshot）。
///
/// 目录结构（与 OpenClaw `memory/*.md` glob 对齐，可直接 symlink）：
///   ~/.opc-companion/memory/
///     ├── MEMORY.md         长期事实 + 行为规则
///     ├── USER.md           用户画像 + 偏好
///     └── YYYY-MM-DD.md     每日日记（非对话类信息沉淀于此；与 MEMORY.md / USER.md 同层，
///                           方便 OpenClaw builtin `memory/*.md` glob 一次命中，不递归）
public final class MemoryService: @unchecked Sendable {
    public static let shared = MemoryService()

    public enum DailySection: String, CaseIterable {
        case conversation = "## 对话主线"
        case tasks        = "## 任务"
        case timers       = "## 定时触发"
        case notes        = "## 随手记"
        case notion       = "## Notion 操作"
        case learnings    = "## [LEARN] 候选"
    }

    public static let memoryCharBudget = 3000
    public static let userCharBudget = 1500
    public static let dailyLoadCharBudget = 2000

    private let lock = NSLock()
    private let rootURL: URL

    /// 运行测试时跳过 default 根目录的文件 I/O，避免污染用户真实 ~/.opc-companion/memory/。
    /// 测试自己 new 一个 MemoryService(rootURL: tempDir) 则不受影响。
    private static let isRunningTests: Bool = NSClassFromString("XCTestCase") != nil
    private var shouldSkipIO: Bool {
        Self.isRunningTests
            && rootURL.standardizedFileURL.path == Self.defaultRootURL.standardizedFileURL.path
    }

    // MARK: - Snapshot 缓存（lock 内读写）
    private var cachedSnapshotYesterdayKey: String?
    private var cachedSnapshot: String?

    public init(rootURL: URL = MemoryService.defaultRootURL) {
        self.rootURL = rootURL
        if !shouldSkipIO {
            bootstrapIfNeeded()
        }
    }

    public static var defaultRootURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".opc-companion/memory")
    }

    // MARK: - Reads

    public func readMemory() -> String { read(file: "MEMORY.md") }
    public func readUser() -> String { read(file: "USER.md") }
    public func readDaily(date: Date) -> String {
        lock.lock(); defer { lock.unlock() }
        return (try? String(contentsOf: urlForDaily(date), encoding: .utf8)) ?? ""
    }

    /// 会话启动时拼接的 frozen snapshot：MEMORY.md + USER.md + 昨日 daily note。
    /// 按"昨日日期 key"缓存一次，避免每条消息都打 3 次文件 I/O；写接口会失效缓存。
    public func composeSnapshot(now: Date = Date()) -> String {
        lock.lock()
        defer { lock.unlock() }

        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now) ?? now
        let yesterdayKey = yyyyMMdd(yesterday)

        if let cached = cachedSnapshot, cachedSnapshotYesterdayKey == yesterdayKey {
            return cached
        }

        // 在同一个 lock 内完成所有读取，避免 read-after-unlock 脏读
        let memory = truncated(readFileLocked("MEMORY.md"), limit: Self.memoryCharBudget)
        let user = truncated(readFileLocked("USER.md"), limit: Self.userCharBudget)
        let yesterdayNote = truncated(readFileLocked(urlForDaily(yesterday)), limit: Self.dailyLoadCharBudget)

        var sections: [String] = []
        if !memory.isEmpty { sections.append("## 长期记忆\n\(memory)") }
        if !user.isEmpty { sections.append("## 用户画像\n\(user)") }
        if !yesterdayNote.isEmpty { sections.append("## 昨日要点（\(yesterdayKey)）\n\(yesterdayNote)") }
        let result = sections.joined(separator: "\n\n")

        cachedSnapshot = result
        cachedSnapshotYesterdayKey = yesterdayKey
        return result
    }

    /// lock 内直接读文件（不重复加锁）
    private func readFileLocked(_ filename: String) -> String {
        (try? String(contentsOf: rootURL.appendingPathComponent(filename), encoding: .utf8)) ?? ""
    }

    private func readFileLocked(_ url: URL) -> String {
        (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    // MARK: - Writes

    /// 追加一条 bullet 到今日 daily note 对应 section。
    /// Section 不存在时按固定顺序插入；文件不存在时先写文件头。
    public func appendToToday(_ section: DailySection, entry: String, now: Date = Date()) {
        guard !shouldSkipIO else { return }
        let trimmed = entry.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        lock.lock()
        defer { lock.unlock() }

        ensureRootDirectory()
        let url = urlForDaily(now)
        let existing = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let updated = insertEntry(into: existing, section: section, entry: trimmed, now: now)
        try? updated.write(to: url, atomically: true, encoding: .utf8)
    }

    public func writeMemory(_ content: String) {
        guard !shouldSkipIO else { return }
        lock.lock(); defer { lock.unlock() }
        try? content.write(to: rootURL.appendingPathComponent("MEMORY.md"), atomically: true, encoding: .utf8)
        invalidateSnapshotLocked()
    }

    public func writeUser(_ content: String) {
        guard !shouldSkipIO else { return }
        lock.lock(); defer { lock.unlock() }
        try? content.write(to: rootURL.appendingPathComponent("USER.md"), atomically: true, encoding: .utf8)
        invalidateSnapshotLocked()
    }

    // MARK: - Paths

    public var memoryFileURL: URL { rootURL.appendingPathComponent("MEMORY.md") }
    public var userFileURL: URL { rootURL.appendingPathComponent("USER.md") }
    public var rootDirURL: URL { rootURL }

    // MARK: - Internal

    private func read(file filename: String) -> String {
        lock.lock(); defer { lock.unlock() }
        return (try? String(contentsOf: rootURL.appendingPathComponent(filename), encoding: .utf8)) ?? ""
    }

    private func urlForDaily(_ date: Date) -> URL {
        // 与 MEMORY.md / USER.md 同层，对齐 OpenClaw `memory/*.md` glob
        rootURL.appendingPathComponent("\(yyyyMMdd(date)).md")
    }

    private func yyyyMMdd(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    private func weekdayCN(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "EEEE"
        return f.string(from: date)
    }

    private func hm(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    private static let truncationNotice = "\n\n（已截断）"

    private func truncated(_ text: String, limit: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return trimmed }
        // 预留截断提示的字符数，避免返回内容溢出 limit
        let noticeCount = Self.truncationNotice.count
        let budget = max(0, limit - noticeCount)
        let idx = trimmed.index(trimmed.startIndex, offsetBy: budget)
        return String(trimmed[..<idx]) + Self.truncationNotice
    }

    private func invalidateSnapshotLocked() {
        cachedSnapshot = nil
        cachedSnapshotYesterdayKey = nil
    }

    private func insertEntry(into existing: String, section: DailySection, entry: String, now: Date) -> String {
        let header = "# \(yyyyMMdd(now)) \(weekdayCN(now))"
        let sectionLine = section.rawValue
        let bullet = "- \(hm(now)) \(entry)"

        var lines = existing.isEmpty ? [header, ""] : existing.components(separatedBy: "\n")

        if !lines.contains(where: { $0.hasPrefix("# ") && !$0.hasPrefix("## ") }) {
            lines.insert(contentsOf: [header, ""], at: 0)
        }

        if let sectionIdx = lines.firstIndex(of: sectionLine) {
            var insertIdx = sectionIdx + 1
            while insertIdx < lines.count && !lines[insertIdx].hasPrefix("## ") {
                insertIdx += 1
            }
            while insertIdx > sectionIdx + 1 && lines[insertIdx - 1].trimmingCharacters(in: .whitespaces).isEmpty {
                insertIdx -= 1
            }
            lines.insert(bullet, at: insertIdx)
            if insertIdx + 1 >= lines.count || !lines[insertIdx + 1].trimmingCharacters(in: .whitespaces).isEmpty {
                lines.insert("", at: insertIdx + 1)
            }
        } else {
            let ordered = DailySection.allCases.map { $0.rawValue }
            let targetIdx = ordered.firstIndex(of: sectionLine) ?? 0
            var insertAt = lines.count
            for i in (targetIdx + 1)..<ordered.count {
                if let idx = lines.firstIndex(of: ordered[i]) {
                    insertAt = idx
                    break
                }
            }
            if insertAt > 0, !lines[insertAt - 1].trimmingCharacters(in: .whitespaces).isEmpty {
                lines.insert("", at: insertAt)
                insertAt += 1
            }
            lines.insert(contentsOf: [sectionLine, "", bullet, ""], at: insertAt)
        }

        return lines.joined(separator: "\n")
    }

    private func ensureRootDirectory() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: rootURL.path) {
            try? fm.createDirectory(at: rootURL, withIntermediateDirectories: true)
        }
    }

    private func bootstrapIfNeeded() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: rootURL.path) {
            try? fm.createDirectory(at: rootURL, withIntermediateDirectories: true)
        }

        if !fm.fileExists(atPath: memoryFileURL.path) {
            try? Self.memoryTemplate.write(to: memoryFileURL, atomically: true, encoding: .utf8)
        }
        if !fm.fileExists(atPath: userFileURL.path) {
            try? Self.userTemplate.write(to: userFileURL, atomically: true, encoding: .utf8)
        }
    }

    private static let memoryTemplate = """
    ## 行为规则
    - Notion 写操作必须先经过用户确认
    - 定时到期不主动打断对话

    ## 工作上下文
    （记录工作相关的关键事实与决策）

    ## 关键决策与教训
    （由 Dreaming 流程沉淀，用户审核保留）
    """

    private static let userTemplate = """
    ## 偏好
    （记录用户的工作习惯、时段、沟通偏好）

    ## 沟通风格
    - 中文、简短
    - 允许被挑战，不要一味附和
    """
}
