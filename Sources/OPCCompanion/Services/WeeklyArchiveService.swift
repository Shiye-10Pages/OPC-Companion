import Foundation

/// 周日 23:59 → 周一 00:00 跨周切换时，让 AI 汇总本周 daily notes，
/// 写入 `~/.opc-companion/memory/weekly/YYYY-WXX.md`。包含：完成率 / 时段 / 模式观察。
@MainActor
public final class WeeklyArchiveService {
    public static let shared = WeeklyArchiveService()

    private var isGenerating = false

    private static let isRunningTests: Bool = NSClassFromString("XCTestCase") != nil

    public init() {}

    /// 幂等：同一周重复调用不会产生多份文件。
    public func checkWeeklyRolloverIfNeeded(now: Date = Date()) async {
        guard !Self.isRunningTests else { return }
        guard !isGenerating else { return }

        let calendar = isoCalendar()
        let comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
        guard let year = comps.yearForWeekOfYear, let week = comps.weekOfYear else { return }

        // 年初 week=1 → week-1=0，跨年用 ISO 周日历正确回退
        var targetYear = year
        var targetWeek = week - 1
        if targetWeek < 1 {
            targetYear -= 1
            let prevYearEnd = calendar.date(from: DateComponents(weekday: 2, weekOfYear: 52, yearForWeekOfYear: targetYear))!
            let prevComps = calendar.dateComponents([.weekOfYear], from: prevYearEnd)
            targetWeek = prevComps.weekOfYear ?? 52
        }
        let targetKey = String(format: "%04d-W%02d", targetYear, targetWeek)
        let weeklyURL = Self.weeklyDir().appendingPathComponent("\(targetKey).md")

        let fm = FileManager.default
        if fm.fileExists(atPath: weeklyURL.path) { return }

        // 只在周一（macOS 上 ISO 周一 = weekday 2）生成上周报告
        let weekday = calendar.component(.weekday, from: now)
        guard weekday == 2 else { return }

        isGenerating = true
        defer { isGenerating = false }

        await generateWeekly(year: year, week: week - 1, writeTo: weeklyURL)
    }

    private func generateWeekly(year: Int, week: Int, writeTo url: URL) async {
        let calendar = isoCalendar()
        var dateComps = DateComponents()
        dateComps.yearForWeekOfYear = year
        dateComps.weekOfYear = week
        dateComps.weekday = calendar.firstWeekday
        guard let weekStart = calendar.date(from: dateComps) else { return }

        var dailies: [(day: String, content: String)] = []
        let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"
        for offset in 0..<7 {
            guard let d = calendar.date(byAdding: .day, value: offset, to: weekStart) else { continue }
            let key = formatter.string(from: d)
            let path = AppState.dataDirectory
                .appendingPathComponent("memory")
                .appendingPathComponent("\(key).md")
            if let content = try? String(contentsOf: path, encoding: .utf8), !content.isEmpty {
                dailies.append((key, content))
            }
        }

        guard !dailies.isEmpty else { return }

        let joined = dailies.map { "## \($0.day)\n\($0.content)" }.joined(separator: "\n\n---\n\n")
        let prompt = """
        以下是用户本周（第 \(week) 周）每日的活动日记（daily note），包含任务、随手记、定时触发等。

        请生成一份周报，结构化且简洁。**只输出 markdown 正文**，不要加引号或前后缀。包含以下 section：

        ## 本周成果
        - (列 3–6 条关键完成事项)

        ## 时间分布
        - (哪类任务占比最高；高产时段大致分布)

        ## 节奏模式观察
        - (2–4 条关于工作习惯的观察，如周几效率高、常超时任务、拖延信号)

        ## 下周建议
        - (1–3 条具体可行的调整)

        ---
        原始每日记录：
        \(joined)
        """

        do {
            let summary = try await ChatEngine.shared.sendMessage(
                prompt,
                systemPrompt: "你是高质量的节奏教练，擅长从日记中提炼模式。",
                useConversationHistory: false
            )
            let cleaned = summary.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else { return }

            Self.ensureWeeklyDir()
            let header = "# \(year)-W\(String(format: "%02d", week))\n\n"
            try? (header + cleaned + "\n").write(to: url, atomically: true, encoding: .utf8)

            await MainActor.run {
                AppState.shared.showBanner("本周周报已生成", kind: .info, duration: 4.0)
            }
        } catch {
            OPCLogger.shared.log(.error, "weekly", "周报生成失败: \(error.localizedDescription)")
            await MainActor.run {
                AppState.shared.showBanner("本周周报生成失败，稍后重试", kind: .warning, duration: 4.0)
            }
        }
    }

    private func isoCalendar() -> Calendar {
        var c = Calendar(identifier: .iso8601)
        c.firstWeekday = 2  // Monday
        c.minimumDaysInFirstWeek = 4
        return c
    }

    private static func weeklyDir() -> URL {
        AppState.dataDirectory
            .appendingPathComponent("memory")
            .appendingPathComponent("weekly")
    }

    private static func ensureWeeklyDir() {
        let dir = weeklyDir()
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }
}
