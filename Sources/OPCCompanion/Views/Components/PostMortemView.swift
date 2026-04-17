import SwiftUI

/// 任务完成 / 取消后排队弹出的 post-mortem：一句话，卡在哪 / 学到什么。
struct PostMortemView: View {
    @EnvironmentObject var state: AppState
    let task: TaskItem
    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Color(nsColor: .systemYellow))
                Text(task.status == .done ? "完成：\(task.title)" : "取消：\(task.title)")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Spacer()
                Button {
                    state.dequeuePostMortem()
                } label: {
                    Text("跳过")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }

            TextField("一句话，这次卡在哪 / 学到什么（可跳过）", text: $text)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
                .focused($isFocused)
                .onSubmit { submit() }

            HStack {
                if let actual = task.actualMinutes, let est = task.timerMinutes, est > 0 {
                    let ratio = Double(actual) / Double(est)
                    Text(String(format: "实 %dm · 估 %dm · %.1f×", actual, est, ratio))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(ratio > 1.5 ? Color(nsColor: .systemOrange) : .secondary)
                }
                Spacer()
                Button("保存") { submit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(16)
        .frame(width: 380)
        .glassBackground(cornerRadius: AppCornerRadius.card)
        .onAppear { isFocused = true }
    }

    private func submit() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            let label = task.status == .done ? "完成" : "取消"
            MemoryService.shared.appendToToday(.learnings, entry: "[\(label)] \(task.title)：\(trimmed)")
        }
        state.dequeuePostMortem()
    }
}
