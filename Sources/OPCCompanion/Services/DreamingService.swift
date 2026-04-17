import Foundation

/// Dreaming：从 daily note 的 `## [LEARN] 候选` section 收割候选条目，
/// 用户审核后 approve → 晋升到 MEMORY.md 的 `## 关键决策与教训`；reject → 丢弃。
///
/// 触发时机：每日首次打开面板时，扫描最近 7 天 daily notes 的 [LEARN] section。
@MainActor
public final class DreamingService {
    public static let shared = DreamingService()

    private static let isRunningTests: Bool = NSClassFromString("XCTestCase") != nil

    public init() {}

    /// 扫描最近 7 天 daily note 的 `## [LEARN] 候选` section，提取未晋升的条目。
    public func harvestCandidates() -> [(date: String, entry: String)] {
        guard !Self.isRunningTests else { return [] }
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        var results: [(String, String)] = []

        for offset in 0..<7 {
            guard let d = cal.date(byAdding: .day, value: -offset, to: today) else { continue }
            let key = f.string(from: d)
            let url = AppState.dataDirectory
                .appendingPathComponent("memory")
                .appendingPathComponent("\(key).md")
            guard let content = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let entries = extractLearnSection(from: content)
            for entry in entries {
                results.append((key, entry))
            }
        }
        return results
    }

    /// 晋升一条 learn 到 MEMORY.md 的 `## 关键决策与教训` section 末尾（不打乱现有顺序）。
    public func promote(entry: String) {
        var lines = MemoryService.shared.readMemory().components(separatedBy: "\n")
        let section = "## 关键决策与教训"

        if let sectionIdx = lines.firstIndex(of: section) {
            var insertIdx = sectionIdx + 1
            while insertIdx < lines.count && !lines[insertIdx].hasPrefix("## ") {
                insertIdx += 1
            }
            while insertIdx > sectionIdx + 1 && lines[insertIdx - 1].trimmingCharacters(in: .whitespaces).isEmpty {
                insertIdx -= 1
            }
            lines.insert("- \(entry)", at: insertIdx)
        } else {
            lines.append(contentsOf: ["", section, "- \(entry)"])
        }
        MemoryService.shared.writeMemory(lines.joined(separator: "\n"))
    }

    private func extractLearnSection(from content: String) -> [String] {
        let lines = content.components(separatedBy: "\n")
        guard let start = lines.firstIndex(of: "## [LEARN] 候选") else { return [] }
        var entries: [String] = []
        for i in (start + 1)..<lines.count {
            let line = lines[i]
            if line.hasPrefix("## ") { break }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("- ") {
                let entry = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                guard !entry.isEmpty else { continue }
                // 用 regex 剥离 HH:mm 时间戳前缀（兼容 9:30 / 09:30 / 14:05 等格式）
                let timePattern = #"^\d{1,2}:\d{2}\s+"#
                if let regex = try? NSRegularExpression(pattern: timePattern),
                   regex.firstMatch(in: entry, range: NSRange(entry.startIndex..<entry.endIndex, in: entry)) != nil {
                    let stripped = regex.stringByReplacingMatches(in: entry, range: NSRange(entry.startIndex..<entry.endIndex, in: entry), withTemplate: "")
                        .trimmingCharacters(in: .whitespaces)
                    if !stripped.isEmpty { entries.append(stripped) }
                } else {
                    entries.append(entry)
                }
            }
        }
        return entries
    }
}
