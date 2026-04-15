import SwiftUI

struct MarkdownText: View {
    let text: String

    var body: some View {
        // 简单解析 Markdown 并渲染 - 只支持基本格式
        FlowStack {
            ForEach(Array(parseMarkdown().enumerated()), id: \.offset) { _, element in
                element
            }
        }
    }

    private func parseMarkdown() -> [Text] {
        var result: [Text] = []
        let lines = text.components(separatedBy: .newlines)

        for line in lines {
            if line.isEmpty {
                result.append(Text(" "))
                continue
            }

            // 解析加粗 **text**
            var remaining = line
            var isFirst = true

            while let boldRange = remaining.range(of: #"\*\*(.+?)\*\*"#, options: .regularExpression) {
                let beforeBold = String(remaining[..<boldRange.lowerBound])
                if !beforeBold.isEmpty {
                    isFirst = false
                }

                let boldContent = String(remaining[boldRange])
                    .replacingOccurrences(of: "**", with: "")

                var styled = Text(boldContent)
                // 不容易直接添加 bold，用普通文本
                result.append(Text(boldContent))

                remaining = String(remaining[boldRange.upperBound...])
                isFirst = false
            }

            if !remaining.isEmpty {
                if result.isEmpty {
                    result.append(Text(remaining))
                } else {
                    result.append(Text(remaining))
                }
            }
        }

        return result.isEmpty ? [Text(text)] : result
    }
}

// 简单的 Markdown 渲染辅助组件
struct FlowStack<Content: View>: View {
    let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        content()
    }
}

// 扩展 Text 支持 Markdown 样式
extension Text {
    func styledMarkdown(_ content: String) -> Text {
        var result = Text("")
        let lines = content.components(separatedBy: .newlines)

        for (index, line) in lines.enumerated() {
            // 检测列表项
            if line.hasPrefix("- ") {
                result = result + Text("  • " + String(line.dropFirst(2)))
            } else if line.hasPrefix("```") {
                // 代码块 - 简化处理
                result = result + Text(line)
            } else {
                result = result + Text(line)
            }

            if index < lines.count - 1 {
                result = result + Text("\n")
            }
        }

        return result
    }
}