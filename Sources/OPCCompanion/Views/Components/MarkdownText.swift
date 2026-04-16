import SwiftUI

/// 把 markdown 文本按段落分块渲染，支持加粗/斜体/链接/代码块/列表/标题。
struct MarkdownText: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                renderBlock(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
        if let attributed = try? AttributedString(
            markdown: text,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace
            )
        ) {
            return Text(attributed)
        }
        return Text(text)
    }
}
