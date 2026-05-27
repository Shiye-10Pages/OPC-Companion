import Foundation

// MARK: - 段类型

/// Stoa AI 回复被解析后的一段。普通文本和 5 种结构化标记。
public enum StoaSegment: Equatable {
    case text(String)
    case moduleTag(String)             // <module>M1 · Dichotomy of Control</module>
    case dichotomy(inn: [String], out: [String])
    case factJudge(fact: String, judge: String, action: String)
    case ritual(items: [(prompt: String, answer: String)])
    case tempo(energyPct: Int, options: [TempoOption])
    case virtues(rows: [VirtueRow])
    case quote(text: String, author: String)

    public static func == (lhs: StoaSegment, rhs: StoaSegment) -> Bool {
        // 简化：仅供调试/测试
        switch (lhs, rhs) {
        case (.text(let a), .text(let b)): return a == b
        case (.moduleTag(let a), .moduleTag(let b)): return a == b
        default: return false
        }
    }
}

public struct TempoOption: Equatable {
    public var roman: String       // I / II / III
    public var title: String       // 深度工作 / 低阻力任务 / 5 分钟最小版本
    public var detail: String      // "90 min 写作 / 推理"
    public var tag: String         // "Now" / "Skip" / "Fallback"
    public var recommended: Bool
}

public struct VirtueRow: Equatable {
    public var name: String        // Veritas
    public var chineseName: String // 诚实
    public var score: Int          // 0~5
    public var note: String        // "承认了卡住..."
}

// MARK: - 解析器

/// 把 AI 回复字符串解析为 StoaSegment 数组。
/// 解析失败的部分回退为 `.text`。
public enum StoaParser {

    public static func parse(_ raw: String) -> [StoaSegment] {
        var segments: [StoaSegment] = []
        var remaining = raw

        // 按出现顺序逐个匹配第一个标记，将它前后的文本切开
        while !remaining.isEmpty {
            guard let firstMatch = findFirstTag(in: remaining) else {
                appendText(remaining, into: &segments)
                break
            }
            // 标记前的文字
            let head = String(remaining[remaining.startIndex..<firstMatch.range.lowerBound])
            appendText(head, into: &segments)

            // 标记本身
            if let seg = decode(tag: firstMatch.tag, body: firstMatch.body, attrs: firstMatch.attrs) {
                segments.append(seg)
            } else {
                // 解析失败 → 保留原文不丢
                segments.append(.text(String(remaining[firstMatch.range])))
            }

            remaining = String(remaining[firstMatch.range.upperBound...])
        }
        return segments
    }

    private static func appendText(_ s: String, into segments: inout [StoaSegment]) {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { segments.append(.text(trimmed)) }
    }

    // 支持的标记名（每个 key 是规范名；value 是常见 LLM typo 别名）
    // M2 在 strict XML 输出场景偶尔会拼错（empo / facjudge / virtus），容错回归到规范名
    private static let tagAliases: [String: [String]] = [
        "module":    ["module"],
        "dichotomy": ["dichotomy", "dichoto"],
        "factjudge": ["factjudge", "facjudge", "fact-judge", "factjudgement"],
        "ritual":    ["ritual", "rituals"],
        "tempo":     ["tempo", "empo", "tempos"],
        "virtues":   ["virtues", "virtus", "virtuelist"],
        "quote":     ["quote", "quotes", "qoute"]
    ]
    /// 所有可识别标签名（含 typo 别名），保持原排序作为优先级
    private static let tagNames: [String] = tagAliases.values.flatMap { $0 }

    private struct Match {
        let tag: String
        let body: String
        let attrs: [String: String]
        let range: Range<String.Index>
    }

    /// 找到字符串里第一个出现的支持标记。
    /// 支持属性：<tempo energy="32">...</tempo> 会保留属性供卡片解析。
    private static func findFirstTag(in text: String) -> Match? {
        var best: Match?
        for name in tagNames {
            // 用宽松正则：<name (任意属性)?> ... </name>
            let pattern = "<\(name)((?:\\s+[^>]*)?)>([\\s\\S]*?)</\(name)>"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            guard let m = regex.firstMatch(in: text, range: range) else { continue }
            guard let fullRange = Range(m.range, in: text),
                  let attrRange = Range(m.range(at: 1), in: text),
                  let bodyRange = Range(m.range(at: 2), in: text) else { continue }
            // 把 typo 别名归一化到规范 tag 名
            let canonicalTag = tagAliases.first(where: { $0.value.contains(name) })?.key ?? name
            let candidate = Match(tag: canonicalTag,
                                  body: String(text[bodyRange]),
                                  attrs: parseAttributes(String(text[attrRange])),
                                  range: fullRange)
            if best == nil || candidate.range.lowerBound < best!.range.lowerBound {
                best = candidate
            }
        }
        return best
    }

    private static func decode(tag: String, body: String, attrs: [String: String]) -> StoaSegment? {
        switch tag {
        case "module":
            return .moduleTag(body.trimmingCharacters(in: .whitespacesAndNewlines))
        case "dichotomy":
            return decodeDichotomy(body)
        case "factjudge":
            return decodeFactJudge(body)
        case "ritual":
            return decodeRitual(body)
        case "tempo":
            return decodeTempo(body, attrs: attrs)
        case "virtues":
            return decodeVirtues(body)
        case "quote":
            return decodeQuote(body)
        default:
            return nil
        }
    }

    // <dichotomy><in>...</in><out>...</out></dichotomy>
    // <in> 内每行（- xxx）作为一个条目
    private static func decodeDichotomy(_ body: String) -> StoaSegment {
        let inn = extractList(from: body, tag: "in")
        let out = extractList(from: body, tag: "out")
        return .dichotomy(inn: inn, out: out)
    }

    // <factjudge><fact>...</fact><judge>...</judge><act>...</act></factjudge>
    private static func decodeFactJudge(_ body: String) -> StoaSegment {
        return .factJudge(
            fact: extractFirst(body, tag: "fact"),
            judge: extractFirst(body, tag: "judge"),
            action: extractFirst(body, tag: "act")
        )
    }

    // <ritual><q prompt="..." answer="..."/></ritual>
    // 或 <ritual><q><p>...</p><a>...</a></q></ritual>
    // 简化：用 <q>...</q> 包裹，内部用 "|" 分隔 prompt | answer
    private static func decodeRitual(_ body: String) -> StoaSegment {
        let qs = extractAll(body, tag: "q")
        let items: [(String, String)] = qs.map { q in
            if let pipeIdx = q.range(of: "|") {
                let p = String(q[q.startIndex..<pipeIdx.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                let a = String(q[pipeIdx.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                return (p, a)
            }
            return (q.trimmingCharacters(in: .whitespacesAndNewlines), "")
        }
        return .ritual(items: items)
    }

    // <tempo energy="32"><opt roman="II" title="..." tag="Now" recommended>...</opt></tempo>
    // 简化版：每个 opt 用一行，格式："roman | title | detail | tag | recommended?"
    private static func decodeTempo(_ body: String, attrs: [String: String]) -> StoaSegment {
        let energyPct = Int(attrs["energy"] ?? "0") ?? 0
        let opts = extractAll(body, tag: "opt")
        let options: [TempoOption] = opts.map { line in
            let parts = line.split(separator: "|", omittingEmptySubsequences: false).map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return TempoOption(
                roman: parts.indices.contains(0) ? parts[0] : "",
                title: parts.indices.contains(1) ? parts[1] : "",
                detail: parts.indices.contains(2) ? parts[2] : "",
                tag: parts.indices.contains(3) ? parts[3] : "",
                recommended: parts.indices.contains(4) && parts[4].lowercased().contains("recommended")
            )
        }
        return .tempo(energyPct: energyPct, options: options)
    }

    // <virtues>
    //   <row name="Veritas" zh="诚实" score="4">承认了卡住...</row>
    //   ...
    // </virtues>
    private static func decodeVirtues(_ body: String) -> StoaSegment {
        let rows = extractAllWithAttrs(body, tag: "row")
        let parsed: [VirtueRow] = rows.map { (attrs, inner) in
            VirtueRow(
                name: attrs["name"] ?? "",
                chineseName: attrs["zh"] ?? "",
                score: Int(attrs["score"] ?? "0") ?? 0,
                note: inner.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        return .virtues(rows: parsed)
    }

    // <quote from="Epictetus · IV.1">No man is free...</quote>
    private static func decodeQuote(_ body: String) -> StoaSegment {
        // body 是引言文本；from 在标记外，需要在 findFirstTag 中保留 —— 这里简化处理
        // 我们重写为：body 形如 "引言文本|出处"
        if let pipeIdx = body.range(of: "|") {
            let text = String(body[body.startIndex..<pipeIdx.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            let author = String(body[pipeIdx.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            return .quote(text: text, author: author)
        }
        return .quote(text: body.trimmingCharacters(in: .whitespacesAndNewlines), author: "")
    }

    // MARK: helpers

    private static func extractFirst(_ body: String, tag: String) -> String {
        guard let regex = try? NSRegularExpression(
                pattern: "<\(tag)(?:\\s+[^>]*)?>([\\s\\S]*?)</\(tag)>",
                options: [.caseInsensitive]) else { return "" }
        let range = NSRange(body.startIndex..<body.endIndex, in: body)
        guard let m = regex.firstMatch(in: body, range: range),
              let r = Range(m.range(at: 1), in: body) else { return "" }
        return String(body[r]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func extractAll(_ body: String, tag: String) -> [String] {
        guard let regex = try? NSRegularExpression(
                pattern: "<\(tag)(?:\\s+[^>]*)?>([\\s\\S]*?)</\(tag)>",
                options: [.caseInsensitive]) else { return [] }
        let range = NSRange(body.startIndex..<body.endIndex, in: body)
        let matches = regex.matches(in: body, range: range)
        return matches.compactMap { m in
            guard let r = Range(m.range(at: 1), in: body) else { return nil }
            return String(body[r])
        }
    }

    private static func extractAllWithAttrs(_ body: String, tag: String) -> [(attrs: [String: String], inner: String)] {
        guard let regex = try? NSRegularExpression(
                pattern: "<\(tag)((?:\\s+[^>]*)?)>([\\s\\S]*?)</\(tag)>",
                options: [.caseInsensitive]) else { return [] }
        let range = NSRange(body.startIndex..<body.endIndex, in: body)
        let matches = regex.matches(in: body, range: range)
        return matches.compactMap { m in
            guard let attrRange = Range(m.range(at: 1), in: body),
                  let innerRange = Range(m.range(at: 2), in: body) else { return nil }
            let attrs = parseAttributes(String(body[attrRange]))
            let inner = String(body[innerRange])
            return (attrs, inner)
        }
    }

    private static func parseAttributes(_ s: String) -> [String: String] {
        // 解析 name="..." score="3" 这种
        var result: [String: String] = [:]
        guard let regex = try? NSRegularExpression(
                pattern: "([a-zA-Z_][\\w-]*)=\"([^\"]*)\"") else { return result }
        let range = NSRange(s.startIndex..<s.endIndex, in: s)
        let matches = regex.matches(in: s, range: range)
        for m in matches {
            guard let keyRange = Range(m.range(at: 1), in: s),
                  let valRange = Range(m.range(at: 2), in: s) else { continue }
            result[String(s[keyRange])] = String(s[valRange])
        }
        return result
    }

    // 在 <in>...</in> 里把每个 "- xxx" 列出
    private static func extractList(from body: String, tag: String) -> [String] {
        let inner = extractFirst(body, tag: tag)
        return inner.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .compactMap { line -> String? in
                guard !line.isEmpty else { return nil }
                if line.hasPrefix("- ")  { return String(line.dropFirst(2)) }
                if line.hasPrefix("· ")  { return String(line.dropFirst(2)) }
                return line
            }
    }
}
