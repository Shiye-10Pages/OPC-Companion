import SwiftUI

struct NotionConfirmCard: View {
    let toolCall: WireToolCall
    let onConfirm: () -> Void
    let onCancel: () -> Void

    private var prettyArguments: String {
        guard let data = toolCall.function.arguments.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: pretty, encoding: .utf8) else {
            return toolCall.function.arguments
        }
        return text
    }

    private var operationLabel: String {
        switch toolCall.function.name {
        case "create_notion_page": return "新增页面"
        case "update_notion_page": return "更新页面"
        default: return toolCall.function.name
        }
    }

    private var operationIcon: String {
        switch toolCall.function.name {
        case "create_notion_page": return "plus.square.on.square"
        case "update_notion_page": return "square.and.pencil"
        default: return "doc.text.fill"
        }
    }

    private var argsDict: [String: Any] {
        guard let data = toolCall.function.arguments.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return obj
    }

    private var databaseLabel: String? {
        guard let key = argsDict["database_key"] as? String else { return nil }
        switch key {
        case "calendar": return "日历"
        case "todos": return "待办"
        case "inbox": return "收件箱"
        default: return key
        }
    }

    private var pageId: String? { argsDict["page_id"] as? String }

    private var titleSummary: String? {
        guard let props = argsDict["properties"] as? [String: Any] else { return nil }
        for (_, value) in props {
            if let titleObj = value as? [String: Any],
               let titleArr = titleObj["title"] as? [[String: Any]],
               let first = titleArr.first,
               let textObj = first["text"] as? [String: Any],
               let content = textObj["content"] as? String {
                return content
            }
        }
        return nil
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .frame(width: 56, alignment: .leading)
            Text(value)
                .font(.system(size: 12))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: operationIcon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(AppColors.primary)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(AppColors.primary.opacity(0.15)))
                VStack(alignment: .leading, spacing: 2) {
                    Text("请确认 Notion 操作").font(.headline)
                    Text(operationLabel).font(.caption).foregroundColor(.secondary)
                }
                Spacer()
            }

            Divider()

            Text("操作: \(operationLabel)")
                .font(.subheadline)
            if let db = databaseLabel { infoRow(label: "数据库", value: db) }
            if let title = titleSummary { infoRow(label: "标题", value: title) }
            if let pid = pageId { infoRow(label: "页面 ID", value: String(pid.prefix(12)) + "…") }

            ScrollView {
                Text(prettyArguments)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(nsColor: .textBackgroundColor))
                    )
            }
            .frame(maxHeight: 160)

            HStack {
                Button("取消", role: .cancel) { onCancel() }
                    .buttonStyle(.bordered)
                Spacer()
                Button("确认执行") { onConfirm() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: AppCornerRadius.card)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .shadow(radius: 4)
        .frame(maxWidth: 480)
    }
}

@MainActor
final class NotionConfirmManager: ObservableObject {
    static let shared = NotionConfirmManager()

    @Published var pendingToolCall: WireToolCall?
    @Published var showConfirmation = false

    private var continuation: CheckedContinuation<Bool, Never>?

    private init() {}

    /// 请求用户确认；await 直到用户点 确认/取消。返回 true=执行，false=取消。
    @preconcurrency
    func requestConfirmation(toolCall: WireToolCall) async -> Bool {
        await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            self.pendingToolCall = toolCall
            self.continuation = cont
            self.showConfirmation = true
        }
    }

    func confirm() {
        let cont = continuation
        clear()
        cont?.resume(returning: true)
    }

    func cancel() {
        let cont = continuation
        clear()
        cont?.resume(returning: false)
    }

    private func clear() {
        pendingToolCall = nil
        continuation = nil
        showConfirmation = false
    }
}
