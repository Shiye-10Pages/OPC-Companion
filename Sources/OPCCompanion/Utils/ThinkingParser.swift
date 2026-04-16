import Foundation

/// 把模型响应里的 `<think>...</think>` 段提取出来，与正文分离。
public enum ThinkingParser {
    public struct ParsedContent: Sendable, Equatable {
        public let thinking: String?
        public let main: String
    }

    public static func parse(_ text: String) -> ParsedContent {
        let pattern = #"<think>([\s\S]*?)</think>\s*"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
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
            main: mainText
        )
    }
}
