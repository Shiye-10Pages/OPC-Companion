import Foundation

/// 日志/诊断文本脱敏（**标准**强度）。
///
/// 抹掉可识别个人信息与凭证——API Key / Bearer token / Notion token、主目录用户名、邮箱、手机号；
/// 保留 HTTP 码、错误类型、`文件:行` 等无隐私但对排查有用的结构信息。
///
/// 两处复用：
/// 1. 失败日志里动态字符串落盘前的兜底脱敏（防御纵深，源头已尽量不记敏感值）；
/// 2. 将来「复制诊断日志」导出时，对整段日志统一过一遍。
public enum LogRedactor {
    /// 对单段文本做标准脱敏。规则按顺序应用：先清最敏感的凭证，再清路径/联系方式。
    public static func redact(_ input: String) -> String {
        var s = input
        for (regex, template) in rules {
            let range = NSRange(s.startIndex..<s.endIndex, in: s)
            s = regex.stringByReplacingMatches(in: s, options: [], range: range, withTemplate: template)
        }
        return s
    }

    private static let rules: [(NSRegularExpression, String)] = {
        let patterns: [(String, String)] = [
            // Authorization: Bearer <token>
            ("(?i)(bearer\\s+)[A-Za-z0-9._\\-]+", "$1***"),
            // OpenAI / 通用 sk- 密钥
            ("(?i)\\bsk-[A-Za-z0-9._\\-]{8,}", "sk-***"),
            // Notion 内部集成 token（secret_xxx / ntn_xxx）
            ("(?i)\\b(secret_|ntn_)[A-Za-z0-9]{8,}", "$1***"),
            // 形如 "apiKey":"xxx" / api_key=xxx
            ("(?i)(api[_-]?key\"?\\s*[:=]\\s*\"?)[A-Za-z0-9._\\-]{6,}", "$1***"),
            // 形如 "token":"xxx" / token=xxx（不误伤 token_limit 这类无冒号/等号的词）
            ("(?i)(token\"?\\s*[:=]\\s*\"?)[A-Za-z0-9._\\-]{6,}", "$1***"),
            // 主目录路径里的用户名 /Users/<name>/ → /Users/USER/
            ("/Users/[^/\\s\"]+", "/Users/USER"),
            // 邮箱
            ("[A-Za-z0-9._%+\\-]+@[A-Za-z0-9.\\-]+\\.[A-Za-z]{2,}", "***@***"),
            // 中国大陆手机号
            ("(?<!\\d)1[3-9]\\d{9}(?!\\d)", "***")
        ]
        return patterns.compactMap { pattern, template in
            guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
            return (re, template)
        }
    }()
}
