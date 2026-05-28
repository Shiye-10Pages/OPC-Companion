import SwiftUI

/// 把 markdown 文本按段落分块渲染，支持加粗/斜体/链接/代码块/列表/标题。
struct MarkdownText: View {
    let text: String
    @Environment(\.theme) private var theme
    /// 字体方案：必须接入，否则 AttributedString 带的 default font 会盖掉外层 .font()
    @Environment(\.fontStyle) private var fontStyle

    var body: some View {
        if shouldUseStoaRenderer {
            stoaContent
        } else {
            plainContent
        }
    }

    private var shouldUseStoaRenderer: Bool {
        theme.id == .stoa && containsStoaTags
    }

    private var containsStoaTags: Bool {
        StoaParser.containsRecognizedTag(in: text)
    }

    private var stoaContent: some View {
        let segments = StoaParser.parse(text)
        return VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, seg in
                segmentView(seg)
            }
        }
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func segmentView(_ seg: StoaSegment) -> some View {
        switch seg {
        case .text(let s):
            Text(stoaAttributed(s))
                .font(fontStyle.bodyFont)
                .foregroundStyle(theme.textPrimary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        case .moduleTag(let s):
            StoaModuleTag(text: s)
        case .dichotomy(let inn, let out):
            StoaDichotomyCard(inn: inn, out: out)
        case .factJudge(let f, let j, let a):
            StoaFactJudgeCard(fact: f, judge: j, action: a)
        case .ritual(let items):
            StoaRitualCard(items: items)
                .padding(.top, 4)
        case .tempo(let pct, let opts):
            StoaTempoCard(energyPct: pct, options: opts)
        case .virtues(let rows):
            StoaVirtuesCard(rows: rows)
        case .quote(let t, let a):
            StoaQuoteTail(text: t, author: a)
        }
    }

    private func stoaAttributed(_ raw: String) -> AttributedString {
        var attr = AttributedString(raw)
        // 整段先 set 用户选的字体方案 bodyFont；再给关键词重置成 medium + ink 色
        attr.font = fontStyle.bodyFont
        for keyword in ["既然", "如此，则", "如此则", "因此"] {
            if let range = attr.range(of: keyword) {
                attr[range].foregroundColor = theme.ink
                attr[range].font = fontStyle.bodyFont.weight(.medium)
            }
        }
        return attr
    }

    private var plainContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                renderBlock(block)
            }
        }
        .textSelection(.enabled)
    }

    private enum Block {
        case heading(level: Int, text: String)
        case codeBlock(String)
        case bullet([String])
        case paragraph(String)
    }

    private var blocks: [Block] {
        var result: [Block] = []
        let lines = text.components(separatedBy: "\n")
        var i = 0
        var buffer: [String] = []
        var bulletBuffer: [String] = []

        func flushBuffer() {
            if !buffer.isEmpty {
                let para = buffer.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                if !para.isEmpty { result.append(.paragraph(para)) }
                buffer.removeAll()
            }
        }
        func flushBullets() {
            if !bulletBuffer.isEmpty {
                result.append(.bullet(bulletBuffer))
                bulletBuffer.removeAll()
            }
        }

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // 代码块
            if trimmed.hasPrefix("```") {
                flushBuffer(); flushBullets()
                var code: [String] = []
                i += 1
                while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    code.append(lines[i])
                    i += 1
                }
                result.append(.codeBlock(code.joined(separator: "\n")))
                i += 1
                continue
            }

            // 标题 # / ## / ###
            if let level = headingLevel(line: trimmed) {
                flushBuffer(); flushBullets()
                let dropped = trimmed.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)
                result.append(.heading(level: level, text: dropped))
                i += 1
                continue
            }

            // 列表项
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                flushBuffer()
                bulletBuffer.append(String(trimmed.dropFirst(2)))
                i += 1
                continue
            }

            // 空行 → 段落分隔
            if trimmed.isEmpty {
                flushBullets()
                flushBuffer()
                i += 1
                continue
            }

            // 普通段落
            flushBullets()
            buffer.append(line)
            i += 1
        }
        flushBullets()
        flushBuffer()
        return result
    }

    private func headingLevel(line: String) -> Int? {
        guard line.hasPrefix("#") else { return nil }
        let hashes = line.prefix { $0 == "#" }.count
        guard hashes >= 1, hashes <= 6, line.dropFirst(hashes).first == " " else { return nil }
        return hashes
    }

    @ViewBuilder
    private func renderBlock(_ block: Block) -> some View {
        switch block {
        case .heading(let level, let text):
            inlineMarkdown(text)
                .font(.system(size: max(13, 20 - CGFloat(level) * 2), weight: .semibold))
        case .paragraph(let text):
            inlineMarkdown(text)
                .fixedSize(horizontal: false, vertical: true)
        case .bullet(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 6) {
                        Text("•").foregroundColor(.secondary)
                        inlineMarkdown(item)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        case .codeBlock(let code):
            Text(code)
                .font(.system(size: 12, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(nsColor: .textBackgroundColor).opacity(0.5))
                )
                .textSelection(.enabled)
        }
    }

    private func inlineMarkdown(_ text: String) -> Text {
        if var attributed = try? AttributedString(
            markdown: text,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace
            )
        ) {
            applyFontStylePreservingEmphasis(&attributed)
            return Text(attributed)
        }
        return Text(text)
    }

    /// 把 fontStyle.bodyFont 应用到 AttributedString，同时保留 markdown 解析出的
    /// bold / italic 强调（用 inlinePresentationIntent 判断每段 run 的 emphasis，
    /// 再用对应 weight/italic 的 fontStyle 字体覆盖）。
    /// 不这么做的话整段 set font 会丢 markdown 的 **加粗** / *斜体*。
    private func applyFontStylePreservingEmphasis(_ attr: inout AttributedString) {
        let baseBody = fontStyle.bodyFont
        let baseStrong = fontStyle.strongFont
        for run in attr.runs {
            let intent = run.inlinePresentationIntent ?? []
            let font: Font
            if intent.contains(.stronglyEmphasized) && intent.contains(.emphasized) {
                font = baseStrong.italic()
            } else if intent.contains(.stronglyEmphasized) {
                font = baseStrong
            } else if intent.contains(.emphasized) {
                font = baseBody.italic()
            } else if intent.contains(.code) {
                font = fontStyle.monoFont
            } else {
                font = baseBody
            }
            attr[run.range].font = font
        }
    }
}
