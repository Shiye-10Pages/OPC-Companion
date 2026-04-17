import SwiftUI

/// 计时进行中每 20 分钟从 StatusBar 下方滑出的进展输入条。
/// 用户填一句 / 跳过 / 忽略 —— 内容写入当日 daily note，不污染消息流。
struct ProgressPingView: View {
    @EnvironmentObject var state: AppState
    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 13))
                .foregroundStyle(Color.accentColor)

            if let title = state.activeTask?.title {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: 140, alignment: .leading)
            }

            TextField("一句话，进展？", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($isFocused)
                .onSubmit { submit() }

            Button { submit() } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(text.isEmpty ? AnyShapeStyle(Color.secondary.opacity(0.4)) : AnyShapeStyle(Color.accentColor))
            }
            .buttonStyle(.plain)
            .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)

            Button {
                state.skipProgressPing()
            } label: {
                Text("跳过")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassBackground(cornerRadius: 10)
        .onAppear { isFocused = true }
    }

    private func submit() {
        state.submitProgressNote(text)
        text = ""
    }
}
