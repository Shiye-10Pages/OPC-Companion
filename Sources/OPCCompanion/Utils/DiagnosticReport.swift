import Foundation

/// 组装一份**已脱敏**的诊断报告，供用户一键复制发给开发者。
///
/// 不含任何密钥/token（只报「已设置/未设置」），用户原文（会议标题、随手记等）在源头已不落盘，
/// 这里再对整段日志过一遍 [LogRedactor] 兜底。日志只取有用类别 + 全部 WARN/ERROR 的尾部若干行。
public enum DiagnosticReport {
    private static let maxLogLines = 200

    @MainActor
    public static func build() -> String {
        let state = AppState.shared
        let cfg = state.config.apiConfig
        let db = state.config.notionDatabaseIds

        var lines: [String] = []
        lines.append("=== OPC 伴侣 诊断报告 ===")
        lines.append("生成时间: \(timestamp())")
        lines.append("App 版本: \(AppVersion.current)")
        lines.append("系统: macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
        lines.append("语言/时区: \(Locale.current.identifier) / \(TimeZone.current.identifier)")
        lines.append("")
        lines.append("--- 配置（不含密钥）---")
        lines.append("服务商: \(cfg.provider)")
        lines.append("接口地址(host): \(URL(string: cfg.normalizedBaseURL)?.host ?? cfg.normalizedBaseURL)")
        lines.append("模型: \(cfg.resolvedModel)")
        lines.append("API Key: \(CredentialCache.shared.getAPIKey(provider: cfg.provider).isEmpty ? "未设置" : "已设置")")
        lines.append("Notion Token: \(CredentialCache.shared.getNotionToken().isEmpty ? "未设置" : "已设置")")
        lines.append("Notion 数据库: calendar=\(bound(db.calendar)) todos=\(bound(db.todos)) inbox=\(bound(db.inbox))")
        if state.config.proxyConfig.enabled { lines.append("代理: 已启用") }
        if let up = state.availableUpdate { lines.append("可更新到: v\(up.version)") }
        lines.append("")
        lines.append("--- 最近日志（已脱敏，最多 \(maxLogLines) 行）---")
        lines.append(recentLogs())
        return lines.joined(separator: "\n")
    }

    private static func bound(_ s: String?) -> String { (s?.isEmpty == false) ? "已绑定" : "未绑定" }

    private static func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: Date())
    }

    /// 读今天（不足则补昨天）的日志尾部，过滤掉 DIAG/secure-input/hotkey 噪声、保留 WARN/ERROR 与
    /// chat/tool/notion/llm/update/credential 类别，再整体脱敏。
    private static func recentLogs() -> String {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".opc-companion/logs")
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        let today = f.string(from: Date())
        let yesterday = f.string(from: Date().addingTimeInterval(-86_400))

        var raw = readTail(dir.appendingPathComponent("\(today).log"), lines: maxLogLines)
        if raw.count < maxLogLines {
            raw = readTail(dir.appendingPathComponent("\(yesterday).log"), lines: maxLogLines - raw.count) + raw
        }

        let useful = raw.filter { line in
            if line.contains("[ERROR]") || line.contains("[WARN]") { return true }
            if line.contains("[DIAG]") || line.contains("secure-input") || line.contains("[hotkey]") { return false }
            return ["[chat]", "[tool]", "[notion]", "[llm]", "[update]", "[credential]"].contains { line.contains($0) }
        }
        let tail = Array(useful.suffix(maxLogLines))
        let joined = tail.isEmpty ? "(暂无相关日志)" : tail.joined(separator: "\n")
        return LogRedactor.redact(joined)
    }

    private static func readTail(_ url: URL, lines: Int) -> [String] {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        let all = content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        return Array(all.suffix(lines))
    }
}
