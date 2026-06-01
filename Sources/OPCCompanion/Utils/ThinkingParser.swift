import Foundation

/// 把模型响应里的 `<think>...</think>` 段提取出来，与正文分离。
public enum ThinkingParser {
    public struct ParsedContent: Sendable, Equatable {
        public let thinking: String?
        public let main: String
    }

    public static func parse(_ text: String) -> ParsedContent {
        let pattern = #"<think(?:\s+[^>]*)?>([\s\S]*?)(?:</think>|<\\/think>)\s*"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return ParsedContent(thinking: nil, main: text)
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)

        var thinkingParts: [String] = []
        regex.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
            guard let m = match,
                  let r = Range(m.range(at: 1), in: text) else { return }
            let part = String(text[r]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !part.isEmpty { thinkingParts.append(part) }
        }

        let mainText = regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return ParsedContent(
            thinking: thinkingParts.isEmpty ? nil : thinkingParts.joined(separator: "\n\n"),
            main: stripLegacyActionTags(stripStrayThinkingTags(mainText))
        )
    }

    /// 兼容期兜底：老 system prompt 教过模型在文本尾附加 `[ACTION:timer:start:{...}]` 等指令串。
    /// 当前已改走 function calling，prompt 也删了教程，但历史 jsonl / 个别 bypass 还可能泄漏。
    /// 这里统一在展示前剥离，避免用户看到裸露指令串；发回 AI 服务商的 wire history 也会复用此函数。
    public static func stripLegacyActionTags(_ text: String) -> String {
        let pattern = #"\[ACTION:[^\]]*\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return text
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let stripped = regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
        return stripped.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func stripStrayThinkingTags(_ text: String) -> String {
        let pattern = #"</?think(?:\s+[^>]*)?>|<\\/?think>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return text
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let stripped = regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
        return stripped.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
