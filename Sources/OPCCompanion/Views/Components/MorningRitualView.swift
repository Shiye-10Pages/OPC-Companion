import SwiftUI

/// 每日首次打开面板触发：让用户锁定今天的 3 件事。
struct MorningRitualView: View {
    @EnvironmentObject var state: AppState
    @State private var item1 = ""
    @State private var item2 = ""
    @State private var item3 = ""
    @FocusState private var focusedField: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "sunrise.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(Color(nsColor: .systemOrange))
                Text("今天锁定的 3 件事")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button {
                    // 跳过：不创建任务，但标记仪式已完成，避免重复弹出
                    state.finishMorningRitual(items: [])
                } label: {
                    Text("稍后")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("跳过但标记今日已完成仪式")
            }

            VStack(spacing: 8) {
                numberedField(index: 1, text: $item1)
                numberedField(index: 2, text: $item2)
                numberedField(index: 3, text: $item3)
            }

            HStack {
                Text("填满后回车提交；稍后可在任务 popover 里继续调整")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary.opacity(0.8))
                Spacer()
                Button("锁定") { submit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(allEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
        .glassBackground()
        .onAppear { focusedField = 1 }
    }

    private var allEmpty: Bool {
        [item1, item2, item3].allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    @ViewBuilder
    private func numberedField(index: Int, text: Binding<String>) -> some View {
        HStack(spacing: 10) {
            Text("\(index).")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary)
                .frame(width: 18, alignment: .trailing)
            TextField("第 \(index) 件事", text: text)
                .textFieldStyle(.roundedBorder)
                .focused($focusedField, equals: index)
                .onSubmit {
                    if index < 3 { focusedField = index + 1 }
                    else { submit() }
                }
        }
    }

    private func submit() {
        state.finishMorningRitual(items: [item1, item2, item3])
    }
}
